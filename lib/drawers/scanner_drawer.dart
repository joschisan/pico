import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pico/bridge_generated.dart/client.dart';
import 'package:pico/bridge_generated.dart/factory.dart';
import 'package:pico/bridge_generated.dart/fountain.dart';
import 'package:pico/bridge_generated.dart/lib.dart';
import 'package:pico/bridge_generated.dart/lnurl.dart';
import 'package:pico/drawers/ecash_drawer.dart';
import 'package:pico/drawers/invite_drawer.dart';
import 'package:pico/drawers/lightning_invoice_drawer.dart';
import 'package:pico/drawers/lnurl_drawer.dart';
import 'package:pico/drawers/onchain_address_drawer.dart';
import 'package:pico/utils/drawer_utils.dart';
import 'package:pico/utils/notification_utils.dart';
import 'package:pico/widgets/qr_scanner_widget.dart';

/// One scanner for everything: invite codes (always allowed),
/// payment-method inputs (only when a federation is warm). With no
/// federations joined the user can still scan an invite to onboard.
class ScannerDrawer extends StatefulWidget {
  final PicoClient? client;
  final PicoClientFactory clientFactory;

  const ScannerDrawer({
    super.key,
    required this.client,
    required this.clientFactory,
  });

  static Future<void> show(
    BuildContext context, {
    required PicoClient? client,
    required PicoClientFactory clientFactory,
  }) {
    return DrawerUtils.show(
      context: context,
      child: ScannerDrawer(client: client, clientFactory: clientFactory),
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

    // Invite codes always win and don't need a warm client — that's
    // how the user joins their first federation. InviteDrawer owns the
    // join/recover lifecycle so its own (still-mounted) context drives
    // the pop and toast.
    final invite = parseInviteCode(invite: input);
    if (invite != null) {
      _isScanning = false;
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop();
      InviteDrawer.show(
        context,
        invite: invite,
        clientFactory: widget.clientFactory,
      );
      return;
    }

    final client = widget.client;
    if (client == null) {
      _isScanning = false;
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop();
      NotificationUtils.showError(context, 'Join a federation first');
      return;
    }

    final parsers = [
      (
        parseBolt11Invoice(invoice: input),
        (dynamic result) => LightningInvoiceDrawer.show(
          context,
          client: client,
          invoice: result,
        ),
      ),
      (
        parseEcash(ecash: input),
        (dynamic result) =>
            EcashDrawer.show(context, client: client, ecash: result),
      ),
      (
        parseBitcoinAddress(address: input),
        (dynamic result) => OnchainAddressDrawer.show(
          context,
          client: client,
          clientFactory: widget.clientFactory,
          address: result,
        ),
      ),
      (
        parseLnurl(request: input),
        (dynamic result) => LnurlDrawer.show(
          context,
          client: client,
          clientFactory: widget.clientFactory,
          lnurl: result,
        ),
      ),
      (
        _decoder.addFragment(fragment: input),
        (dynamic result) =>
            EcashDrawer.show(context, client: client, ecash: result),
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
    return QrScannerWidget(onScan: _processInput);
  }
}
