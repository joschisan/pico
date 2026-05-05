use std::str::FromStr;
use std::sync::Arc;

use bitcoin::Amount as BtcAmount;
use flutter_rust_bridge::frb;
use futures::StreamExt;
use picomint_client::Client;
use picomint_client::OperationId;
use picomint_core::Amount;
use picomint_core::bitcoin::hashes::sha256;

use crate::db::NamespaceId;
use crate::events::{PaymentEvent, parse_payment_event};
use crate::exchange::{ExchangeRateCache, fetch_exchange_rate};
use crate::frb_generated::StreamSink;
use crate::{BitcoinAddressWrapper, Bolt11InvoiceWrapper, ECashWrapper, InviteCodeWrapper};

#[frb(opaque)]
#[derive(Clone)]
pub struct PicoClient {
    pub(crate) client: Arc<Client>,
    /// Stable handle for this client in the factory map; survives
    /// rejoins since each rejoin draws a fresh random namespace.
    pub(crate) namespace: NamespaceId,
    pub(crate) currency_code: String,
    pub(crate) exchange_rate_cache: ExchangeRateCache,
}

impl PicoClient {
    #[frb]
    pub async fn federation_name(&self) -> Option<String> {
        Some(self.client.config().await.name)
    }

    #[frb(sync)]
    pub fn namespace(&self) -> [u8; 16] {
        self.namespace.0
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
            .generate_lnurl("http://207.154.233.120:8091/".to_string())
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

    /// Live tail of every picomint event for a single operation, parsed
    /// into the rich [`PaymentEvent`] enum for the details drawer timeline.
    /// Replays existing events first (oldest → newest) then yields new
    /// ones as they're committed. Silently exits if `operation_id` doesn't
    /// parse as a valid sha256 hash. Operation ids are globally unique
    /// sha256s so any client can serve any op — no fed_id scoping needed.
    #[frb]
    pub async fn subscribe_payment_events(
        &self,
        operation_id: String,
        sink: StreamSink<PaymentEvent>,
    ) {
        let Ok(hash) = sha256::Hash::from_str(&operation_id) else {
            return;
        };
        let op = OperationId(hash);

        let mut stream = self.client.subscribe_operation_events(op);

        while let Some(entry) = stream.next().await {
            let Some(event) = parse_payment_event(&entry) else {
                continue;
            };
            if sink.add(event).is_err() {
                break;
            }
        }
    }
}
