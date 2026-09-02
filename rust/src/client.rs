//! The flat money surface, mirroring the picomint client: every operation
//! is a method on [`Pico`] named for the module that serves it — `mint_send`,
//! `wallet_send`, `ln_receive` — and takes the `(federation, account)` it
//! acts on as arguments. There is no per-account handle to hold or leak;
//! [`PicoAccount`] is the plain data row the home pager renders.

use std::collections::BTreeMap;

use bitcoin::Amount as BtcAmount;
use flutter_rust_bridge::frb;
use futures::StreamExt;
use picomint_client::{Account, ConnStatus};
use picomint_core::Amount;
use picomint_core::PeerId;
use picomint_core::config::FederationId;
use picomint_core::ln::gateway::{GatewayInfo, GatewayPk};

use crate::app::Pico;
use crate::frb_generated::StreamSink;
use crate::{
    AccountWrapper, BitcoinAddressWrapper, Bolt11InvoiceWrapper, ECashWrapper, FederationIdWrapper,
    InviteCodeWrapper,
};

/// Holds a caller-selected gateway plus its routing info, returned by
/// [`Pico::ln_select_gateway`] and handed back to
/// [`Pico::ln_send`] so the fee we previewed is the fee we pay.
/// Opaque on purpose — Dart only needs the two fee getters.
#[frb(opaque)]
#[derive(Clone)]
pub struct GatewayInfoWrapper {
    pub(crate) gateway_pk: GatewayPk,
    pub(crate) gateway_info: GatewayInfo,
}

impl GatewayInfoWrapper {
    /// Exact fee (sats) for paying this invoice through this gateway. One
    /// flat price however the payment settles — routed over Lightning or
    /// swapped internally by the invoice's own issuer — so nothing about the
    /// invoice changes what it costs.
    #[frb(sync)]
    pub fn gateway_fee_for_invoice(&self, invoice: &Bolt11InvoiceWrapper) -> i64 {
        self.gateway_fee_for_amount((invoice.0.amount_milli_satoshis().unwrap_or(0) / 1000) as i64)
    }

    /// Exact fee (sats) for paying `amount_sats` through this gateway — the
    /// same flat price an invoice for the amount will be quoted.
    #[frb(sync)]
    pub fn gateway_fee_for_amount(&self, amount_sats: i64) -> i64 {
        let msats = (amount_sats as u64).saturating_mul(1000);

        (self.gateway_info.send_fee.fee(msats).msat / 1000) as i64
    }

    /// Fee (sats) the gateway deducts from a `amount_sats` incoming
    /// payment. The recipient ultimately ends up with `amount - fee`.
    #[frb(sync)]
    pub fn gateway_fee_for_receive_amount(&self, amount_sats: i64) -> i64 {
        let msats = (amount_sats as u64).saturating_mul(1000);
        (self.gateway_info.receive_fee.fee(msats).msat / 1000) as i64
    }
}

/// One `(federation, account)` row of the wallet, as plain data — every
/// money method on [`Pico`] takes the typed pair back. The name rides along
/// so the pager renders without a config lookup per page.
#[frb]
#[derive(Clone)]
pub struct PicoAccount {
    pub federation: FederationIdWrapper,
    pub account: AccountWrapper,
    pub federation_name: String,
}

impl PicoAccount {
    pub(crate) fn new(federation: FederationId, account: Account, name: String) -> PicoAccount {
        PicoAccount {
            federation: FederationIdWrapper(federation),
            account: AccountWrapper(account),
            federation_name: name,
        }
    }
}

impl Pico {
    #[frb]
    pub async fn mint_send(
        &self,
        federation: &FederationIdWrapper,
        account: &AccountWrapper,
        amount_sat: i64,
    ) -> Result<ECashWrapper, String> {
        self.client
            .mint_send(federation.0, account.0, Amount::from_sat(amount_sat as u64))
            .await
            .map(ECashWrapper)
            .map_err(|e| e.to_string())
    }

    /// Everything this account holds, as one note bundle.
    ///
    /// Not `mint_send` with the balance as its amount: `send` rounds up to a
    /// whole denomination and takes its fast path only when the account's
    /// notes sum to that amount exactly, which a figure in whole sats
    /// generally isn't — denominations are powers of two millisats, and the
    /// balance the UI shows is millisats floored to sats besides. Missing the
    /// fast path drops the send onto the path that builds a real transaction,
    /// which covers its fees out of the account being emptied, so asking for
    /// everything fails on a balance the user is looking at.
    ///
    /// Infallible: `None` is an account holding no notes, which is the empty
    /// wallet the caller shouldn't have offered this on.
    #[frb]
    pub async fn mint_send_max(
        &self,
        federation: &FederationIdWrapper,
        account: &AccountWrapper,
    ) -> Option<ECashWrapper> {
        self.client
            .mint_send_max(federation.0, account.0)
            .ok()
            .flatten()
            .map(ECashWrapper)
    }

    #[frb]
    pub async fn mint_receive(
        &self,
        federation: &FederationIdWrapper,
        account: &AccountWrapper,
        ecash: &ECashWrapper,
    ) -> Result<(), String> {
        self.client
            .mint_receive(federation.0, account.0, &ecash.0)
            .map(|_| ())
            .map_err(|e| e.to_string())
    }

    #[frb]
    pub async fn mint_subscribe_balance(
        &self,
        federation: &FederationIdWrapper,
        account: &AccountWrapper,
        sink: StreamSink<i64>,
    ) {
        let mut stream = self.client.mint_subscribe_balance(federation.0, account.0);

        while let Some(amount) = stream.next().await {
            if sink.add((amount.msat / 1000) as i64).is_err() {
                break;
            }
        }
    }

    /// Pre-select an online gateway. Any will do for any payment: a gateway
    /// charges the same fee however a payment settles, so there is nothing
    /// about an invoice to select one by.
    #[frb]
    pub async fn ln_select_gateway(
        &self,
        federation: &FederationIdWrapper,
    ) -> Result<GatewayInfoWrapper, String> {
        let (gateway_pk, gateway_info) = self
            .client
            .ln_select_gateway(federation.0)
            .map_err(|e| e.to_string())?;

        Ok(GatewayInfoWrapper {
            gateway_pk,
            gateway_info,
        })
    }

    #[frb]
    pub async fn ln_send(
        &self,
        federation: &FederationIdWrapper,
        account: &AccountWrapper,
        gateway: &GatewayInfoWrapper,
        invoice: &Bolt11InvoiceWrapper,
    ) -> Result<String, String> {
        self.client
            .ln_send(
                federation.0,
                account.0,
                gateway.gateway_pk,
                gateway.gateway_info.clone(),
                invoice.0.clone(),
            )
            .await
            .map(|op| op.to_string())
            .map_err(|e| e.to_string())
    }

    #[frb]
    pub async fn ln_receive(
        &self,
        federation: &FederationIdWrapper,
        account: &AccountWrapper,
        gateway: &GatewayInfoWrapper,
        amount_sat: i64,
    ) -> Result<String, String> {
        let invoice = self
            .client
            .ln_receive(
                federation.0,
                account.0,
                gateway.gateway_pk,
                gateway.gateway_info.clone(),
                Amount::from_sat(amount_sat as u64),
            )
            .await
            .map_err(|e| e.to_string())?;

        Ok(invoice.to_string())
    }

    /// The largest whole-sat payment this account can make through `gateway`:
    /// what its notes deliver when spent in full, less the gateway's flat
    /// fee, the transaction fee and the app's cut. Needs no invoice — the
    /// gateway's fee is the same however a payment settles, so the figure
    /// holds for whatever invoice is later resolved for it.
    ///
    /// Picomint's figure, not ours: a max send funds from every note and
    /// mints no change at exactly this amount, so the sizing has to live
    /// where the spending does.
    #[frb]
    pub async fn ln_send_max_amount(
        &self,
        federation: &FederationIdWrapper,
        account: &AccountWrapper,
        gateway: &GatewayInfoWrapper,
    ) -> i64 {
        self.client
            .ln_send_max_amount(federation.0, account.0, &gateway.gateway_info)
            .map(|amount| (amount.msat / 1000) as i64)
            .unwrap_or(0)
    }

    /// Empties the account to `lnurl` through `gateway`: picomint resolves
    /// the one invoice it pays, sized fresh by the same code that spends it,
    /// so every note goes in and no change comes back. The figure
    /// [`Self::ln_send_max_amount`] previewed through this gateway is the
    /// figure paid, short of the balance moving in between — which moves the
    /// payment with it.
    #[frb]
    pub async fn ln_send_max(
        &self,
        federation: &FederationIdWrapper,
        account: &AccountWrapper,
        gateway: &GatewayInfoWrapper,
        lnurl: String,
    ) -> Result<String, String> {
        self.client
            .ln_send_max(
                federation.0,
                account.0,
                gateway.gateway_pk,
                gateway.gateway_info.clone(),
                &lnurl,
            )
            .await
            .map(|op| op.to_string())
            .map_err(|e| e.to_string())
    }

    /// Reads the locally mirrored gateway set, so it never touches the network.
    #[frb(sync)]
    pub fn ln_generate_lnurl(
        &self,
        federation: &FederationIdWrapper,
        account: &AccountWrapper,
    ) -> String {
        self.client
            .ln_generate_lnurl(
                federation.0,
                account.0,
                "http://159.223.25.182:8082/".to_string(),
            )
            .unwrap_or_default()
    }

    /// The current flat per-tx fee for sending onchain, independent of
    /// address and amount.
    #[frb]
    pub async fn wallet_send_fee(&self, federation: &FederationIdWrapper) -> Result<i64, String> {
        self.client
            .wallet_send_fee(federation.0)
            .await
            .map(|fee| fee.to_sat() as i64)
            .map_err(|e| e.to_string())
    }

    #[frb]
    pub async fn wallet_send(
        &self,
        federation: &FederationIdWrapper,
        account: &AccountWrapper,
        address: &BitcoinAddressWrapper,
        amount_sats: i64,
    ) -> Result<(), String> {
        self.client
            .wallet_send(
                federation.0,
                account.0,
                address.0.clone(),
                BtcAmount::from_sat(amount_sats as u64),
                None,
            )
            .await
            .map(|_| ())
            .map_err(|e| e.to_string())
    }

    /// The largest whole-sat amount this account can send onchain: what its
    /// notes deliver when spent in full, less the onchain fee at the current
    /// consensus feerate, the transaction fee and the app's cut.
    ///
    /// Picomint's quote, from the same code [`Self::wallet_send_max`] sizes
    /// with. The two can differ by a feerate that moved in between — the
    /// send recomputes at the moment it is submitted, and that figure is the
    /// one that goes out.
    #[frb]
    pub async fn wallet_send_max_amount(
        &self,
        federation: &FederationIdWrapper,
        account: &AccountWrapper,
    ) -> Result<i64, String> {
        self.client
            .wallet_send_max_amount(federation.0, account.0)
            .await
            .map(|amount| amount.to_sat() as i64)
            .map_err(|e| e.to_string())
    }

    /// Sends everything to `address`, leaving the account empty. The amount is
    /// picomint's to compute — it funds from every note and sizes the output
    /// to what they cover — so nothing is passed in but where it goes.
    #[frb]
    pub async fn wallet_send_max(
        &self,
        federation: &FederationIdWrapper,
        account: &AccountWrapper,
        address: &BitcoinAddressWrapper,
    ) -> Result<(), String> {
        self.client
            .wallet_send_max(federation.0, account.0, address.0.clone())
            .await
            .map(|_| ())
            .map_err(|e| e.to_string())
    }

    /// `account`'s next unused deposit address, derived locally from the
    /// mirrored wallet state, so it never touches the network. Errors only
    /// while the initial address derivation has not completed yet.
    #[frb(sync)]
    pub fn wallet_deposit_address(
        &self,
        federation: &FederationIdWrapper,
        account: &AccountWrapper,
    ) -> Result<String, String> {
        self.client
            .wallet_deposit_address(federation.0, account.0)
            .map(|address| address.to_string())
            .map_err(|e| e.to_string())
    }

    /// Live per-guardian reachability, one entry per guardian in
    /// `config().peers` (PeerId) order: `(name, rtt_ms)` where `rtt_ms` is
    /// `Some(round-trip millis)` while connected and `None` while
    /// disconnected. Sourced from the client's `connection_status_stream`,
    /// which is backed by the same kept-alive connections requests travel
    /// over and emits the current snapshot first — so a freshly-opened
    /// screen never shows a cold-start flicker. Multiple subscribers (home
    /// ring + connection-status screen) each get their own cheap view of
    /// the shared connections; subscribing starts no new polling.
    #[frb]
    pub async fn subscribe_connection_status(
        &self,
        federation: &FederationIdWrapper,
        sink: StreamSink<Vec<(String, Option<f64>)>>,
    ) {
        let Some(config) = self.client.config(federation.0) else {
            return;
        };

        // Guardian names keyed by PeerId so every emission renders all
        // guardians (even before their first status lands) in a stable order.
        let names: BTreeMap<PeerId, String> = config
            .peers
            .iter()
            .map(|entry| (*entry.0, entry.1.name.clone()))
            .collect();

        let Ok(mut stream) = self.client.connection_status_stream(federation.0) else {
            return;
        };

        while let Some(status_map) = stream.next().await {
            let statuses: Vec<(String, Option<f64>)> = names
                .iter()
                .map(|(peer, name)| {
                    let rtt_ms = match status_map.get(peer) {
                        Some(ConnStatus::Connected(rtt)) => Some(rtt.as_secs_f64() * 1000.0),
                        _ => None,
                    };
                    (name.clone(), rtt_ms)
                })
                .collect();

            if sink.add(statuses).is_err() {
                break;
            }
        }
    }

    /// The federation's announced expiry date (unix seconds), from the
    /// expiry-status cache populated at bring-up. `None` until that fetch
    /// completes or for a federation that has not announced an expiry —
    /// either way the UI screens that key off this stay dormant.
    #[frb]
    pub async fn expiration_date(&self, federation: &FederationIdWrapper) -> Option<i64> {
        self.client
            .expiry_status(federation.0)
            .map(|status| status.timestamp as i64)
    }

    /// Invite for the announced successor federation, if the expiring
    /// federation named one. Same cache as [`Self::expiration_date`].
    #[frb]
    pub async fn expiration_successor(
        &self,
        federation: &FederationIdWrapper,
    ) -> Option<InviteCodeWrapper> {
        self.client
            .expiry_status(federation.0)?
            .successor
            .map(InviteCodeWrapper)
    }
}
