import 'package:flutter/material.dart';
import 'package:pico/bridge_generated.dart/client.dart';
import 'package:pico/bridge_generated.dart/factory.dart';
import 'package:pico/bridge_generated.dart/lib.dart';
import 'package:pico/utils/auth_utils.dart';
import 'package:pico/widgets/amount_entry_widget.dart';
import 'package:pico/widgets/fee_preview_widget.dart';

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
  late final PicoClient _client = widget.client;
  late Future<int> _feeFuture;
  int? _feeSats;

  @override
  void initState() {
    super.initState();
    _kickoffFeeFetch();
  }

  void _kickoffFeeFetch() {
    _feeSats = null;
    // Picomint's wallet quotes a flat per-tx fee independent of
    // address/amount, so we can resolve it as soon as the screen opens.
    _feeFuture = _client.onchainCalculateFees(
      address: widget.address,
      amountSats: 0,
    );
    _feeFuture.then((v) {
      if (mounted) setState(() => _feeSats = v);
    }, onError: (_) {});
  }

  Future<void> _handleConfirm(int amountSats) async {
    if (_feeSats == null) throw 'Querying fee…';

    await requireBiometricAuth(context);

    await _client.onchainSend(
      address: widget.address,
      amountSats: amountSats,
    );

    if (!mounted) return;

    Navigator.of(context).pop();
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
              child: FeePreview.fromFuture(_feeFuture),
            ),
            Expanded(
              child: AmountEntryWidget(
                key: ValueKey(_client.federationId()),
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
