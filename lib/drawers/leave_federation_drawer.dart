import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:pico/bridge_generated.dart/client.dart';
import 'package:pico/bridge_generated.dart/factory.dart';
import 'package:pico/utils/drawer_utils.dart';
import 'package:pico/widgets/async_button_widget.dart';
import 'package:pico/widgets/drawer_shell_widget.dart';

class LeaveFederationDrawer extends StatefulWidget {
  final PicoClient client;
  final PicoClientFactory clientFactory;
  final VoidCallback onSuccess;

  const LeaveFederationDrawer({
    super.key,
    required this.client,
    required this.clientFactory,
    required this.onSuccess,
  });

  static Future<void> show(
    BuildContext context, {
    required PicoClient client,
    required PicoClientFactory clientFactory,
    required VoidCallback onSuccess,
  }) {
    return DrawerUtils.show(
      context: context,
      child: LeaveFederationDrawer(
        client: client,
        clientFactory: clientFactory,
        onSuccess: onSuccess,
      ),
    );
  }

  @override
  State<LeaveFederationDrawer> createState() => _LeaveFederationDrawerState();
}

class _LeaveFederationDrawerState extends State<LeaveFederationDrawer> {
  Future<void> _handleLeaveFederation() async {
    await widget.clientFactory.leave(
      federationId: widget.client.federationId(),
    );

    if (!mounted) return;

    Navigator.of(context).pop();
    widget.onSuccess();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: widget.client.federationName(),
      builder: (context, snapshot) {
        final name = snapshot.data ?? 'this federation';
        return DrawerShell(
          icon: PhosphorIconsRegular.signOut,
          title: 'Leave $name?',
          children: [
            AsyncButton(text: 'Confirm', onPressed: _handleLeaveFederation),
          ],
        );
      },
    );
  }
}
