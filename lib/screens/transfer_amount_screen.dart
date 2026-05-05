import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:pico/bridge_generated.dart/client.dart';
import 'package:pico/bridge_generated.dart/lib.dart';
import 'package:pico/screens/confirm_onchain_send_screen.dart';
import 'package:pico/utils/notification_utils.dart';
import 'package:pico/utils/styles.dart';
import 'package:pico/widgets/amount_entry_widget.dart';

/// Transfer between two federations, either over Lightning (dest mints
/// a bolt11, source pays it — routing fees come out silently) or onchain
/// (dest hands over a receive address, source sends; miner fee preview
/// goes through the standard ConfirmOnchainSendScreen).
class TransferAmountScreen extends StatefulWidget {
  final PicoClient source;
  final PicoClient dest;

  const TransferAmountScreen({
    super.key,
    required this.source,
    required this.dest,
  });

  @override
  State<TransferAmountScreen> createState() => _TransferAmountScreenState();
}

class _TransferAmountScreenState extends State<TransferAmountScreen> {
  bool _isOnchain = false;

  Future<void> _handleConfirm(int amountSats) async {
    if (_isOnchain) {
      await _confirmOnchain(amountSats);
    } else {
      await _confirmLightning(amountSats);
    }
  }

  Future<void> _confirmLightning(int amountSats) async {
    final bolt11 = await widget.dest.lnReceive(amountSat: amountSats);
    final invoice = parseBolt11Invoice(invoice: bolt11)!;
    await widget.source.lnSend(invoice: invoice);

    if (!mounted) return;

    NotificationUtils.showSuccess(context, 'Transfer sent');
    Navigator.of(context).pop();
  }

  Future<void> _confirmOnchain(int amountSats) async {
    final addressStr = await widget.dest.onchainReceiveAddress();
    final address = parseBitcoinAddress(address: addressStr)!;
    final feeSats = await widget.source.onchainCalculateFees(
      address: address,
      amountSats: amountSats,
    );

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ConfirmOnchainSendScreen(
          client: widget.source,
          address: address,
          amountSats: amountSats,
          feeSats: feeSats,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transfer'),
        actions: [
          IconButton(
            icon: Icon(
              _isOnchain
                  ? PhosphorIconsRegular.link
                  : PhosphorIconsRegular.lightning,
              size: smallIconSize,
            ),
            onPressed: () => setState(() => _isOnchain = !_isOnchain),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: FutureBuilder<List<String?>>(
                future: Future.wait([
                  widget.source.federationName(),
                  widget.dest.federationName(),
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
                client: widget.source,
                onConfirm: _handleConfirm,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
