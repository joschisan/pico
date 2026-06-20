use std::sync::Arc;

use bitcoin::Amount as BtcAmount;
use flutter_rust_bridge::frb;
use futures::StreamExt;
use picomint_client::Client;
use picomint_core::Amount;
use picomint_core::config::FederationId;
use picomint_core::ln::gateway::{GatewayInfo, GatewayPk};
use tokio::sync::watch;

use crate::exchange::{ExchangeRateCache, fetch_exchange_rate};
use crate::frb_generated::StreamSink;
use crate::{BitcoinAddressWrapper, Bolt11InvoiceWrapper, ECashWrapper, InviteCodeWrapper};

/// Holds a caller-selected gateway plus its routing info, returned by
/// [`PicoClient::ln_select_gateway`] and handed back to
/// [`PicoClient::ln_send`] so the fee we previewed is the fee we pay.
/// Opaque on purpose — Dart only needs the two fee getters.
#[frb(opaque)]
#[derive(Clone)]
pub struct GatewayInfoWrapper {
    pub(crate) gateway_pk: GatewayPk,
    pub(crate) gateway_info: GatewayInfo,
}

impl GatewayInfoWrapper {
    /// Exact fee (sats) for paying this invoice through this gateway —
    /// `send_fee + ln_fee`, with `ln_fee` zeroed when the gateway is the
    /// invoice's payee (direct ecash swap).
    #[frb(sync)]
    pub fn gateway_fee_for_invoice(&self, invoice: &Bolt11InvoiceWrapper) -> i64 {
        let amount_msats = invoice.0.amount_milli_satoshis().unwrap_or(0);
        let is_direct =
            invoice.0.recover_payee_pub_key() == self.gateway_info.lightning_public_key;
        let ln_msats = if is_direct {
            0
        } else {
            self.gateway_info.ln_fee.fee(amount_msats).msat
        };
        let send_msats = self.gateway_info.send_fee.fee(amount_msats).msat;
        ((ln_msats + send_msats) / 1000) as i64
    }

    /// Worst-case fee (sats) for paying `amount_sats` through this gateway —
    /// no direct-swap shortcut since we don't have an invoice yet.
    #[frb(sync)]
    pub fn gateway_fee_for_amount(&self, amount_sats: i64) -> i64 {
        let msats = (amount_sats as u64).saturating_mul(1000);
        let ln_msats = self.gateway_info.ln_fee.fee(msats).msat;
        let send_msats = self.gateway_info.send_fee.fee(msats).msat;
        ((ln_msats + send_msats) / 1000) as i64
    }

    /// Fee (sats) the gateway deducts from a `amount_sats` incoming
    /// payment. The recipient ultimately ends up with `amount - fee`.
    #[frb(sync)]
    pub fn gateway_fee_for_receive_amount(&self, amount_sats: i64) -> i64 {
        let msats = (amount_sats as u64).saturating_mul(1000);
        (self.gateway_info.receive_fee.fee(msats).msat / 1000) as i64
    }
}

#[frb(opaque)]
#[derive(Clone)]
pub struct PicoClient {
    pub(crate) client: Arc<Client>,
    pub(crate) federation_id: FederationId,
    /// Cached at construction so the factory can resolve names for
    /// `OperationSummary` synchronously while iterating the event log.
    pub(crate) federation_name: String,
    pub(crate) currency_code: String,
    pub(crate) exchange_rate_cache: ExchangeRateCache,
    /// Latest per-guardian reachability, one slot per guardian in
    /// `config().peers` order: `(name, None)` until that guardian's first
    /// poll resolves, then `(name, Some(online))`. Driven by the persistent
    /// monitor spawned in `build_pico_client`, so the home ring and the
    /// connection-status screen read identical state and a freshly-opened
    /// screen gets the current snapshot with no cold-start flicker.
    pub(crate) connection_status: watch::Receiver<Vec<(String, Option<bool>)>>,
    /// Supervisor handle for the per-guardian poll loops. Held so `leave`
    /// can abort the whole monitor (releasing its `Arc<Client>` clone) in
    /// one call. `Arc` because `PicoClient` is `Clone`.
    pub(crate) connection_monitor: Arc<tokio::task::JoinHandle<()>>,
}

impl PicoClient {
    #[frb]
    pub async fn federation_name(&self) -> Option<String> {
        Some(self.federation_name.clone())
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

    /// Converts `amount_sats` to the user's fiat currency using the cached
    /// exchange rate, without triggering a network fetch. Returns `None` when
    /// no fresh rate is cached, so callers can omit the fiat row rather than
    /// block on the network.
    #[frb(sync)]
    pub fn sats_to_fiat(&self, amount_sats: i64) -> Option<f64> {
        let guard = self.exchange_rate_cache.try_lock().ok()?;
        let (rate, timestamp) = guard.as_ref()?;
        if timestamp.elapsed() < std::time::Duration::from_secs(600) {
            Some((amount_sats as f64 / 100_000_000.0) * rate)
        } else {
            None
        }
    }

    #[frb]
    pub async fn subscribe_balance(&self, sink: StreamSink<i64>) {
        let mut stream = self.client.subscribe_balance_changes().await;

        while let Some(amount) = stream.next().await {
            if sink.add((amount.msat / 1000) as i64).is_err() {
                break;
            }
        }
    }

    /// Live recovery progress (0.0..=100.0). Stream ends when the
    /// recovery row is removed (i.e. terminal `RecoveryEvent` has
    /// fired) or immediately if no recovery is in progress at
    /// subscribe time.
    #[frb]
    pub async fn subscribe_recovery_progress(&self, sink: StreamSink<f64>) {
        let mut stream = self.client.mint().subscribe_recovery_progress();

        while let Some(percent) = stream.next().await {
            if sink.add(percent).is_err() {
                break;
            }
        }
    }

    /// Live `(name, online)` status for every guardian, sourced from the
    /// persistent monitor's shared cache. Emits the current snapshot
    /// immediately on subscribe — so a freshly-opened screen never shows a
    /// cold-start flicker — then re-emits whenever any guardian's status
    /// changes. Multiple subscribers (home ring + connection-status screen)
    /// share the one monitor; subscribing here starts no new polling.
    #[frb]
    pub async fn subscribe_connection_status(
        &self,
        sink: StreamSink<Vec<(String, Option<bool>)>>,
    ) {
        let mut rx = self.connection_status.clone();

        if sink.add(rx.borrow().clone()).is_err() {
            return;
        }

        while rx.changed().await.is_ok() {
            if sink.add(rx.borrow().clone()).is_err() {
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
            .send(Amount::from_sat(amount_sat as u64))
            .await
            .map(ECashWrapper)
            .map_err(|e| e.to_string())
    }

    #[frb]
    pub async fn ecash_receive(&self, ecash: &ECashWrapper) -> Result<(), String> {
        self.client
            .mint()
            .receive(&ecash.0)
            .map(|_| ())
            .map_err(|e| e.to_string())
    }

    #[frb]
    pub async fn ln_receive(
        &self,
        gateway: &GatewayInfoWrapper,
        amount_sat: i64,
    ) -> Result<String, String> {
        let invoice = self
            .client
            .ln()
            .receive(
                gateway.gateway_pk,
                gateway.gateway_info.clone(),
                Amount::from_sat(amount_sat as u64),
                60 * 60 * 24,
            )
            .await
            .map_err(|e| e.to_string())?;

        Ok(invoice.to_string())
    }

    /// Pre-select a gateway biased toward the invoice's payee — picomint
    /// picks the same gateway that issued the invoice when available, so
    /// the payment becomes a direct ecash swap with zero LN fee.
    #[frb]
    pub async fn ln_select_gateway_for_invoice(
        &self,
        invoice: &Bolt11InvoiceWrapper,
    ) -> Result<GatewayInfoWrapper, String> {
        let (gateway_pk, gateway_info) = self
            .client
            .ln()
            .select_gateway(Some(&invoice.0))
            .map_err(|e| e.to_string())?;

        Ok(GatewayInfoWrapper {
            gateway_pk,
            gateway_info,
        })
    }

    /// Pre-select any online gateway — for amount-entry flows like lnurl
    /// where we don't have an invoice yet.
    #[frb]
    pub async fn ln_select_any_gateway(&self) -> Result<GatewayInfoWrapper, String> {
        let (gateway_pk, gateway_info) = self
            .client
            .ln()
            .select_gateway(None)
            .map_err(|e| e.to_string())?;

        Ok(GatewayInfoWrapper {
            gateway_pk,
            gateway_info,
        })
    }

    #[frb]
    pub async fn ln_send(
        &self,
        gateway: &GatewayInfoWrapper,
        invoice: &Bolt11InvoiceWrapper,
    ) -> Result<String, String> {
        self.client
            .ln()
            .send(
                gateway.gateway_pk,
                gateway.gateway_info.clone(),
                invoice.0.clone(),
            )
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
}
