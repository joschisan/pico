import 'package:flutter/material.dart';
import 'package:pico/utils/styles.dart';
import 'package:pico/widgets/qr_code_widget.dart';
import 'package:pico/widgets/shareable_data_widget.dart';

class WalletV2ReceiveScreen extends StatelessWidget {
  final String address;

  const WalletV2ReceiveScreen({super.key, required this.address});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Onchain Address')),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            QrCodeWidget(data: address),
            const SizedBox(height: 16),
            ShareableData(data: address),
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
