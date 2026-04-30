import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter/material.dart';
import 'package:pico/bridge_generated.dart/lib.dart';
import 'package:pico/bridge_generated.dart/client.dart';
import 'package:pico/widgets/drawer_shell_widget.dart';
import 'package:pico/widgets/async_button_widget.dart';
import 'package:pico/screens/onchain_amount_screen.dart';
import 'package:pico/utils/drawer_utils.dart';

class OnchainAddressDrawer extends StatelessWidget {
  final PicoClient client;
  final BitcoinAddressWrapper address;

  const OnchainAddressDrawer({
    super.key,
    required this.client,
    required this.address,
  });

  static Future<void> show(
    BuildContext context, {
    required PicoClient client,
    required BitcoinAddressWrapper address,
  }) {
    return DrawerUtils.show(
      context: context,
      child: OnchainAddressDrawer(client: client, address: address),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DrawerShell(
      icon: PhosphorIconsRegular.link,
      title: 'Send Onchain',
      children: [
        const SizedBox(height: 8),
        AsyncButton(
          text: 'Continue',
          onPressed:
              () async => DrawerUtils.popAndPush(
                context,
                OnchainAmountScreen(client: client, address: address),
              ),
        ),
      ],
    );
  }
}
