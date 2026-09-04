//! Pico's app-level database tables. Everything mint-scoped lives in
//! tables owned by `picomint_client::Client` (config, notes, state machines,
//! the daemon-wide event log) — what remains here is app state the client
//! has no concept of.

use picomint_core::core::OperationId;
use picomint_redb::table;

table!(
    RootEntropy,
    () => Vec<u8>,
    "root-entropy",
);

table!(
    SelectedCurrency,
    () => String,
    "selected-currency",
);

// Exchange rate snapshotted against an operation when its trigger event is
// first observed live, so history can show the fiat value as of the time of
// the payment. `(currency_code, btc_price)`, the price as `f64::to_bits` —
// consensus encoding has no float impl, and the bit pattern round-trips
// exactly. Absent for operations that predate the feature or landed with no
// fresh rate cached.
table!(
    OperationFiat,
    OperationId => (String, u64),
    "operation-fiat",
);

table!(
    CONTACT,
    String => String,
    "contact",
);
