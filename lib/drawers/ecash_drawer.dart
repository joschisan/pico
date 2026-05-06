import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter/material.dart';
import 'package:pico/bridge_generated.dart/lib.dart';
import 'package:pico/bridge_generated.dart/client.dart';
import 'package:pico/widgets/drawer_shell_widget.dart';
import 'package:pico/widgets/amount_display_widget.dart';
import 'package:pico/widgets/primary_card_widget.dart';
import 'package:pico/widgets/async_button_widget.dart';
import 'package:pico/utils/drawer_utils.dart';

class EcashDrawer extends StatefulWidget {
  final PicoClient client;
  final ECashWrapper ecash;

  const EcashDrawer({super.key, required this.client, required this.ecash});

  static Future<bool?> show(
    BuildContext context, {
    required PicoClient client,
    required ECashWrapper ecash,
  }) {
    return DrawerUtils.show<bool>(
      context: context,
      child: EcashDrawer(client: client, ecash: ecash),
    );
  }

  @override
  State<EcashDrawer> createState() => _EcashDrawerState();
}

class _EcashDrawerState extends State<EcashDrawer> {
  Future<void> _handleReceive() async {
    await widget.client.ecashReceive(ecash: widget.ecash);

    if (!mounted) return;

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return DrawerShell(
      icon: PhosphorIconsRegular.coinVertical,
      title: 'Receive eCash',
      children: [
        PrimaryCard(child: AmountDisplay(widget.ecash.amountSats())),
        const SizedBox(height: 16),
        AsyncButton(text: 'Receive', onPressed: _handleReceive),
      ],
    );
  }
}
