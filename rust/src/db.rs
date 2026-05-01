//! Pico's app-level redb tables, kept on the root (un-isolated) handle.
//! Per-federation client state lives in `db.isolate(...)` namespaces below
//! these and is owned entirely by `picomint_client::Client`.

use picomint_core::config::FederationId;
use picomint_encoding::{Decodable, Encodable};
use picomint_redb::{consensus_value, table};

/// Encoded byte blob — used as the value type for tables whose payload
/// would otherwise reference a foreign Rust type that flutter_rust_bridge
/// can't generate Dart bindings for. Callers consensus-encode/decode at
/// the boundary.
#[derive(Debug, Clone, Encodable, Decodable)]
pub(crate) struct Blob {
    pub(crate) bytes: Vec<u8>,
}

consensus_value!(Blob);

table!(
    ROOT_ENTROPY,
    () => Blob,
    "root-entropy",
);

table!(
    CLIENT_CONFIG,
    FederationId => Blob,
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
