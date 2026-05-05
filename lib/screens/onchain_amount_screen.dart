import 'package:flutter/material.dart';
import 'package:pico/bridge_generated.dart/client.dart';
import 'package:pico/bridge_generated.dart/factory.dart';
import 'package:pico/bridge_generated.dart/lib.dart';
import 'package:pico/screens/confirm_onchain_send_screen.dart';
import 'package:pico/widgets/amount_entry_widget.dart';
import 'package:pico/widgets/federation_chip_widget.dart';

class OnchainAmountScreen extends StatefulWidget {
  final PicoClient client;
  final PicoClientFactory clientFactory;
  final BitcoinAddressWrapper address;

  const OnchainAmountScreen({
    super.key,
    required this.client,
    required this.clientFactory,
    required this.address,
  });

  @override
  State<OnchainAmountScreen> createState() => _OnchainAmountScreenState();
}

class _OnchainAmountScreenState extends State<OnchainAmountScreen> {
  late PicoClient _client = widget.client;

  Future<void> _handleConfirm(int amountSats) async {
    final feeSats = await _client.onchainCalculateFees(
      address: widget.address,
      amountSats: amountSats,
    );

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ConfirmOnchainSendScreen(
          client: _client,
          address: widget.address,
          amountSats: amountSats,
          feeSats: feeSats,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Send Onchain')),
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
