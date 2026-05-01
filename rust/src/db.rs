//! Pico's app-level redb tables, kept on the root (un-isolated) handle.
//! Per-federation client state lives in `db.isolate(...)` namespaces below
//! these and is owned entirely by `picomint_client::Client`.

use picomint_core::config::{ConsensusConfig, FederationId};
use picomint_redb::table;

table!(
    ROOT_ENTROPY,
    () => Vec<u8>,
    "root-entropy",
);

table!(
    CLIENT_CONFIG,
    FederationId => ConsensusConfig,
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
