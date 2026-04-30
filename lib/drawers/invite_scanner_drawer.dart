import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pico/bridge_generated.dart/lib.dart';
import 'package:pico/bridge_generated.dart/factory.dart';
import 'package:pico/utils/notification_utils.dart';
import 'package:pico/widgets/qr_scanner_widget.dart';
import 'package:pico/drawers/invite_drawer.dart';
import 'package:pico/utils/drawer_utils.dart';

class InviteScannerDrawer extends StatefulWidget {
  final PicoClientFactory clientFactory;
  final Future<void> Function(InviteCodeWrapper) onJoin;
  final Future<void> Function(InviteCodeWrapper) onRecover;

  const InviteScannerDrawer({
    super.key,
    required this.clientFactory,
    required this.onJoin,
    required this.onRecover,
  });

  static Future<void> show(
    BuildContext context, {
    required PicoClientFactory clientFactory,
    required Future<void> Function(InviteCodeWrapper) onJoin,
    required Future<void> Function(InviteCodeWrapper) onRecover,
  }) {
    return DrawerUtils.show(
      context: context,
      child: InviteScannerDrawer(
        clientFactory: clientFactory,
        onJoin: onJoin,
        onRecover: onRecover,
      ),
    );
  }

  @override
  State<InviteScannerDrawer> createState() => _InviteScannerDrawerState();
}

class _InviteScannerDrawerState extends State<InviteScannerDrawer> {
  bool _isScanning = true;

  void _processInput(String invite) {
    if (!_isScanning) return;

    final inviteCode = parseInviteCode(invite: invite);

    if (inviteCode != null) {
      _isScanning = false;
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop();

      InviteDrawer.show(
        context,
        invite: inviteCode,
        onJoin: widget.onJoin,
        onRecover: widget.onRecover,
      );
      return;
    }

    if (mounted) {
      NotificationUtils.showError(context, 'Failed to parse invite code');
    }
  }

  @override
  Widget build(BuildContext context) {
    return QrScannerWidget(onScan: _processInput);
  }
}
