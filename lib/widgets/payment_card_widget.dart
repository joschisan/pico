import 'package:flutter/material.dart';
import 'package:pico/utils/styles.dart';
import 'package:intl/intl.dart';
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

class PaymentCard extends StatelessWidget {
  final OperationSummary event;
  final VoidCallback onTap;

  const PaymentCard({super.key, required this.event, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final date = DateTime.fromMillisecondsSinceEpoch(event.timestamp);
    final formattedAmount = NumberFormat('#,###').format(event.amountSats);
    final sign = event.incoming ? '+' : '-';

    return ListTile(
      onTap: onTap,
      contentPadding: listTilePadding,
      leading: Icon(
        PaymentTypeUtils.getIcon(event.paymentType),
        size: mediumIconSize,
        color: Theme.of(context).colorScheme.primary,
      ),
      title: Text(
        '$sign $formattedAmount sat',
        style: mediumStyle.copyWith(
          color: event.incoming ? Theme.of(context).colorScheme.primary : null,
        ),
      ),
      trailing: Text(
        _formatTime(date),
        style: smallStyle.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
