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

/// Confirms receiving an out-of-band ecash bundle, into the account resolved
/// by [_resolveDestination].
class EcashDrawer extends StatefulWidget {
  /// The account in view when the bundle arrived. Used when it belongs to the
  /// bundle's federation — the balance the user is looking at is the one they
  /// mean — and ignored otherwise, since notes can only be received by the
  /// federation that issued them.
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
  // Cached so the lookup doesn't re-fire on every rebuild.
  late final Future<PicoAccount?> _destination = _resolveDestination();

  /// Which account the bundle lands in. The selected one when it belongs to
  /// the issuing federation, so scanning while parked on a page pays into the
  /// balance shown on it. Otherwise the bundle names a federation and nothing
  /// more, and [Pico.account] answers with its primary account — or `null` if
  /// the user isn't joined to it at all.
  Future<PicoAccount?> _resolveDestination() async {
    if (widget.selected.federationId == widget.ecash.federationId()) {
      return widget.selected;
    }

    return widget.pico.account(federationId: widget.ecash.federationId());
  }

  Future<void> _handleReceive() async {
    final destination = await _destination;
    if (destination == null) throw Exception('Mint is unknown');

    await widget.pico.mintReceive(
      federationId: destination.federationId,
      account: destination.account,
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
            // The exchange-rate cache is app-wide, so the fiat row renders
            // without waiting on the destination lookup.
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
