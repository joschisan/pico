import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:pico/utils/styles.dart';
import 'package:pico/bridge_generated.dart/lib.dart';
import 'package:pico/bridge_generated.dart/client.dart';
import 'package:pico/bridge_generated.dart/fountain.dart';
import 'package:pico/widgets/qr_code_widget.dart';
import 'package:pico/widgets/bordered_list_widget.dart';
import 'package:pico/widgets/shareable_row_widget.dart';
import 'package:pico/widgets/detail_row_widget.dart';
import 'package:pico/widgets/amount_rows.dart';
import 'package:pico/drawers/cancel_ecash_drawer.dart';

Stream<String> _createFrameStream(ECashEncoder encoder) async* {
  while (true) {
    yield await encoder.nextFragment();
    await Future.delayed(const Duration(milliseconds: 300));
  }
}

class DisplayEcashScreen extends StatelessWidget {
  // Optional so the payment-details drawer can replay an old ecash
  // bundle even after the user has left the issuing federation — in
  // that case we drop the cancel action since reissuing requires a
  // warm client for the same federation.
  final PicoClient? client;
  final ECashWrapper ecash;
  final ECashEncoder encoder;

  const DisplayEcashScreen({
    super.key,
    this.client,
    required this.ecash,
    required this.encoder,
  });

  @override
  Widget build(BuildContext context) {
    final client = this.client;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Send eCash'),
        actions: [
          if (client != null)
            IconButton(
              icon: const Icon(
                PhosphorIconsRegular.xCircle,
                size: smallIconSize,
              ),
              onPressed:
                  () => CancelEcashDrawer.show(
                    context,
                    client: client,
                    ecash: ecash,
                  ),
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              StreamBuilder<String>(
                stream: _createFrameStream(encoder),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return QrCodeWidget(data: snapshot.data!);
                },
              ),
              const SizedBox(height: 16),
              BorderedList.column(
                children: [
                  ShareableRow(data: ecash.toString(), label: 'eCash'),
                  if (client != null)
                    ...amountRows(client: client, amountSats: ecash.amountSats())
                  else
                    DetailRow(
                      icon: PhosphorIconsRegular.currencyBtc,
                      label: 'Amount in Bitcoin',
                      value:
                          '${NumberFormat('#,###').format(ecash.amountSats())} sat',
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
