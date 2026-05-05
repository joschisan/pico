import 'dart:async';

import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter/material.dart';
import 'package:pico/utils/styles.dart';
import 'package:intl/intl.dart';
import 'package:pico/bridge_generated.dart/client.dart';
import 'package:pico/bridge_generated.dart/events.dart';
import 'package:pico/utils/payment_utils.dart';

String _formatTime(DateTime dateTime) {
  final difference = DateTime.now().difference(dateTime);

  return switch (difference) {
    _ when difference.inMinutes < 1 => 'Now',
    _ when difference.inMinutes < 60 => '${difference.inMinutes}m ago',
    _ when difference.inHours < 24 => '${difference.inHours}h ago',
    _ => '${difference.inDays}d ago',
  };
}

enum _Status { ok, warning, error }

_Status? _classify(PaymentEvent event) => switch (event) {
  PaymentEvent_TxReject() => _Status.error,
  PaymentEvent_LnSendRefund() => _Status.warning,
  PaymentEvent_LnSendFailure() => _Status.error,
  PaymentEvent_MintFailure() => _Status.error,
  PaymentEvent_WalletSendFailure() => _Status.error,
  _ => null,
};

class PaymentCard extends StatefulWidget {
  final PicoClient client;
  final OperationSummary event;
  final VoidCallback onTap;

  const PaymentCard({
    super.key,
    required this.client,
    required this.event,
    required this.onTap,
  });

  @override
  State<PaymentCard> createState() => _PaymentCardState();
}

class _PaymentCardState extends State<PaymentCard> {
  _Status _status = _Status.ok;
  StreamSubscription<PaymentEvent>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = widget.client
        .subscribePaymentEvents(operationId: widget.event.operationId)
        .listen((e) {
          if (!mounted) return;
          final next = _classify(e);
          if (next != null) setState(() => _status = next);
        });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final date = DateTime.fromMillisecondsSinceEpoch(widget.event.timestamp);
    final formattedAmount = NumberFormat(
      '#,###',
    ).format(widget.event.amountSats);
    final sign = widget.event.incoming ? '+' : '-';

    final (iconData, iconColor, titleColor) = switch (_status) {
      _Status.error => (
        PhosphorIconsRegular.warningCircle,
        Colors.red,
        Colors.red,
      ),
      _Status.warning => (
        PhosphorIconsRegular.warning,
        Colors.amber.shade700,
        Colors.amber.shade700,
      ),
      _Status.ok => (
        PaymentTypeUtils.getIcon(widget.event.paymentType),
        scheme.primary,
        widget.event.incoming ? scheme.primary : null,
      ),
    };

    return ListTile(
      onTap: widget.onTap,
      contentPadding: listTilePadding,
      leading: Icon(iconData, size: mediumIconSize, color: iconColor),
      title: Text(
        '$sign $formattedAmount sat',
        style: mediumStyle.copyWith(color: titleColor),
      ),
      trailing: Text(
        _formatTime(date),
        style: smallStyle.copyWith(color: scheme.onSurfaceVariant),
      ),
    );
  }
}
