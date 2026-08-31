import 'package:flutter/material.dart';
import 'package:pico/bridge_generated.dart/app.dart';
import 'package:pico/bridge_generated.dart/client.dart';
import 'package:pico/utils/notification_utils.dart';
import 'package:pico/utils/styles.dart';
import 'package:pico/widgets/qr_code_widget.dart';
import 'package:pico/widgets/bordered_list_widget.dart';
import 'package:pico/widgets/shareable_row_widget.dart';
import 'package:pico/widgets/bleed_column_widget.dart';
import 'package:pico/widgets/scrollable_body_widget.dart';

class WalletV2ReceiveScreen extends StatefulWidget {
  final PicoAccount account;
  final Pico pico;

  const WalletV2ReceiveScreen({
    super.key,
    required this.account,
    required this.pico,
  });

  @override
  State<WalletV2ReceiveScreen> createState() => _WalletV2ReceiveScreenState();
}

class _WalletV2ReceiveScreenState extends State<WalletV2ReceiveScreen> {
  String? _address;

  @override
  void initState() {
    super.initState();
    _fetchAddress();
  }

  Future<void> _fetchAddress() async {
    setState(() => _address = null);
    try {
      final addr = await widget.pico.walletDepositAddress(
        federation: widget.account.federation,
        account: widget.account.account,
      );
      if (!mounted) return;
      setState(() => _address = addr);
    } catch (_) {
      if (!mounted) return;
      NotificationUtils.showError(context, 'Failed to load address');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Receive Onchain')),
    body: ScrollableBody(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        child: BleedColumn(
          children: [
            if (_address case final address?) ...[
              QrCodeWidget(data: address),
              const SizedBox(height: 16),
              BorderedList.column(
                children: [
                  ShareableRow(data: address, label: 'Bitcoin Address'),
                ],
              ),
            ] else
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 64),
                child: Center(child: smallSpinner),
              ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    'Confirmed onchain payments will take about an hour to appear.',
                    style: smallStyle.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
