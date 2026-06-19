import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter/material.dart';
import 'package:pico/bridge_generated.dart/lib.dart';
import 'package:pico/bridge_generated.dart/client.dart';
import 'package:pico/bridge_generated.dart/factory.dart';
import 'package:pico/widgets/drawer_shell_widget.dart';
import 'package:pico/widgets/bordered_list_widget.dart';
import 'package:pico/widgets/amount_rows.dart';
import 'package:pico/widgets/async_button_widget.dart';
import 'package:pico/drawers/confirm_lightning_send_drawer.dart';
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
  /// Selects the gateway and quotes its fee, then hands off to the
  /// confirmation drawer. The gateway is only chosen here, once the user opts
  /// to continue, and is passed through so [PicoClient.lnSend] uses the gateway
  /// the fee was quoted against.
  Future<void> _handleContinue() async {
    final gateway = await widget.client.lnSelectGatewayForInvoice(
      invoice: widget.invoice,
    );

    final feeSats = gateway.gatewayFeeForInvoice(invoice: widget.invoice);

    if (!mounted) return;

    Navigator.of(context).pop();
    ConfirmLightningSendDrawer.show(
      context,
      client: widget.client,
      invoice: widget.invoice,
      gateway: gateway,
      feeSats: feeSats,
    );
  }

  @override
  Widget build(BuildContext context) {
    return DrawerShell(
      icon: PhosphorIconsRegular.lightning,
      title: 'Send Lightning',
      children: [
        BorderedList.column(
          children: [
            ...amountRows(
              client: widget.client,
              amountSats: widget.invoice.amountSats(),
            ),
          ],
        ),
        const SizedBox(height: 16),
        AsyncButton(text: 'Continue', onPressed: _handleContinue),
      ],
    );
  }
}
