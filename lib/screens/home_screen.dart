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
import 'package:pico/screens/display_contacts_screen.dart';
import 'package:pico/screens/ecash_amount_screen.dart';
import 'package:pico/screens/invoice_amount_screen.dart';
import 'package:pico/screens/lightning_address_entry_screen.dart';
import 'package:pico/screens/settings_screen.dart';
import 'package:pico/screens/wallet_v2_receive_screen.dart';
import 'package:pico/utils/notification_utils.dart';
import 'package:pico/utils/styles.dart';
import 'package:pico/widgets/animated_balance_widget.dart';
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

  late final Stream<int> _balanceStream;
  late final Stream<List<OperationSummary>> _recentStream;
  late final AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;
  StreamSubscription<Notification>? _notificationSubscription;

  List<PicoClient> _clients = [];
  bool _balanceHidden = true;

  @override
  void initState() {
    super.initState();
    _balanceStream = widget.clientFactory.subscribeGlobalBalance();
    _recentStream = widget.clientFactory.subscribeRecentOperations();
    _notificationSubscription = widget.clientFactory
        .subscribeNotifications()
        .listen(_handleNotification);
    _refreshClients();
    _initDeepLinks();
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    _notificationSubscription?.cancel();
    super.dispose();
  }

  /// Cache the warm client list for picker-style actions. Re-fetched
  /// after a successful join from the scanner so newly-joined clients
  /// become eligible for random selection.
  Future<void> _refreshClients() async {
    final clients = await widget.clientFactory.clients();
    if (!mounted) return;
    setState(() => _clients = clients);
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
    final client = _pickClient();
    if (client == null) return;
    ScannerDrawer.show(
      context,
      client: client,
      clientFactory: widget.clientFactory,
    );
  }

  Future<void> _onSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(clientFactory: widget.clientFactory),
      ),
    );
    // A leave from settings drops a client; refresh the warm list so
    // random pick doesn't reach for a dead namespace.
    _refreshClients();
  }

  void _showEventDetails(OperationSummary event) {
    // Operation ids are global sha256s, so any client can serve as a
    // host for the per-op subscription. Step 6 will replace this once
    // the empty-state join flow is consolidated.
    final client = _pickClient();
    if (client == null) return;
    PaymentDetailsDrawer.show(context, client: client, event: event);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pico'),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(PhosphorIconsRegular.at, size: smallIconSize),
            onPressed: _onLightningAddress,
          ),
          IconButton(
            icon: const Icon(PhosphorIconsRegular.users, size: smallIconSize),
            onPressed: _onContacts,
          ),
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const SizedBox(height: 64),
            GestureDetector(
              onTap: () => setState(() => _balanceHidden = !_balanceHidden),
              child: StreamBuilder<int>(
                stream: _balanceStream,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const CircularProgressIndicator();
                  }
                  if (_balanceHidden) {
                    return Text.rich(
                      TextSpan(text: '* * * *', style: heroStyle),
                    );
                  }
                  return AnimatedBalanceDisplay(snapshot.data!);
                },
              ),
            ),
            const SizedBox(height: 64),
            if (_clients.isEmpty)
              const _OnboardingCard()
            else ...[
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
                client: _clients.first,
                stream: _recentStream,
                onTransactionTap: _showEventDetails,
              ),
            ],
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
