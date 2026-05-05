import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
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

    if (clients.length <= 1) return;

    FederationPickerDrawer.show(
      context,
      clients: clients,
      selected: client,
      onSelected: onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: () => _openPicker(context),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              PhosphorIconsRegular.stack,
              size: smallIconSize,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            FutureBuilder<String?>(
              future: client.federationName(),
              builder: (_, snapshot) => Text(
                snapshot.data ?? '…',
                style: smallStyle.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
