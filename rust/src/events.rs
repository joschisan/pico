//! Map picomint event log entries onto the flat shapes the Dart UI consumes.
//!
//! Three projections live here:
//! - [`parse_summary`] — six trigger events (`*Send`/`*Receive`) → static
//!   [`OperationSummary`] for the recent-payments / history card.
//! - [`parse_outcome`] — terminal events → `Some(success)` for one-shot
//!   notifications. Trigger events that the federation has nothing further
//!   to do for ("immediately terminal") also return `Some(true)` here.
//! - [`parse_payment_event`] — every public picomint event → rich
//!   [`PaymentEvent`] for the per-op timeline drawer.

use std::collections::BTreeMap;

use flutter_rust_bridge::frb;
use picomint_client::ln::events::{
    ReceiveEvent as LnReceive, SendEvent as LnSend, SendFailureEvent as LnSendFailureEvent,
    SendRefundEvent, SendSuccessEvent,
};
use picomint_client::mint::{
    MintFailureEvent, MintSuccessEvent, ReceiveEvent as MintReceive, RecoveryEvent, RemintEvent,
    SendEvent as MintSend, SendFailureEvent as MintSendFailureEvent,
    SendSuccessEvent as MintSendSuccessEvent,
};
use picomint_client::wallet::events::{
    ReceiveEvent as WalletReceive, SendEvent as WalletSend, SendFailureEvent,
    SendSuccessEvent as WalletSendSuccessEvent,
};
use picomint_client::{TxAcceptEvent, TxCreateEvent, TxRejectEvent};
use picomint_core::config::FederationId;
use picomint_core::bitcoin::hex::DisplayHex;
use picomint_eventlog::EventLogEntry;

#[frb]
#[derive(Clone)]
pub enum PaymentType {
    Lightning,
    Bitcoin,
    Ecash,
}

/// Static card metadata derived once from the trigger event. Live status
/// updates are not folded back in — to see those, the user opens the
/// per-operation drawer which subscribes via `subscribe_payment_events`.
#[frb]
#[derive(Clone)]
pub struct OperationSummary {
    pub operation_id: String,
    pub incoming: bool,
    pub payment_type: PaymentType,
    pub amount_sats: i64,
    pub timestamp: i64,
    /// `Some(name)` if the federation is still warm at parse time;
    /// `None` if the user has since left, in which case the Dart side
    /// renders "Unknown Federation". Resolved against a snapshot of
    /// the client set — past summaries don't get re-resolved on leave.
    pub federation_name: Option<String>,
}

/// One-shot toast/haptic events fired by `subscribe_notifications`. Each
/// variant maps 1:1 to the picomint event whose payload alone is enough to
/// render the toast — no summary lookup needed. Anything more nuanced
/// (e.g. send completion / failure with amount) belongs in the per-op
/// timeline drawer instead.
#[frb]
#[derive(Clone)]
pub enum Notification {
    LightningReceived { amount_sats: i64 },
    OnchainReceived { amount_sats: i64 },
    EcashRecovered { amount_sats: i64 },
    LightningRefunding,
    TransactionRejected,
}

/// One-to-one mirror of every public picomint client event, flattened for
/// transport over the frb bridge. Variant names follow `<Module><Event>`
/// (e.g. `LnSend`, `MintIssuanceComplete`) so the Dart side can match the
/// picomint source on sight. All amounts are converted to sats; all hashes
/// (txids, preimages, signatures) are rendered as lowercase hex.
#[frb]
#[derive(Clone)]
pub enum PaymentEvent {
    // ── Core (transaction-layer events shared across all modules) ────────
    TxCreate {
        timestamp: i64,
        txid: String,
        change_sats: i64,
        fee_sats: i64,
    },
    TxAccept {
        timestamp: i64,
        txid: String,
    },
    TxReject {
        timestamp: i64,
        txid: String,
        error: String,
    },

    // ── Lightning (`picomint_client::ln`) ────────────────────────────────
    LnSend {
        timestamp: i64,
        txid: String,
        amount_sats: i64,
        fee_sats: i64,
    },
    LnSendSuccess {
        timestamp: i64,
        preimage: String,
    },
    LnSendRefund {
        timestamp: i64,
        txid: String,
        expired: bool,
    },
    LnSendFailure {
        timestamp: i64,
    },
    LnReceive {
        timestamp: i64,
        txid: String,
        amount_sats: i64,
        fee_sats: i64,
    },

    // ── Mint / ECash (`picomint_client::mint`) ───────────────────────────
    MintSend {
        timestamp: i64,
        amount_sats: i64,
    },
    MintSendSuccess {
        timestamp: i64,
        /// Base32-encoded ecash; the Dart side parses it back into an
        /// `ECashWrapper` on demand for the display screen. Stored as a
        /// `String` (not `ECashWrapper`) because frb can't put opaque
        /// types inside a value-typed enum without flipping the whole
        /// enum opaque.
        ecash: String,
    },
    MintSendFailure {
        timestamp: i64,
    },
    MintRemint {
        timestamp: i64,
        txid: String,
    },
    MintReceive {
        timestamp: i64,
        txid: String,
        amount_sats: i64,
    },
    MintSuccess {
        timestamp: i64,
        txid: String,
        amount_sats: i64,
    },
    MintFailure {
        timestamp: i64,
    },
    MintRecovery {
        timestamp: i64,
        amount_sats: i64,
        txid: Option<String>,
    },

    // ── Wallet / on-chain (`picomint_client::wallet`) ────────────────────
    WalletSend {
        timestamp: i64,
        txid: String,
        amount_sats: i64,
        fee_sats: i64,
    },
    WalletSendSuccess {
        timestamp: i64,
        txid: String,
    },
    WalletSendFailure {
        timestamp: i64,
    },
    WalletReceive {
        timestamp: i64,
        txid: String,
        amount_sats: i64,
        fee_sats: i64,
    },
}

/// Parse the six trigger events that materialize a new operation in the
/// list. Every other event type returns `None`. `names` is a snapshot
/// of currently-warm federation ids → names; entries from federations
/// the user has since left resolve to `federation_name: None`.
pub(crate) fn parse_summary(
    entry: &EventLogEntry,
    names: &BTreeMap<FederationId, String>,
) -> Option<OperationSummary> {
    let operation_id = entry.operation.to_string();
    let timestamp = entry.timestamp as i64;
    let federation_name = names.get(&entry.federation).cloned();

    if let Some(e) = entry.to_event::<MintSend>() {
        return Some(OperationSummary {
            operation_id,
            incoming: false,
            payment_type: PaymentType::Ecash,
            amount_sats: (e.amount.msat / 1000) as i64,
            timestamp,
            federation_name,
        });
    }
    if let Some(e) = entry.to_event::<MintReceive>() {
        return Some(OperationSummary {
            operation_id,
            incoming: true,
            payment_type: PaymentType::Ecash,
            amount_sats: (e.amount.msat / 1000) as i64,
            timestamp,
            federation_name,
        });
    }
    if let Some(e) = entry.to_event::<LnSend>() {
        return Some(OperationSummary {
            operation_id,
            incoming: false,
            payment_type: PaymentType::Lightning,
            amount_sats: (e.amount.msat / 1000) as i64,
            timestamp,
            federation_name,
        });
    }
    if let Some(e) = entry.to_event::<LnReceive>() {
        return Some(OperationSummary {
            operation_id,
            incoming: true,
            payment_type: PaymentType::Lightning,
            amount_sats: (e.amount.msat / 1000) as i64,
            timestamp,
            federation_name,
        });
    }
    if let Some(e) = entry.to_event::<WalletSend>() {
        return Some(OperationSummary {
            operation_id,
            incoming: false,
            payment_type: PaymentType::Bitcoin,
            amount_sats: e.amount.to_sat() as i64,
            timestamp,
            federation_name,
        });
    }
    if let Some(e) = entry.to_event::<WalletReceive>() {
        return Some(OperationSummary {
            operation_id,
            incoming: true,
            payment_type: PaymentType::Bitcoin,
            amount_sats: e.amount.to_sat() as i64,
            timestamp,
            federation_name,
        });
    }
    // Recovery is now terminal-only — `RecoveryEvent` fires once with
    // the gross recovered amount, so it materializes a card the same
    // way a regular ECash receive does.
    if let Some(e) = entry.to_event::<RecoveryEvent>() {
        return Some(OperationSummary {
            operation_id,
            incoming: true,
            payment_type: PaymentType::Ecash,
            amount_sats: (e.amount.msat / 1000) as i64,
            timestamp,
            federation_name,
        });
    }
    None
}

/// `Some(notification)` for events whose own payload carries everything the
/// toast needs — no `summary` cache, no extra roundtrip. Other events are
/// either internal status updates (visible only via the per-op drawer) or
/// would require summary lookup we deliberately avoid.
pub(crate) fn parse_notification(entry: &EventLogEntry) -> Option<Notification> {
    if let Some(e) = entry.to_event::<LnReceive>() {
        return Some(Notification::LightningReceived {
            amount_sats: (e.amount.msat / 1000) as i64,
        });
    }
    if let Some(e) = entry.to_event::<WalletReceive>() {
        return Some(Notification::OnchainReceived {
            amount_sats: e.amount.to_sat() as i64,
        });
    }
    if let Some(e) = entry.to_event::<RecoveryEvent>() {
        return Some(Notification::EcashRecovered {
            amount_sats: (e.amount.msat / 1000) as i64,
        });
    }
    if entry.to_event::<SendRefundEvent>().is_some() {
        return Some(Notification::LightningRefunding);
    }
    if entry.to_event::<TxRejectEvent>().is_some() {
        return Some(Notification::TransactionRejected);
    }
    None
}

/// Classify a single event log entry into a [`PaymentEvent`]. Returns
/// `None` for entries that don't correspond to any known picomint client
/// event type (forward-compatible with new modules added upstream).
pub(crate) fn parse_payment_event(entry: &EventLogEntry) -> Option<PaymentEvent> {
    let timestamp = entry.timestamp as i64;

    // ── Core ────────────────────────────────────────────────────────────
    if let Some(e) = entry.to_event::<TxCreateEvent>() {
        return Some(PaymentEvent::TxCreate {
            timestamp,
            txid: e.txid.to_string(),
            change_sats: (e.remint.msat / 1000) as i64,
            fee_sats: (e.fee.msat / 1000) as i64,
        });
    }
    if let Some(e) = entry.to_event::<TxAcceptEvent>() {
        return Some(PaymentEvent::TxAccept {
            timestamp,
            txid: e.txid.to_string(),
        });
    }
    if let Some(e) = entry.to_event::<TxRejectEvent>() {
        return Some(PaymentEvent::TxReject {
            timestamp,
            txid: e.txid.to_string(),
            error: e.error,
        });
    }

    // ── Lightning ───────────────────────────────────────────────────────
    if let Some(e) = entry.to_event::<LnSend>() {
        return Some(PaymentEvent::LnSend {
            timestamp,
            txid: e.txid.to_string(),
            amount_sats: (e.amount.msat / 1000) as i64,
            fee_sats: (e.fee.msat / 1000) as i64,
        });
    }
    if let Some(e) = entry.to_event::<SendSuccessEvent>() {
        return Some(PaymentEvent::LnSendSuccess {
            timestamp,
            preimage: e.preimage.to_lower_hex_string(),
        });
    }
    if let Some(e) = entry.to_event::<SendRefundEvent>() {
        return Some(PaymentEvent::LnSendRefund {
            timestamp,
            txid: e.txid.to_string(),
            expired: e.expired,
        });
    }
    if entry.to_event::<LnSendFailureEvent>().is_some() {
        return Some(PaymentEvent::LnSendFailure { timestamp });
    }
    if let Some(e) = entry.to_event::<LnReceive>() {
        return Some(PaymentEvent::LnReceive {
            timestamp,
            txid: e.txid.to_string(),
            amount_sats: (e.amount.msat / 1000) as i64,
            fee_sats: (e.fee.msat / 1000) as i64,
        });
    }

    // ── Mint (ECash) ────────────────────────────────────────────────────
    if let Some(e) = entry.to_event::<MintSend>() {
        return Some(PaymentEvent::MintSend {
            timestamp,
            amount_sats: (e.amount.msat / 1000) as i64,
        });
    }
    if let Some(e) = entry.to_event::<MintSendSuccessEvent>() {
        return Some(PaymentEvent::MintSendSuccess {
            timestamp,
            ecash: e.ecash.to_string(),
        });
    }
    if entry.to_event::<MintSendFailureEvent>().is_some() {
        return Some(PaymentEvent::MintSendFailure { timestamp });
    }
    if let Some(e) = entry.to_event::<RemintEvent>() {
        return Some(PaymentEvent::MintRemint {
            timestamp,
            txid: e.txid.to_string(),
        });
    }
    if let Some(e) = entry.to_event::<MintReceive>() {
        return Some(PaymentEvent::MintReceive {
            timestamp,
            txid: e.txid.to_string(),
            amount_sats: (e.amount.msat / 1000) as i64,
        });
    }
    if let Some(e) = entry.to_event::<MintSuccessEvent>() {
        return Some(PaymentEvent::MintSuccess {
            timestamp,
            txid: e.txid.to_string(),
            amount_sats: (e.amount.msat / 1000) as i64,
        });
    }
    if entry.to_event::<MintFailureEvent>().is_some() {
        return Some(PaymentEvent::MintFailure { timestamp });
    }
    if let Some(e) = entry.to_event::<RecoveryEvent>() {
        return Some(PaymentEvent::MintRecovery {
            timestamp,
            amount_sats: (e.amount.msat / 1000) as i64,
            txid: e.txid.map(|t| t.to_string()),
        });
    }

    // ── Wallet (on-chain) ───────────────────────────────────────────────
    if let Some(e) = entry.to_event::<WalletSend>() {
        return Some(PaymentEvent::WalletSend {
            timestamp,
            txid: e.txid.to_string(),
            amount_sats: e.amount.to_sat() as i64,
            fee_sats: e.fee.to_sat() as i64,
        });
    }
    if let Some(e) = entry.to_event::<WalletSendSuccessEvent>() {
        return Some(PaymentEvent::WalletSendSuccess {
            timestamp,
            txid: e.txid.to_string(),
        });
    }
    if entry.to_event::<SendFailureEvent>().is_some() {
        return Some(PaymentEvent::WalletSendFailure { timestamp });
    }
    if let Some(e) = entry.to_event::<WalletReceive>() {
        return Some(PaymentEvent::WalletReceive {
            timestamp,
            txid: e.txid.to_string(),
            amount_sats: e.amount.to_sat() as i64,
            fee_sats: e.fee.to_sat() as i64,
        });
    }

    None
}
