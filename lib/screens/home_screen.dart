import 'dart:async';

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
import 'package:pico/widgets/animated_entry_widget.dart';
import 'package:pico/widgets/bordered_list_widget.dart';
import 'package:pico/widgets/recent_payments_widget.dart';

/// Multimint home: the federation list doubles as the active-federation
/// selector — short-tap selects, long-press opens connection status. Every
/// action routes through the selected federation. The picomint eventlog is
/// daemon-wide so recent ops and notifications come from a single
/// factory-level stream — no per-client merging needed.
class HomeScreen extends StatefulWidget {
  final PicoClientFactory clientFactory;

  const HomeScreen({super.key, required this.clientFactory});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final Stream<List<OperationSummary>> _recentStream;
  late final AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;
  StreamSubscription<Notification>? _notificationSubscription;
  StreamSubscription<List<PicoClient>>? _clientsSubscription;

  List<PicoClient> _clients = [];
  // The federation every action routes through. Defaults to the first
  // joined federation and follows short-taps on the list; in-memory only,
  // so it resets to the first on restart.
  String? _selectedFederationId;
  // Off until after the first frame paints — federations rendered
  // before the flip snap in; joins after the flip animate on entry.
  bool _initialBuildDone = false;

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
      final wasFirst = !_initialBuildDone;
      setState(() {
        _clients = clients;
        // Keep the selection valid: default to / fall back on the first
        // federation when nothing is selected or the selected one is gone.
        final ids = clients.map((c) => c.federationId()).toSet();
        if (_selectedFederationId == null ||
            !ids.contains(_selectedFederationId)) {
          _selectedFederationId =
              clients.isEmpty ? null : clients.first.federationId();
        }
      });
      // Warm each federation's exchange-rate cache in the background so the
      // fiat amount rows on the send/receive screens render from cache
      // without blocking on a fetch.
      for (final client in clients) {
        client.prefetchExchangeRates();
      }
      // Wait for the first emission to actually paint, then flip the
      // flag so subsequent joins animate. Scheduling in initState was
      // too eager — the stream emits after the first frame, so by the
      // time clients arrived, animations were already enabled.
      if (wasFirst) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _initialBuildDone = true);
        });
      }
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
      case Notification_EcashRecovered(:final amountSats):
        NotificationUtils.showReceive(
          context,
          amountSats.toInt(),
          PaymentType.ecash,
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
    final client = _selectedClient();
    if (client == null) return;

    final parsers = [
      (
        parseBolt11Invoice(invoice: input),
        (dynamic result) => LightningInvoiceDrawer.show(
          context,
          clientFactory: widget.clientFactory,
          client: client,
          invoice: result,
        ),
      ),
      (
        parseEcash(ecash: input),
        (dynamic result) => EcashDrawer.show(
          context,
          clientFactory: widget.clientFactory,
          ecash: result,
        ),
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

  /// The currently selected federation that every action routes through.
  /// Resolves the selected id against the live list, falling back to the
  /// first federation. Returns null only when no federations are joined;
  /// the onboarding empty-state handles that case before the user can tap
  /// anything.
  PicoClient? _selectedClient() {
    if (_clients.isEmpty) return null;
    for (final client in _clients) {
      if (client.federationId() == _selectedFederationId) return client;
    }
    return _clients.first;
  }

  void _onCreateInvoice() {
    final client = _selectedClient();
    if (client == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => InvoiceAmountScreen(
              client: client,
              clientFactory: widget.clientFactory,
            ),
      ),
    );
  }

  void _onSendEcash() {
    final client = _selectedClient();
    if (client == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => EcashAmountScreen(
              client: client,
              clientFactory: widget.clientFactory,
            ),
      ),
    );
  }

  void _onReceiveBitcoin() {
    final client = _selectedClient();
    if (client == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => WalletV2ReceiveScreen(
              client: client,
              clientFactory: widget.clientFactory,
            ),
      ),
    );
  }

  void _onLightningAddress() {
    final client = _selectedClient();
    if (client == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => LightningAddressEntryScreen(
              client: client,
              clientFactory: widget.clientFactory,
            ),
      ),
    );
  }

  void _onContacts() {
    final client = _selectedClient();
    if (client == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => DisplayContactsScreen(
              client: client,
              clientFactory: widget.clientFactory,
            ),
      ),
    );
  }

  void _onScan() {
    ScannerDrawer.show(
      context,
      client: _selectedClient(),
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

  void _onSelectFederation(PicoClient client) {
    HapticFeedback.selectionClick();
    setState(() => _selectedFederationId = client.federationId());
  }

  void _onTapFederation(PicoClient client) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => ConnectionStatusScreen(
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
        leading: IconButton(
          icon: const Icon(PhosphorIconsRegular.gear, size: smallIconSize),
          onPressed: _onSettings,
        ),
        actions: [
          if (_clients.isNotEmpty) ...[
            IconButton(
              icon: const Icon(PhosphorIconsRegular.at, size: smallIconSize),
              onPressed: _onLightningAddress,
            ),
            IconButton(
              icon: const Icon(PhosphorIconsRegular.users, size: smallIconSize),
              onPressed: _onContacts,
            ),
          ],
          IconButton(
            icon: const Icon(PhosphorIconsRegular.qrCode, size: smallIconSize),
            onPressed: _onScan,
          ),
        ],
      ),
      body:
          _clients.isEmpty
              ? const Center(child: _OnboardingCard())
              : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    BorderedList.column(
                      children: [
                        for (final client in _clients)
                          KeyedSubtree(
                            key: ValueKey(client.federationId()),
                            child: AnimatedEntry(
                              animate: _initialBuildDone,
                              child: _FederationRow(
                                client: client,
                                selected:
                                    client.federationId() ==
                                    _selectedFederationId,
                                onTap: () => _onSelectFederation(client),
                                onLongPress: () => _onTapFederation(client),
                              ),
                            ),
                          ),
                      ],
                    ),
                    // ListTile centering + contentPadding leave ~32px of
                    // implicit slack between the federation list border
                    // and the action row. Pull the row up 16px and drop
                    // the SizedBox below so the visible gap above is
                    // ~16px and the gap to RecentPayments stays ~16px.
                    Transform.translate(
                      offset: const Offset(0, -16),
                      child: Row(
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
                    ),
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
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _FederationRow({
    required this.client,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ListTile(
      onTap: onTap,
      onLongPress: onLongPress,
      contentPadding: listTilePadding,
      leading: StreamBuilder<bool>(
        stream: client.liveness(),
        builder: (_, snapshot) {
          return Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: switch (snapshot.data) {
                null => scheme.primary.withValues(alpha: 0.3),
                true => scheme.primary,
                false => Colors.red,
              },
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
            builder:
                (_, snapshot) => AnimatedBalance(
                  sats: snapshot.data ?? 0,
                  style: mediumStyle,
                ),
          ),
          // Federation name + live recovery progress — picomint ends
          // the stream on completion, so the % vanishes once recovery
          // finalizes and the row falls back to just the name.
          FutureBuilder<String?>(
            future: client.federationName(),
            builder: (_, nameSnap) {
              final name = nameSnap.data ?? '…';
              return StreamBuilder<double>(
                stream: client.subscribeRecoveryProgress(),
                builder: (_, progressSnap) {
                  // hasData stays sticky after the stream closes, so
                  // also gate on connectionState — picomint ends the
                  // stream the moment recovery finalizes.
                  final inProgress =
                      progressSnap.hasData &&
                      progressSnap.connectionState != ConnectionState.done;
                  final text =
                      inProgress
                          ? '$name · ${progressSnap.data!.round()}%'
                          : name;
                  // The selected federation drives every action — flag it
                  // by tinting its name in the primary color.
                  return Text(
                    text,
                    style: smallStyle.copyWith(
                      color:
                          selected ? scheme.primary : scheme.onSurfaceVariant,
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
