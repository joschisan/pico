import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pico/utils/styles.dart';
import 'package:pico/bridge_generated.dart/client.dart';
import 'package:pico/bridge_generated.dart/currency.dart';
import 'package:pico/utils/currency_utils.dart';
import 'package:pico/widgets/amount_headline_widget.dart';
import 'package:pico/widgets/async_button_widget.dart';

class AmountEntryWidget extends StatefulWidget {
  final PicoClient client;
  final Future<void> Function(int amountSats) onConfirm;
  final void Function(int currentAmount)? onAmountChanged;
  final String buttonText;
  // The largest amount this screen can send: the balance on ecash, which
  // pays no fee, and the balance less the rail's fees everywhere else. Null
  // on the flows with no max to offer — a receive has no ceiling, and the
  // rails that do have one need a moment to price it. Read when max mode is
  // entered from the app bar's Max action, and to refill the figure across a
  // currency switch.
  final ValueListenable<int?>? maxAmount;
  // Sends everything, as its own call rather than [onConfirm] with the max as
  // its amount: emptying an account funds from every note and mints no
  // change, which is a different operation downstream, not a large payment.
  // Offered only alongside [maxAmount].
  final Future<void> Function()? onConfirmMax;

  const AmountEntryWidget({
    super.key,
    required this.client,
    required this.onConfirm,
    this.onAmountChanged,
    this.buttonText = 'Confirm',
    this.maxAmount,
    this.onConfirmMax,
  });

  @override
  State<AmountEntryWidget> createState() => AmountEntryWidgetState();
}

class AmountEntryWidgetState extends State<AmountEntryWidget> {
  int _currentAmount = 0;
  bool _enterFiat = false;
  // Whether the figure on screen is the max because the user asked for
  // everything, rather than a number they typed that happens to equal it.
  // Confirm routes on this, so it is cleared by anything that makes the
  // figure the user's own again — a digit, a backspace, a clear. Switching
  // currency keeps it: the same max in the other unit is still the max, so
  // the figure is refilled rather than reinterpreted.
  bool _isMax = false;
  // Snapshot the selected currency once on entry. The user can't change
  // currency from this flow, so a fixed string is correct and spares a db read
  // per keystroke — the home screen, which must track live switches, reads it
  // fresh instead (see `cachedFiatAmount`).
  late final String _currencyCode = widget.client.currencyCode();

  @override
  void initState() {
    super.initState();
    // Refresh the exchange-rate cache on entry so the fiat amount rows on the
    // following confirm/display screen stay populated even if the rate cached
    // at home start has since expired.
    widget.client.prefetchExchangeRates();
  }

  FiatCurrency get _currency {
    return findFiatCurrency(code: _currencyCode)!;
  }

  void _onKeyboardTap(String value) {
    // The amount display auto-shrinks to fit, so up to 10 digits stay on one
    // line — a 10th digit reaches 10 BTC in sats (1,000,000,000 sat).
    if (_currentAmount.toString().length >= 10) return;

    setState(() {
      _currentAmount = _currentAmount * 10 + int.parse(value);
      _isMax = false;
    });

    // Notify parent about amount change (always in sat)
    _notifyParentAmountChanged();
  }

  void _onBackspace() {
    if (_currentAmount > 0) {
      setState(() {
        _currentAmount = _currentAmount ~/ 10;
        _isMax = false;
      });

      // Notify parent about amount change (always in sat)
      _notifyParentAmountChanged();
    }
  }

  void _onClear() {
    setState(() {
      _currentAmount = 0;
      _isMax = false;
    });

    // Notify parent about amount change
    widget.onAmountChanged?.call(0);
  }

  Future<void> _notifyParentAmountChanged() async {
    if (widget.onAmountChanged == null) return;

    if (_enterFiat) {
      final amountSats = await widget.client.fiatToSats(
        amountFiat: _fiatAmount,
        currencyCode: _currencyCode,
      );
      widget.onAmountChanged?.call(amountSats);
    } else {
      // Already in sat
      widget.onAmountChanged?.call(_currentAmount);
    }
  }

  double get _fiatAmount => _currentAmount / pow(10, _currency.decimalDigits);

  String _formatFiatAmount() => formatFiat(_currency, _fiatAmount);

  /// The digit buffer that shows [sats] in the unit the display is currently
  /// in: sats as they are, or the fiat value in minor units. Null in fiat
  /// with no rate cached, which is the one case that can't be shown as money.
  int? _bufferFor(int sats, {required bool enterFiat}) {
    if (!enterFiat) return sats;

    final fiat = widget.client.satsToFiat(
      amountSats: sats,
      currencyCode: _currencyCode,
    );

    if (fiat == null) return null;

    return (fiat * pow(10, _currency.decimalDigits)).round();
  }

  /// Fills the figure with the max and arms max mode — the app bar's Max
  /// action reaches this through a [GlobalKey], since the action lives in
  /// the hosting screen's app bar and the figure lives here. Comes with the
  /// haptic every commitment in the app gets: it rewrites an amount that may
  /// already be typed, and a tap that silently did that would read as a slip
  /// of the finger. A no-op until a max has been priced, though the action
  /// stays untappable until then anyway.
  void enterMax() {
    final sats = widget.maxAmount?.value;

    if (sats == null || sats == 0) return;

    HapticFeedback.lightImpact();

    _onMax(sats);
  }

  /// Fills the display with the max, in whichever unit is on screen. The
  /// figure is only ever the display: what confirm sends is its own max
  /// operation, so the cent the conversion rounds off costs nothing. Falls
  /// back to sats when no rate has been cached, which is the only honest way
  /// to show the figure there.
  void _onMax(int sats) {
    final buffer = _bufferFor(sats, enterFiat: _enterFiat);

    setState(() {
      _currentAmount = buffer ?? sats;
      _enterFiat = buffer != null && _enterFiat;
      _isMax = true;
    });

    // The parent prices in sats, so it gets the max itself rather than the
    // figure standing in for it.
    widget.onAmountChanged?.call(sats);
  }

  /// Swaps the unit the figure is read in. The digits stay put and change
  /// meaning — a deliberate reinterpretation, since they are the user's — but
  /// a max figure is refilled instead: it stands for the balance, and the
  /// balance is the same money in either unit.
  void _toggleCurrency() {
    final maxSats = _isMax ? widget.maxAmount?.value : null;
    final buffer =
        maxSats == null ? null : _bufferFor(maxSats, enterFiat: !_enterFiat);

    setState(() {
      _enterFiat = !_enterFiat;
      // No rate cached, so the balance can't be shown as money: the figure
      // becomes whatever the digits now read as, which is no longer a claim
      // about the balance.
      _isMax = maxSats != null && buffer != null;

      if (buffer != null) _currentAmount = buffer;
    });

    // Prefetch exchange rates when switching to fiat mode
    if (_enterFiat) {
      widget.client.prefetchExchangeRates();
    }

    if (maxSats != null && buffer != null) {
      widget.onAmountChanged?.call(maxSats);
    } else {
      // Same digits, different sat value — parent's fee preview would
      // otherwise stay frozen on the old interpretation.
      _notifyParentAmountChanged();
    }
  }

  Future<void> _handleConfirm() async {
    // Everything goes by its own call, which spends the notes the account
    // holds rather than an amount named in sats that they may not add up to.
    // Ahead of the empty check: a balance worth less than a cent shows as
    // zero in fiat, and it is still a balance to send.
    if (_isMax) {
      await widget.onConfirmMax!();

      return;
    }

    if (_currentAmount == 0) {
      throw 'Please enter an amount';
    }

    final amountSats =
        _enterFiat
            ? await widget.client.fiatToSats(
              amountFiat: _fiatAmount,
              currencyCode: _currencyCode,
            )
            : _currentAmount;

    await widget.onConfirm(amountSats);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Amount display - fills remaining space above confirm button
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleCurrency,
            child: Center(
              child: AmountHeadline(
                unit: _enterFiat ? _currency.name : 'Bitcoin',
                figure:
                    _enterFiat
                        ? Text(
                          _formatFiatAmount(),
                          textAlign: TextAlign.center,
                          style: amountStyle,
                        )
                        : SatsFigure.sats(_currentAmount),
              ),
            ),
          ),
        ),

        // Confirm button
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: AsyncButton(
            text: widget.buttonText,
            onPressed: _handleConfirm,
          ),
        ),

        const SizedBox(height: 16),

        // Custom number pad
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 2.0,
          children: [
            _buildNumberButton('1'),
            _buildNumberButton('2'),
            _buildNumberButton('3'),
            _buildNumberButton('4'),
            _buildNumberButton('5'),
            _buildNumberButton('6'),
            _buildNumberButton('7'),
            _buildNumberButton('8'),
            _buildNumberButton('9'),
            _buildActionButton(PhosphorIconsRegular.x, _onClear),
            _buildNumberButton('0'),
            _buildActionButton(PhosphorIconsRegular.arrowLeft, _onBackspace),
          ],
        ),
      ],
    );
  }

  Widget _buildNumberButton(String number) {
    return Material(
      color: Colors.transparent,
      borderRadius: cornerRadius,
      child: InkWell(
        borderRadius: cornerRadius,
        onTap: () => _onKeyboardTap(number),
        child: Center(child: Text(number, style: largeStyle)),
      ),
    );
  }

  Widget _buildActionButton(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      borderRadius: cornerRadius,
      child: InkWell(
        borderRadius: cornerRadius,
        onTap: onTap,
        child: Center(child: Icon(icon, size: smallIconSize)),
      ),
    );
  }
}
