import 'package:flutter/material.dart';
import 'package:pico/utils/styles.dart';
import 'package:pico/bridge_generated.dart/lib.dart';
import 'package:pico/bridge_generated.dart/app.dart';
import 'package:pico/bridge_generated.dart/client.dart';
import 'package:pico/bridge_generated.dart/fountain.dart';
import 'package:pico/widgets/qr_code_widget.dart';
import 'package:pico/widgets/bleed_list_widget.dart';
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

class DisplayEcashScreen extends StatefulWidget {
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

  @override
  State<DisplayEcashScreen> createState() => _DisplayEcashScreenState();
}

class _DisplayEcashScreenState extends State<DisplayEcashScreen> {
  // Held across rebuilds: a stream built inside `build` would restart the
  // frame sequence on every repaint instead of fountain-cycling on.
  late final Stream<String> _frames = _createFrameStream(widget.encoder);

  /// Reclaim the unsent ecash back into the balance, then return home.
  Future<void> _handleCancel(PicoAccount account) async {
    await widget.pico.ecashReceive(
      mint: account.mint,
      account: account.account,
      ecash: widget.ecash,
    );

    if (!mounted) return;

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final account = widget.account;
    return Scaffold(
      appBar: AppBar(title: const Text('Send Ecash')),
      body: ScrollableBody(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          child: BleedColumn(
            children: [
              StreamBuilder<String>(
                stream: _frames,
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
                  onPressed: () => _handleCancel(account),
                ),
                const SizedBox(height: 16),
              ],
              BleedList.column(
                children: [
                  ShareableRow(data: widget.ecash.toString(), label: 'Ecash'),
                  ...amountRows(
                    pico: widget.pico,
                    amountSats: widget.ecash.amountSats(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
