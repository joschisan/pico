import 'package:flutter/material.dart';
import 'package:pico/bridge_generated.dart/client.dart';
import 'package:pico/bridge_generated.dart/factory.dart';
import 'package:pico/bridge_generated.dart/lib.dart';
import 'package:pico/screens/confirm_onchain_send_screen.dart';
import 'package:pico/widgets/amount_entry_widget.dart';
import 'package:pico/widgets/max_action_widget.dart';

class OnchainAmountScreen extends StatefulWidget {
  final PicoClient client;
  final PicoClientFactory clientFactory;
  final BitcoinAddressWrapper address;

  const OnchainAmountScreen({
    super.key,
    required this.client,
    required this.clientFactory,
    required this.address,
  });

  @override
  State<OnchainAmountScreen> createState() => _OnchainAmountScreenState();
}

class _OnchainAmountScreenState extends State<OnchainAmountScreen> {
  // What a max send would send: the balance less the onchain fee, the
  // transaction fee and the app's cut, priced by the same code that will
  // spend it. Null until it has been priced, and on the accounts that can't
  // cover a transaction at all, where there is no max to offer.
  final ValueNotifier<int?> _maxAmount = ValueNotifier(null);
  // Reaches the entry widget's figure from the app bar's Max action; the
  // client never changes under this screen, so the key carries no reset duty.
  final _entryKey = GlobalKey<AmountEntryWidgetState>();

  @override
  void initState() {
    super.initState();
    _loadMaxAmount();
  }

  @override
  void dispose() {
    _maxAmount.dispose();
    super.dispose();
  }

  /// Prices the max once on entry, as the fee preview is priced. A failure
  /// leaves it unpriced and the line undrawn — the screen still sends any
  /// amount typed into it, which is what it was opened to do.
  Future<void> _loadMaxAmount() async {
    try {
      final max = await widget.client.onchainMaxAmount();

      if (mounted && max > 0) _maxAmount.value = max;
    } catch (_) {
      // Nothing to show and nothing to say: the max line is an offer, not a
      // step the user is waiting on.
    }
  }

  Future<void> _handleConfirm(int amountSats) async {
    final feeSats = await widget.client.onchainCalculateFees(
      address: widget.address,
      amountSats: amountSats,
    );

    _confirm(amountSats: amountSats, feeSats: feeSats, isMax: false);
  }

  /// Carries the max through to the confirmation screen rather than sending
  /// from here, so emptying the account is reviewed like any other send. The
  /// amount shown is this screen's quote; the send re-prices at the feerate
  /// current when it is submitted, so a feerate that moves in between moves
  /// the amount with it.
  Future<void> _handleConfirmMax() async {
    final feeSats = await widget.client.onchainCalculateFees(
      address: widget.address,
      amountSats: _maxAmount.value!,
    );

    _confirm(amountSats: _maxAmount.value!, feeSats: feeSats, isMax: true);
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
              client: widget.client,
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
        actions: [MaxAction(maxAmount: _maxAmount, entry: _entryKey)],
      ),
      body: SafeArea(
        child: AmountEntryWidget(
          key: _entryKey,
          client: widget.client,
          onConfirm: _handleConfirm,
          maxAmount: _maxAmount,
          onConfirmMax: _handleConfirmMax,
          buttonText: 'Continue',
        ),
      ),
    );
  }
}
