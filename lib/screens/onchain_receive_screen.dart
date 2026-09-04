import 'dart:async';

import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter/material.dart';
import 'package:pico/bridge_generated.dart/app.dart';
import 'package:pico/bridge_generated.dart/client.dart';
import 'package:pico/bridge_generated.dart/lib.dart';
import 'package:pico/drawers/mint_details_drawer.dart';
import 'package:pico/utils/notification_utils.dart';
import 'package:pico/utils/styles.dart';
import 'package:pico/widgets/async_icon_button_widget.dart';
import 'package:pico/widgets/qr_code_widget.dart';
import 'package:pico/widgets/bleed_list_widget.dart';
import 'package:pico/widgets/shareable_row_widget.dart';
import 'package:pico/widgets/bleed_column_widget.dart';
import 'package:pico/widgets/scrollable_body_widget.dart';

/// Shows a deposit address the caller has already derived. The address comes
/// from the mirrored onchain state without a round trip, so the home screen
/// reads it before pushing this route and the screen has nothing to load.
class OnchainReceiveScreen extends StatelessWidget {
  final String address;
  final Pico pico;
  final MintIdWrapper mint;

  const OnchainReceiveScreen({
    super.key,
    required this.address,
    required this.pico,
    required this.mint,
  });

  Future<void> _showDetails(BuildContext context) async {
    final MintStats stats;
    try {
      stats = await pico.mintStats(mint: mint);
    } catch (error) {
      if (context.mounted) {
        NotificationUtils.showError(context, error.toString());
      }
      return;
    }

    if (!context.mounted) return;

    // Don't await the drawer's dismissal here, otherwise the icon's spinner
    // keeps running for as long as the drawer stays open.
    unawaited(MintDetailsDrawer.show(context, pico: pico, stats: stats));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Receive Onchain'),
      actions: [
        AsyncIconButton(
          icon: PhosphorIconsRegular.dotsThreeVertical,
          onPressed: () => _showDetails(context),
        ),
      ],
    ),
    body: ScrollableBody(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        child: BleedColumn(
          children: [
            QrCodeWidget(data: address),
            const SizedBox(height: 16),
            BleedList.column(
              children: [ShareableRow(data: address, label: 'Bitcoin Address')],
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    'Confirmed onchain payments will take about an hour to appear.',
                    style: smallStyle.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
