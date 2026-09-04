import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pico/bridge_generated.dart/app.dart';
import 'package:pico/bridge_generated.dart/client.dart';
import 'package:pico/bridge_generated.dart/fountain.dart';
import 'package:pico/utils/input_router.dart';
import 'package:pico/utils/notification_utils.dart';
import 'package:pico/widgets/qr_scanner_widget.dart';
import 'package:pico/widgets/scanner_overlay_widget.dart';

/// One scanner for everything: invite codes (always allowed),
/// payment-method inputs (only when a mint is warm). With no
/// mints added the user can still scan an invite to onboard.
///
/// Presented full-screen rather than in a sheet, so the camera gets the whole
/// viewport and a QR only has to fill the viewfinder to read.
class ScannerScreen extends StatefulWidget {
  final PicoAccount? account;
  final Pico pico;

  const ScannerScreen({super.key, required this.account, required this.pico});

  static Future<void> show(
    BuildContext context, {
    required PicoAccount? account,
    required Pico pico,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ScannerScreen(account: account, pico: pico),
      ),
    );
  }

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final _decoder = EcashDecoder();
  bool _isScanning = true;

  void _processInput(String input) {
    if (!_isScanning) return;

    final action = matchInput(
      context,
      pico: widget.pico,
      input: input,
      account: widget.account,
      decoder: _decoder,
    );

    if (action != null) {
      _isScanning = false;
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop();
      // The scanner has already popped itself by the time this runs; the
      // flows it opens live on this State's still-mounted context.
      action();
      return;
    }

    // With no mint added only invites match, so any other scan pops with
    // the one instruction that unblocks everything else.
    if (widget.account == null) {
      _isScanning = false;
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop();
      NotificationUtils.showError(context, 'Add a mint first');
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
