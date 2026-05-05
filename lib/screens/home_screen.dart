import 'dart:async';
import 'dart:math';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart' hide Notification;
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:pico/bridge_generated.dart/client.dart';
import 'package:pico/bridge_generated.dart/events.dart';
import 'package:pico/bridge_generated.dart/factory.dart';
import 'package:pico/bridge_generated.dart/lib.dart';
import 'package:pico/bridge_generated.dart/lnurl.dart';
import 'package:pico/drawers/ecash_drawer.dart';
import 'package:pico/drawers/lightning_invoice_drawer.dart';
import 'package:pico/drawers/lnurl_drawer.dart';
import 'package:pico/drawers/onchain_address_drawer.dart';
import 'package:pico/drawers/payment_details_drawer.dart';
import 'package:pico/drawers/scanner_drawer.dart';
import 'package:pico/screens/connection_status_screen.dart';
import 'package:pico/screens/display_contacts_screen.dart';
import 'package:pico/screens/ecash_amount_screen.dart';
import 'package:pico/screens/invoice_amount_screen.dart';
import 'package:pico/screens/lightning_address_entry_screen.dart';
import 'package:pico/screens/settings_screen.dart';
import 'package:pico/screens/wallet_v2_receive_screen.dart';
import 'package:pico/utils/notification_utils.dart';
import 'package:pico/utils/styles.dart';
import 'package:pico/widgets/animated_balance_widget.dart';
import 'package:pico/widgets/bordered_list_widget.dart';
import 'package:pico/widgets/recent_payments_widget.dart';

/// Multimint home: aggregated balance + global recent activity + three
/// receive buttons that auto-pick a fresh random client per tap. The
/// picomint eventlog is daemon-wide so recent ops and notifications come
/// from a single factory-level stream — no per-client merging needed.
class HomeScreen extends StatefulWidget {
  final PicoClientFactory clientFactory;

  const HomeScreen({super.key, required this.clientFactory});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _random = Random();

  late final Stream<List<OperationSummary>> _recentStream;
  late final AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;
  StreamSubscription<Notification>? _notificationSubscription;
  StreamSubscription<List<PicoClient>>? _clientsSubscription;

  List<PicoClient> _clients = [];

  @override
  void initState() {
    super.initState();
    _recentStream = widget.clientFactory.subscribeRecentOperations();
    _notificationSubscription = widget.clientFactory
        .subscribeNotifications()
        .listen(_handleNotification);
    _clientsSubscription = widget.clientFactory.subscribeClients().listen((
      clients,
    ) {
      if (!mounted) return;
      setState(() => _clients = clients);
    });
    _initDeepLinks();
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    _notificationSubscription?.cancel();
    _clientsSubscription?.cancel();
    super.dispose();
  }

  void _handleNotification(Notification notification) {
    if (!mounted) return;
    switch (notification) {
      case Notification_LightningReceived(:final amountSats):
        NotificationUtils.showReceive(
          context,
          amountSats.toInt(),
          PaymentType.lightning,
        );
      case Notification_OnchainReceived(:final amountSats):
        NotificationUtils.showReceive(
          context,
          amountSats.toInt(),
          PaymentType.bitcoin,
        );
      case Notification_LightningRefunding():
        HapticFeedback.heavyImpact();
        NotificationUtils.showWarning(context, 'Lightning Refund');
      case Notification_TransactionRejected():
        HapticFeedback.heavyImpact();
        NotificationUtils.showError(context, 'Transaction Rejected');
    }
  }

  void _initDeepLinks() {
    _appLinks = AppLinks();
    _linkSubscription = _appLinks.uriLinkStream.listen(_handleDeepLink);
    _appLinks.getInitialLink().then((uri) {
      if (uri != null) _handleDeepLink(uri);
    });
  }

  void _handleDeepLink(Uri uri) {
    final input = uri.toString();
    final client = _pickClient();
    if (client == null) return;

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
        parseEcash(notes: input),
        (dynamic result) =>
            EcashDrawer.show(context, client: client, notes: result),
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
    ];

    for (final (result, showDrawer) in parsers) {
      if (result != null) {
        showDrawer(result);
        return;
      }
    }
  }

  /// Auto-pick a random warm client for actions that are payment-type
  /// agnostic. Returns null only when no federations are joined; the
  /// onboarding empty-state handles that case before the user can tap
  /// anything.
  PicoClient? _pickClient() {
    if (_clients.isEmpty) return null;
    return _clients[_random.nextInt(_clients.length)];
  }

  void _onCreateInvoice() {
    final client = _pickClient();
    if (client == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => InvoiceAmountScreen(
          client: client,
          clientFactory: widget.clientFactory,
        ),
      ),
    );
  }

  void _onSendEcash() {
    final client = _pickClient();
    if (client == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EcashAmountScreen(
          client: client,
          clientFactory: widget.clientFactory,
        ),
      ),
    );
  }

  void _onReceiveBitcoin() {
    final client = _pickClient();
    if (client == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WalletV2ReceiveScreen(
          client: client,
          clientFactory: widget.clientFactory,
        ),
      ),
    );
  }

  void _onLightningAddress() {
    final client = _pickClient();
    if (client == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LightningAddressEntryScreen(
          client: client,
          clientFactory: widget.clientFactory,
        ),
      ),
    );
  }

  void _onContacts() {
    final client = _pickClient();
    if (client == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DisplayContactsScreen(
          client: client,
          clientFactory: widget.clientFactory,
        ),
      ),
    );
  }

  void _onScan() {
    ScannerDrawer.show(
      context,
      client: _pickClient(),
      clientFactory: widget.clientFactory,
    );
  }

  Future<void> _onSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(clientFactory: widget.clientFactory),
      ),
    );
  }

  void _onTapFederation(PicoClient client) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConnectionStatusScreen(
          client: client,
          clientFactory: widget.clientFactory,
        ),
      ),
    );
  }

  void _showEventDetails(OperationSummary event) {
    PaymentDetailsDrawer.show(
      context,
      clientFactory: widget.clientFactory,
      event: event,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pico'),
        centerTitle: false,
        actions: [
          if (_clients.isNotEmpty) ...[
            IconButton(
              icon: const Icon(PhosphorIconsRegular.at, size: smallIconSize),
              onPressed: _onLightningAddress,
            ),
            IconButton(
              icon: const Icon(
                PhosphorIconsRegular.users,
                size: smallIconSize,
              ),
              onPressed: _onContacts,
            ),
          ],
          IconButton(
            icon: const Icon(PhosphorIconsRegular.qrCode, size: smallIconSize),
            onPressed: _onScan,
          ),
          IconButton(
            icon: const Icon(PhosphorIconsRegular.gear, size: smallIconSize),
            onPressed: _onSettings,
          ),
        ],
      ),
      body: _clients.isEmpty
          ? const Center(child: _OnboardingCard())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  BorderedList.column(
                    children: [
                      for (final client in _clients)
                        _FederationRow(
                          client: client,
                          onTap: () => _onTapFederation(client),
                        ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _CircularActionButton(
                        icon: PhosphorIconsRegular.lightning,
                        label: 'Lightning',
                        onTap: _onCreateInvoice,
                      ),
                      _CircularActionButton(
                        icon: PhosphorIconsRegular.link,
                        label: 'Onchain',
                        onTap: _onReceiveBitcoin,
                      ),
                      _CircularActionButton(
                        icon: PhosphorIconsRegular.coinVertical,
                        label: 'eCash',
                        onTap: _onSendEcash,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  RecentPayments(
                    clientFactory: widget.clientFactory,
                    stream: _recentStream,
                    onTransactionTap: _showEventDetails,
                  ),
                ],
              ),
            ),
    );
  }
}

class _CircularActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _CircularActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      borderRadius: BorderRadius.circular(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Theme.of(context).colorScheme.primary,
            ),
            child: Icon(
              icon,
              size: mediumIconSize,
              color: Theme.of(context).colorScheme.onPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(label, style: smallStyle),
        ],
      ),
    );
  }
}

class _OnboardingCard extends StatelessWidget {
  const _OnboardingCard();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Text(
        'Tap the scanner to join your first federation.',
        textAlign: TextAlign.center,
        style: smallStyle.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
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
      // Both texts go in the title slot so ListTile sees a single-line
      // tile (56dp min) instead of the 72dp two-line tile a populated
      // `subtitle` would force. Keeps the row height consistent with
      // the no-subheader cards used elsewhere in the app.
      title: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StreamBuilder<int>(
            stream: client.subscribeBalance(),
            builder: (_, snapshot) =>
                AnimatedBalance(sats: snapshot.data ?? 0, style: mediumStyle),
          ),
          FutureBuilder<String?>(
            future: client.federationName(),
            builder: (_, snapshot) => Text(
              snapshot.data ?? '…',
              style: smallStyle.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
