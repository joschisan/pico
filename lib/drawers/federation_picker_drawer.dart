import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:pico/bridge_generated.dart/client.dart';
import 'package:pico/utils/drawer_utils.dart';
import 'package:pico/utils/styles.dart';
import 'package:pico/widgets/animated_balance_widget.dart';
import 'package:pico/widgets/bordered_list_widget.dart';
import 'package:pico/widgets/drawer_shell_widget.dart';

/// Bottom-sheet picker over every warm `PicoClient`. Each row carries a
/// live connection dot + balance subscription so the user can pick by
/// glancing at availability and funds rather than memorising names.
class FederationPickerDrawer extends StatelessWidget {
  final List<PicoClient> clients;
  final ValueChanged<PicoClient> onSelected;
  final String title;

  const FederationPickerDrawer({
    super.key,
    required this.clients,
    required this.onSelected,
    this.title = 'Select Federation',
  });

  static Future<void> show(
    BuildContext context, {
    required List<PicoClient> clients,
    required ValueChanged<PicoClient> onSelected,
    String title = 'Select Federation',
  }) {
    return DrawerUtils.show(
      context: context,
      child: FederationPickerDrawer(
        clients: clients,
        onSelected: onSelected,
        title: title,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DrawerShell(
      icon: PhosphorIconsRegular.wallet,
      title: title,
      children: [
        BorderedList.column(
          children: [
            for (final client in clients)
              _FederationRow(
                client: client,
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
  final VoidCallback onTap;

  const _FederationRow({required this.client, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ListTile(
      onTap: onTap,
      contentPadding: listTilePadding,
      leading: StreamBuilder<bool>(
        stream: client.liveness(),
        builder: (_, snapshot) => _ConnectionDot(online: snapshot.data),
      ),
      // Both texts in the title slot so ListTile renders as
      // single-line (56dp) instead of the taller two-line variant
      // a populated `subtitle` would force.
      title: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StreamBuilder<int>(
            stream: client.subscribeBalance(),
            builder:
                (_, snapshot) => AnimatedBalance(
                  sats: snapshot.data ?? 0,
                  style: mediumStyle,
                ),
          ),
          FutureBuilder<String?>(
            future: client.federationName(),
            builder:
                (_, snapshot) => Text(
                  snapshot.data ?? '…',
                  style: smallStyle.copyWith(color: scheme.onSurfaceVariant),
                ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionDot extends StatelessWidget {
  /// `null` until the first liveness sample arrives (faded), `true`
  /// after a successful poll (primary), `false` after a failed poll (red).
  final bool? online;
  const _ConnectionDot({required this.online});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: switch (online) {
          null => color.withValues(alpha: 0.3),
          true => color,
          false => Colors.red,
        },
      ),
    );
  }
}
