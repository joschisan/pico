use std::collections::{HashMap, HashSet};
use std::sync::Arc;

use flutter_rust_bridge::frb;
use futures::StreamExt;
use futures::stream::{self, BoxStream};
use iroh::Endpoint;
use iroh::address_lookup::MdnsAddressLookup;
use iroh::endpoint::presets::N0;
use picomint_client::{Client, Mnemonic, download};
use picomint_redb::Database;
use tokio::sync::{Mutex, Notify, RwLock};

use crate::client::PicoClient;
use crate::db::{CLIENT_CONFIG, CONTACT, NamespaceId, ROOT_ENTROPY, SELECTED_CURRENCY};
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
    /// All warm clients, keyed by their persistent namespace. The factory
    /// constructs every entry from `CLIENT_CONFIG` at startup; `join` /
    /// `recover` insert, `leave` removes. `subscribe_global_balance` and
    /// any future cross-client iteration read from this map.
    clients: Arc<RwLock<HashMap<NamespaceId, PicoClient>>>,
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

    /// Build the factory and warm every persisted namespace into a
    /// ready-to-use `PicoClient`. Each `Client::new` here re-runs the
    /// per-federation handshake; doing them in parallel keeps cold
    /// startup time bounded by the slowest peer rather than their sum.
    async fn assemble(db: Database, mnemonic: Mnemonic, endpoint: Endpoint) -> Result<Self, String> {
        let entries: Vec<(NamespaceId, picomint_core::config::ConsensusConfig)> =
            db.begin_read().iter(&CLIENT_CONFIG, |it| it.collect());

        let currency_code = db
            .begin_read()
            .get(&SELECTED_CURRENCY, &())
            .unwrap_or_else(|| "USD".to_string());

        let mut warmed: HashMap<NamespaceId, PicoClient> = HashMap::new();
        for (ns, config) in entries {
            let federation_id = config.calculate_federation_id();
            let isolated = db.isolate(ns);

            let client = Client::new(endpoint.clone(), isolated, &mnemonic, config)
                .await
                .map_err(|e| e.to_string())?;

            warmed.insert(
                ns,
                build_pico_client(client, ns, federation_id, currency_code.clone()),
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

    #[frb]
    pub async fn join(&self, invite: &InviteCodeWrapper) -> Result<PicoClient, String> {
        let config = download(&self.endpoint, &invite.0)
            .await
            .map_err(|e| e.to_string())?;

        let federation_id = config.calculate_federation_id();
        let namespace = NamespaceId::random();

        let dbtx = self.db.begin_write();
        dbtx.insert(&CLIENT_CONFIG, &namespace, &config);
        dbtx.commit();

        let isolated = self.db.isolate(namespace);

        let client = Client::new(self.endpoint.clone(), isolated, &self.mnemonic, config)
            .await
            .map_err(|e| e.to_string())?;

        let pico = build_pico_client(client, namespace, federation_id, self.currency().await);

        self.clients.write().await.insert(namespace, pico.clone());
        self.set_changed.notify_waiters();

        Ok(pico)
    }

    #[frb]
    pub async fn recover(&self, invite: &InviteCodeWrapper) -> Result<PicoClient, String> {
        let config = download(&self.endpoint, &invite.0)
            .await
            .map_err(|e| e.to_string())?;

        let federation_id = config.calculate_federation_id();
        let namespace = NamespaceId::random();

        // Persist the config AND seed the per-namespace RECOVERY row in
        // one atomic commit so `Client::new` reliably picks the recovery
        // row up via `MintClientModule::new`.
        let dbtx = self.db.begin_write();

        dbtx.insert(&CLIENT_CONFIG, &namespace, &config);

        Client::init_recovery(&dbtx.as_ref().isolate(namespace), federation_id);

        dbtx.commit();

        let isolated = self.db.isolate(namespace);

        let client = Client::new(self.endpoint.clone(), isolated, &self.mnemonic, config)
            .await
            .map_err(|e| e.to_string())?;

        let pico = build_pico_client(client, namespace, federation_id, self.currency().await);

        self.clients.write().await.insert(namespace, pico.clone());
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

    /// Drop a federation: shuts down its client, removes it from the
    /// in-memory map, and deletes the config row. The per-namespace
    /// isolated tables remain in the file (picomint-redb has no
    /// "delete prefix" yet) but are unreferenced; a future re-join
    /// uses a fresh random namespace, so leftovers can't bleed in.
    #[frb]
    pub async fn leave(&self, namespace: [u8; 16]) {
        let ns = NamespaceId(namespace);

        if let Some(client) = self.clients.write().await.remove(&ns) {
            client.client.shutdown().await;
        }

        let dbtx = self.db.begin_write();
        dbtx.remove(&CLIENT_CONFIG, &ns);
        dbtx.commit();

        self.set_changed.notify_waiters();
    }

    /// Aggregated balance across every warm client, in sats. Re-emits on
    /// any per-client balance change AND on client-set changes
    /// (`join`/`leave`/`recover`). The totals map survives rebuilds so a
    /// join/leave doesn't reset the running sum to zero.
    #[frb]
    pub async fn subscribe_global_balance(&self, sink: StreamSink<i64>) {
        let mut totals: HashMap<NamespaceId, i64> = HashMap::new();

        loop {
            // Snapshot the live client set; build a tagged stream per
            // client so we can attribute incoming balances back to a
            // namespace and discard departed clients on the next rebuild.
            let snapshot: Vec<(NamespaceId, PicoClient)> = self
                .clients
                .read()
                .await
                .iter()
                .map(|(k, v)| (*k, v.clone()))
                .collect();

            let alive: HashSet<NamespaceId> = snapshot.iter().map(|(k, _)| *k).collect();
            totals.retain(|ns, _| alive.contains(ns));

            let mut tagged: Vec<BoxStream<'static, (NamespaceId, i64)>> =
                Vec::with_capacity(snapshot.len());
            for (ns, client) in snapshot {
                let stream = client
                    .client
                    .subscribe_balance_changes()
                    .await
                    .map(move |amt| (ns, (amt.msats / 1000) as i64));
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
                    Some((ns, balance)) = merged.next() => {
                        totals.insert(ns, balance);
                        if sink.add(totals.values().sum()).is_err() {
                            return;
                        }
                    }
                    _ = &mut set_changed => break,
                }
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

fn build_pico_client(
    client: Arc<Client>,
    namespace: NamespaceId,
    federation_id: picomint_core::config::FederationId,
    currency_code: String,
) -> PicoClient {
    PicoClient {
        client,
        namespace,
        federation_id,
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
