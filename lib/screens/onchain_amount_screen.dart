import 'package:flutter/material.dart';
import 'package:pico/bridge_generated.dart/app.dart';
import 'package:pico/bridge_generated.dart/client.dart';
import 'package:pico/bridge_generated.dart/lib.dart';
import 'package:pico/screens/confirm_onchain_send_screen.dart';
import 'package:pico/widgets/amount_entry_widget.dart';
import 'package:pico/widgets/max_action_widget.dart';

class OnchainAmountScreen extends StatefulWidget {
  final PicoAccount account;
  final Pico pico;
  final BitcoinAddressWrapper address;

  const OnchainAmountScreen({
    super.key,
    required this.account,
    required this.pico,
    required this.address,
  });

  @override
  State<OnchainAmountScreen> createState() => _OnchainAmountScreenState();
}

class _OnchainAmountScreenState extends State<OnchainAmountScreen> {
  Future<void> _handleConfirm(int amountSats) async {
    final feeSats = await widget.pico.onchainSendFee(
      mint: widget.account.mint,
    );

    _confirm(amountSats: amountSats, feeSats: feeSats, isMax: false);
  }

  /// Runs from the app bar's Max action, straight to the confirmation
  /// screen, so emptying the account is reviewed like any other send. The
  /// amount shown is this tap's quote; the send re-prices at the feerate
  /// current when it is submitted, so a feerate that moves in between moves
  /// the amount with it.
  Future<void> _handleConfirmMax() async {
    final amountSats = await widget.pico.onchainSendMaxAmount(
      mint: widget.account.mint,
      account: widget.account.account,
    );

    if (amountSats <= 0) throw 'This account cannot cover the onchain fee';

    final feeSats = await widget.pico.onchainSendFee(
      mint: widget.account.mint,
    );

    _confirm(amountSats: amountSats, feeSats: feeSats, isMax: true);
  }

  void _confirm({
    required int amountSats,
    required int feeSats,
    required bool isMax,
  }) {
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder:
            (_) => ConfirmOnchainSendScreen(
              account: widget.account,
              pico: widget.pico,
              address: widget.address,
              amountSats: amountSats,
              feeSats: feeSats,
              isMax: isMax,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Send Onchain'),
        actions: [MaxAction(onPressed: _handleConfirmMax)],
      ),
      body: SafeArea(
        child: AmountEntryWidget(
          pico: widget.pico,
          onConfirm: _handleConfirm,
          buttonText: 'Continue',
        ),
      ),
    );
  }
}
