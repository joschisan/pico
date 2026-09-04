/// Number of nodes that must be reachable for the mint to sign.
///
/// picomint sizes mints as `3f + 1` and signs at `2f + 1`
/// (picomint-core `NumNodes`), so the threshold falls out of the node count.
int signingThreshold(int nodes) => 2 * (nodes ~/ 3) + 1;

/// Whether enough nodes are reachable for the mint to operate.
/// Drives the green/amber split shown wherever connectivity surfaces — the
/// mint rows on home and the connection-status header — so the two can
/// never disagree about what "online" means.
bool mintOperational({required int online, required int total}) =>
    total > 0 && online >= signingThreshold(total);
