import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:pico/bridge_generated.dart/factory.dart';
import 'package:pico/screens/display_recovery_phrase_screen.dart';
import 'package:pico/screens/select_currency_screen.dart';
import 'package:pico/utils/auth_utils.dart';
import 'package:pico/utils/notification_utils.dart';
import 'package:pico/widgets/bordered_list_widget.dart';
import 'package:pico/widgets/settings_card_widget.dart';

/// Settings hub: recovery phrase + currency. The federation list moved
/// to the home screen — tapping a fed there drills into the connection
/// status / leave flow directly.
class SettingsScreen extends StatelessWidget {
  final PicoClientFactory clientFactory;

  const SettingsScreen({super.key, required this.clientFactory});

  Future<void> _handleSeedPhraseTap(BuildContext context) async {
    try {
      await requireBiometricAuth(context);

      if (!context.mounted) return;

      final seedPhrase = await clientFactory.seedPhrase();

      if (!context.mounted) return;

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DisplayRecoveryPhraseScreen(seedPhrase: seedPhrase),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        NotificationUtils.showError(context, e.toString());
      }
    }
  }

  Future<void> _handleCurrencyTap(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SelectCurrencyScreen(clientFactory: clientFactory),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settings')),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: BorderedList.column(
          children: [
            SettingsCard(
              icon: PhosphorIconsRegular.key,
              title: 'Recovery Phrase',
              onTap: () => _handleSeedPhraseTap(context),
            ),
            SettingsCard(
              icon: PhosphorIconsRegular.currencyDollar,
              title: 'Select Currency',
              onTap: () => _handleCurrencyTap(context),
            ),
          ],
        ),
      ),
    ),
  );
}
