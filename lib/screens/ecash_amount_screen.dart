import 'package:flutter/material.dart';
import 'package:pico/bridge_generated.dart/client.dart';
import 'package:pico/bridge_generated.dart/fountain.dart';
import 'package:pico/widgets/amount_entry_widget.dart';
import 'package:pico/screens/display_ecash_screen.dart';
import 'package:pico/utils/auth_utils.dart';

class EcashAmountScreen extends StatelessWidget {
  final PicoClient client;

  const EcashAmountScreen({super.key, required this.client});

  Future<void> _handleConfirm(BuildContext context, int amountSats) async {
    await requireBiometricAuth(context);

    final notes = await client.ecashSend(amountSat: amountSats);

    if (!context.mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder:
            (_) => DisplayEcashScreen(
              client: client,
              notes: notes,
              encoder: ECashEncoder(notes: notes),
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Send eCash')),
      body: SafeArea(
        child: AmountEntryWidget(
          client: client,
          onConfirm: (amountSats) => _handleConfirm(context, amountSats),
        ),
      ),
    );
  }
}
