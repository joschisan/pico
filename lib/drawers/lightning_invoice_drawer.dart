import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter/material.dart';
import 'package:pico/bridge_generated.dart/lib.dart';
import 'package:pico/bridge_generated.dart/client.dart';
import 'package:pico/bridge_generated.dart/factory.dart';
import 'package:pico/widgets/drawer_shell_widget.dart';
import 'package:pico/widgets/amount_display_widget.dart';
import 'package:pico/widgets/federation_chip_widget.dart';
import 'package:pico/widgets/primary_card_widget.dart';
import 'package:pico/widgets/async_button_widget.dart';
import 'package:pico/utils/auth_utils.dart';
import 'package:pico/utils/drawer_utils.dart';

class LightningInvoiceDrawer extends StatefulWidget {
  final PicoClientFactory clientFactory;
  final PicoClient client;
  final Bolt11InvoiceWrapper invoice;

  const LightningInvoiceDrawer({
    super.key,
    required this.clientFactory,
    required this.client,
    required this.invoice,
  });

  static Future<bool?> show(
    BuildContext context, {
    required PicoClientFactory clientFactory,
    required PicoClient client,
    required Bolt11InvoiceWrapper invoice,
  }) {
    return DrawerUtils.show<bool>(
      context: context,
      child: LightningInvoiceDrawer(
        clientFactory: clientFactory,
        client: client,
        invoice: invoice,
      ),
    );
  }

  @override
  State<LightningInvoiceDrawer> createState() => _LightningInvoiceDrawerState();
}

class _LightningInvoiceDrawerState extends State<LightningInvoiceDrawer> {
  late PicoClient _client = widget.client;

  Future<void> _handleConfirm() async {
    await requireBiometricAuth(context);

    await _client.lnSend(invoice: widget.invoice);

    if (!mounted) return;

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return DrawerShell(
      icon: PhosphorIconsRegular.lightning,
      title: 'Send Lightning',
      children: [
        Center(
          child: FederationChip(
            clientFactory: widget.clientFactory,
            client: _client,
            onChanged: (next) => setState(() => _client = next),
          ),
        ),
        const SizedBox(height: 16),
        PrimaryCard(child: AmountDisplay(widget.invoice.amountSats())),
        const SizedBox(height: 16),
        AsyncButton(text: 'Confirm', onPressed: _handleConfirm),
      ],
    );
  }
}
