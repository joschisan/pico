import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:pico/bridge_generated.dart/app.dart';
import 'package:pico/bridge_generated.dart/client.dart';
import 'package:pico/screens/scanner_screen.dart';
import 'package:pico/screens/home_screen.dart';
import 'package:pico/utils/styles.dart';
import 'package:pico/widgets/balanced_text_widget.dart';
import 'package:pico/widgets/circular_action_button_widget.dart';

/// Where a wallet with no mint lands. Scanning an invite is the only
/// thing to do here, so the screen is just that: the reason and the action.
///
/// Watches for the first mint and hands the wallet to [HomeScreen] for
/// good — removing the last mint is blocked, so nothing comes back here
/// short of a restart with an empty wallet.
class OnboardingScreen extends StatefulWidget {
  final Pico pico;

  const OnboardingScreen({super.key, required this.pico});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  StreamSubscription<List<PicoAccount>>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = widget.pico.subscribeAccounts().listen((accounts) {
      if (!mounted || accounts.isEmpty) return;
      // Clears the scanner and invite drawers along with this screen, so the
      // wallet lands on the home screen with nothing stacked behind it. The
      // invite drawer's own pop is a no-op once its route is gone.
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder:
              (_) => HomeScreen(pico: widget.pico, initialAccounts: accounts),
        ),
        (_) => false,
      );
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: BalancedText(
                'Add a mint to transact.',
                textAlign: TextAlign.center,
                style: smallStyle.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 24),
            CircularActionButton(
              icon: PhosphorIconsRegular.qrCode,
              label: 'Scan',
              // No account to hand the scanner — with none added it accepts
              // invite codes only, which is exactly the one input this screen
              // is here to take.
              onTap:
                  () => ScannerScreen.show(
                    context,
                    account: null,
                    pico: widget.pico,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
