use std::sync::Arc;

use bitcoin::Amount as BtcAmount;
use flutter_rust_bridge::frb;
use futures::StreamExt;
use picomint_client::Client;
use picomint_core::Amount;
use picomint_core::config::FederationId;
use picomint_eventlog::EventLogId;
use tokio::sync::Notify;

use crate::events::{
    ParsedEvent, PaymentNotification, PicoPayment, RecentPaymentsUpdate, apply_update,
    parse_event_log_entry, snapshot,
};
use crate::exchange::{ExchangeRateCache, fetch_exchange_rate};
use crate::frb_generated::StreamSink;
use crate::{BitcoinAddressWrapper, Bolt11InvoiceWrapper, ECashWrapper, InviteCodeWrapper};

#[frb]
#[derive(Clone)]
pub struct PicoClient {
    pub(crate) client: Arc<Client>,
    pub(crate) federation_id: FederationId,
    pub(crate) currency_code: String,
    pub(crate) exchange_rate_cache: ExchangeRateCache,
}

impl PicoClient {
    #[frb]
    pub async fn federation_name(&self) -> Option<String> {
        Some(self.client.config().await.name)
    }

    #[frb(sync)]
    pub fn federation_id(&self) -> String {
        self.federation_id.to_string()
    }

    #[frb(sync)]
    pub fn currency_code(&self) -> String {
        self.currency_code.clone()
    }

    #[frb]
    pub async fn shutdown(&self) {
        self.client.shutdown().await;
    }

    #[frb]
    pub async fn prefetch_exchange_rates(&self) {
        tokio::task::spawn(fetch_exchange_rate(
            self.exchange_rate_cache.clone(),
            self.currency_code.clone(),
        ));
    }

    #[frb]
    pub async fn fiat_to_sats(&self, amount_fiat: f64) -> Result<i64, String> {
        fetch_exchange_rate(self.exchange_rate_cache.clone(), self.currency_code.clone())
            .await
            .map(|r| ((amount_fiat / r) * 100_000_000.0).round() as i64)
    }

    #[frb]
    pub async fn subscribe_balance(&self, sink: StreamSink<i64>) {
        let mut stream = self.client.subscribe_balance_changes().await;

        while let Some(amount) = stream.next().await {
            if sink.add((amount.msats / 1000) as i64).is_err() {
                break;
            }
        }
    }

    #[frb]
    pub async fn subscribe_connection_status(&self, sink: StreamSink<Vec<(String, bool)>>) {
        let names: Vec<String> = self
            .client
            .config()
            .await
            .peers
            .values()
            .map(|peer| peer.name.clone())
            .collect();

        let mut stream = self.client.connection_status_stream();

        while let Some(status_map) = stream.next().await {
            let statuses: Vec<(String, bool)> = names
                .iter()
                .zip(status_map.into_values())
                .map(|(name, status)| (name.clone(), status))
                .collect();

            if sink.add(statuses).is_err() {
                break;
            }
        }
    }

    /// Federation-expiry metadata. Picomint has no MetaService yet, so
    /// always `None` — UI screens that key off this stay dormant.
    #[frb]
    pub async fn expiration_date(&self) -> Option<i64> {
        None
    }

    /// Successor-federation invite. Same story as `expiration_date` —
    /// stubbed until picomint exposes a metadata channel.
    #[frb]
    pub async fn expiration_successor(&self) -> Option<InviteCodeWrapper> {
        None
    }

    #[frb]
    pub async fn ecash_send(&self, amount_sat: i64) -> Result<ECashWrapper, String> {
        self.client
            .mint()
            .send(Amount::from_sats(amount_sat as u64))
            .await
            .map(ECashWrapper)
            .map_err(|e| e.to_string())
    }

    #[frb]
    pub async fn ecash_receive(&self, notes: &ECashWrapper) -> Result<(), String> {
        self.client
            .mint()
            .receive(&notes.0)
            .map(|_| ())
            .map_err(|e| e.to_string())
    }

    #[frb]
    pub async fn ln_receive(&self, amount_sat: i64) -> Result<String, String> {
        let invoice = self
            .client
            .ln()
            .receive(
                Amount::from_sats(amount_sat as u64),
                60 * 60 * 24,
                picomint_core::ln::Bolt11InvoiceDescription::Direct(String::new()),
            )
            .await
            .map_err(|e| e.to_string())?;

        Ok(invoice.to_string())
    }

    #[frb]
    pub async fn ln_send(&self, invoice: &Bolt11InvoiceWrapper) -> Result<String, String> {
        self.client
            .ln()
            .send(invoice.0.clone())
            .await
            .map(|op| op.to_string())
            .map_err(|e| e.to_string())
    }

    #[frb]
    pub async fn lnurl(&self) -> Result<String, String> {
        self.client
            .ln()
            .generate_lnurl("https://recurringd.picomint.org/".to_string())
            .await
            .map_err(|e| e.to_string())
    }

    #[frb]
    pub async fn onchain_calculate_fees(
        &self,
        _address: &BitcoinAddressWrapper,
        _amount_sats: i64,
    ) -> Result<i64, String> {
        // Picomint's wallet quotes a flat per-tx fee independent of
        // address/amount. Match the existing UI signature; ignore the
        // extra inputs.
        self.client
            .wallet()
            .send_fee()
            .await
            .map(|fee| fee.to_sat() as i64)
            .map_err(|e| e.to_string())
    }

    #[frb]
    pub async fn onchain_send(
        &self,
        address: &BitcoinAddressWrapper,
        amount_sats: i64,
    ) -> Result<(), String> {
        self.client
            .wallet()
            .send(
                address.0.clone(),
                BtcAmount::from_sat(amount_sats as u64),
                None,
            )
            .await
            .map(|_| ())
            .map_err(|e| e.to_string())
    }

    #[frb]
    pub async fn onchain_receive_address(&self) -> Result<String, String> {
        Ok(self.client.wallet().receive().await.to_string())
    }

    #[frb]
    pub async fn get_payment_history(&self) -> Vec<PicoPayment> {
        let entries = self
            .client
            .get_event_log(EventLogId::LOG_START, u64::MAX)
            .await;

        let mut payments = Vec::new();

        for (_, entry) in entries {
            if entry.federation_id != self.federation_id {
                continue;
            }

            if let Some(parsed) = parse_event_log_entry(&entry) {
                match parsed {
                    ParsedEvent::Payment(payment) => payments.push(payment),
                    ParsedEvent::Update {
                        operation_id,
                        success,
                        oob,
                    } => {
                        apply_update(&mut payments, &operation_id, success, oob);
                    }
                }
            }
        }

        payments.reverse();

        payments
    }

    /// Live tail of the global event log filtered to this federation.
    ///
    /// Always replays from `LOG_START` on every subscription — the global
    /// event log persists across runs at the un-prefixed redb root, so
    /// rebuilding the in-memory payment list from it is cheap and removes
    /// the need for a per-federation copy table in pico's own db.
    #[frb]
    pub async fn subscribe_event_log(&self, sink: StreamSink<RecentPaymentsUpdate>) {
        let notify: Arc<Notify> = self.client.event_notify();

        let mut position = EventLogId::LOG_START;
        let mut payments: Vec<PicoPayment> = Vec::new();
        let mut n_display: usize = 3;
        let mut have_seeded_initial = false;

        loop {
            let notified = notify.notified();

            let batch = self.client.get_event_log(position, 100).await;

            for (id, entry) in &batch {
                position = id.saturating_add(1);

                if entry.federation_id != self.federation_id {
                    continue;
                }

                let Some(parsed) = parse_event_log_entry(entry) else {
                    continue;
                };

                let notification = match parsed {
                    ParsedEvent::Payment(payment) => {
                        if have_seeded_initial {
                            n_display += 1;
                        }

                        let row = payment.clone();

                        payments.push(payment);

                        row.success.map(|success| PaymentNotification {
                            incoming: row.incoming,
                            success,
                            amount_sats: row.amount_sats,
                            payment_type: row.payment_type,
                        })
                    }
                    ParsedEvent::Update {
                        operation_id,
                        success,
                        oob,
                    } => apply_update(&mut payments, &operation_id, success, oob),
                };

                if !have_seeded_initial {
                    // Don't emit per-event notifications while replaying
                    // historical entries — they'd flash through the UI as
                    // "new payment" toasts.
                    continue;
                }

                if sink
                    .add(RecentPaymentsUpdate {
                        payments: snapshot(&payments, n_display),
                        notification,
                    })
                    .is_err()
                {
                    return;
                }
            }

            if !have_seeded_initial && batch.len() < 100 {
                have_seeded_initial = true;

                if sink
                    .add(RecentPaymentsUpdate {
                        payments: snapshot(&payments, n_display),
                        notification: None,
                    })
                    .is_err()
                {
                    return;
                }
            }

            if batch.len() < 100 {
                notified.await;
            }
        }
    }
}
