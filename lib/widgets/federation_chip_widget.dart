import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pico/bridge_generated.dart/client.dart';
import 'package:pico/bridge_generated.dart/factory.dart';
import 'package:pico/drawers/federation_picker_drawer.dart';
import 'package:pico/utils/styles.dart';

/// Inline tile that names the federation a payment will route through.
/// When `onChanged` is provided the tile is tappable and opens the
/// picker; when null it's a read-only display (e.g. ecash receive,
/// where the federation is fixed by the bundle).
class FederationChip extends StatelessWidget {
  final PicoClientFactory clientFactory;
  final PicoClient client;
  final ValueChanged<PicoClient>? onChanged;

  const FederationChip({
    super.key,
    required this.clientFactory,
    required this.client,
    this.onChanged,
  });

  Future<void> _openPicker(BuildContext context) async {
    final onChanged = this.onChanged;
    if (onChanged == null) return;

    final clients = await clientFactory.clients();

    if (!context.mounted) return;

    FederationPickerDrawer.show(
      context,
      clients: clients,
      onSelected: onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // Single-tile mirror of `_FederationRow` on the home screen:
    // bordered Material wrapping a ListTile with the status dot in
    // `leading` and a balance/name stack in `title` — same widget
    // tree as a `BorderedList` row, just standalone.
    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onChanged == null ? null : () => _openPicker(context),
        contentPadding: listTilePadding,
        leading: StreamBuilder<List<(String, double)>>(
          stream: client.subscribeConnectionStatus(),
          builder: (_, snapshot) {
            final online = snapshot.data?.any((s) => s.$2 > 0.0) ?? false;
            return Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color:
                    online
                        ? scheme.primary
                        : scheme.primary.withValues(alpha: 0.3),
              ),
            );
          },
        ),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StreamBuilder<int>(
              stream: client.subscribeBalance(),
              builder: (_, snapshot) {
                final sats = snapshot.data ?? 0;
                return Text(
                  '${NumberFormat('#,###').format(sats)} sat',
                  style: mediumStyle,
                );
              },
            ),
            FutureBuilder<String?>(
              future: client.federationName(),
              builder:
                  (_, snapshot) => Text(
                    snapshot.data ?? '…',
                    style: smallStyle.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
