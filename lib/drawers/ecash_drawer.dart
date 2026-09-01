import 'package:flutter/material.dart';
import 'package:pico/bridge_generated.dart/lib.dart';
import 'package:pico/bridge_generated.dart/app.dart';
import 'package:pico/bridge_generated.dart/client.dart';
import 'package:pico/widgets/drawer_shell_widget.dart';
import 'package:pico/widgets/bordered_list_widget.dart';
import 'package:pico/widgets/amount_rows.dart';
import 'package:pico/widgets/async_button_widget.dart';
import 'package:pico/utils/drawer_utils.dart';
import 'package:pico/widgets/payment_summary_row_widget.dart';
import 'package:pico/bridge_generated.dart/events.dart';

/// Confirms receiving an out-of-band ecash bundle, into the selected account.
class EcashDrawer extends StatefulWidget {
  /// The account in view when the bundle arrived — the balance the user is
  /// looking at is the one they mean. A bundle issued by a different
  /// federation is rejected by the receive itself with an explicit error.
  final PicoAccount selected;
  final Pico pico;
  final ECashWrapper ecash;

  const EcashDrawer({
    super.key,
    required this.selected,
    required this.pico,
    required this.ecash,
  });

  static Future<bool?> show(
    BuildContext context, {
    required PicoAccount selected,
    required Pico pico,
    required ECashWrapper ecash,
  }) {
    return DrawerUtils.show<bool>(
      context: context,
      child: EcashDrawer(selected: selected, pico: pico, ecash: ecash),
    );
  }

  @override
  State<EcashDrawer> createState() => _EcashDrawerState();
}

class _EcashDrawerState extends State<EcashDrawer> {
  Future<void> _handleReceive() async {
    await widget.pico.mintReceive(
      federation: widget.selected.federation,
      account: widget.selected.account,
      ecash: widget.ecash,
    );

    if (!mounted) return;

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return DrawerShell(
      children: [
        BorderedList.column(
          children: [
            const PaymentSummaryRow(
              paymentType: PaymentType.ecash,
              incoming: true,
              status: 'Receive',
            ),
            ...amountRows(
              pico: widget.pico,
              amountSats: widget.ecash.amountSats(),
            ),
          ],
        ),
        const SizedBox(height: 16),
        AsyncButton(text: 'Receive', onPressed: _handleReceive),
      ],
    );
  }
}
