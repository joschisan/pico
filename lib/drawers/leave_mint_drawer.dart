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
class LeaveMintDrawer extends StatefulWidget {
  final PicoAccount account;
  final Pico pico;
  final VoidCallback onSuccess;

  const LeaveMintDrawer({
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
      child: LeaveMintDrawer(
        account: account,
        pico: pico,
        onSuccess: onSuccess,
      ),
    );
  }

  @override
  State<LeaveMintDrawer> createState() => _LeaveMintDrawerState();
}

class _LeaveMintDrawerState extends State<LeaveMintDrawer> {
  Future<void> _handleLeaveMint() async {
    await widget.pico.removeMint(mint: widget.account.mint);

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
              subtitle: widget.account.mintName,
            ),
          ],
        ),
        const SizedBox(height: 16),
        AsyncButton(text: 'Confirm', onPressed: _handleLeaveMint),
      ],
    );
  }
}
