import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter/material.dart';
import 'package:pico/bridge_generated.dart/lib.dart';
import 'package:pico/bridge_generated.dart/client.dart';
import 'package:pico/bridge_generated.dart/factory.dart';
import 'package:pico/widgets/drawer_shell_widget.dart';
import 'package:pico/widgets/amount_display_widget.dart';
import 'package:pico/widgets/federation_chip_widget.dart';
import 'package:pico/widgets/primary_card_widget.dart';
import 'package:pico/widgets/async_button_widget.dart';
import 'package:pico/utils/drawer_utils.dart';

class EcashDrawer extends StatefulWidget {
  final PicoClientFactory clientFactory;
  final ECashWrapper ecash;

  const EcashDrawer({
    super.key,
    required this.clientFactory,
    required this.ecash,
  });

  static Future<bool?> show(
    BuildContext context, {
    required PicoClientFactory clientFactory,
    required ECashWrapper ecash,
  }) {
    return DrawerUtils.show<bool>(
      context: context,
      child: EcashDrawer(clientFactory: clientFactory, ecash: ecash),
    );
  }

  @override
  State<EcashDrawer> createState() => _EcashDrawerState();
}

class _EcashDrawerState extends State<EcashDrawer> {
  // Cached so the chip's FutureBuilder and the receive button look at
  // the same lookup — and so the lookup doesn't re-fire on every
  // rebuild.
  late final Future<PicoClient?> _issuer = widget.clientFactory.client(
    federationId: widget.ecash.federationId(),
  );

  Future<void> _handleReceive() async {
    final issuer = await _issuer;
    if (issuer == null) throw Exception('Federation is unknown');

    await issuer.ecashReceive(ecash: widget.ecash);

    if (!mounted) return;

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return DrawerShell(
      icon: PhosphorIconsRegular.coinVertical,
      title: 'Receive eCash',
      children: [
        // Read-only — the federation is fixed by the ecash bundle.
        // While loading or if the user has since left, the chip
        // silently drops; the receive button throws on the same null
        // and AsyncButton surfaces it as a toast.
        FutureBuilder<PicoClient?>(
          future: _issuer,
          builder: (_, snapshot) {
            final issuer = snapshot.data;
            if (issuer == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: FederationChip(
                clientFactory: widget.clientFactory,
                client: issuer,
              ),
            );
          },
        ),
        PrimaryCard(child: AmountDisplay(widget.ecash.amountSats())),
        const SizedBox(height: 16),
        AsyncButton(text: 'Receive', onPressed: _handleReceive),
      ],
    );
  }
}
