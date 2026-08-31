import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:pico/bridge_generated.dart/app.dart';
import 'package:pico/bridge_generated.dart/client.dart';
import 'package:pico/bridge_generated.dart/currency.dart';
import 'package:pico/utils/drawer_utils.dart';
import 'package:pico/utils/federation_utils.dart';
import 'package:pico/widgets/bordered_list_widget.dart';
import 'package:pico/widgets/drawer_shell_widget.dart';
import 'package:pico/widgets/settings_card_widget.dart';

/// Bottom-sheet settings: app-wide rows (recovery phrase, currency) above the
/// selected account's own (which account, connectivity, and leaving the
/// mint). Each row pops the drawer
/// and hands off to a caller callback, whose stable context owns the
/// navigation — this drawer's own context dies with the pop.
class SettingsDrawer extends StatefulWidget {
  final PicoAccount account;
  final Pico pico;
  final VoidCallback onSelectRecoveryPhrase;
  final VoidCallback onSelectCurrency;
  final VoidCallback onSelectAccount;
  final VoidCallback onSelectConnectivity;
  // Null with only one federation joined: leaving the last one would strand
  // the wallet on onboarding, so the row is left out entirely.
  final VoidCallback? onSelectLeave;

  const SettingsDrawer({
    super.key,
    required this.account,
    required this.pico,
    required this.onSelectRecoveryPhrase,
    required this.onSelectCurrency,
    required this.onSelectAccount,
    required this.onSelectConnectivity,
    required this.onSelectLeave,
  });

  static Future<void> show(
    BuildContext context, {
    required PicoAccount account,
    required Pico pico,
    required VoidCallback onSelectRecoveryPhrase,
    required VoidCallback onSelectCurrency,
    required VoidCallback onSelectAccount,
    required VoidCallback onSelectConnectivity,
    required VoidCallback? onSelectLeave,
  }) {
    return DrawerUtils.show(
      context: context,
      child: SettingsDrawer(
        account: account,
        pico: pico,
        onSelectRecoveryPhrase: onSelectRecoveryPhrase,
        onSelectCurrency: onSelectCurrency,
        onSelectAccount: onSelectAccount,
        onSelectConnectivity: onSelectConnectivity,
        onSelectLeave: onSelectLeave,
      ),
    );
  }

  @override
  State<SettingsDrawer> createState() => _SettingsDrawerState();
}

class _SettingsDrawerState extends State<SettingsDrawer> {
  // Cached so rebuilds don't re-subscribe. Each entry is `(name, rttMs)`: a
  // non-null RTT means that guardian is connected.
  late final Stream<List<(String, double?)>> _connectionStream = widget.pico
      .subscribeConnectionStatus(federationId: widget.account.federationId);

  late final String? _currencyName =
      findFiatCurrency(code: widget.pico.currencyCode())?.name;

  /// Pops the drawer, then runs the caller's action against its own context.
  void _select(VoidCallback action) {
    Navigator.of(context).pop();
    action();
  }

  @override
  Widget build(BuildContext context) {
    final onSelectLeave = widget.onSelectLeave;

    return DrawerShell(
      children: [
        BorderedList.column(
          children: [
            SettingsCard(
              icon: PhosphorIconsRegular.key,
              title: 'Recovery Phrase',
              subtitle: 'Backup your Wallet',
              onTap: () => _select(widget.onSelectRecoveryPhrase),
            ),
            SettingsCard(
              icon: PhosphorIconsRegular.currencyDollar,
              title: 'Select Currency',
              subtitle: _currencyName,
              onTap: () => _select(widget.onSelectCurrency),
            ),
            SettingsCard(
              icon: PhosphorIconsRegular.stack,
              title: 'Select Account',
              subtitle: widget.account.account,
              onTap: () => _select(widget.onSelectAccount),
            ),
            _buildConnectivityCard(),
            // Destroys what the mint still holds, so it sits at the bottom
            // away from the rows that only navigate.
            if (onSelectLeave != null)
              SettingsCard(
                icon: PhosphorIconsRegular.trash,
                title: 'Remove Mint',
                subtitle: widget.account.federationName,
                onTap: () => _select(onSelectLeave),
              ),
          ],
        ),
      ],
    );
  }

  /// Carries the same amber/plain split as the home row, so opening settings
  /// on a degraded federation says so before the screen behind it is gone.
  Widget _buildConnectivityCard() {
    return StreamBuilder<List<(String, double?)>>(
      stream: _connectionStream,
      builder: (context, snapshot) {
        final statuses = snapshot.data;

        final operational =
            statuses != null &&
            federationOperational(
              online: statuses.where((s) => s.$2 != null).length,
              total: statuses.length,
            );

        return SettingsCard(
          icon: PhosphorIconsRegular.broadcast,
          // Left untinted until the first status lands, so amber only ever
          // means "too few guardians to sign".
          iconColor:
              statuses == null ? null : (operational ? null : Colors.amber),
          title: 'Connectivity',
          subtitle:
              statuses == null ? null : (operational ? 'Online' : 'Offline'),
          onTap: () => _select(widget.onSelectConnectivity),
        );
      },
    );
  }
}
