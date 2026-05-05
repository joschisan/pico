import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:pico/bridge_generated.dart/client.dart';
import 'package:pico/utils/drawer_utils.dart';
import 'package:pico/utils/styles.dart';
import 'package:pico/widgets/bordered_list_widget.dart';
import 'package:pico/widgets/drawer_shell_widget.dart';

/// Bottom-sheet picker over every warm `PicoClient`. Each row carries a
/// live connection dot + balance subscription so the user can pick by
/// glancing at availability and funds rather than memorising names.
class FederationPickerDrawer extends StatelessWidget {
  final List<PicoClient> clients;
  final PicoClient selected;
  final ValueChanged<PicoClient> onSelected;

  const FederationPickerDrawer({
    super.key,
    required this.clients,
    required this.selected,
    required this.onSelected,
  });

  static Future<void> show(
    BuildContext context, {
    required List<PicoClient> clients,
    required PicoClient selected,
    required ValueChanged<PicoClient> onSelected,
  }) {
    return DrawerUtils.show(
      context: context,
      child: FederationPickerDrawer(
        clients: clients,
        selected: selected,
        onSelected: onSelected,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DrawerShell(
      icon: PhosphorIconsRegular.stack,
      title: 'Select Federation',
      children: [
        BorderedList.column(
          children: [
            for (final client in clients)
              _FederationRow(
                client: client,
                isSelected: listEquals(client.namespace(), selected.namespace()),
                onTap: () {
                  Navigator.of(context).pop();
                  onSelected(client);
                },
              ),
          ],
        ),
      ],
    );
  }
}

class _FederationRow extends StatelessWidget {
  final PicoClient client;
  final bool isSelected;
  final VoidCallback onTap;

  const _FederationRow({
    required this.client,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ListTile(
      onTap: onTap,
      contentPadding: listTilePadding,
      leading: StreamBuilder<List<(String, bool)>>(
        stream: client.subscribeConnectionStatus(),
        builder: (_, snapshot) {
          final online = snapshot.data?.any((s) => s.$2) ?? false;
          return _ConnectionDot(online: online);
        },
      ),
      title: FutureBuilder<String?>(
        future: client.federationName(),
        builder: (_, snapshot) =>
            Text(snapshot.data ?? '…', style: mediumStyle),
      ),
      trailing: StreamBuilder<int>(
        stream: client.subscribeBalance(),
        builder: (_, snapshot) {
          final sats = snapshot.data ?? 0;
          return Text(
            '${NumberFormat('#,###').format(sats)} sat',
            style: smallStyle.copyWith(
              color: isSelected ? scheme.primary : scheme.onSurfaceVariant,
            ),
          );
        },
      ),
    );
  }
}

class _ConnectionDot extends StatelessWidget {
  final bool online;
  const _ConnectionDot({required this.online});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: online ? color : color.withValues(alpha: 0.3),
      ),
    );
  }
}
