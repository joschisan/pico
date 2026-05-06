import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pico/bridge_generated.dart/client.dart';
import 'package:pico/bridge_generated.dart/factory.dart';
import 'package:pico/drawers/federation_picker_drawer.dart';
import 'package:pico/utils/styles.dart';

/// Inline pill that names the federation a payment will route through and
/// opens the picker on tap. The hosting screen owns the selected client
/// and updates it via `onChanged`; the chip itself is stateless.
class FederationChip extends StatelessWidget {
  final PicoClientFactory clientFactory;
  final PicoClient client;
  final ValueChanged<PicoClient> onChanged;

  const FederationChip({
    super.key,
    required this.clientFactory,
    required this.client,
    required this.onChanged,
  });

  Future<void> _openPicker(BuildContext context) async {
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

    // Matches the rounded-rect border styling of `BorderedList` items
    // so the chip reads as a single-row tile in the same visual family
    // as the federation list on the home screen.
    return InkWell(
      onTap: () => _openPicker(context),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: listTilePadding,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            StreamBuilder<List<(String, bool)>>(
              stream: client.subscribeConnectionStatus(),
              builder: (_, snapshot) {
                final online = snapshot.data?.any((s) => s.$2) ?? false;
                return Container(
                  width: 10,
                  height: 10,
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
            const SizedBox(width: 8),
            Flexible(
              child: FutureBuilder<String?>(
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
            ),
            const SizedBox(width: 8),
            StreamBuilder<int>(
              stream: client.subscribeBalance(),
              builder: (_, snapshot) {
                final sats = snapshot.data ?? 0;
                return Text(
                  '· ${NumberFormat('#,###').format(sats)} sat',
                  style: smallStyle.copyWith(color: scheme.onSurfaceVariant),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
