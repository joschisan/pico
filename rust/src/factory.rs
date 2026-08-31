use std::collections::{BTreeMap, HashMap, HashSet};
use std::str::FromStr;
use std::sync::Arc;

use flutter_rust_bridge::frb;
use futures::StreamExt;
use futures::stream::{self, BoxStream};
use iroh::Endpoint;
use iroh::endpoint::presets::N0;
use iroh_mdns_address_lookup::MdnsAddressLookup;
use picomint_client::{Account, Client, Mnemonic, OperationId};
use picomint_core::bitcoin::hashes::sha256;
use picomint_core::config::FederationId;
use picomint_eventlog::EventLogId;
use picomint_sqlite::{Database, DbRead};
use tokio::sync::{Mutex, Notify};

use crate::client::PicoClient;
use crate::db::{CONTACT, OperationFiat, RootEntropy, SelectedCurrency};
use crate::events::{
    Notification, OperationSummary, PaymentEvent, is_summary_trigger, parse_notification,
    parse_payment_event, parse_summary,
};
use crate::exchange::{ExchangeRateCache, FRESHNESS, btc_price};
use crate::frb_generated::StreamSink;
use crate::lnurl::LnurlWrapper;
use crate::{DatabaseWrapper, InviteCodeWrapper, MnemonicWrapper};

#[frb(opaque)]
pub struct PicoClientFactory {
    db: Database,
    mnemonic: Mnemonic,
    /// The one picomint client, holding every joined federation as data.
    /// It owns the shared iroh endpoint, the federation configs and the
    /// daemon-wide event log; every operation names the federation it
    /// acts on. There is no handle map to keep in sync — a [`PicoClient`]
    /// is a pure derivation of `(federation, account)` plus the shared
    /// handles, built on demand from the client's joined set.
    client: Arc<Client>,
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

impl PicoClientFactory {
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

    /// The `(federation, account)` handle Dart holds: the shared client plus
    /// the pair every money method passes back down, derived fresh — nothing
    /// in it lives anywhere but here and the client's own tables.
    fn handle(&self, federation_id: FederationId, account: Account, name: String) -> PicoClient {
        PicoClient {
            client: self.client.clone(),
            federation_id,
            account,
            federation_name: name,
            db: self.db.clone(),
            exchange_rate_cache: self.exchange_rate_cache.clone(),
        }
    }

    /// One handle per `(federation, account)` pair, federation-major and
    /// account-minor — the order the home pager swipes in.
    fn handles(&self) -> Vec<PicoClient> {
        self.client
            .federation_configs()
            .into_iter()
            .flat_map(|entry| {
                Account::USER_ACCOUNTS
                    .into_iter()
                    .map(move |account| (entry.0, account, entry.1.name.clone()))
            })
            .map(|entry| self.handle(entry.0, entry.1, entry.2))
            .collect()
    }

    #[frb]
    pub async fn seed_phrase(&self) -> Vec<String> {
        self.mnemonic.words().map(|s| s.to_string()).collect()
    }

    /// A handle for every joined `(federation, account)` pair. All share the
    /// one inner `Arc<Client>`, so callers all see the same connection state.
    #[frb]
    pub async fn clients(&self) -> Vec<PicoClient> {
        self.handles()
    }

    /// Look up a federation's [`Account::PRIMARY`] client. `None` if the user
    /// isn't joined to it, which is how the ecash drawer tells a bundle from
    /// a mint the wallet doesn't have.
    ///
    /// Primary because a caller reaching for this holds a federation id and
    /// nothing more — an ecash bundle names no account. It is the fallback,
    /// not the usual path: the drawer receives into the account on screen
    /// when the bundle belongs to its federation, and only asks here when it
    /// doesn't.
    #[frb]
    pub async fn client(&self, federation_id: &str) -> Option<PicoClient> {
        let id = FederationId::from_str(federation_id).ok()?;

        let config = self.client.config(id)?;

        Some(self.handle(id, Account::PRIMARY, config.name))
    }

    /// Adds a federation, rebuilding whatever this seed already owns there.
    ///
    /// One path, whether or not the seed has been here before: `join` scans
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
    pub async fn join(&self, invite: &InviteCodeWrapper) -> Result<PicoClient, String> {
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
        // account the pager lands on, and the only one a screen holding a
        // single client can mean.
        Ok(self.handle(federation_id, Account::PRIMARY, config.name))
    }

    #[frb]
    pub async fn set_currency(&self, currency_code: &str) {
        let dbtx = self.db.begin_write();

        dbtx.insert(&SelectedCurrency, &(), &currency_code.to_string());

        dbtx.commit();
    }

    #[frb]
    pub async fn get_currency(&self) -> String {
        self.currency().await
    }

    async fn currency(&self) -> String {
        self.db
            .begin_read()
            .get(&SelectedCurrency, &())
            .unwrap_or_else(|| "USD".to_string())
    }

    /// Drop a federation: `Client::remove` shuts its runtime down, then
    /// wipes its rows and drops its config in one dbtx, so a crash
    /// mid-leave can never leave orphan client state behind a missing
    /// config row. Re-joining the same federation later starts from a
    /// fresh ledger.
    #[frb]
    pub async fn leave(&self, federation_id: &str) -> Result<(), String> {
        let fed_id = FederationId::from_str(federation_id).map_err(|e| e.to_string())?;

        // A federation that is already gone is a leave that already
        // succeeded, not an error to surface — the drawer may fire twice.
        if self.client.config(fed_id).is_none() {
            return Ok(());
        }

        // Every account goes at once — accounts are a split of one
        // federation's client state, not something a user joins or leaves
        // individually.
        self.client
            .remove(fed_id)
            .await
            .map_err(|e| e.to_string())?;

        self.set_changed.notify_waiters();
        Ok(())
    }

    /// Live snapshot of every joined federation's handles; re-emits on every
    /// set change (`join`/`leave`). Subscribers re-render passively
    /// instead of re-fetching `clients()` after each navigation pop.
    #[frb]
    pub async fn subscribe_clients(&self, sink: StreamSink<Vec<PicoClient>>) {
        loop {
            let snapshot = self.handles();
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
    /// (`join`/`leave`). The totals map survives rebuilds so a
    /// join/leave doesn't reset the running sum to zero.
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
            // initial sum, so a join/leave landing between the snapshot
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

    /// One-shot list of every operation across every federation in
    /// chronological order (oldest first — Dart reverses for display).
    /// Cards rendered from this snapshot stay static; live status is
    /// reachable only by opening the per-op drawer.
    #[frb]
    pub async fn list_operations(&self) -> Vec<OperationSummary> {
        let names = self.federation_names_snapshot();
        let mut position = EventLogId::LOG_START;
        let mut summaries: Vec<OperationSummary> = Vec::new();

        loop {
            let batch = self.client.get_event_log(position, 1000);

            for entry in &batch {
                let fiat = self
                    .db
                    .begin_read()
                    .get(&OperationFiat, &entry.1.operation)
                    .map(|snapshot| (snapshot.0, f64::from_bits(snapshot.1)));
                if let Some(summary) = parse_summary(&entry.1, &names, fiat) {
                    summaries.push(summary);
                }
            }

            position = position.saturating_add(batch.len() as u64);

            if batch.len() < 1000 {
                break;
            }
        }

        summaries
    }

    /// Live ordered list of operation summaries (newest first) across
    /// every federation. Emits once after the historical replay
    /// completes, then re-emits whenever a new trigger event lands.
    /// Follow-up events that only change live status do not re-emit —
    /// those reach the UI through `subscribe_payment_events` when the
    /// user opens the drawer.
    #[frb]
    pub async fn subscribe_recent_operations(&self, sink: StreamSink<Vec<OperationSummary>>) {
        // Phase 1: drain history into the full summaries vector. No emits.
        let mut summaries: Vec<OperationSummary> = Vec::new();
        let mut position = EventLogId::LOG_START;
        let names = self.federation_names_snapshot();

        loop {
            let batch = self.client.get_event_log(position, 1000);

            for entry in &batch {
                let fiat = self
                    .db
                    .begin_read()
                    .get(&OperationFiat, &entry.1.operation)
                    .map(|snapshot| (snapshot.0, f64::from_bits(snapshot.1)));
                if let Some(summary) = parse_summary(&entry.1, &names, fiat) {
                    summaries.push(summary);
                }
            }

            position = position.saturating_add(batch.len() as u64);

            if batch.len() < 1000 {
                break;
            }
        }

        summaries = summaries.into_iter().rev().take(3).rev().collect();

        if sink.add(summaries.clone()).is_err() {
            return;
        }

        // Phase 2: tail live events. Re-snapshot names per batch so a
        // newly-joined federation's name lands on its own first event.
        let notify: Arc<Notify> = self.client.event_notify();

        loop {
            let notified = notify.notified();

            let batch = self.client.get_event_log(position, 1000);
            let names = self.federation_names_snapshot();

            for entry in &batch {
                // Price each new payment as we observe it, so the summary we
                // emit already carries its fiat value rather than gaining it
                // only on a later restart.
                let fiat = if is_summary_trigger(&entry.1) {
                    snapshot_fiat(&self.db, &self.exchange_rate_cache, &entry.1.operation)
                } else {
                    None
                };
                if let Some(summary) = parse_summary(&entry.1, &names, fiat) {
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

    /// Snapshot of joined federation ids → names. Used to resolve
    /// `OperationSummary.federation_name` at parse time.
    fn federation_names_snapshot(&self) -> BTreeMap<FederationId, String> {
        self.client
            .federation_configs()
            .into_iter()
            .map(|entry| (entry.0, entry.1.name))
            .collect()
    }

    /// Live tail of every picomint event for a single operation, parsed
    /// into the rich [`PaymentEvent`] enum for the details drawer timeline.
    /// Replays existing events first (oldest → newest) then yields new
    /// ones as they're committed. Silently exits if `operation_id` doesn't
    /// parse as a valid sha256 hash. Operation ids are globally unique so
    /// no federation context is required — reads the daemon-wide eventlog
    /// directly.
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

    #[frb]
    pub async fn save_contact(&self, lnurl: &LnurlWrapper, name: &str) {
        let dbtx = self.db.begin_write();

        dbtx.insert(&CONTACT, &lnurl.0, &name.to_string());

        dbtx.commit();
    }

    #[frb]
    pub async fn get_contact_name(&self, lnurl: &LnurlWrapper) -> Option<String> {
        self.db.begin_read().get(&CONTACT, &lnurl.0)
    }

    #[frb]
    pub async fn list_contacts(&self) -> Vec<PicoContact> {
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

    #[frb]
    pub async fn delete_contact(&self, lnurl: &LnurlWrapper) {
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
