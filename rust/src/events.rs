//! Map picomint event log entries onto the flat shapes the Dart UI consumes.
//!
//! Three projections live here:
//! - [`parse_summary`] — six trigger events (`*Send`/`*Receive`) → static
//!   [`OperationSummary`] for the recent-payments / history card.
//! - [`parse_outcome`] — terminal events → `Some(success)` for one-shot
//!   notifications. Trigger events that the mint has nothing further
//!   to do for ("immediately terminal") also return `Some(true)` here.
//! - [`parse_payment_event`] — every public picomint event → rich
//!   [`PaymentEvent`] for the per-op timeline drawer.

use flutter_rust_bridge::frb;
use picomint_client::ecash::{
    EcashFailureEvent, EcashSuccessEvent, ReceiveEvent as EcashReceive, RemintEvent,
    SendEvent as EcashSend, SendFailureEvent as EcashSendFailureEvent,
    SendSuccessEvent as EcashSendSuccessEvent,
};
use picomint_client::eventlog::EventLogEntry;
use picomint_client::lightning::events::{
    ReceiveEvent as LightningReceive, SendEvent as LightningSend,
    SendFailureEvent as LightningSendFailureEvent, SendRefundEvent, SendSuccessEvent,
};
use picomint_client::onchain::events::{
    ReceiveEvent as OnchainReceive, SendEvent as OnchainSend,
    SendFailureEvent as OnchainSendFailureEvent, SendSuccessEvent as OnchainSendSuccessEvent,
};
use picomint_client::{TxAcceptEvent, TxCreateEvent, TxRejectEvent};
use picomint_core::bitcoin::hex::DisplayHex;

use crate::{MintIdWrapper, OperationIdWrapper};

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
    pub operation: OperationIdWrapper,
    pub mint: MintIdWrapper,
    pub incoming: bool,
    pub payment_type: PaymentType,
    pub amount_sats: i64,
    pub timestamp: i64,
    /// Fiat value of `amount_sats` at the rate snapshotted when the payment
    /// was first observed live. `None` for operations with no stored
    /// snapshot (predating the feature, or no rate cached at the time) — the
    /// card falls back to sats.
    pub fiat_amount: Option<f64>,
    /// ISO code the `fiat_amount` is denominated in; pairs with `fiat_amount`
    /// so the Dart side can format it via `find_fiat_currency`.
    pub fiat_currency_code: Option<String>,
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
    LightningRefunding,
    TransactionRejected,
}

/// One-to-one mirror of every public picomint client event, flattened for
/// transport over the frb bridge. Variant names follow `<Module><Event>`
/// (e.g. `LightningSend`, `MintIssuanceComplete`) so the Dart side can match the
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
    LightningSend {
        timestamp: i64,
        txid: String,
        amount_sats: i64,
        fee_sats: i64,
    },
    LightningSendSuccess {
        timestamp: i64,
        preimage: String,
    },
    LightningSendRefund {
        timestamp: i64,
        txid: String,
        expired: bool,
    },
    LightningSendFailure {
        timestamp: i64,
    },
    LightningReceive {
        timestamp: i64,
        txid: String,
        amount_sats: i64,
        fee_sats: i64,
    },

    // ── Mint / Ecash (`picomint_client::mint`) ───────────────────────────
    EcashSend {
        timestamp: i64,
        amount_sats: i64,
    },
    EcashSendSuccess {
        timestamp: i64,
        /// Base32-encoded ecash, passed through verbatim from the picomint
        /// event — which carries the string for the same reasons this
        /// stays one while the ids went typed: replaying history shouldn't
        /// decode every bundle, and frb can't put opaque types inside a
        /// value-typed enum anyway. `parse_ecash` reverses it on demand
        /// for the display screen.
        ecash: String,
    },
    EcashSendFailure {
        timestamp: i64,
    },
    EcashRemint {
        timestamp: i64,
        txid: String,
    },
    EcashReceive {
        timestamp: i64,
        txid: String,
        amount_sats: i64,
    },
    EcashSuccess {
        timestamp: i64,
        txid: String,
        amount_sats: i64,
    },
    EcashFailure {
        timestamp: i64,
    },

    // ── Wallet / on-chain (`picomint_client::wallet`) ────────────────────
    OnchainSend {
        timestamp: i64,
        txid: String,
        amount_sats: i64,
        fee_sats: i64,
    },
    OnchainSendSuccess {
        timestamp: i64,
        txid: String,
    },
    OnchainSendFailure {
        timestamp: i64,
    },
    OnchainReceive {
        timestamp: i64,
        txid: String,
        amount_sats: i64,
        fee_sats: i64,
    },
}

/// The `(incoming, payment_type, amount_sats)` carried by the seven trigger
/// events that materialize a card. `None` for any other event. The single
/// source of truth for "is this a summary trigger", shared by `parse_summary`
/// and `is_summary_trigger` so the snapshot recorder and the card parser
/// never disagree on which operations count.
///
/// An add's restored notes need no entry of their own, and get none: they are
/// written straight into the wallet beside the counter marks, before the
/// client that would log anything exists. A restore surfaces as balance
/// rather than as history — the transactions that earned those notes belong
/// to the session that was lost.
fn trigger_fields(entry: &EventLogEntry) -> Option<(bool, PaymentType, i64)> {
    if let Some(e) = entry.to_event::<EcashSend>() {
        return Some((false, PaymentType::Ecash, (e.amount.msat / 1000) as i64));
    }
    if let Some(e) = entry.to_event::<EcashReceive>() {
        return Some((true, PaymentType::Ecash, (e.amount.msat / 1000) as i64));
    }
    if let Some(e) = entry.to_event::<LightningSend>() {
        return Some((false, PaymentType::Lightning, (e.amount.msat / 1000) as i64));
    }
    if let Some(e) = entry.to_event::<LightningReceive>() {
        return Some((true, PaymentType::Lightning, (e.amount.msat / 1000) as i64));
    }
    if let Some(e) = entry.to_event::<OnchainSend>() {
        return Some((false, PaymentType::Bitcoin, e.amount.to_sat() as i64));
    }
    if let Some(e) = entry.to_event::<OnchainReceive>() {
        return Some((true, PaymentType::Bitcoin, e.amount.to_sat() as i64));
    }
    None
}

/// `true` for the trigger events that materialize an `OperationSummary` card.
/// Used by the fiat-snapshot recorder to decide which operations to price,
/// without needing the mint-name map `parse_summary` requires.
pub(crate) fn is_summary_trigger(entry: &EventLogEntry) -> bool {
    trigger_fields(entry).is_some()
}

/// Parse the trigger events that materialize a new operation in the list.
/// Every other event type returns `None`. `fiat` is the
/// `(currency_code, btc_price)` snapshotted for this operation, if any —
/// converted to the displayed `fiat_amount`.
pub(crate) fn parse_summary(
    entry: &EventLogEntry,
    fiat: Option<(String, f64)>,
) -> Option<OperationSummary> {
    let (incoming, payment_type, amount_sats) = trigger_fields(entry)?;

    let (fiat_currency_code, fiat_amount) = match fiat {
        Some((code, rate)) => (
            Some(code),
            Some((amount_sats as f64 / 100_000_000.0) * rate),
        ),
        None => (None, None),
    };

    Some(OperationSummary {
        operation: OperationIdWrapper(entry.operation),
        mint: MintIdWrapper(entry.mint),
        incoming,
        payment_type,
        amount_sats,
        timestamp: entry.timestamp as i64,
        fiat_amount,
        fiat_currency_code,
    })
}

/// `Some(notification)` for events whose own payload carries everything the
/// toast needs — no `summary` cache, no extra roundtrip. Other events are
/// either internal status updates (visible only via the per-op drawer) or
/// would require summary lookup we deliberately avoid.
pub(crate) fn parse_notification(entry: &EventLogEntry) -> Option<Notification> {
    if let Some(e) = entry.to_event::<LightningReceive>() {
        return Some(Notification::LightningReceived {
            amount_sats: (e.amount.msat / 1000) as i64,
        });
    }
    if let Some(e) = entry.to_event::<OnchainReceive>() {
        return Some(Notification::OnchainReceived {
            amount_sats: e.amount.to_sat() as i64,
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
    if let Some(e) = entry.to_event::<LightningSend>() {
        return Some(PaymentEvent::LightningSend {
            timestamp,
            txid: e.txid.to_string(),
            amount_sats: (e.amount.msat / 1000) as i64,
            fee_sats: (e.fee.msat / 1000) as i64,
        });
    }
    if let Some(e) = entry.to_event::<SendSuccessEvent>() {
        return Some(PaymentEvent::LightningSendSuccess {
            timestamp,
            preimage: e.preimage.to_lower_hex_string(),
        });
    }
    if let Some(e) = entry.to_event::<SendRefundEvent>() {
        return Some(PaymentEvent::LightningSendRefund {
            timestamp,
            txid: e.txid.to_string(),
            expired: e.expired,
        });
    }
    if entry.to_event::<LightningSendFailureEvent>().is_some() {
        return Some(PaymentEvent::LightningSendFailure { timestamp });
    }
    if let Some(e) = entry.to_event::<LightningReceive>() {
        return Some(PaymentEvent::LightningReceive {
            timestamp,
            txid: e.txid.to_string(),
            amount_sats: (e.amount.msat / 1000) as i64,
            fee_sats: (e.fee.msat / 1000) as i64,
        });
    }

    // ── Mint (Ecash) ────────────────────────────────────────────────────
    if let Some(e) = entry.to_event::<EcashSend>() {
        return Some(PaymentEvent::EcashSend {
            timestamp,
            amount_sats: (e.amount.msat / 1000) as i64,
        });
    }
    if let Some(e) = entry.to_event::<EcashSendSuccessEvent>() {
        return Some(PaymentEvent::EcashSendSuccess {
            timestamp,
            ecash: e.ecash.clone(),
        });
    }
    if entry.to_event::<EcashSendFailureEvent>().is_some() {
        return Some(PaymentEvent::EcashSendFailure { timestamp });
    }
    if let Some(e) = entry.to_event::<RemintEvent>() {
        return Some(PaymentEvent::EcashRemint {
            timestamp,
            txid: e.txid.to_string(),
        });
    }
    if let Some(e) = entry.to_event::<EcashReceive>() {
        return Some(PaymentEvent::EcashReceive {
            timestamp,
            txid: e.txid.to_string(),
            amount_sats: (e.amount.msat / 1000) as i64,
        });
    }
    if let Some(e) = entry.to_event::<EcashSuccessEvent>() {
        return Some(PaymentEvent::EcashSuccess {
            timestamp,
            txid: e.txid.to_string(),
            amount_sats: (e.amount.msat / 1000) as i64,
        });
    }
    if entry.to_event::<EcashFailureEvent>().is_some() {
        return Some(PaymentEvent::EcashFailure { timestamp });
    }

    // ── Wallet (on-chain) ───────────────────────────────────────────────
    if let Some(e) = entry.to_event::<OnchainSend>() {
        return Some(PaymentEvent::OnchainSend {
            timestamp,
            txid: e.txid.to_string(),
            amount_sats: e.amount.to_sat() as i64,
            fee_sats: e.fee.to_sat() as i64,
        });
    }
    if let Some(e) = entry.to_event::<OnchainSendSuccessEvent>() {
        return Some(PaymentEvent::OnchainSendSuccess {
            timestamp,
            txid: e.txid.to_string(),
        });
    }
    if entry.to_event::<OnchainSendFailureEvent>().is_some() {
        return Some(PaymentEvent::OnchainSendFailure { timestamp });
    }
    if let Some(e) = entry.to_event::<OnchainReceive>() {
        return Some(PaymentEvent::OnchainReceive {
            timestamp,
            txid: e.txid.to_string(),
            amount_sats: e.amount.to_sat() as i64,
            fee_sats: e.fee.to_sat() as i64,
        });
    }

    None
}
