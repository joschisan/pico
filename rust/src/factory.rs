use std::collections::{BTreeMap, HashMap, HashSet};
use std::str::FromStr;
use std::sync::Arc;

use flutter_rust_bridge::frb;
use futures::StreamExt;
use futures::stream::{self, BoxStream};
use iroh::Endpoint;
use iroh::endpoint::presets::N0;
use iroh_mdns_address_lookup::MdnsAddressLookup;
use picomint_client::{Client, Mnemonic, OperationId, download};
use picomint_core::bitcoin::hashes::sha256;
use picomint_core::config::FederationId;
use picomint_eventlog::EventLogId;
use picomint_redb::Database;
use tokio::sync::{Mutex, Notify, RwLock};

use crate::client::PicoClient;
use crate::db::{CLIENT_CONFIG, CONTACT, ROOT_ENTROPY, SELECTED_CURRENCY};
use crate::events::{
    Notification, OperationSummary, PaymentEvent, parse_notification, parse_payment_event,
    parse_summary,
};
use crate::frb_generated::StreamSink;
use crate::lnurl::LnurlWrapper;
use crate::{DatabaseWrapper, InviteCodeWrapper, MnemonicWrapper};

#[frb(opaque)]
pub struct PicoClientFactory {
    db: Database,
    mnemonic: Mnemonic,
    /// Single iroh endpoint shared across all per-federation clients.
    /// Address grinding is the slowest part of bringup so we bind once
    /// at factory construction and reuse for every `Client::new`.
    endpoint: Endpoint,
    /// All warm clients, keyed by `FederationId`. Constructed at startup
    /// from `CLIENT_CONFIG`; `join` / `recover` insert, `leave` removes.
    /// Re-joining a previously-left federation reuses the same key —
    /// `Client::wipe` clears the per-federation isolated tables on
    /// leave, so the second join sees a clean state.
    clients: Arc<RwLock<BTreeMap<FederationId, PicoClient>>>,
    /// Wakes anyone iterating the client set when membership changes.
    /// `notify_waiters` is fire-and-forget; subscribers re-snapshot the
    /// map after waking.
    set_changed: Arc<Notify>,
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

        dbtx.insert(&ROOT_ENTROPY, &(), &mnemonic.0.to_entropy().to_vec());

        dbtx.commit();

        let endpoint = bind_endpoint().await.map_err(|e| e.to_string())?;

        Self::assemble(db.0.clone(), mnemonic.0.clone(), endpoint).await
    }

    #[frb]
    pub async fn try_load(db: &DatabaseWrapper) -> Option<Self> {
        let entropy = db.0.begin_read().get(&ROOT_ENTROPY, &())?;

        let mnemonic = Mnemonic::from_entropy(&entropy).ok()?;

        let endpoint = bind_endpoint().await.ok()?;

        Self::assemble(db.0.clone(), mnemonic, endpoint).await.ok()
    }

    /// Build the factory and warm every persisted federation into a
    /// ready-to-use `PicoClient`. Each `Client::new` here re-runs the
    /// per-federation handshake; doing them in parallel keeps cold
    /// startup time bounded by the slowest peer rather than their sum.
    async fn assemble(
        db: Database,
        mnemonic: Mnemonic,
        endpoint: Endpoint,
    ) -> Result<Self, String> {
        let entries: Vec<(FederationId, picomint_core::config::ConsensusConfig)> =
            db.begin_read().iter(&CLIENT_CONFIG, |it| it.collect());

        let currency_code = db
            .begin_read()
            .get(&SELECTED_CURRENCY, &())
            .unwrap_or_else(|| "USD".to_string());

        let mut warmed: BTreeMap<FederationId, PicoClient> = BTreeMap::new();
        for (fed_id, config) in entries {
            let isolated = db.isolate(fed_id);

            let client = Client::new(endpoint.clone(), isolated, &mnemonic, config)
                .await
                .map_err(|e| e.to_string())?;

            warmed.insert(
                fed_id,
                build_pico_client(client, fed_id, currency_code.clone()).await,
            );
        }

        Ok(Self {
            db,
            mnemonic,
            endpoint,
            clients: Arc::new(RwLock::new(warmed)),
            set_changed: Arc::new(Notify::new()),
        })
    }

    #[frb]
    pub async fn seed_phrase(&self) -> Vec<String> {
        self.mnemonic.words().map(|s| s.to_string()).collect()
    }

    /// Snapshot of every warm client. Cheap (`PicoClient: Clone`) — the
    /// inner `Arc<Client>` is shared, so callers all see the same
    /// connection state.
    #[frb]
    pub async fn clients(&self) -> Vec<PicoClient> {
        self.clients.read().await.values().cloned().collect()
    }

    /// Look up a single warm client by federation id. `None` if the user
    /// has since left — used by the payment-details drawer to display
    /// historical ecash without a cancel option when the federation is
    /// no longer joined.
    #[frb]
    pub async fn client(&self, federation_id: &str) -> Option<PicoClient> {
        let id = FederationId::from_str(federation_id).ok()?;
        self.clients.read().await.get(&id).cloned()
    }

    #[frb]
    pub async fn join(&self, invite: &InviteCodeWrapper) -> Result<PicoClient, String> {
        let config = download(&self.endpoint, &invite.0)
            .await
            .map_err(|e| e.to_string())?;

        let federation_id = config.calculate_federation_id();

        if let Some(existing) = self.clients.read().await.get(&federation_id) {
            return Ok(existing.clone());
        }

        let dbtx = self.db.begin_write();
        dbtx.insert(&CLIENT_CONFIG, &federation_id, &config);
        dbtx.commit();

        let isolated = self.db.isolate(federation_id);

        let client = Client::new(self.endpoint.clone(), isolated, &self.mnemonic, config)
            .await
            .map_err(|e| e.to_string())?;

        let pico = build_pico_client(client, federation_id, self.currency().await).await;

        self.clients
            .write()
            .await
            .insert(federation_id, pico.clone());
        self.set_changed.notify_waiters();

        Ok(pico)
    }

    #[frb]
    pub async fn recover(&self, invite: &InviteCodeWrapper) -> Result<PicoClient, String> {
        let config = download(&self.endpoint, &invite.0)
            .await
            .map_err(|e| e.to_string())?;

        let federation_id = config.calculate_federation_id();

        if let Some(existing) = self.clients.read().await.get(&federation_id) {
            return Ok(existing.clone());
        }

        // Persist the config AND seed the per-federation RECOVERY row in
        // one atomic commit so `Client::new` reliably picks the recovery
        // row up via `MintClientModule::new`.
        let dbtx = self.db.begin_write();

        dbtx.insert(&CLIENT_CONFIG, &federation_id, &config);

        Client::init_recovery(&dbtx.as_ref().isolate(federation_id));

        dbtx.commit();

        let isolated = self.db.isolate(federation_id);

        let client = Client::new(self.endpoint.clone(), isolated, &self.mnemonic, config)
            .await
            .map_err(|e| e.to_string())?;

        let pico = build_pico_client(client, federation_id, self.currency().await).await;

        self.clients
            .write()
            .await
            .insert(federation_id, pico.clone());
        self.set_changed.notify_waiters();

        Ok(pico)
    }

    #[frb]
    pub async fn set_currency(&self, currency_code: &str) {
        let dbtx = self.db.begin_write();

        dbtx.insert(&SELECTED_CURRENCY, &(), &currency_code.to_string());

        dbtx.commit();
    }

    #[frb]
    pub async fn get_currency(&self) -> String {
        self.currency().await
    }

    async fn currency(&self) -> String {
        self.db
            .begin_read()
            .get(&SELECTED_CURRENCY, &())
            .unwrap_or_else(|| "USD".to_string())
    }

    /// Drop a federation: shut down the client, wipe its isolated
    /// per-federation tables, then drop the config row. Wipe + remove
    /// share a single write tx so a crash mid-leave can never leave
    /// orphan client state behind a missing config row. Re-joining the
    /// same federation later starts from a fresh ledger.
    #[frb]
    pub async fn leave(&self, federation_id: &str) -> Result<(), String> {
        let fed_id = FederationId::from_str(federation_id).map_err(|e| e.to_string())?;

        let Some(client) = self.clients.write().await.remove(&fed_id) else {
            return Ok(());
        };

        client.client.shutdown().await;

        let dbtx = self.db.begin_write();
        client.client.wipe(&dbtx.as_ref().isolate(fed_id));
        dbtx.remove(&CLIENT_CONFIG, &fed_id);
        dbtx.commit();

        self.set_changed.notify_waiters();
        Ok(())
    }

    /// Live snapshot of every warm client; re-emits on every set change
    /// (`join`/`leave`/`recover`). Subscribers re-render passively
    /// instead of re-fetching `clients()` after each navigation pop.
    #[frb]
    pub async fn subscribe_clients(&self, sink: StreamSink<Vec<PicoClient>>) {
        loop {
            let snapshot: Vec<PicoClient> = self.clients.read().await.values().cloned().collect();
            let set_changed = self.set_changed.notified();
            tokio::pin!(set_changed);
            if sink.add(snapshot).is_err() {
                return;
            }
            set_changed.await;
        }
    }

    /// Aggregated balance across every warm client, in sats. Re-emits on
    /// any per-client balance change AND on client-set changes
    /// (`join`/`leave`/`recover`). The totals map survives rebuilds so a
    /// join/leave doesn't reset the running sum to zero.
    #[frb]
    pub async fn subscribe_global_balance(&self, sink: StreamSink<i64>) {
        let mut totals: HashMap<FederationId, i64> = HashMap::new();

        loop {
            // Snapshot the live client set; build a tagged stream per
            // client so we can attribute incoming balances back to a
            // federation and discard departed clients on the next rebuild.
            let snapshot: Vec<(FederationId, PicoClient)> = self
                .clients
                .read()
                .await
                .iter()
                .map(|(k, v)| (*k, v.clone()))
                .collect();

            let alive: HashSet<FederationId> = snapshot.iter().map(|(k, _)| *k).collect();
            totals.retain(|fed, _| alive.contains(fed));

            let mut tagged: Vec<BoxStream<'static, (FederationId, i64)>> =
                Vec::with_capacity(snapshot.len());
            for (fed_id, client) in snapshot {
                let stream = client
                    .client
                    .subscribe_balance_changes()
                    .await
                    .map(move |amt| (fed_id, (amt.msats / 1000) as i64));
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
                    Some((fed_id, balance)) = merged.next() => {
                        totals.insert(fed_id, balance);
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
        let names = self.federation_names_snapshot().await;
        let mut position = EventLogId::LOG_START;
        let mut summaries: Vec<OperationSummary> = Vec::new();

        loop {
            let batch = picomint_eventlog::get_event_log(&self.db, position, 1000);

            for entry in &batch {
                if let Some(summary) = parse_summary(&entry.1, &names) {
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
        let names = self.federation_names_snapshot().await;

        loop {
            let batch = picomint_eventlog::get_event_log(&self.db, position, 1000);

            for entry in &batch {
                if let Some(summary) = parse_summary(&entry.1, &names) {
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
        let notify: Arc<Notify> = picomint_eventlog::event_notify(&self.db);

        loop {
            let notified = notify.notified();

            let batch = picomint_eventlog::get_event_log(&self.db, position, 1000);
            let names = self.federation_names_snapshot().await;

            for entry in &batch {
                if let Some(summary) = parse_summary(&entry.1, &names) {
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

    /// Snapshot of currently-warm federation ids → names. Used to
    /// resolve `OperationSummary.federation_name` at parse time.
    async fn federation_names_snapshot(&self) -> BTreeMap<FederationId, String> {
        self.clients
            .read()
            .await
            .iter()
            .map(|(id, c)| (*id, c.federation_name.clone()))
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

        let notify = picomint_eventlog::event_notify(&self.db);
        let mut stream =
            picomint_eventlog::subscribe_operation_events(self.db.clone(), notify, op).boxed();

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
            let batch = picomint_eventlog::get_event_log(&self.db, position, 1000);

            position = position.saturating_add(batch.len() as u64);

            if batch.len() < 1000 {
                break;
            }
        }

        // Phase 2: tail live events; every match fires a notification.
        let notify: Arc<Notify> = picomint_eventlog::event_notify(&self.db);

        loop {
            let notified = notify.notified();

            let batch = picomint_eventlog::get_event_log(&self.db, position, 1000);

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

async fn build_pico_client(
    client: Arc<Client>,
    federation_id: FederationId,
    currency_code: String,
) -> PicoClient {
    let federation_name = client.config().await.name;
    PicoClient {
        client,
        federation_id,
        federation_name,
        currency_code,
        exchange_rate_cache: Arc::new(Mutex::new(None)),
    }
}

async fn bind_endpoint() -> anyhow::Result<Endpoint> {
    Endpoint::builder(N0)
        .address_lookup(MdnsAddressLookup::builder())
        .bind()
        .await
        .map_err(|e| anyhow::anyhow!(e.to_string()))
}
