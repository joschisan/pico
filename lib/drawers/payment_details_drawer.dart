import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pico/bridge_generated.dart/events.dart';
import 'package:pico/widgets/drawer_shell_widget.dart';
import 'package:pico/widgets/amount_display_widget.dart';
import 'package:pico/widgets/primary_card_widget.dart';
import 'package:pico/widgets/shareable_data_widget.dart';
import 'package:pico/utils/payment_utils.dart';
import 'package:pico/utils/drawer_utils.dart';

class PaymentDetailsDrawer extends StatelessWidget {
  final PicoPayment event;

  const PaymentDetailsDrawer({super.key, required this.event});

  static Future<void> show(BuildContext context, {required PicoPayment event}) {
    return DrawerUtils.show(
      context: context,
      child: PaymentDetailsDrawer(event: event),
    );
  }

  String _formatDateTime(int timestamp) {
    final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return DateFormat('EEEE d MMMM, HH:mm').format(dateTime);
  }

  @override
  Widget build(BuildContext context) {
    return DrawerShell(
      icon: PaymentTypeUtils.getIcon(event.paymentType),
      title: _formatDateTime(event.timestamp),
      children: [
        PrimaryCard(child: AmountDisplay(event.amountSats, fee: event.feeSats)),
        if (event.oob != null) ...[
          const SizedBox(height: 16),
          ShareableData(data: event.oob!),
        ],
      ],
    );
  }
}
