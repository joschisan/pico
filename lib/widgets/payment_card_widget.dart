import 'dart:async';

import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter/material.dart';
import 'package:pico/utils/styles.dart';
import 'package:intl/intl.dart';
import 'package:pico/bridge_generated.dart/events.dart';
import 'package:pico/bridge_generated.dart/factory.dart';
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
  PaymentEvent_MintSendFailure() => _Status.error,
  PaymentEvent_MintFailure() => _Status.error,
  PaymentEvent_WalletSendFailure() => _Status.error,
  _ => null,
};

class PaymentCard extends StatefulWidget {
  final PicoClientFactory clientFactory;
  final OperationSummary event;
  final VoidCallback onTap;

  const PaymentCard({
    super.key,
    required this.clientFactory,
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
    _subscription = widget.clientFactory
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
    final federationName = widget.event.federationName;

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
      // Amount over federation name in the title slot (rather than
      // `subtitle`) so the tile keeps the single-line height of the other
      // bordered rows — matching `DetailRow`. The name is dropped when the
      // federation has been left (`federationName == null`).
      title: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$sign$formattedAmount sat',
            style: mediumStyle.copyWith(color: titleColor),
          ),
          if (federationName != null)
            Text(
              federationName,
              style: smallStyle.copyWith(color: scheme.onSurfaceVariant),
            ),
        ],
      ),
      trailing: Text(
        _formatTime(date),
        style: smallStyle.copyWith(color: scheme.onSurfaceVariant),
      ),
    );
  }
}
