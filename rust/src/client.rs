//! The flat money surface, mirroring the picomint client: every operation
//! is a method on [`Pico`] named for the module that serves it —
//! `ecash_send`, `onchain_send`, `lightning_receive` — and takes the
//! `(mint, account)` it acts on as arguments. There is no per-account handle to hold or leak;
//! [`PicoAccount`] is the plain data row the home pager renders.

use std::collections::BTreeMap;

use bitcoin::Amount as BtcAmount;
use flutter_rust_bridge::frb;
use futures::StreamExt;
use picomint_client::{Account, ConnStatus};
use picomint_core::Amount;
use picomint_core::NodeId;
use picomint_core::config::MintId;
use picomint_core::lightning::gateway::{GatewayInfo, GatewayPk};

use picomint_core::NumNodesExt;

use crate::app::Pico;
use crate::frb_generated::StreamSink;
use crate::{
    AccountWrapper, BitcoinAddressWrapper, Bolt11InvoiceWrapper, EcashWrapper, InviteCodeWrapper,
    MintIdWrapper,
};

/// Holds a caller-selected gateway plus its routing info, returned by
/// [`Pico::lightning_select_gateway`] and handed back to
/// [`Pico::lightning_send`] so the fee we previewed is the fee we pay.
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

/// The lnurl daemon that serves this wallet's reusable receive codes.
/// Self-hosted infrastructure, named here as the one deliberate constant
/// rather than buried at the call site: the daemon holds no funds — it
/// relays lnurl requests to the recipient's mint — so swapping it only
/// changes who serves the codes, not who can spend them.
const LNURL_DAEMON_URL: &str = "http://159.223.25.182:8082/";

/// One `(mint, account)` row of the wallet, as plain data — every
/// money method on [`Pico`] takes the typed pair back. The name rides along
/// so the pager renders without a config lookup per page.
#[frb]
#[derive(Clone)]
pub struct PicoAccount {
    pub mint: MintIdWrapper,
    pub account: AccountWrapper,
    pub mint_name: String,
}

impl PicoAccount {
    pub(crate) fn new(mint: MintId, account: Account, name: String) -> PicoAccount {
        PicoAccount {
            mint: MintIdWrapper(mint),
            account: AccountWrapper(account),
            mint_name: name,
        }
    }
}

/// One node of a mint as the connectivity surfaces show it: its name and,
/// while connected, the live link's round-trip time in milliseconds.
#[frb]
#[derive(Clone)]
pub struct NodeStatus {
    pub name: String,
    pub rtt_ms: Option<f64>,
}

/// One connectivity snapshot: the per-node statuses in `NodeId` order,
/// and whether enough nodes are reachable for the mint to sign — judged
/// against the same `2f + 1` threshold picomint-core defines, computed
/// on this side of the bridge so the app can never drift from it.
#[frb]
#[derive(Clone)]
pub struct MintConnectivity {
    pub nodes: Vec<NodeStatus>,
    pub operational: bool,
}

/// Mint-wide wallet stats shown in the receive screen's details
/// drawer. The feerate is in sats per 1000 vbytes (kvB).
#[frb]
pub struct MintStats {
    pub total_value_sat: i64,
    pub block_count: i64,
    pub feerate: Option<i64>,
}

impl Pico {
    #[frb]
    pub async fn ecash_send(
        &self,
        mint: &MintIdWrapper,
        account: &AccountWrapper,
        amount_sats: i64,
    ) -> Result<EcashWrapper, String> {
        self.client
            .ecash_send(mint.0, account.0, Amount::from_sat(amount_sats as u64))
            .await
            .map(EcashWrapper)
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
    pub async fn ecash_send_max(
        &self,
        mint: &MintIdWrapper,
        account: &AccountWrapper,
    ) -> Option<EcashWrapper> {
        self.client
            .ecash_send_max(mint.0, account.0)
            .ok()
            .flatten()
            .map(EcashWrapper)
    }

    #[frb]
    pub async fn ecash_receive(
        &self,
        mint: &MintIdWrapper,
        account: &AccountWrapper,
        ecash: &EcashWrapper,
    ) -> Result<(), String> {
        self.client
            .ecash_receive(mint.0, account.0, &ecash.0)
            .map(|_| ())
            .map_err(|e| e.to_string())
    }

    #[frb]
    pub async fn ecash_subscribe_balance(
        &self,
        mint: &MintIdWrapper,
        account: &AccountWrapper,
        sink: StreamSink<i64>,
    ) {
        let mut stream = self.client.ecash_subscribe_balance(mint.0, account.0);

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
    pub async fn lightning_select_gateway(
        &self,
        mint: &MintIdWrapper,
    ) -> Result<GatewayInfoWrapper, String> {
        let (gateway_pk, gateway_info) = self
            .client
            .lightning_select_gateway(mint.0)
            .map_err(|e| e.to_string())?;

        Ok(GatewayInfoWrapper {
            gateway_pk,
            gateway_info,
        })
    }

    #[frb]
    pub async fn lightning_send(
        &self,
        mint: &MintIdWrapper,
        account: &AccountWrapper,
        gateway: &GatewayInfoWrapper,
        invoice: &Bolt11InvoiceWrapper,
    ) -> Result<String, String> {
        self.client
            .lightning_send(
                mint.0,
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
    pub async fn lightning_receive(
        &self,
        mint: &MintIdWrapper,
        account: &AccountWrapper,
        gateway: &GatewayInfoWrapper,
        amount_sats: i64,
    ) -> Result<String, String> {
        let invoice = self
            .client
            .lightning_receive(
                mint.0,
                account.0,
                gateway.gateway_pk,
                gateway.gateway_info.clone(),
                Amount::from_sat(amount_sats as u64),
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
    pub async fn lightning_send_max_amount(
        &self,
        mint: &MintIdWrapper,
        account: &AccountWrapper,
        gateway: &GatewayInfoWrapper,
    ) -> i64 {
        self.client
            .lightning_send_max_amount(mint.0, account.0, &gateway.gateway_info)
            .map(|amount| (amount.msat / 1000) as i64)
            .unwrap_or(0)
    }

    /// Empties the account to `lnurl` through `gateway`: picomint resolves
    /// the one invoice it pays, sized fresh by the same code that spends it,
    /// so every note goes in and no change comes back. The figure
    /// [`Self::lightning_send_max_amount`] previewed through this gateway is the
    /// figure paid, short of the balance moving in between — which moves the
    /// payment with it.
    #[frb]
    pub async fn lightning_send_max(
        &self,
        mint: &MintIdWrapper,
        account: &AccountWrapper,
        gateway: &GatewayInfoWrapper,
        lnurl: String,
    ) -> Result<String, String> {
        self.client
            .lightning_send_max(
                mint.0,
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
    pub fn lightning_generate_lnurl(
        &self,
        mint: &MintIdWrapper,
        account: &AccountWrapper,
    ) -> String {
        self.client
            .lightning_generate_lnurl(mint.0, account.0, LNURL_DAEMON_URL.to_string())
            .unwrap_or_default()
    }

    /// The current flat per-tx fee for sending onchain, independent of
    /// address and amount.
    #[frb]
    pub async fn onchain_send_fee(&self, mint: &MintIdWrapper) -> Result<i64, String> {
        self.client
            .onchain_send_fee(mint.0)
            .await
            .map(|fee| fee.to_sat() as i64)
            .map_err(|e| e.to_string())
    }

    #[frb]
    pub async fn onchain_send(
        &self,
        mint: &MintIdWrapper,
        account: &AccountWrapper,
        address: &BitcoinAddressWrapper,
        amount_sats: i64,
    ) -> Result<(), String> {
        self.client
            .onchain_send(
                mint.0,
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
    /// Picomint's quote, from the same code [`Self::onchain_send_max`] sizes
    /// with. The two can differ by a feerate that moved in between — the
    /// send recomputes at the moment it is submitted, and that figure is the
    /// one that goes out.
    #[frb]
    pub async fn onchain_send_max_amount(
        &self,
        mint: &MintIdWrapper,
        account: &AccountWrapper,
    ) -> Result<i64, String> {
        self.client
            .onchain_send_max_amount(mint.0, account.0)
            .await
            .map(|amount| amount.to_sat() as i64)
            .map_err(|e| e.to_string())
    }

    /// Sends everything to `address`, leaving the account empty. The amount is
    /// picomint's to compute — it funds from every note and sizes the output
    /// to what they cover — so nothing is passed in but where it goes.
    #[frb]
    pub async fn onchain_send_max(
        &self,
        mint: &MintIdWrapper,
        account: &AccountWrapper,
        address: &BitcoinAddressWrapper,
    ) -> Result<(), String> {
        self.client
            .onchain_send_max(mint.0, account.0, address.0.clone())
            .await
            .map(|_| ())
            .map_err(|e| e.to_string())
    }

    /// `account`'s next unused deposit address, derived locally from the
    /// mirrored onchain state, so it never touches the network. Errors only
    /// while the initial address derivation has not completed yet.
    #[frb(sync)]
    pub fn onchain_receive(
        &self,
        mint: &MintIdWrapper,
        account: &AccountWrapper,
    ) -> Result<String, String> {
        self.client
            .onchain_receive(mint.0, account.0)
            .map(|address| address.to_string())
            .map_err(|e| e.to_string())
    }

    /// Mint-wide wallet stats for the receive screen's details drawer:
    /// bitcoin in custody, consensus block count and consensus feerate.
    #[frb]
    pub async fn mint_stats(&self, mint: &MintIdWrapper) -> Result<MintStats, String> {
        let total_value = self
            .client
            .onchain_total_value(mint.0)
            .await
            .map_err(|e| e.to_string())?;

        let block_count = self
            .client
            .block_count(mint.0)
            .await
            .map_err(|e| e.to_string())?;

        let feerate = self
            .client
            .onchain_feerate(mint.0)
            .await
            .map_err(|e| e.to_string())?;

        Ok(MintStats {
            total_value_sat: total_value.to_sat() as i64,
            block_count: i64::from(block_count),
            feerate: feerate.map(i64::from),
        })
    }

    /// Live per-mint connectivity, one [`MintConnectivity`] snapshot per
    /// change. Sourced from the client's `connection_status_stream`, which
    /// is backed by the same kept-alive connections requests travel over
    /// and emits the current snapshot first — so a freshly-opened screen
    /// never shows a cold-start flicker. Multiple subscribers (home ring +
    /// connection-status screen) each get their own cheap view of the
    /// shared connections; subscribing starts no new polling.
    #[frb]
    pub async fn subscribe_connectivity(
        &self,
        mint: &MintIdWrapper,
        sink: StreamSink<MintConnectivity>,
    ) {
        let Some(config) = self.client.config(mint.0) else {
            return;
        };

        let threshold = config.nodes.to_num_nodes().threshold();

        // Node names keyed by NodeId so every emission renders all
        // nodes (even before their first status lands) in a stable order.
        let names: BTreeMap<NodeId, String> = config
            .nodes
            .iter()
            .map(|entry| (*entry.0, entry.1.name.clone()))
            .collect();

        let Ok(mut stream) = self.client.connection_status_stream(mint.0) else {
            return;
        };

        while let Some(status_map) = stream.next().await {
            let nodes: Vec<NodeStatus> = names
                .iter()
                .map(|(node, name)| NodeStatus {
                    name: name.clone(),
                    rtt_ms: match status_map.get(node) {
                        Some(ConnStatus::Connected(rtt)) => Some(rtt.as_secs_f64() * 1000.0),
                        _ => None,
                    },
                })
                .collect();

            let snapshot = MintConnectivity {
                operational: nodes.iter().filter(|node| node.rtt_ms.is_some()).count() >= threshold,
                nodes,
            };

            if sink.add(snapshot).is_err() {
                break;
            }
        }
    }

    /// The mint's announced expiry date (unix seconds), from the
    /// expiry-status cache populated at bring-up. `None` until that fetch
    /// completes or for a mint that has not announced an expiry —
    /// either way the UI screens that key off this stay dormant.
    #[frb]
    pub async fn expiration_date(&self, mint: &MintIdWrapper) -> Option<i64> {
        self.client
            .expiry_status(mint.0)
            .map(|status| status.timestamp as i64)
    }

    /// Invite for the announced successor mint, if the expiring
    /// mint named one. Same cache as [`Self::expiration_date`].
    #[frb]
    pub async fn expiration_successor(&self, mint: &MintIdWrapper) -> Option<InviteCodeWrapper> {
        self.client
            .expiry_status(mint.0)?
            .successor
            .map(InviteCodeWrapper)
    }
}
