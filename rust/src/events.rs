//! Map picomint event log entries onto the flat `PicoPayment` shape the
//! Dart UI consumes.
//!
//! Each picomint module emits a creation event (`SendEvent` / `ReceiveEvent`)
//! and zero or more follow-up events that update the operation's status.
//! `parse_event_log_entry` returns either a brand-new payment or an update
//! to fold into an existing one (matched by `operation_id`).

use flutter_rust_bridge::frb;
use picomint_client::ln::events::{
    ReceiveEvent as LnReceive, SendEvent as LnSend, SendRefundEvent, SendSuccessEvent,
};
use picomint_client::mint::{
    IssuanceComplete, OutputFailureEvent, ReceiveEvent as MintReceive, ReissueEvent,
    SendEvent as MintSend,
};
use picomint_client::wallet::events::{
    ReceiveEvent as WalletReceive, SendConfirmEvent, SendEvent as WalletSend, SendFailureEvent,
};
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
    let op = entry.operation_id.to_string();
    let ts = (entry.ts_usecs / 1000) as i64;

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

    if entry.to_event::<IssuanceComplete>().is_some() {
        return Some(ParsedEvent::Update {
            operation_id: op,
            success: true,
            oob: None,
        });
    }

    if entry.to_event::<OutputFailureEvent>().is_some() {
        return Some(ParsedEvent::Update {
            operation_id: op,
            success: false,
            oob: None,
        });
    }

    if entry.to_event::<ReissueEvent>().is_some() {
        // Internal reissue used to top up missing denominations before
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

    if let Some(confirm) = entry.to_event::<SendConfirmEvent>() {
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
