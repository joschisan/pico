import 'package:flutter/material.dart';
import 'package:pico/utils/styles.dart';
import 'package:pico/bridge_generated.dart/lib.dart';
import 'package:pico/bridge_generated.dart/app.dart';
import 'package:pico/bridge_generated.dart/client.dart';
import 'package:pico/bridge_generated.dart/fountain.dart';
import 'package:pico/widgets/qr_code_widget.dart';
import 'package:pico/widgets/bordered_list_widget.dart';
import 'package:pico/widgets/bleed_column_widget.dart';
import 'package:pico/widgets/scrollable_body_widget.dart';
import 'package:pico/widgets/async_button_widget.dart';
import 'package:pico/widgets/shareable_row_widget.dart';
import 'package:pico/widgets/amount_rows.dart';

Stream<String> _createFrameStream(EcashEncoder encoder) async* {
  while (true) {
    yield await encoder.nextFragment();
    await Future.delayed(const Duration(milliseconds: 300));
  }
}

class DisplayEcashScreen extends StatelessWidget {
  // Optional so the payment-details drawer can replay an old ecash
  // bundle even after the user has removed the issuing mint — in
  // that case we drop the cancel action since reissuing requires an
  // account at the same mint.
  final PicoAccount? account;
  final Pico pico;
  final EcashWrapper ecash;
  final EcashEncoder encoder;

  const DisplayEcashScreen({
    super.key,
    this.account,
    required this.pico,
    required this.ecash,
    required this.encoder,
  });

  /// Reclaim the unsent eCash back into the balance, then return home.
  Future<void> _handleCancel(BuildContext context, PicoAccount account) async {
    await pico.ecashReceive(
      mint: account.mint,
      account: account.account,
      ecash: ecash,
    );

    if (!context.mounted) return;

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final account = this.account;
    return Scaffold(
      appBar: AppBar(title: const Text('Send eCash')),
      body: ScrollableBody(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          child: BleedColumn(
            children: [
              StreamBuilder<String>(
                stream: _createFrameStream(encoder),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: smallSpinner);
                  }
                  return QrCodeWidget(data: snapshot.data!);
                },
              ),
              const SizedBox(height: 16),
              // Cancelling needs an account at the issuing mint, so
              // it is dropped when replaying an old bundle after removal.
              if (account != null) ...[
                AsyncButton(
                  text: 'Cancel',
                  onPressed: () => _handleCancel(context, account),
                ),
                const SizedBox(height: 16),
              ],
              BorderedList.column(
                children: [
                  ShareableRow(data: ecash.toString(), label: 'eCash'),
                  ...amountRows(pico: pico, amountSats: ecash.amountSats()),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
