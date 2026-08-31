import 'package:flutter/material.dart';
import 'package:pico/bridge_generated.dart/app.dart';
import 'package:pico/bridge_generated.dart/client.dart';
import 'package:pico/screens/display_invoice_screen.dart';
import 'package:pico/widgets/amount_entry_widget.dart';

class InvoiceAmountScreen extends StatefulWidget {
  final PicoAccount account;
  final Pico pico;

  const InvoiceAmountScreen({
    super.key,
    required this.account,
    required this.pico,
  });

  @override
  State<InvoiceAmountScreen> createState() => _InvoiceAmountScreenState();
}

class _InvoiceAmountScreenState extends State<InvoiceAmountScreen> {
  Future<void> _handleConfirm(int amountSats) async {
    final gateway = await widget.pico.lnSelectGateway(
      federation: widget.account.federation,
    );

    final feeSats = gateway.gatewayFeeForReceiveAmount(amountSats: amountSats);

    final invoice = await widget.pico.lnReceive(
      federation: widget.account.federation,
      account: widget.account.account,
      gateway: gateway,
      amountSat: amountSats,
    );

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder:
            (_) => DisplayInvoiceScreen(
              pico: widget.pico,
              invoice: invoice,
              amount: amountSats,
              feeSats: feeSats,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Receive Lightning')),
      body: SafeArea(
        child: AmountEntryWidget(
          key: ValueKey(widget.account.federation.display()),
          pico: widget.pico,
          onConfirm: _handleConfirm,
        ),
      ),
    );
  }
}
