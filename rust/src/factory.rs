use std::str::FromStr;
use std::sync::Arc;

use flutter_rust_bridge::frb;
use iroh::Endpoint;
use iroh::address_lookup::MdnsAddressLookup;
use iroh::endpoint::presets::N0;
use picomint_client::{Client, Mnemonic, download};
use picomint_core::config::FederationId;
use picomint_core::invite::InviteCode;
use picomint_redb::Database;
use tokio::sync::Mutex;

use crate::client::PicoClient;
use crate::db::{CLIENT_CONFIG, CONTACT, ROOT_ENTROPY, SELECTED_CURRENCY};
use crate::lnurl::LnurlWrapper;
use crate::{DatabaseWrapper, InviteCodeWrapper, MnemonicWrapper};

#[frb]
pub struct PicoClientFactory {
    db: Database,
    mnemonic: Mnemonic,
    /// Single iroh endpoint shared across all per-federation clients.
    /// Address grinding is the slowest part of bringup so we bind once
    /// at factory construction and reuse for every `Client::new`.
    endpoint: Endpoint,
}

#[frb]
pub struct FederationInfo {
    pub id: String,
    pub name: String,
    pub invite: String,
}

impl FederationInfo {
    pub(crate) fn new(id: FederationId, config: &picomint_core::config::ConsensusConfig) -> Self {
        let name = config.name.clone();

        let (_, peer_endpoint) = config
            .peers
            .iter()
            .next()
            .expect("federation has at least one peer");

        let invite = picomint_base32::encode(&InviteCode::new(peer_endpoint.iroh_pk, id));

        Self {
            id: id.to_string(),
            name,
            invite,
        }
    }
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

        Ok(Self {
            db: db.0.clone(),
            mnemonic: mnemonic.0.clone(),
            endpoint,
        })
    }

    #[frb]
    pub async fn try_load(db: &DatabaseWrapper) -> Option<Self> {
        let entropy = db.0.begin_read().get(&ROOT_ENTROPY, &())?;

        let mnemonic = Mnemonic::from_entropy(&entropy).ok()?;

        let endpoint = bind_endpoint().await.ok()?;

        Some(Self {
            db: db.0.clone(),
            mnemonic,
            endpoint,
        })
    }

    #[frb]
    pub async fn seed_phrase(&self) -> Vec<String> {
        self.mnemonic.words().map(|s| s.to_string()).collect()
    }

    #[frb]
    pub async fn join(&self, invite: &InviteCodeWrapper) -> Result<PicoClient, String> {
        if let Some(client) = self.load_typed(invite.0.federation_id).await {
            return Ok(client);
        }

        let config = download(&self.endpoint, &invite.0)
            .await
            .map_err(|e| e.to_string())?;

        let federation_id = config.calculate_federation_id();

        let dbtx = self.db.begin_write();

        dbtx.insert(&CLIENT_CONFIG, &federation_id, &config);

        dbtx.commit();

        let isolated = self.db.isolate(federation_id);

        let client = Client::new(self.endpoint.clone(), isolated, &self.mnemonic, config)
            .await
            .map_err(|e| e.to_string())?;

        Ok(self.create_client(client, federation_id).await)
    }

    #[frb]
    pub async fn recover(&self, invite: &InviteCodeWrapper) -> Result<PicoClient, String> {
        if let Some(client) = self.load_typed(invite.0.federation_id).await {
            return Ok(client);
        }

        let config = download(&self.endpoint, &invite.0)
            .await
            .map_err(|e| e.to_string())?;

        let federation_id = config.calculate_federation_id();

        // Persist the config on the root db AND seed the per-federation
        // RECOVERY row in one atomic commit, so `Client::new` reliably
        // picks the recovery row up via `MintClientModule::new`.
        let dbtx = self.db.begin_write();

        dbtx.insert(&CLIENT_CONFIG, &federation_id, &config);

        Client::init_recovery(&dbtx.as_ref().isolate(federation_id), federation_id);

        dbtx.commit();

        let isolated = self.db.isolate(federation_id);

        let client = Client::new(self.endpoint.clone(), isolated, &self.mnemonic, config)
            .await
            .map_err(|e| e.to_string())?;

        Ok(self.create_client(client, federation_id).await)
    }

    #[frb]
    pub async fn load(&self, federation_id: &str) -> Option<PicoClient> {
        let id = FederationId::from_str(federation_id).ok()?;

        self.load_typed(id).await
    }

    async fn load_typed(&self, federation_id: FederationId) -> Option<PicoClient> {
        let config = self.db.begin_read().get(&CLIENT_CONFIG, &federation_id)?;

        let isolated = self.db.isolate(federation_id);

        let client = Client::new(self.endpoint.clone(), isolated, &self.mnemonic, config)
            .await
            .expect("config previously validated; client construction should succeed");

        Some(self.create_client(client, federation_id).await)
    }

    async fn create_client(&self, client: Arc<Client>, federation_id: FederationId) -> PicoClient {
        let currency_code = self
            .db
            .begin_read()
            .get(&SELECTED_CURRENCY, &())
            .unwrap_or_else(|| "USD".to_string());

        PicoClient {
            client,
            federation_id,
            currency_code,
            exchange_rate_cache: Arc::new(Mutex::new(None)),
        }
    }

    #[frb]
    pub async fn list_federations(&self) -> Vec<FederationInfo> {
        self.db.begin_read().iter(&CLIENT_CONFIG, |it| {
            it.map(|(id, config)| FederationInfo::new(id, &config))
                .collect()
        })
    }

    #[frb]
    pub async fn set_currency(&self, currency_code: &str) {
        let dbtx = self.db.begin_write();

        dbtx.insert(&SELECTED_CURRENCY, &(), &currency_code.to_string());

        dbtx.commit();
    }

    #[frb]
    pub async fn get_currency(&self) -> String {
        self.db
            .begin_read()
            .get(&SELECTED_CURRENCY, &())
            .unwrap_or_else(|| "USD".to_string())
    }

    #[frb]
    pub async fn leave(&self, federation_id: &str) {
        let Ok(id) = FederationId::from_str(federation_id) else {
            return;
        };

        // Removes the federation from the top-level registry; the
        // per-federation isolated namespace's tables remain in the file.
        // Picomint-redb doesn't yet expose a "delete prefix" op — when it
        // does, sweep the leftovers here too.
        let dbtx = self.db.begin_write();

        dbtx.remove(&CLIENT_CONFIG, &id);

        dbtx.commit();
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

async fn bind_endpoint() -> anyhow::Result<Endpoint> {
    Endpoint::builder(N0)
        .address_lookup(MdnsAddressLookup::builder())
        .bind()
        .await
        .map_err(|e| anyhow::anyhow!(e.to_string()))
}
