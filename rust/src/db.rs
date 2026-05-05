//! Pico's app-level redb tables, kept on the root (un-isolated) handle.
//! Per-federation client state lives in `db.isolate(...)` namespaces below
//! these and is owned entirely by `picomint_client::Client`.

use std::fmt;

use bitcoin::hex::DisplayHex;
use picomint_core::config::ConsensusConfig;
use picomint_encoding::{Decodable, Encodable};
use picomint_redb::{consensus_key, table};

/// Random 16-byte handle for a single joined-federation entry. We key the
/// per-client redb namespace on this rather than `FederationId` so that
/// leaving and re-joining the same federation gives a fresh, isolated
/// client state — no leftover note secrets, recovery rows, or eventlog.
#[derive(Debug, Clone, Copy, Eq, PartialEq, Hash, Encodable, Decodable)]
pub struct NamespaceId(pub [u8; 16]);

consensus_key!(NamespaceId);

impl NamespaceId {
    pub fn random() -> Self {
        Self(rand::random())
    }
}

impl fmt::Display for NamespaceId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.0.as_hex())
    }
}

table!(
    ROOT_ENTROPY,
    () => Vec<u8>,
    "root-entropy",
);

table!(
    CLIENT_CONFIG,
    NamespaceId => ConsensusConfig,
    "client-config",
);

table!(
    SELECTED_CURRENCY,
    () => String,
    "selected-currency",
);

table!(
    CONTACT,
    String => String,
    "contact",
);
