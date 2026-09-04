import 'package:flutter/material.dart';
import 'package:pico/bridge_generated.dart/app.dart';
import 'package:pico/bridge_generated.dart/client.dart';
import 'package:pico/bridge_generated.dart/lnurl.dart';
import 'package:pico/bridge_generated.dart/events.dart';
import 'package:pico/widgets/drawer_shell_widget.dart';
import 'package:pico/widgets/bleed_list_widget.dart';
import 'package:pico/widgets/payment_summary_row_widget.dart';
import 'package:pico/widgets/async_button_widget.dart';
import 'package:pico/screens/lnurl_amount_screen.dart';
import 'package:pico/drawers/lightning_send_drawer.dart';
import 'package:pico/utils/drawer_utils.dart';

class LnurlDrawer extends StatefulWidget {
  final PicoAccount account;
  final Pico pico;
  final LnurlWrapper lnurl;

  const LnurlDrawer({
    super.key,
    required this.account,
    required this.pico,
    required this.lnurl,
  });

  static Future<void> show(
    BuildContext context, {
    required PicoAccount account,
    required Pico pico,
    required LnurlWrapper lnurl,
  }) {
    return DrawerUtils.show(
      context: context,
      child: LnurlDrawer(account: account, pico: pico, lnurl: lnurl),
    );
  }

  @override
  State<LnurlDrawer> createState() => _LnurlDrawerState();
}

class _LnurlDrawerState extends State<LnurlDrawer> {
  Future<void> _handleContinue() async {
    final payResponse = await lnurlFetchLimits(lnurl: widget.lnurl);

    if (!mounted) return;

    if (payResponse.isFixedAmount()) {
      final invoice = await lnurlResolve(
        payResponse: payResponse,
        amountSats: payResponse.minSats,
      );

      if (!mounted) return;

      Navigator.of(context).pop();
      LightningSendDrawer.show(
        context,
        account: widget.account,
        pico: widget.pico,
        invoice: invoice,
      );
    } else {
      final contactName = widget.pico.getContactName(lnurl: widget.lnurl);

      if (!mounted) return;

      DrawerUtils.popAndPush(
        context,
        LnurlAmountScreen(
          account: widget.account,
          pico: widget.pico,
          lnurl: widget.lnurl,
          payResponse: payResponse,
          contactName: contactName,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DrawerShell(
      children: [
        // No amount row yet: a variable-amount lnurl has none until the
        // amount screen, and a fixed-amount one only after its limits are
        // fetched — both of which happen behind the button below.
        BleedList.column(
          children: const [
            PaymentSummaryRow(
              paymentType: PaymentType.lightning,
              incoming: false,
              status: 'Send',
            ),
          ],
        ),
        const SizedBox(height: 16),
        AsyncButton(text: 'Continue', onPressed: _handleContinue),
      ],
    );
  }
}
