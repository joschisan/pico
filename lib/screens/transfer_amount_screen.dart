import 'package:flutter/material.dart';
import 'package:pico/bridge_generated.dart/client.dart';
import 'package:pico/bridge_generated.dart/lib.dart';
import 'package:pico/utils/notification_utils.dart';
import 'package:pico/utils/styles.dart';
import 'package:pico/widgets/amount_entry_widget.dart';

/// Source-funds-dest transfer over Lightning. Dest mints a fresh bolt11
/// for the entered amount; source pays it. Routing fees come out of
/// source silently — no fee UI in v1.
class TransferAmountScreen extends StatelessWidget {
  final PicoClient source;
  final PicoClient dest;

  const TransferAmountScreen({
    super.key,
    required this.source,
    required this.dest,
  });

  Future<void> _handleConfirm(BuildContext context, int amountSats) async {
    final bolt11 = await dest.lnReceive(amountSat: amountSats);
    final invoice = parseBolt11Invoice(invoice: bolt11)!;
    await source.lnSend(invoice: invoice);

    if (!context.mounted) return;

    NotificationUtils.showSuccess(context, 'Transfer sent');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Transfer')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: FutureBuilder<List<String?>>(
                future: Future.wait([
                  source.federationName(),
                  dest.federationName(),
                ]),
                builder: (_, snapshot) {
                  final names = snapshot.data ?? const [null, null];
                  return Text(
                    '${names[0] ?? '…'} → ${names[1] ?? '…'}',
                    style: smallStyle.copyWith(color: scheme.onSurfaceVariant),
                  );
                },
              ),
            ),
            Expanded(
              child: AmountEntryWidget(
                client: source,
                onConfirm: (sats) => _handleConfirm(context, sats),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
