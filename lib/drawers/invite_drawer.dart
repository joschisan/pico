import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:pico/bridge_generated.dart/factory.dart';
import 'package:pico/bridge_generated.dart/lib.dart';
import 'package:pico/utils/drawer_utils.dart';
import 'package:pico/utils/styles.dart';
import 'package:pico/widgets/async_button_widget.dart';
import 'package:pico/widgets/bordered_list_widget.dart';
import 'package:pico/widgets/drawer_shell_widget.dart';
import 'package:pico/widgets/settings_card_widget.dart';

/// Confirms a scanned invite — the user picks Add (fresh state) or
/// Restore (rebuild from prior session). Calls into the factory itself
/// rather than firing caller callbacks; the scanner that pushed this
/// drawer has already popped, so the drawer's own context is the only
/// reliable one to pop from once the call returns.
class InviteDrawer extends StatelessWidget {
  final InviteCodeWrapper invite;
  final PicoClientFactory clientFactory;

  const InviteDrawer({
    super.key,
    required this.invite,
    required this.clientFactory,
  });

  static Future<void> show(
    BuildContext context, {
    required InviteCodeWrapper invite,
    required PicoClientFactory clientFactory,
  }) {
    return DrawerUtils.show(
      context: context,
      child: InviteDrawer(invite: invite, clientFactory: clientFactory),
    );
  }

  // No toast: the mint is selected on arrival and its row names it, which says
  // more than a one-off message would.
  Future<void> _handleAdd(BuildContext context) async {
    await clientFactory.join(invite: invite);
    if (!context.mounted) return;
    Navigator.of(context).pop();
  }

  void _showRestoreDrawer(BuildContext context) {
    Navigator.of(context).pop();
    DrawerUtils.show(
      context: context,
      child: _RestoreDrawer(invite: invite, clientFactory: clientFactory),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _InviteActionDrawer(
      title: 'Add Mint',
      subtitle: 'Add a new mint',
      onConfirm: () => _handleAdd(context),
      linkText: 'Previously added this mint?',
      onLink: () => _showRestoreDrawer(context),
    );
  }
}

class _RestoreDrawer extends StatelessWidget {
  final InviteCodeWrapper invite;
  final PicoClientFactory clientFactory;

  const _RestoreDrawer({required this.invite, required this.clientFactory});

  // The scan runs inside `recover`, so the button spins for its duration and
  // the drawer only closes once the wallet is actually back — which reads as
  // the confirmation a toast would otherwise have to give.
  Future<void> _handleRestore(BuildContext context) async {
    await clientFactory.recover(invite: invite);
    if (!context.mounted) return;
    Navigator.of(context).pop();
  }

  void _showAddDrawer(BuildContext context) {
    Navigator.of(context).pop();
    InviteDrawer.show(context, invite: invite, clientFactory: clientFactory);
  }

  @override
  Widget build(BuildContext context) {
    return _InviteActionDrawer(
      title: 'Restore Mint',
      subtitle: 'Restore unspent eCash',
      onConfirm: () => _handleRestore(context),
      linkText: 'New to this mint?',
      onLink: () => _showAddDrawer(context),
    );
  }
}

/// Shared layout for the add/restore pair: the standard mint row above a
/// confirm button, with a text link that toggles to the other variant. The two
/// differ only in wording and which factory call the button makes, so the
/// layout is written once.
class _InviteActionDrawer extends StatelessWidget {
  final String title;
  final String subtitle;
  final Future<void> Function() onConfirm;
  final String linkText;
  final VoidCallback onLink;

  const _InviteActionDrawer({
    required this.title,
    required this.subtitle,
    required this.onConfirm,
    required this.linkText,
    required this.onLink,
  });

  @override
  Widget build(BuildContext context) {
    return DrawerShell(
      children: [
        BorderedList.column(
          children: [
            SettingsCard(
              icon: PhosphorIconsRegular.stack,
              title: title,
              subtitle: subtitle,
            ),
          ],
        ),
        const SizedBox(height: 16),
        AsyncButton(text: 'Confirm', onPressed: onConfirm),
        const SizedBox(height: 24),
        GestureDetector(
          onTap: onLink,
          child: Text(
            linkText,
            style: mediumStyle.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}
