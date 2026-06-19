import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:pico/bridge_generated.dart/client.dart';
import 'package:pico/bridge_generated.dart/factory.dart';
import 'package:pico/screens/display_invoice_screen.dart';
import 'package:pico/screens/display_lnurl_screen.dart';
import 'package:pico/widgets/amount_entry_widget.dart';
import 'package:pico/widgets/async_icon_button_widget.dart';

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

  @override
  void initState() {
    super.initState();
    _kickoffGatewaySelection();
  }

  void _kickoffGatewaySelection() {
    _client.lnSelectAnyGateway().then(
      (g) {
        if (mounted) _gateway = g;
      },
      onError: (_) {},
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

    final feeSats = gateway.gatewayFeeForReceiveAmount(amountSats: amountSats);

    final invoice = await _client.lnReceive(
      gateway: gateway,
      amountSat: amountSats,
    );

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => DisplayInvoiceScreen(
          client: _client,
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
        child: AmountEntryWidget(
          key: ValueKey(_client.federationId()),
          client: _client,
          onConfirm: _handleConfirm,
          buttonText: 'Continue',
        ),
      ),
    );
  }
}
