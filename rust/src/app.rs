use std::collections::{HashMap, HashSet};
use std::sync::Arc;

use flutter_rust_bridge::frb;
use futures::StreamExt;
use futures::stream::{self, BoxStream};
use iroh::Endpoint;
use iroh::endpoint::presets::N0;
use iroh_mdns_address_lookup::MdnsAddressLookup;
use picomint_client::{Account, Client, Mnemonic, OperationId};
use picomint_core::config::FederationId;
use picomint_eventlog::EventLogId;
use picomint_redb::{Database, DbRead};
use tokio::sync::{Mutex, Notify};

use crate::client::PicoAccount;
use crate::db::{CONTACT, OperationFiat, RootEntropy, SelectedCurrency};
use crate::events::{
    Notification, OperationSummary, PaymentEvent, is_summary_trigger, parse_notification,
    parse_payment_event, parse_summary,
};
use crate::exchange::{ExchangeRateCache, FRESHNESS, btc_price, fetch_exchange_rates};
use crate::frb_generated::StreamSink;
use crate::lnurl::LnurlWrapper;
use crate::{
    AccountWrapper, DatabaseWrapper, FederationIdWrapper, InviteCodeWrapper, MnemonicWrapper,
    OperationIdWrapper,
};

#[frb(opaque)]
pub struct Pico {
    db: Database,
    mnemonic: Mnemonic,
    /// The one picomint client, holding every joined federation as data.
    /// It owns the shared iroh endpoint, the federation configs and the
    /// daemon-wide event log; every operation names the federation it
    /// acts on. The money methods mirroring its `mint_` / `wallet_` / `ln_`
    /// surface live in `crate::client`.
    pub(crate) client: Arc<Client>,
    /// Wakes anyone iterating the client set when membership changes.
    /// `notify_waiters` is fire-and-forget; subscribers re-snapshot the
    /// joined set after waking.
    set_changed: Arc<Notify>,
    /// Single exchange-rate cache shared by every client (the BTC price is
    /// global, not per-federation) and by the fiat-snapshot recorder. One
    /// fetch warms it for all consumers.
    exchange_rate_cache: ExchangeRateCache,
}

#[frb(opaque)]
pub struct PicoContact {
    lnurl: LnurlWrapper,
    name: String,
}

fn contains(haystack: &str, needle: &str) -> bool {
    haystack.to_lowercase().contains(&needle.to_lowercase())
}

impl PicoContact {
    #[frb(sync, getter)]
    pub fn name(&self) -> String {
        self.name.clone()
    }

    #[frb(sync, getter)]
    pub fn lnurl(&self) -> LnurlWrapper {
        LnurlWrapper(self.lnurl.0.clone())
    }

    #[frb(sync)]
    pub fn match_query(&self, query: &str) -> bool {
        contains(&self.name, query) || contains(&self.lnurl.0, query)
    }
}

impl Pico {
    #[frb]
    pub async fn init(db: &DatabaseWrapper, mnemonic: &MnemonicWrapper) -> Result<Self, String> {
        let dbtx = db.0.begin_write();

        dbtx.insert(&RootEntropy, &(), &mnemonic.0.to_entropy().to_vec());

        dbtx.commit();

        let endpoint = bind_endpoint().await.map_err(|e| e.to_string())?;

        Self::assemble(db.0.clone(), mnemonic.0.clone(), endpoint).await
    }

    #[frb]
    pub async fn try_load(db: &DatabaseWrapper) -> Option<Self> {
        let entropy = db.0.begin_read().get(&RootEntropy, &())?;

        let mnemonic = Mnemonic::from_entropy(&entropy).ok()?;

        let endpoint = bind_endpoint().await.ok()?;

        Self::assemble(db.0.clone(), mnemonic, endpoint).await.ok()
    }

    /// Build the factory and bring every joined federation up. `connect` is
    /// pico's eager path — the gateway leaves federations dormant, but every
    /// federation in this wallet has a balance on screen, so all of them
    /// come up at startup.
    async fn assemble(
        db: Database,
        mnemonic: Mnemonic,
        endpoint: Endpoint,
    ) -> Result<Self, String> {
        let client = Arc::new(Client::new(
            endpoint,
            db.clone(),
            mnemonic.clone(),
            Some(crate::payout::fee_config()),
        ));

        for fed_id in client.federations() {
            client.connect(fed_id).map_err(|e| e.to_string())?;
        }

        Ok(Self {
            db,
            mnemonic,
            client,
            set_changed: Arc::new(Notify::new()),
            exchange_rate_cache: Arc::new(Mutex::new(None)),
        })
    }

    /// One row per joined `(federation, account)` pair, federation-major
    /// and account-minor — the order the home pager swipes in.
    fn rows(&self) -> Vec<PicoAccount> {
        self.client
            .federation_configs()
            .into_iter()
            .flat_map(|entry| {
                Account::USER_ACCOUNTS
                    .into_iter()
                    .map(move |account| PicoAccount::new(entry.0, account, entry.1.name.clone()))
            })
            .collect()
    }

    #[frb(sync)]
    pub fn seed_phrase(&self) -> Vec<String> {
        self.mnemonic.words().map(|s| s.to_string()).collect()
    }

    /// Every joined `(federation, account)` pair, as plain data.
    #[frb(sync)]
    pub fn accounts(&self) -> Vec<PicoAccount> {
        self.rows()
    }

    /// Look up a federation's [`Account::PRIMARY`] row. `None` if the user
    /// isn't joined to it, which is how the ecash drawer tells a bundle from
    /// a mint the wallet doesn't have.
    ///
    /// Primary because a caller reaching for this holds a federation id and
    /// nothing more — an ecash bundle names no account. It is the fallback,
    /// not the usual path: the drawer receives into the account on screen
    /// when the bundle belongs to its federation, and only asks here when it
    /// doesn't.
    #[frb(sync)]
    pub fn account(&self, federation: &FederationIdWrapper) -> Option<PicoAccount> {
        let config = self.client.config(federation.0)?;

        Some(PicoAccount::new(
            federation.0,
            Account::PRIMARY,
            config.name,
        ))
    }

    /// Adds a federation, rebuilding whatever this seed already owns there.
    ///
    /// One path, whether or not the seed has been here before: `add` scans
    /// every account before anything is opened or written, and a seed that
    /// never held anything scans to nothing. There is no question to put to
    /// the user and so nothing for them to get wrong — answering "new mint"
    /// for a federation this seed has used would write counter zero over an
    /// account that has issued and strand every note behind the nonces it
    /// re-derives.
    ///
    /// Returns only once the notes are back, so there is no progress to
    /// report and no half-joined federation to detect on the next launch.
    #[frb]
    pub async fn add(&self, invite: &InviteCodeWrapper) -> Result<PicoAccount, String> {
        // Rejected before the scan rather than after it. The invite code
        // commits to the federation id — `add` below refuses a config that
        // computes to any other — so a duplicate is knowable up front, and
        // there is no reason to make the user wait out four account scans to
        // be told what the code alone already said. The check inside `add`
        // is atomic with the write, so it is the authority; this one only
        // spares the wait.
        if self.client.config(invite.0.federation).is_some() {
            return Err("This mint is already added".to_string());
        }

        // Downloads the config, scans every account, and lands config,
        // counter marks and restored notes in one dbtx: either the
        // federation is joined with every counter in place and its balance
        // already there, or it isn't joined at all. A failure leaves the
        // wallet exactly as it was.
        let federation_id = self
            .client
            .add(&invite.0, None)
            .await
            .map_err(|e| e.to_string())?;

        self.client
            .connect(federation_id)
            .map_err(|e| e.to_string())?;

        let config = self
            .client
            .config(federation_id)
            .expect("the federation was just added");

        self.set_changed.notify_waiters();

        // Primary is what a caller that just joined gets handed: it is the
        // account the pager lands on.
        Ok(PicoAccount::new(
            federation_id,
            Account::PRIMARY,
            config.name,
        ))
    }

    #[frb(sync)]
    pub fn set_currency(&self, currency_code: &str) {
        let dbtx = self.db.begin_write();

        dbtx.insert(&SelectedCurrency, &(), &currency_code.to_string());

        dbtx.commit();
    }

    #[frb(sync)]
    pub fn currency_code(&self) -> String {
        self.db
            .begin_read()
            .get(&SelectedCurrency, &())
            .unwrap_or_else(|| "USD".to_string())
    }

    /// Warm the exchange-rate cache, resolving only once a rate is actually
    /// stored (or the fetch fails). Awaiting it lets callers repaint
    /// fiat-dependent UI the moment a rate becomes available; a fresh cache
    /// short-circuits without a network hit.
    #[frb]
    pub async fn prefetch_exchange_rates(&self) {
        let _ = fetch_exchange_rates(self.exchange_rate_cache.clone()).await;
    }

    /// Converts a fiat amount in `currency_code` to sats. The caller supplies
    /// the currency: the home screen reads it live via [`Self::currency_code`],
    /// while the send/receive amount flow snapshots it once on entry (the user
    /// can't change currency mid-flow), so this does no db read of its own.
    #[frb]
    pub async fn fiat_to_sats(
        &self,
        amount_fiat: f64,
        currency_code: String,
    ) -> Result<i64, String> {
        fetch_exchange_rates(self.exchange_rate_cache.clone()).await?;

        let guard = self.exchange_rate_cache.lock().await;
        let (prices, _) = guard.as_ref().ok_or("No exchange rate cached")?;
        let rate = btc_price(prices, &currency_code).ok_or("Currency not supported")?;

        Ok(((amount_fiat / rate) * 100_000_000.0).round() as i64)
    }

    /// Converts `amount_sats` to `currency_code` using the cached exchange
    /// rate, without triggering a network fetch. Returns `None` when no fresh
    /// rate is cached, so callers can omit the fiat row rather than block on
    /// the network. Currency is caller-supplied — see [`Self::fiat_to_sats`].
    #[frb(sync)]
    pub fn sats_to_fiat(&self, amount_sats: i64, currency_code: String) -> Option<f64> {
        let guard = self.exchange_rate_cache.try_lock().ok()?;
        let (prices, timestamp) = guard.as_ref()?;
        if timestamp.elapsed() >= FRESHNESS {
            return None;
        }
        let rate = btc_price(prices, &currency_code)?;
        Some((amount_sats as f64 / 100_000_000.0) * rate)
    }

    /// Drop a federation: `Client::remove` shuts its runtime down, then
    /// wipes its rows and drops its config in one dbtx, so a crash
    /// mid-leave can never leave orphan client state behind a missing
    /// config row. Re-joining the same federation later starts from a
    /// fresh ledger.
    #[frb]
    pub async fn remove(&self, federation: &FederationIdWrapper) -> Result<(), String> {
        // A federation that is already gone is a removal that already
        // succeeded, not an error to surface — the drawer may fire twice.
        if self.client.config(federation.0).is_none() {
            return Ok(());
        }

        // Every account goes at once — accounts are a split of one
        // federation's client state, not something a user joins or leaves
        // individually.
        self.client
            .remove(federation.0)
            .await
            .map_err(|e| e.to_string())?;

        self.set_changed.notify_waiters();
        Ok(())
    }

    /// Live snapshot of every joined `(federation, account)` row; re-emits
    /// on every set change (`add`/`remove`). Subscribers re-render passively
    /// instead of re-fetching `accounts()` after each navigation pop.
    #[frb]
    pub async fn subscribe_accounts(&self, sink: StreamSink<Vec<PicoAccount>>) {
        loop {
            let snapshot = self.rows();
            let set_changed = self.set_changed.notified();
            tokio::pin!(set_changed);
            if sink.add(snapshot).is_err() {
                return;
            }
            set_changed.await;
        }
    }

    /// Aggregated balance across every joined federation, in sats. Re-emits
    /// on any per-account balance change AND on set changes
    /// (`add`/`remove`). The totals map survives rebuilds so an
    /// add/remove doesn't reset the running sum to zero.
    #[frb]
    pub async fn subscribe_global_balance(&self, sink: StreamSink<i64>) {
        let mut totals: HashMap<(FederationId, Account), i64> = HashMap::new();

        loop {
            // Snapshot the joined set; build a tagged stream per account so
            // we can attribute incoming balances back to an account and
            // discard departed federations on the next rebuild.
            let snapshot: Vec<(FederationId, Account)> = self
                .client
                .federations()
                .into_iter()
                .flat_map(|fed_id| {
                    Account::USER_ACCOUNTS
                        .into_iter()
                        .map(move |account| (fed_id, account))
                })
                .collect();

            let alive: HashSet<(FederationId, Account)> = snapshot.iter().copied().collect();
            totals.retain(|key, _| alive.contains(key));

            let mut tagged: Vec<BoxStream<'static, ((FederationId, Account), i64)>> =
                Vec::with_capacity(snapshot.len());
            for key in snapshot {
                let stream = self
                    .client
                    .mint_subscribe_balance(key.0, key.1)
                    .map(move |amt| (key, (amt.msat / 1000) as i64));
                tagged.push(stream.boxed());
            }
            let mut merged = stream::select_all(tagged);

            // Re-arm the set-change notifier *before* emitting the
            // initial sum, so an add/remove landing between the snapshot
            // and the await still wakes us.
            let set_changed = self.set_changed.notified();
            tokio::pin!(set_changed);

            if sink.add(totals.values().sum()).is_err() {
                return;
            }

            loop {
                tokio::select! {
                    Some((key, balance)) = merged.next() => {
                        totals.insert(key, balance);
                        if sink.add(totals.values().sum()).is_err() {
                            return;
                        }
                    }
                    _ = &mut set_changed => break,
                }
            }
        }
    }

    /// One-shot history of the operations `(federation, account)` ran, in
    /// chronological order (oldest first — Dart reverses for display).
    /// Filtered here rather than in Dart so only the account's rows cross
    /// the bridge. Cards rendered from this snapshot stay static; live
    /// status is reachable only by opening the per-op drawer.
    #[frb(sync)]
    pub fn list_operations(
        &self,
        federation: &FederationIdWrapper,
        account: &AccountWrapper,
    ) -> Vec<OperationSummary> {
        self.drain_summaries(Some((federation.0, account.0))).0
    }

    /// The last three operations across every federation, oldest first —
    /// the synchronous initial value for the recent-payments list, so its
    /// first frame renders the truth; `subscribe_recent_operations` then
    /// carries every change.
    #[frb(sync)]
    pub fn recent_operations(&self) -> Vec<OperationSummary> {
        self.drain_summaries(None)
            .0
            .into_iter()
            .rev()
            .take(3)
            .rev()
            .collect()
    }

    /// Drain the full event log into summaries, returning them with the
    /// log position the drain reached — the tail point a live subscription
    /// continues from. `scope` narrows to one `(federation, account)`;
    /// `None` spans everything.
    fn drain_summaries(
        &self,
        scope: Option<(FederationId, Account)>,
    ) -> (Vec<OperationSummary>, EventLogId) {
        let mut position = EventLogId::LOG_START;
        let mut summaries: Vec<OperationSummary> = Vec::new();

        loop {
            let batch = self.client.get_event_log(position, 1000);

            for entry in &batch {
                if let Some(scope) = scope
                    && (entry.1.federation, entry.1.account) != scope
                {
                    continue;
                }
                let fiat = self
                    .db
                    .begin_read()
                    .get(&OperationFiat, &entry.1.operation)
                    .map(|snapshot| (snapshot.0, f64::from_bits(snapshot.1)));
                if let Some(summary) = parse_summary(&entry.1, fiat) {
                    summaries.push(summary);
                }
            }

            position = position.saturating_add(batch.len() as u64);

            if batch.len() < 1000 {
                break;
            }
        }

        (summaries, position)
    }

    /// Live ordered list of operation summaries (newest first) across
    /// every federation. Emits once after the historical replay
    /// completes, then re-emits whenever a new trigger event lands.
    /// Follow-up events that only change live status do not re-emit —
    /// those reach the UI through `subscribe_payment_events` when the
    /// user opens the drawer.
    #[frb]
    pub async fn subscribe_recent_operations(&self, sink: StreamSink<Vec<OperationSummary>>) {
        // Phase 1: drain history. Still emitted despite the widget seeding
        // itself synchronously via `recent_operations` — an event landing
        // between that seed and this drain would otherwise sit unemitted
        // until the next one after it.
        let (drained, mut position) = self.drain_summaries(None);

        let mut summaries: Vec<OperationSummary> =
            drained.into_iter().rev().take(3).rev().collect();

        if sink.add(summaries.clone()).is_err() {
            return;
        }

        // Phase 2: tail live events.
        let notify: Arc<Notify> = self.client.event_notify();

        loop {
            let notified = notify.notified();

            let batch = self.client.get_event_log(position, 1000);

            for entry in &batch {
                // Price each new payment as we observe it, so the summary we
                // emit already carries its fiat value rather than gaining it
                // only on a later restart.
                let fiat = if is_summary_trigger(&entry.1) {
                    snapshot_fiat(&self.db, &self.exchange_rate_cache, &entry.1.operation)
                } else {
                    None
                };
                if let Some(summary) = parse_summary(&entry.1, fiat) {
                    summaries.push(summary);
                }
            }

            if sink.add(summaries.clone()).is_err() {
                return;
            }

            position = position.saturating_add(batch.len() as u64);

            if batch.len() < 1000 {
                notified.await;
            }
        }
    }

    /// Live tail of every picomint event for a single operation, parsed
    /// into the rich [`PaymentEvent`] enum for the details drawer timeline.
    /// Replays existing events first (oldest → newest) then yields new
    /// ones as they're committed. Operation ids are globally unique so
    /// no federation context is required — reads the daemon-wide eventlog
    /// directly.
    #[frb]
    pub async fn subscribe_payment_events(
        &self,
        operation: &OperationIdWrapper,
        sink: StreamSink<PaymentEvent>,
    ) {
        let mut stream = self.client.subscribe_operation_events(operation.0);

        while let Some(entry) = stream.next().await {
            let Some(event) = parse_payment_event(&entry) else {
                continue;
            };
            if sink.add(event).is_err() {
                break;
            }
        }
    }

    /// Whether any picomint state machine is still driving the operation —
    /// the synchronous initial value for the payment-card spinner, so the
    /// first frame renders the truth instead of a guess.
    #[frb(sync)]
    pub fn operation_is_active(
        &self,
        federation: &FederationIdWrapper,
        operation: &OperationIdWrapper,
    ) -> bool {
        self.client.operation_is_active(federation.0, operation.0)
    }

    /// Resolves once no picomint state machine is still driving the
    /// operation — immediately for settled or unknown ones. Backs the
    /// in-progress spinner on payment cards; the outcome itself arrives
    /// through `subscribe_payment_events`.
    #[frb]
    pub async fn subscribe_completion(
        &self,
        federation: &FederationIdWrapper,
        operation: &OperationIdWrapper,
    ) {
        self.client
            .subscribe_completion(federation.0, operation.0)
            .await;
    }

    /// Toast/haptic stream — fires per matching event committed after
    /// the historical replay. Spans every federation, since the picomint
    /// eventlog is daemon-wide.
    #[frb]
    pub async fn subscribe_notifications(&self, sink: StreamSink<Notification>) {
        // Phase 1: drain history to find the live position. No
        // notifications fire — these are old events.
        let mut position = EventLogId::LOG_START;

        loop {
            let batch = self.client.get_event_log(position, 1000);

            position = position.saturating_add(batch.len() as u64);

            if batch.len() < 1000 {
                break;
            }
        }

        // Phase 2: tail live events; every match fires a notification.
        let notify: Arc<Notify> = self.client.event_notify();

        loop {
            let notified = notify.notified();

            let batch = self.client.get_event_log(position, 1000);

            for entry in &batch {
                if let Some(notification) = parse_notification(&entry.1) {
                    if sink.add(notification).is_err() {
                        return;
                    }
                }
            }

            position = position.saturating_add(batch.len() as u64);

            if batch.len() < 1000 {
                notified.await;
            }
        }
    }

    #[frb(sync)]
    pub fn save_contact(&self, lnurl: &LnurlWrapper, name: &str) {
        let dbtx = self.db.begin_write();

        dbtx.insert(&CONTACT, &lnurl.0, &name.to_string());

        dbtx.commit();
    }

    #[frb(sync)]
    pub fn get_contact_name(&self, lnurl: &LnurlWrapper) -> Option<String> {
        self.db.begin_read().get(&CONTACT, &lnurl.0)
    }

    #[frb(sync)]
    pub fn list_contacts(&self) -> Vec<PicoContact> {
        let mut contacts: Vec<_> = self.db.begin_read().iter(&CONTACT, |it| {
            it.map(|(lnurl, name)| PicoContact {
                lnurl: LnurlWrapper(lnurl),
                name,
            })
            .collect()
        });

        contacts.sort_by_key(|c| c.name.to_lowercase());

        contacts
    }

    #[frb(sync)]
    pub fn delete_contact(&self, lnurl: &LnurlWrapper) {
        let dbtx = self.db.begin_write();

        dbtx.remove(&CONTACT, &lnurl.0);

        dbtx.commit();
    }
}

/// Snapshot the live exchange rate against a freshly-observed trigger event,
/// returning the stored `(currency, rate)`. Idempotent write-if-absent: returns
/// an existing snapshot untouched, otherwise reads the selected currency and
/// the cached rate (never fetches) and persists it. `None` — and no write —
/// when no fresh rate is cached or the feed lacks this currency's pair, so the
/// operation falls back to sats. Call only for live trigger events; historical
/// ones predate the session and stay unpriced.
fn snapshot_fiat(
    db: &Database,
    cache: &ExchangeRateCache,
    op: &OperationId,
) -> Option<(String, f64)> {
    if let Some(existing) = db.begin_read().get(&OperationFiat, op) {
        return Some((existing.0, f64::from_bits(existing.1)));
    }

    let currency = db
        .begin_read()
        .get(&SelectedCurrency, &())
        .unwrap_or_else(|| "USD".to_string());

    // Derive the selected currency's rate from the cached map without hitting
    // the network; bail (sats fallback) when nothing fresh is cached or the
    // feed lacks this currency's pair.
    let rate = {
        let guard = cache.try_lock().ok()?;
        let (prices, timestamp) = guard.as_ref()?;
        if timestamp.elapsed() >= FRESHNESS {
            return None;
        }
        btc_price(prices, &currency)?
    };

    let dbtx = db.begin_write();
    dbtx.insert(&OperationFiat, op, &(currency.clone(), rate.to_bits()));
    dbtx.commit();

    Some((currency, rate))
}

async fn bind_endpoint() -> anyhow::Result<Endpoint> {
    Endpoint::builder(N0)
        .address_lookup(MdnsAddressLookup::builder())
        .bind()
        .await
        .map_err(|e| anyhow::anyhow!(e.to_string()))
}
