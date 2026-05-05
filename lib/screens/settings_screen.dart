import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:pico/bridge_generated.dart/client.dart';
import 'package:pico/bridge_generated.dart/factory.dart';
import 'package:pico/screens/connection_status_screen.dart';
import 'package:pico/screens/display_recovery_phrase_screen.dart';
import 'package:pico/screens/select_currency_screen.dart';
import 'package:pico/utils/auth_utils.dart';
import 'package:pico/utils/notification_utils.dart';
import 'package:pico/utils/styles.dart';
import 'package:pico/widgets/bordered_list_widget.dart';
import 'package:pico/widgets/settings_card_widget.dart';

/// Settings hub: recovery phrase + currency, then a per-fed list where
/// each row shows a connection dot + balance subheader. Tapping a fed
/// drills into `ConnectionStatusScreen` (which carries the leave action).
class SettingsScreen extends StatefulWidget {
  final PicoClientFactory clientFactory;

  const SettingsScreen({super.key, required this.clientFactory});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  List<PicoClient> _clients = [];

  @override
  void initState() {
    super.initState();
    _refreshClients();
  }

  Future<void> _refreshClients() async {
    final clients = await widget.clientFactory.clients();
    if (!mounted) return;
    setState(() => _clients = clients);
  }

  Future<void> _onTapFederation(PicoClient client) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConnectionStatusScreen(
          client: client,
          clientFactory: widget.clientFactory,
        ),
      ),
    );
    // The connection screen pops itself on a successful leave;
    // re-fetch so the row disappears from the list.
    _refreshClients();
  }

  Future<void> _handleSeedPhraseTap() async {
    try {
      await requireBiometricAuth(context);

      if (!mounted) return;

      final seedPhrase = await widget.clientFactory.seedPhrase();

      if (!mounted) return;

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DisplayRecoveryPhraseScreen(seedPhrase: seedPhrase),
        ),
      );
    } catch (e) {
      if (mounted) {
        NotificationUtils.showError(context, e.toString());
      }
    }
  }

  Future<void> _handleCurrencyTap() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SelectCurrencyScreen(clientFactory: widget.clientFactory),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settings')),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BorderedList.column(
              children: [
                SettingsCard(
                  icon: PhosphorIconsRegular.key,
                  title: 'Recovery Phrase',
                  onTap: _handleSeedPhraseTap,
                ),
                SettingsCard(
                  icon: PhosphorIconsRegular.currencyDollar,
                  title: 'Select Currency',
                  onTap: _handleCurrencyTap,
                ),
              ],
            ),
            if (_clients.isNotEmpty) ...[
              const SizedBox(height: 32),
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text('Federations', style: mediumStyle),
              ),
              const SizedBox(height: 8),
              BorderedList.column(
                children: [
                  for (final client in _clients)
                    _FederationRow(
                      client: client,
                      onTap: () => _onTapFederation(client),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _FederationRow extends StatelessWidget {
  final PicoClient client;
  final VoidCallback onTap;

  const _FederationRow({required this.client, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ListTile(
      onTap: onTap,
      contentPadding: listTilePadding,
      leading: StreamBuilder<List<(String, bool)>>(
        stream: client.subscribeConnectionStatus(),
        builder: (_, snapshot) {
          final online = snapshot.data?.any((s) => s.$2) ?? false;
          return Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: online
                  ? scheme.primary
                  : scheme.primary.withValues(alpha: 0.3),
            ),
          );
        },
      ),
      title: FutureBuilder<String?>(
        future: client.federationName(),
        builder: (_, snapshot) =>
            Text(snapshot.data ?? '…', style: mediumStyle),
      ),
      subtitle: StreamBuilder<int>(
        stream: client.subscribeBalance(),
        builder: (_, snapshot) {
          final sats = snapshot.data ?? 0;
          return Text(
            '${NumberFormat('#,###').format(sats)} sat',
            style: smallStyle.copyWith(color: scheme.onSurfaceVariant),
          );
        },
      ),
    );
  }
}
