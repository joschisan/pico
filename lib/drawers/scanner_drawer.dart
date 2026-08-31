import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pico/bridge_generated.dart/app.dart';
import 'package:pico/bridge_generated.dart/client.dart';
import 'package:pico/bridge_generated.dart/fountain.dart';
import 'package:pico/bridge_generated.dart/lib.dart';
import 'package:pico/bridge_generated.dart/lnurl.dart';
import 'package:pico/drawers/ecash_drawer.dart';
import 'package:pico/drawers/invite_drawer.dart';
import 'package:pico/drawers/lightning_send_drawer.dart';
import 'package:pico/drawers/lnurl_drawer.dart';
import 'package:pico/utils/notification_utils.dart';
import 'package:pico/widgets/qr_scanner_widget.dart';
import 'package:pico/widgets/scanner_overlay_widget.dart';
import 'package:pico/screens/onchain_amount_screen.dart';

/// One scanner for everything: invite codes (always allowed),
/// payment-method inputs (only when a federation is warm). With no
/// federations joined the user can still scan an invite to onboard.
///
/// Presented full-screen rather than in a sheet, so the camera gets the whole
/// viewport and a QR only has to fill the viewfinder to read.
class ScannerDrawer extends StatefulWidget {
  final PicoAccount? account;
  final Pico pico;

  const ScannerDrawer({super.key, required this.account, required this.pico});

  static Future<void> show(
    BuildContext context, {
    required PicoAccount? account,
    required Pico pico,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ScannerDrawer(account: account, pico: pico),
      ),
    );
  }

  @override
  State<ScannerDrawer> createState() => _ScannerDrawerState();
}

class _ScannerDrawerState extends State<ScannerDrawer> {
  final _decoder = ECashDecoder();
  bool _isScanning = true;

  void _processInput(String input) {
    if (!_isScanning) return;

    // Invite codes always win and don't need a joined federation — that's
    // how the user joins their first one. InviteDrawer owns the add
    // lifecycle so its own (still-mounted) context drives the pop
    // and toast.
    final invite = parseInviteCode(invite: input);
    if (invite != null) {
      _isScanning = false;
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop();
      InviteDrawer.show(context, invite: invite, pico: widget.pico);
      return;
    }

    final account = widget.account;
    if (account == null) {
      _isScanning = false;
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop();
      NotificationUtils.showError(context, 'Add a mint first');
      return;
    }

    final parsers = [
      (
        parseBolt11Invoice(invoice: input),
        (dynamic result) => LightningSendDrawer.show(
          context,
          account: account,
          pico: widget.pico,
          invoice: result,
        ),
      ),
      (
        parseEcash(ecash: input),
        (dynamic result) => EcashDrawer.show(
          context,
          selected: account,
          pico: widget.pico,
          ecash: result,
        ),
      ),
      (
        parseBitcoinAddress(address: input),
        // An address carries no amount, so there is nothing to confirm before
        // asking for one — go straight to the amount entry. The scanner has
        // already popped itself by the time this runs.
        (dynamic result) => Navigator.of(context).push(
          MaterialPageRoute(
            builder:
                (_) => OnchainAmountScreen(
                  account: account,
                  pico: widget.pico,
                  address: result,
                ),
          ),
        ),
      ),
      (
        parseLnurl(request: input),
        (dynamic result) => LnurlDrawer.show(
          context,
          account: account,
          pico: widget.pico,
          lnurl: result,
        ),
      ),
      (
        _decoder.addFragment(fragment: input),
        (dynamic result) => EcashDrawer.show(
          context,
          selected: account,
          pico: widget.pico,
          ecash: result,
        ),
      ),
    ];

    for (final (result, showDrawer) in parsers) {
      if (result != null) {
        _isScanning = false;
        HapticFeedback.mediumImpact();
        Navigator.of(context).pop();
        showDrawer(result);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Let the camera bleed behind a transparent app bar, which still carries
      // the fullscreen-dialog Close (✕) over the preview.
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          QrScannerWidget(onScan: _processInput),
          const IgnorePointer(child: ScannerOverlay()),
        ],
      ),
    );
  }
}
