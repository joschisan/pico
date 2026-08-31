import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:pico/bridge_generated.dart/app.dart';
import 'package:pico/bridge_generated.dart/client.dart';
import 'package:pico/utils/drawer_utils.dart';
import 'package:pico/widgets/async_button_widget.dart';
import 'package:pico/widgets/bordered_list_widget.dart';
import 'package:pico/widgets/drawer_shell_widget.dart';
import 'package:pico/widgets/settings_card_widget.dart';

/// Confirms removing a mint: the row names the mint over what is about to
/// happen to it, and the confirm button carries the caution amber rather than
/// relying on the wording alone. Same shape as the delete-contact drawer.
class LeaveFederationDrawer extends StatefulWidget {
  final PicoAccount account;
  final Pico pico;
  final VoidCallback onSuccess;

  const LeaveFederationDrawer({
    super.key,
    required this.account,
    required this.pico,
    required this.onSuccess,
  });

  static Future<void> show(
    BuildContext context, {
    required PicoAccount account,
    required Pico pico,
    required VoidCallback onSuccess,
  }) {
    return DrawerUtils.show(
      context: context,
      child: LeaveFederationDrawer(
        account: account,
        pico: pico,
        onSuccess: onSuccess,
      ),
    );
  }

  @override
  State<LeaveFederationDrawer> createState() => _LeaveFederationDrawerState();
}

class _LeaveFederationDrawerState extends State<LeaveFederationDrawer> {
  Future<void> _handleLeaveFederation() async {
    await widget.pico.remove(federation: widget.account.federation);

    if (!mounted) return;

    Navigator.of(context).pop();
    widget.onSuccess();
  }

  @override
  Widget build(BuildContext context) {
    return DrawerShell(
      children: [
        BorderedList.column(
          children: [
            SettingsCard(
              icon: PhosphorIconsRegular.trash,
              title: 'Remove Mint',
              subtitle: widget.account.federationName,
            ),
          ],
        ),
        const SizedBox(height: 16),
        AsyncButton(text: 'Confirm', onPressed: _handleLeaveFederation),
      ],
    );
  }
}
