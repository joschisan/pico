//! Map picomint event log entries onto the flat `PicoPayment` shape the
//! Dart UI consumes.
//!
//! Each picomint module emits a creation event (`SendEvent` / `ReceiveEvent`)
//! and zero or more follow-up events that update the operation's status.
//! `parse_event_log_entry` returns either a brand-new payment or an update
//! to fold into an existing one (matched by `operation_id`).

use flutter_rust_bridge::frb;
use picomint_client::gw::events::{
    ReceiveEvent as GwReceive, ReceiveFailureEvent as GwReceiveFailure,
    ReceiveRefundEvent as GwReceiveRefund, ReceiveSuccessEvent as GwReceiveSuccess,
    SendCancelEvent as GwSendCancel, SendEvent as GwSend, SendSuccessEvent as GwSendSuccess,
};
use picomint_client::ln::events::{
    ReceiveEvent as LnReceive, SendEvent as LnSend, SendFailureEvent as LnSendFailureEvent,
    SendRefundEvent, SendSuccessEvent,
};
use picomint_client::mint::{
    MintFailureEvent, MintSuccessEvent, ReceiveEvent as MintReceive, RecoveryEvent, RemintEvent,
    SendEvent as MintSend,
};
use picomint_client::wallet::events::{
    ReceiveEvent as WalletReceive, SendEvent as WalletSend, SendFailureEvent,
    SendSuccessEvent as WalletSendSuccessEvent,
};
use picomint_client::{TxAcceptEvent, TxRejectEvent};
use picomint_core::bitcoin::hex::DisplayHex;
use picomint_eventlog::EventLogEntry;

#[frb]
#[derive(Clone)]
pub enum PaymentType {
    Lightning,
    Bitcoin,
    Ecash,
}

#[frb]
#[derive(Clone)]
pub struct PicoPayment {
    pub operation_id: String,
    pub incoming: bool,
    pub payment_type: PaymentType,
    pub amount_sats: i64,
    pub fee_sats: Option<i64>,
    pub timestamp: i64,
    pub success: Option<bool>,
    /// For ecash sends: the encoded ECash string (so the UI can re-display
    /// the sender-side QR). For wallet sends: the on-chain txid once
    /// `SendConfirmEvent` lands. None otherwise.
    pub oob: Option<String>,
}

#[frb]
pub struct PaymentNotification {
    pub incoming: bool,
    pub success: bool,
    pub amount_sats: i64,
    pub payment_type: PaymentType,
}

#[frb]
pub struct RecentPaymentsUpdate {
    pub payments: Vec<PicoPayment>,
    pub notification: Option<PaymentNotification>,
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
        ln_fee_sats: i64,
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
    },

    // ── Mint / ECash (`picomint_client::mint`) ───────────────────────────
    MintSend {
        timestamp: i64,
        amount_sats: i64,
        ecash: String,
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
    },
    MintFailure {
        timestamp: i64,
    },
    MintRecovery {
        timestamp: i64,
        index: i64,
        total: Option<i64>,
    },

    // ── Wallet / on-chain (`picomint_client::wallet`) ────────────────────
    WalletSend {
        timestamp: i64,
        txid: String,
        address: String,
        value_sats: i64,
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
        address: String,
        value_sats: i64,
        fee_sats: i64,
    },

    // ── Gateway / cross-fed swaps (`picomint_client::gw`) ────────────────
    GwSend {
        timestamp: i64,
        outpoint: String,
        amount_sats: i64,
        ln_fee_sats: i64,
        fee_sats: i64,
    },
    GwSendSuccess {
        timestamp: i64,
        preimage: String,
        txid: String,
        ln_fee_sats: i64,
    },
    GwSendCancel {
        timestamp: i64,
        signature: String,
    },
    GwReceive {
        timestamp: i64,
        txid: String,
        amount_sats: i64,
        fee_sats: i64,
    },
    GwReceiveSuccess {
        timestamp: i64,
        preimage: String,
    },
    GwReceiveFailure {
        timestamp: i64,
    },
    GwReceiveRefund {
        timestamp: i64,
        txid: String,
    },
}

pub(crate) enum ParsedEvent {
    Payment(PicoPayment),
    Update {
        operation_id: String,
        success: bool,
        oob: Option<String>,
    },
}

pub(crate) fn apply_update(
    payments: &mut [PicoPayment],
    operation_id: &str,
    success: bool,
    oob: Option<String>,
) -> Option<PaymentNotification> {
    let payment = payments
        .iter_mut()
        .rfind(|p| p.operation_id == operation_id)?;

    payment.success = Some(success);
    if oob.is_some() {
        payment.oob = oob;
    }

    Some(PaymentNotification {
        incoming: payment.incoming,
        success,
        amount_sats: payment.amount_sats,
        payment_type: payment.payment_type.clone(),
    })
}

pub(crate) fn snapshot(payments: &[PicoPayment], count: usize) -> Vec<PicoPayment> {
    payments.iter().rev().take(count).cloned().collect()
}

pub(crate) fn parse_event_log_entry(entry: &EventLogEntry) -> Option<ParsedEvent> {
    let op = entry.operation.to_string();
    let ts = entry.timestamp as i64;

    // ── Mint (ECash) ────────────────────────────────────────────────────
    if let Some(send) = entry.to_event::<MintSend>() {
        return Some(ParsedEvent::Payment(PicoPayment {
            operation_id: op,
            incoming: false,
            payment_type: PaymentType::Ecash,
            amount_sats: (send.amount.msats / 1000) as i64,
            fee_sats: None,
            timestamp: ts,
            success: Some(true),
            oob: Some(send.ecash),
        }));
    }

    if let Some(receive) = entry.to_event::<MintReceive>() {
        return Some(ParsedEvent::Payment(PicoPayment {
            operation_id: op,
            incoming: true,
            payment_type: PaymentType::Ecash,
            amount_sats: (receive.amount.msats / 1000) as i64,
            fee_sats: None,
            timestamp: ts,
            success: None,
            oob: None,
        }));
    }

    if entry.to_event::<MintSuccessEvent>().is_some() {
        return Some(ParsedEvent::Update {
            operation_id: op,
            success: true,
            oob: None,
        });
    }

    if entry.to_event::<MintFailureEvent>().is_some() {
        return Some(ParsedEvent::Update {
            operation_id: op,
            success: false,
            oob: None,
        });
    }

    if entry.to_event::<RemintEvent>().is_some() {
        // Internal remint used to top up missing denominations before
        // a send completes. Not user-visible — skip.
        return None;
    }

    // ── Lightning ───────────────────────────────────────────────────────
    if let Some(send) = entry.to_event::<LnSend>() {
        let total_fee = (send.ln_fee.msats + send.fee.msats) / 1000;
        return Some(ParsedEvent::Payment(PicoPayment {
            operation_id: op,
            incoming: false,
            payment_type: PaymentType::Lightning,
            amount_sats: (send.amount.msats / 1000) as i64,
            fee_sats: Some(total_fee as i64),
            timestamp: ts,
            success: None,
            oob: None,
        }));
    }

    if entry.to_event::<SendSuccessEvent>().is_some() {
        return Some(ParsedEvent::Update {
            operation_id: op,
            success: true,
            oob: None,
        });
    }

    if entry.to_event::<SendRefundEvent>().is_some() {
        return Some(ParsedEvent::Update {
            operation_id: op,
            success: false,
            oob: None,
        });
    }

    if let Some(receive) = entry.to_event::<LnReceive>() {
        return Some(ParsedEvent::Payment(PicoPayment {
            operation_id: op,
            incoming: true,
            payment_type: PaymentType::Lightning,
            amount_sats: (receive.amount.msats / 1000) as i64,
            fee_sats: None,
            timestamp: ts,
            success: Some(true),
            oob: None,
        }));
    }

    // ── Wallet (on-chain) ───────────────────────────────────────────────
    if let Some(send) = entry.to_event::<WalletSend>() {
        return Some(ParsedEvent::Payment(PicoPayment {
            operation_id: op,
            incoming: false,
            payment_type: PaymentType::Bitcoin,
            amount_sats: send.value.to_sat() as i64,
            fee_sats: Some(send.fee.to_sat() as i64),
            timestamp: ts,
            success: None,
            oob: None,
        }));
    }

    if let Some(confirm) = entry.to_event::<WalletSendSuccessEvent>() {
        return Some(ParsedEvent::Update {
            operation_id: op,
            success: true,
            oob: Some(confirm.txid.to_string()),
        });
    }

    if entry.to_event::<SendFailureEvent>().is_some() {
        return Some(ParsedEvent::Update {
            operation_id: op,
            success: false,
            oob: None,
        });
    }

    if let Some(receive) = entry.to_event::<WalletReceive>() {
        return Some(ParsedEvent::Payment(PicoPayment {
            operation_id: op,
            incoming: true,
            payment_type: PaymentType::Bitcoin,
            amount_sats: receive.value.to_sat() as i64,
            fee_sats: Some(receive.fee.to_sat() as i64),
            timestamp: ts,
            success: Some(true),
            oob: Some(receive.txid.to_string()),
        }));
    }

    None
}

/// Classify a single event log entry into a [`PaymentEvent`]. Returns
/// `None` for entries that don't correspond to any known picomint client
/// event type (forward-compatible with new modules added upstream).
pub(crate) fn parse_payment_event(entry: &EventLogEntry) -> Option<PaymentEvent> {
    let timestamp = entry.timestamp as i64;

    // ── Core ────────────────────────────────────────────────────────────
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
            amount_sats: (e.amount.msats / 1000) as i64,
            ln_fee_sats: (e.ln_fee.msats / 1000) as i64,
            fee_sats: (e.fee.msats / 1000) as i64,
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
            amount_sats: (e.amount.msats / 1000) as i64,
        });
    }

    // ── Mint (ECash) ────────────────────────────────────────────────────
    if let Some(e) = entry.to_event::<MintSend>() {
        return Some(PaymentEvent::MintSend {
            timestamp,
            amount_sats: (e.amount.msats / 1000) as i64,
            ecash: e.ecash,
        });
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
            amount_sats: (e.amount.msats / 1000) as i64,
        });
    }
    if let Some(e) = entry.to_event::<MintSuccessEvent>() {
        return Some(PaymentEvent::MintSuccess {
            timestamp,
            txid: e.txid.to_string(),
        });
    }
    if entry.to_event::<MintFailureEvent>().is_some() {
        return Some(PaymentEvent::MintFailure { timestamp });
    }
    if let Some(e) = entry.to_event::<RecoveryEvent>() {
        return Some(PaymentEvent::MintRecovery {
            timestamp,
            index: e.index as i64,
            total: e.total.map(|t| t as i64),
        });
    }

    // ── Wallet (on-chain) ───────────────────────────────────────────────
    if let Some(e) = entry.to_event::<WalletSend>() {
        return Some(PaymentEvent::WalletSend {
            timestamp,
            txid: e.txid.to_string(),
            address: e.address.assume_checked().to_string(),
            value_sats: e.value.to_sat() as i64,
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
            address: e.address.assume_checked().to_string(),
            value_sats: e.value.to_sat() as i64,
            fee_sats: e.fee.to_sat() as i64,
        });
    }

    // ── Gateway / cross-fed swaps ───────────────────────────────────────
    if let Some(e) = entry.to_event::<GwSend>() {
        return Some(PaymentEvent::GwSend {
            timestamp,
            outpoint: e.outpoint.to_string(),
            amount_sats: (e.amount.msats / 1000) as i64,
            ln_fee_sats: (e.ln_fee.msats / 1000) as i64,
            fee_sats: (e.fee.msats / 1000) as i64,
        });
    }
    if let Some(e) = entry.to_event::<GwSendSuccess>() {
        return Some(PaymentEvent::GwSendSuccess {
            timestamp,
            preimage: e.preimage.to_lower_hex_string(),
            txid: e.txid.to_string(),
            ln_fee_sats: (e.ln_fee.msats / 1000) as i64,
        });
    }
    if let Some(e) = entry.to_event::<GwSendCancel>() {
        return Some(PaymentEvent::GwSendCancel {
            timestamp,
            signature: e.signature.to_string(),
        });
    }
    if let Some(e) = entry.to_event::<GwReceive>() {
        return Some(PaymentEvent::GwReceive {
            timestamp,
            txid: e.txid.to_string(),
            amount_sats: (e.amount.msats / 1000) as i64,
            fee_sats: (e.fee.msats / 1000) as i64,
        });
    }
    if let Some(e) = entry.to_event::<GwReceiveSuccess>() {
        return Some(PaymentEvent::GwReceiveSuccess {
            timestamp,
            preimage: e.preimage.to_lower_hex_string(),
        });
    }
    if entry.to_event::<GwReceiveFailure>().is_some() {
        return Some(PaymentEvent::GwReceiveFailure { timestamp });
    }
    if let Some(e) = entry.to_event::<GwReceiveRefund>() {
        return Some(PaymentEvent::GwReceiveRefund {
            timestamp,
            txid: e.txid.to_string(),
        });
    }

    None
}
