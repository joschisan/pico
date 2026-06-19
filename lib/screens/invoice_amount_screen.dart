import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:pico/bridge_generated.dart/client.dart';
import 'package:pico/bridge_generated.dart/factory.dart';
import 'package:pico/screens/display_invoice_screen.dart';
import 'package:pico/screens/display_lnurl_screen.dart';
import 'package:pico/widgets/amount_entry_widget.dart';
import 'package:pico/widgets/async_icon_button_widget.dart';
import 'package:pico/widgets/fee_preview_widget.dart';

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
  late final PicoClient _client = widget.client;
  GatewayInfoWrapper? _gateway;
  bool _gatewayFailed = false;
  int _amountSats = 0;

  @override
  void initState() {
    super.initState();
    _kickoffGatewaySelection();
  }

  void _kickoffGatewaySelection() {
    _gateway = null;
    _gatewayFailed = false;
    _client.lnSelectAnyGateway().then(
      (g) {
        if (mounted) setState(() => _gateway = g);
      },
      onError: (_) {
        if (mounted) setState(() => _gatewayFailed = true);
      },
    );
  }

  Future<void> _handleLnurlTap() async {
    final lnurl = await _client.lnurl();

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => DisplayLnurlScreen(lnurl: lnurl)),
    );
  }

  Future<void> _handleConfirm(int amountSats) async {
    final gateway = _gateway;
    if (gateway == null) throw 'Querying gateway fee…';

    final invoice = await _client.lnReceive(
      gateway: gateway,
      amountSat: amountSats,
    );

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder:
            (_) => DisplayInvoiceScreen(invoice: invoice, amount: amountSats),
      ),
    );
  }

  Widget _buildFeePreview() {
    if (_gatewayFailed) return const FeePreview.error(label: 'gateway fee');
    final gateway = _gateway;
    if (gateway == null) return const FeePreview.loading(label: 'gateway fee');
    return FeePreview.value(
      gateway.gatewayFeeForReceiveAmount(amountSats: _amountSats),
      label: 'gateway fee',
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
              child: _buildFeePreview(),
            ),
            Expanded(
              child: AmountEntryWidget(
                key: ValueKey(_client.federationId()),
                client: _client,
                onConfirm: _handleConfirm,
                onAmountChanged:
                    (sats) => setState(() => _amountSats = sats),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
