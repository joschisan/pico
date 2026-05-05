import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:pico/bridge_generated.dart/client.dart';
import 'package:pico/bridge_generated.dart/events.dart';
import 'package:pico/utils/drawer_utils.dart';
import 'package:pico/utils/payment_utils.dart';
import 'package:pico/utils/styles.dart';
import 'package:pico/widgets/drawer_shell_widget.dart';
import 'package:share_plus/share_plus.dart';

class PaymentDetailsDrawer extends StatefulWidget {
  final PicoClient client;
  final OperationSummary event;

  const PaymentDetailsDrawer({
    super.key,
    required this.client,
    required this.event,
  });

  static Future<void> show(
    BuildContext context, {
    required PicoClient client,
    required OperationSummary event,
  }) {
    return DrawerUtils.show(
      context: context,
      child: PaymentDetailsDrawer(client: client, event: event),
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
    _subscription = widget.client
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
                      payment: widget.event,
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
  final OperationSummary payment;
  final bool isLast;

  const _TimelineRow({
    required this.event,
    required this.payment,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final desc = _describe(event, payment, context);

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
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 16),

          // Header (label + optional inline action) + optional subheader.
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 36),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(desc.label, style: mediumStyle),
                      if (desc.headerAction != null) ...[
                        const SizedBox(width: 8),
                        desc.headerAction!,
                      ],
                    ],
                  ),
                  if (desc.subtitle != null)
                    Text(
                      desc.subtitle!,
                      style: smallStyle.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
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
  final Widget? headerAction;

  const _Description({
    required this.label,
    required this.tone,
    this.subtitle,
    this.headerAction,
  });
}

String _sats(int n) => '${NumberFormat('#,###').format(n)} sat';

Widget _shareIcon(String text, Color color) => GestureDetector(
  onTap: () => SharePlus.instance.share(ShareParams(text: text)),
  child: Icon(PhosphorIconsRegular.copy, size: smallIconSize, color: color),
);

_Description _describe(
  PaymentEvent event,
  OperationSummary payment,
  BuildContext context,
) {
  final scheme = Theme.of(context).colorScheme;
  final neutral = scheme.onSurfaceVariant;
  final success = scheme.primary;
  final failure = scheme.error;
  final warning = Colors.amber.shade700;

  return switch (event) {
    // ── Core ────────────────────────────────────────────────────────────
    PaymentEvent_TxAccept(:final inputSats, :final outputSats) => _Description(
      label: 'Transaction Accepted',
      subtitle:
          '${_sats(inputSats.toInt())} · ${_sats(inputSats.toInt() - outputSats.toInt())}',
      tone: neutral,
    ),
    PaymentEvent_TxReject() => _Description(
      label: 'Transaction Rejected',
      tone: failure,
    ),

    // ── Lightning ───────────────────────────────────────────────────────
    PaymentEvent_LnSend(:final amountSats, :final feeSats) => _Description(
      label: 'Sending Lightning',
      subtitle:
          '${_sats(amountSats.toInt())} · ${_sats(feeSats.toInt())}',
      tone: neutral,
    ),
    PaymentEvent_LnSendSuccess(:final preimage) => _Description(
      label: 'Sending Success',
      tone: success,
      headerAction: _shareIcon(preimage, success),
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
      subtitle:
          '${_sats(amountSats.toInt())} · ${_sats(feeSats.toInt())}',
      tone: neutral,
    ),

    // ── Mint (ECash) ────────────────────────────────────────────────────
    PaymentEvent_MintSend(:final amountSats, :final ecash) => _Description(
      label: 'Sending eCash',
      subtitle: _sats(amountSats.toInt()),
      tone: neutral,
      headerAction: _shareIcon(ecash, neutral),
    ),
    PaymentEvent_MintRemint() => _Description(
      label: 'Reminting eCash',
      subtitle: _sats(payment.amountSats.toInt()),
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
    PaymentEvent_MintRecovery(:final index, :final total) => _Description(
      label: 'Recovering eCash',
      subtitle: '${total == null ? 0 : (index.toInt() * 100) ~/ total.toInt()}%',
      tone: neutral,
    ),

    // ── Wallet (on-chain) ───────────────────────────────────────────────
    PaymentEvent_WalletSend(:final amountSats, :final feeSats) => _Description(
      label: 'Sending Onchain',
      subtitle:
          '${_sats(amountSats.toInt())} · ${_sats(feeSats.toInt())}',
      tone: neutral,
    ),
    PaymentEvent_WalletSendSuccess(:final txid) => _Description(
      label: 'Sending Success',
      tone: success,
      headerAction: _shareIcon(txid, success),
    ),
    PaymentEvent_WalletSendFailure() => _Description(
      label: 'Sending Failure',
      subtitle: 'missing txid',
      tone: failure,
    ),
    PaymentEvent_WalletReceive(
      :final txid,
      :final amountSats,
      :final feeSats,
    ) =>
      _Description(
        label: 'Receiving Onchain',
        subtitle:
            '${_sats(amountSats.toInt())} · ${_sats(feeSats.toInt())}',
        tone: neutral,
        headerAction: _shareIcon(txid, neutral),
      ),

  };
}
