import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pico/bridge_generated.dart/lib.dart';
import 'package:pico/bridge_generated.dart/client.dart';
import 'package:pico/widgets/drawer_shell_widget.dart';
import 'package:pico/widgets/bordered_list_widget.dart';
import 'package:pico/widgets/detail_row_widget.dart';
import 'package:pico/widgets/amount_rows.dart';
import 'package:pico/widgets/async_button_widget.dart';
import 'package:pico/widgets/warning_card_widget.dart';
import 'package:pico/utils/auth_utils.dart';
import 'package:pico/utils/drawer_utils.dart';

/// Confirms a Lightning payment once a gateway has been selected and its fee
/// quoted. The same [gateway] used to compute [feeSats] is passed to
/// [PicoClient.lnSend] so the fee shown here matches what is charged.
class ConfirmLightningSendDrawer extends StatelessWidget {
  final PicoClient client;
  final Bolt11InvoiceWrapper invoice;
  final GatewayInfoWrapper gateway;
  final int feeSats;

  const ConfirmLightningSendDrawer({
    super.key,
    required this.client,
    required this.invoice,
    required this.gateway,
    required this.feeSats,
  });

  static Future<void> show(
    BuildContext context, {
    required PicoClient client,
    required Bolt11InvoiceWrapper invoice,
    required GatewayInfoWrapper gateway,
    required int feeSats,
  }) {
    return DrawerUtils.show(
      context: context,
      child: ConfirmLightningSendDrawer(
        client: client,
        invoice: invoice,
        gateway: gateway,
        feeSats: feeSats,
      ),
    );
  }

  Future<void> _handleConfirm(BuildContext context) async {
    await requireBiometricAuth(context);

    await client.lnSend(gateway: gateway, invoice: invoice);

    if (!context.mounted) return;

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final amountSats = invoice.amountSats();

    return DrawerShell(
      icon: PhosphorIconsRegular.lightning,
      title: 'Send Lightning',
      children: [
        BorderedList.column(
          children: [
            ...amountRows(client: client, amountSats: amountSats),
            DetailRow(
              icon: PhosphorIconsRegular.network,
              label: 'Network Fee',
              value:
                  '${NumberFormat('#,###').format(feeSats)} sat · ${(feeSats / amountSats * 100).toStringAsFixed(1)}%',
            ),
          ],
        ),
        if (feeSats > amountSats * 0.02) ...[
          const SizedBox(height: 16),
          WarningCard(
            icon: PhosphorIconsRegular.warning,
            text:
                'High Relative Fee of ${(feeSats / amountSats * 100).toStringAsFixed(1)}%',
          ),
        ],
        const SizedBox(height: 16),
        AsyncButton(text: 'Confirm', onPressed: () => _handleConfirm(context)),
      ],
    );
  }
}
