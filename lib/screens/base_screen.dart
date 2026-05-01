import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter/material.dart';
import 'package:pico/bridge_generated.dart/lib.dart';
import 'package:pico/bridge_generated.dart/client.dart';
import 'package:pico/bridge_generated.dart/factory.dart';
import 'package:pico/screens/federation_screen.dart';
import 'package:pico/screens/display_recovery_phrase_screen.dart';
import 'package:pico/screens/select_currency_screen.dart';
import 'package:pico/utils/notification_utils.dart';
import 'package:pico/utils/styles.dart';
import 'package:pico/utils/auth_utils.dart';
import 'package:pico/drawers/invite_scanner_drawer.dart';
import 'package:pico/drawers/leave_federation_drawer.dart';
import 'package:pico/widgets/bordered_list_widget.dart';
import 'package:pico/widgets/settings_card_widget.dart';

class BaseScreen extends StatefulWidget {
  final PicoClientFactory clientFactory;

  const BaseScreen({super.key, required this.clientFactory});

  @override
  State<BaseScreen> createState() => _BaseScreenState();
}

class _BaseScreenState extends State<BaseScreen> {
  List<FederationInfo> _federations = [];

  @override
  void initState() {
    super.initState();

    _refreshFederations(autoNavigate: true);
  }

  Future<void> _refreshFederations({bool autoNavigate = false}) async {
    final federations = await widget.clientFactory.listFederations();

    setState(() {
      _federations = federations;
    });

    if (autoNavigate && federations.length == 1) {
      _handleFederationTap(federations.first);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Pico')),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text('Settings', style: mediumStyle),
            ),
            const SizedBox(height: 8),
            BorderedList.column(
              children: [_buildSeedPhraseCard(), _buildCurrencyCard()],
            ),
            const SizedBox(height: 32),
            if (_federations.isEmpty)
              _buildOnboardingCard()
            else
              _buildFederationsListView(),
          ],
        ),
      ),
    ),
  );

  Widget _buildOnboardingCard() {
    return Column(
      children: [
        const SizedBox(height: 32),
        TextButton(
          onPressed: _showScannerDrawer,
          child: Text(
            'Join Federation',
            style: mediumStyle.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            'The federation cannot link payments to you or deduce your balance.',
            textAlign: TextAlign.center,
            style: smallStyle.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFederationsListView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Text('Federations', style: mediumStyle),
        ),
        const SizedBox(height: 8),
        BorderedList(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _federations.length,
          itemBuilder: (context, index) {
            final federation = _federations[index];
            return _buildFederationCard(federation);
          },
        ),
        Center(
          child: TextButton(
            onPressed: _showScannerDrawer,
            child: Text(
              'Join Federation',
              style: mediumStyle.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showScannerDrawer() {
    InviteScannerDrawer.show(
      context,
      clientFactory: widget.clientFactory,
      onJoin: _handleJoinFederation,
      onRecover: _handleRecoverFederation,
    );
  }

  void _navigateToClientScreen(PicoClient client) {
    if (!mounted) return;

    // Picomint runs recovery silently in the background, so we always
    // navigate straight to the federation screen — even mid-recovery.
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => FederationScreen(
              client: client,
              clientFactory: widget.clientFactory,
            ),
      ),
    );
  }

  Future<void> _handleJoinFederation(InviteCodeWrapper invite) async {
    final client = await widget.clientFactory.join(invite: invite);

    _refreshFederations();

    if (!mounted) return;

    Navigator.of(context).popUntil((route) => route.isFirst);

    _navigateToClientScreen(client);
  }

  Future<void> _handleRecoverFederation(InviteCodeWrapper invite) async {
    final client = await widget.clientFactory.recover(invite: invite);

    _refreshFederations();

    if (!mounted) return;

    Navigator.of(context).popUntil((route) => route.isFirst);

    _navigateToClientScreen(client);
  }

  Widget _buildSeedPhraseCard() {
    return SettingsCard(
      icon: PhosphorIconsRegular.key,
      title: 'Recovery Phrase',
      onTap: _handleSeedPhraseTap,
    );
  }

  Widget _buildCurrencyCard() {
    return SettingsCard(
      icon: PhosphorIconsRegular.currencyDollar,
      title: 'Select Currency',
      onTap: _handleCurrencyTap,
    );
  }

  Widget _buildFederationCard(FederationInfo federation) {
    return SettingsCard(
      icon: PhosphorIconsRegular.wallet,
      title: federation.name,
      onTap: () => _handleFederationTap(federation),
      onLongPress: () => _showLeaveFederationDrawer(federation),
    );
  }

  Future<void> _handleFederationTap(FederationInfo federation) async {
    try {
      final client = await widget.clientFactory.load(
        federationId: federation.id,
      );

      if (client == null) {
        if (mounted) {
          NotificationUtils.showError(context, 'Failed to load federation');
        }
        return;
      }

      _navigateToClientScreen(client);
    } catch (e) {
      if (mounted) {
        NotificationUtils.showError(context, e.toString());
      }
    }
  }

  void _showLeaveFederationDrawer(FederationInfo federation) {
    LeaveFederationDrawer.show(
      context,
      federation: federation,
      clientFactory: widget.clientFactory,
      onSuccess: _refreshFederations,
    );
  }

  Future<void> _handleCurrencyTap() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => SelectCurrencyScreen(clientFactory: widget.clientFactory),
      ),
    );
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
}
