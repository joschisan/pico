import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:pico/bridge_generated.dart/factory.dart';
import 'package:pico/bridge_generated.dart/lib.dart';
import 'package:pico/utils/drawer_utils.dart';
import 'package:pico/utils/notification_utils.dart';
import 'package:pico/utils/styles.dart';
import 'package:pico/widgets/async_button_widget.dart';
import 'package:pico/widgets/drawer_shell_widget.dart';

/// Confirms a scanned invite — the user picks Join (fresh state) or
/// Recover (rebuild from prior session). Calls into the factory itself
/// rather than firing caller callbacks; the scanner that pushed this
/// drawer has already popped, so the drawer's own context is the only
/// reliable one for popping + toasting after the call returns.
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

  Future<void> _handleJoin(BuildContext context) async {
    await clientFactory.join(invite: invite);
    if (!context.mounted) return;
    NotificationUtils.showSuccess(context, 'Joined federation');
    Navigator.of(context).pop();
  }

  void _showRecoverDrawer(BuildContext context) {
    Navigator.of(context).pop();
    DrawerUtils.show(
      context: context,
      child: _RecoverDrawer(invite: invite, clientFactory: clientFactory),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DrawerShell(
      icon: PhosphorIconsRegular.wallet,
      title: 'Federation Invite',
      children: [
        AsyncButton(text: 'Join', onPressed: () => _handleJoin(context)),
        const SizedBox(height: 24),
        GestureDetector(
          onTap: () => _showRecoverDrawer(context),
          child: Text(
            'Already used this federation before?',
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

class _RecoverDrawer extends StatelessWidget {
  final InviteCodeWrapper invite;
  final PicoClientFactory clientFactory;

  const _RecoverDrawer({required this.invite, required this.clientFactory});

  Future<void> _handleRecover(BuildContext context) async {
    await clientFactory.recover(invite: invite);
    if (!context.mounted) return;
    NotificationUtils.showSuccess(context, 'Recovering federation');
    Navigator.of(context).pop();
  }

  void _showJoinDrawer(BuildContext context) {
    Navigator.of(context).pop();
    InviteDrawer.show(context, invite: invite, clientFactory: clientFactory);
  }

  @override
  Widget build(BuildContext context) {
    return DrawerShell(
      icon: PhosphorIconsRegular.wallet,
      title: 'Federation Invite',
      children: [
        AsyncButton(text: 'Recover', onPressed: () => _handleRecover(context)),
        const SizedBox(height: 24),
        GestureDetector(
          onTap: () => _showJoinDrawer(context),
          child: Text(
            'New to this federation?',
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
