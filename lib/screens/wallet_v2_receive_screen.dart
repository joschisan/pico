import 'package:flutter/material.dart';
import 'package:pico/utils/styles.dart';
import 'package:pico/widgets/qr_code_widget.dart';
import 'package:pico/widgets/bordered_list_widget.dart';
import 'package:pico/widgets/shareable_row_widget.dart';
import 'package:pico/widgets/bleed_column_widget.dart';
import 'package:pico/widgets/scrollable_body_widget.dart';

/// Shows a deposit address the caller has already fetched. The home screen
/// waits on the mint before pushing this route, so the screen never opens
/// onto a spinner and has nothing to load itself.
class WalletV2ReceiveScreen extends StatelessWidget {
  final String address;

  const WalletV2ReceiveScreen({super.key, required this.address});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Receive Onchain')),
    body: ScrollableBody(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        child: BleedColumn(
          children: [
            QrCodeWidget(data: address),
            const SizedBox(height: 16),
            BorderedList.column(
              children: [ShareableRow(data: address, label: 'Bitcoin Address')],
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
