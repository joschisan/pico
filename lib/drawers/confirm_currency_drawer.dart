import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter/material.dart';
import 'package:pico/bridge_generated.dart/factory.dart';
import 'package:pico/widgets/drawer_shell_widget.dart';
import 'package:pico/widgets/async_button_widget.dart';
import 'package:pico/utils/drawer_utils.dart';
import 'package:pico/bridge_generated.dart/currency.dart';

class ConfirmCurrencyDrawer extends StatefulWidget {
  final FiatCurrency currency;
  final PicoClientFactory clientFactory;

  const ConfirmCurrencyDrawer({
    super.key,
    required this.currency,
    required this.clientFactory,
  });

  static Future<void> show(
    BuildContext context, {
    required FiatCurrency currency,
    required PicoClientFactory clientFactory,
  }) {
    return DrawerUtils.show(
      context: context,
      child: ConfirmCurrencyDrawer(
        currency: currency,
        clientFactory: clientFactory,
      ),
    );
  }

  @override
  State<ConfirmCurrencyDrawer> createState() => _ConfirmCurrencyDrawerState();
}

class _ConfirmCurrencyDrawerState extends State<ConfirmCurrencyDrawer> {
  Future<void> _handleConfirm() async {
    await widget.clientFactory.setCurrency(currencyCode: widget.currency.code);

    if (!mounted) return;

    Navigator.of(context).pop();

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return DrawerShell(
      icon: PhosphorIconsRegular.currencyDollar,
      title: 'Select ${widget.currency.name}?',
      children: [AsyncButton(text: 'Confirm', onPressed: _handleConfirm)],
    );
  }
}
