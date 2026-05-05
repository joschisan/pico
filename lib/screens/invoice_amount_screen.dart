import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:pico/bridge_generated.dart/client.dart';
import 'package:pico/bridge_generated.dart/factory.dart';
import 'package:pico/screens/display_invoice_screen.dart';
import 'package:pico/screens/display_lnurl_screen.dart';
import 'package:pico/widgets/amount_entry_widget.dart';
import 'package:pico/widgets/async_icon_button_widget.dart';
import 'package:pico/widgets/federation_chip_widget.dart';

class InvoiceAmountScreen extends StatefulWidget {
  final PicoClient client;
  final PicoClientFactory clientFactory;

  const InvoiceAmountScreen({
    super.key,
    required this.client,
    required this.clientFactory,
  });

  @override
  State<InvoiceAmountScreen> createState() => _InvoiceAmountScreenState();
}

class _InvoiceAmountScreenState extends State<InvoiceAmountScreen> {
  late PicoClient _client = widget.client;

  Future<void> _handleLnurlTap() async {
    final lnurl = await _client.lnurl();

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => DisplayLnurlScreen(lnurl: lnurl)),
    );
  }

  Future<void> _handleConfirm(int amountSats) async {
    final invoice = await _client.lnReceive(amountSat: amountSats);

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) =>
            DisplayInvoiceScreen(invoice: invoice, amount: amountSats),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Receive Lightning'),
        actions: [
          AsyncIconButton(
            icon: PhosphorIconsRegular.lightning,
            onPressed: _handleLnurlTap,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: FederationChip(
                clientFactory: widget.clientFactory,
                client: _client,
                onChanged: (next) => setState(() => _client = next),
              ),
            ),
            Expanded(
              child: AmountEntryWidget(
                key: ValueKey(_client.namespace()),
                client: _client,
                onConfirm: _handleConfirm,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
