import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pico/bridge_generated.dart/events.dart';
import 'package:pico/bridge_generated.dart/factory.dart';
import 'package:pico/bridge_generated.dart/fountain.dart';
import 'package:pico/bridge_generated.dart/lib.dart';
import 'package:pico/screens/display_ecash_screen.dart';
import 'package:pico/utils/drawer_utils.dart';
import 'package:pico/utils/payment_utils.dart';
import 'package:pico/utils/styles.dart';
import 'package:pico/widgets/drawer_shell_widget.dart';
import 'package:share_plus/share_plus.dart';

class PaymentDetailsDrawer extends StatefulWidget {
  final PicoClientFactory clientFactory;
  final OperationSummary event;

  const PaymentDetailsDrawer({
    super.key,
    required this.clientFactory,
    required this.event,
  });

  static Future<void> show(
    BuildContext context, {
    required PicoClientFactory clientFactory,
    required OperationSummary event,
  }) {
    return DrawerUtils.show(
      context: context,
      child: PaymentDetailsDrawer(clientFactory: clientFactory, event: event),
    );
  }

  @override
  State<PaymentDetailsDrawer> createState() => _PaymentDetailsDrawerState();
}

class _PaymentDetailsDrawerState extends State<PaymentDetailsDrawer> {
  final List<PaymentEvent> _events = [];
  StreamSubscription<PaymentEvent>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = widget.clientFactory
        .subscribePaymentEvents(operationId: widget.event.operationId)
        .listen((e) {
          if (!mounted) return;
          setState(() => _events.add(e));
        });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  String _formatDateTime(int timestamp) {
    final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return DateFormat('EEEE d MMMM, HH:mm').format(dateTime);
  }

  @override
  Widget build(BuildContext context) {
    return DrawerShell(
      icon: PaymentTypeUtils.getIcon(widget.event.paymentType),
      title: _formatDateTime(widget.event.timestamp.toInt()),
      subtitle: widget.event.federationName ?? 'Unknown Federation',
      children: [
        if (_events.isNotEmpty)
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < _events.length; i++)
                    _TimelineRow(
                      event: _events[i],
                      clientFactory: widget.clientFactory,
                      isLast: i == _events.length - 1,
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _TimelineRow extends StatelessWidget {
  final PaymentEvent event;
  final PicoClientFactory clientFactory;
  final bool isLast;

  const _TimelineRow({
    required this.event,
    required this.clientFactory,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final desc = _describe(event, clientFactory, context);
    final scheme = Theme.of(context).colorScheme;
    final isAction = desc.onTap != null;
    // Tappable subtitles get the tone color so they read as a link;
    // plain subtitles stay muted onSurfaceVariant.
    final subtitleColor = isAction ? desc.tone : scheme.onSurfaceVariant;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Dot + connecting line column. Width matches largeIconSize so
          // the dot's horizontal center aligns with the drawer header icon.
          SizedBox(
            width: largeIconSize,
            child: Column(
              children: [
                const SizedBox(height: 4),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: desc.tone,
                    shape: BoxShape.circle,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: scheme.outlineVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 16),

          // Header label + optional subheader. When the description has
          // an `onTap`, the subheader doubles as the tappable action
          // surface (no inline icon — the wording itself signals intent).
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 36),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(desc.label, style: mediumStyle),
                  if (desc.subtitle != null)
                    GestureDetector(
                      onTap: desc.onTap,
                      behavior: HitTestBehavior.opaque,
                      child: Text(
                        desc.subtitle!,
                        style: smallStyle.copyWith(color: subtitleColor),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Description {
  final String label;
  final String? subtitle;
  final Color tone;
  final VoidCallback? onTap;

  const _Description({
    required this.label,
    required this.tone,
    this.subtitle,
    this.onTap,
  });
}

String _sats(int n) => '${NumberFormat('#,###').format(n)} sat';

void _share(String text) {
  SharePlus.instance.share(ShareParams(text: text));
}

Future<void> _openEcash(
  BuildContext context,
  PicoClientFactory clientFactory,
  String ecashString,
) async {
  final ecash = parseEcash(ecash: ecashString);
  if (ecash == null) return;
  // `client` may be null if the user has since left this federation —
  // DisplayEcashScreen drops the cancel action in that case but still
  // renders the QR + shareable string + amount.
  final client = await clientFactory.client(
    federationId: ecash.federationId(),
  );
  if (!context.mounted) return;
  Navigator.of(context).push(
    MaterialPageRoute(
      builder:
          (_) => DisplayEcashScreen(
            client: client,
            ecash: ecash,
            encoder: ECashEncoder(ecash: ecash),
          ),
    ),
  );
}

_Description _describe(
  PaymentEvent event,
  PicoClientFactory clientFactory,
  BuildContext context,
) {
  final scheme = Theme.of(context).colorScheme;
  final neutral = scheme.onSurfaceVariant;
  final success = scheme.primary;
  final failure = Colors.red;
  final warning = Colors.amber.shade700;

  return switch (event) {
    // ── Core ────────────────────────────────────────────────────────────
    PaymentEvent_TxCreate(:final changeSats, :final feeSats) => _Description(
      label: 'Transaction Created',
      subtitle: '${_sats(changeSats.toInt())} · ${_sats(feeSats.toInt())}',
      tone: neutral,
    ),
    PaymentEvent_TxAccept() => _Description(
      label: 'Transaction Accepted',
      tone: neutral,
    ),
    PaymentEvent_TxReject() => _Description(
      label: 'Transaction Rejected',
      tone: failure,
    ),

    // ── Lightning ───────────────────────────────────────────────────────
    PaymentEvent_LnSend(:final amountSats, :final feeSats) => _Description(
      label: 'Sending Lightning',
      subtitle: '${_sats(amountSats.toInt())} · ${_sats(feeSats.toInt())}',
      tone: neutral,
    ),
    PaymentEvent_LnSendSuccess(:final preimage) => _Description(
      label: 'Sending Success',
      subtitle: 'Tap to share preimage',
      tone: success,
      onTap: () => _share(preimage),
    ),
    PaymentEvent_LnSendRefund(:final expired) => _Description(
      label: 'Refunding',
      subtitle: expired ? 'contract expired' : 'gateway cancelled',
      tone: warning,
    ),
    PaymentEvent_LnSendFailure() => _Description(
      label: 'Sending Failure',
      subtitle: 'missing preimage',
      tone: failure,
    ),
    PaymentEvent_LnReceive(:final amountSats, :final feeSats) => _Description(
      label: 'Receiving Lightning',
      subtitle: '${_sats(amountSats.toInt())} · ${_sats(feeSats.toInt())}',
      tone: neutral,
    ),

    // ── Mint (ECash) ────────────────────────────────────────────────────
    PaymentEvent_MintSend(:final amountSats) => _Description(
      label: 'Sending eCash',
      subtitle: _sats(amountSats.toInt()),
      tone: neutral,
    ),
    PaymentEvent_MintSendSuccess(:final ecash) => _Description(
      label: 'Sending Success',
      subtitle: 'Tap to display eCash',
      tone: success,
      onTap: () => _openEcash(context, clientFactory, ecash),
    ),
    PaymentEvent_MintSendFailure() => _Description(
      label: 'Sending Failure',
      tone: failure,
    ),
    PaymentEvent_MintRemint() => _Description(
      label: 'Reminting eCash',
      tone: neutral,
    ),
    PaymentEvent_MintReceive(:final amountSats) => _Description(
      label: 'Receiving eCash',
      subtitle: _sats(amountSats.toInt()),
      tone: neutral,
    ),
    PaymentEvent_MintSuccess(:final amountSats) => _Description(
      label: 'Minting Success',
      subtitle: _sats(amountSats.toInt()),
      tone: success,
    ),
    PaymentEvent_MintFailure() => _Description(
      label: 'Minting Failure',
      subtitle: 'threshold signature invalid',
      tone: failure,
    ),
    PaymentEvent_MintRecovery(:final amountSats) => _Description(
      label: 'Recovery Complete',
      subtitle: _sats(amountSats.toInt()),
      tone: success,
    ),

    // ── Wallet (on-chain) ───────────────────────────────────────────────
    PaymentEvent_WalletSend(:final amountSats, :final feeSats) => _Description(
      label: 'Sending Onchain',
      subtitle: '${_sats(amountSats.toInt())} · ${_sats(feeSats.toInt())}',
      tone: neutral,
    ),
    PaymentEvent_WalletSendSuccess(:final txid) => _Description(
      label: 'Sending Success',
      subtitle: 'Tap to share txid',
      tone: success,
      onTap: () => _share(txid),
    ),
    PaymentEvent_WalletSendFailure() => _Description(
      label: 'Sending Failure',
      subtitle: 'missing txid',
      tone: failure,
    ),
    PaymentEvent_WalletReceive(:final amountSats, :final feeSats) =>
      _Description(
        label: 'Receiving Onchain',
        subtitle: '${_sats(amountSats.toInt())} · ${_sats(feeSats.toInt())}',
        tone: neutral,
      ),
  };
}
