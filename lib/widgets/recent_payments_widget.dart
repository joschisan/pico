import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pico/bridge_generated.dart/events.dart';
import 'package:pico/bridge_generated.dart/app.dart';
import 'package:pico/widgets/animated_entry_widget.dart';
import 'package:pico/widgets/bleed_column_widget.dart';
import 'package:pico/widgets/bordered_list_widget.dart';
import 'package:pico/widgets/payment_card_widget.dart';
import 'package:pico/widgets/section_header_widget.dart';
import 'package:pico/utils/styles.dart';
import 'package:pico/screens/payment_history_screen.dart';

class RecentPayments extends StatefulWidget implements Bleeds {
  final Pico pico;
  final Stream<List<OperationSummary>> stream;
  final void Function(OperationSummary) onTransactionTap;

  const RecentPayments({
    super.key,
    required this.pico,
    required this.stream,
    required this.onTransactionTap,
  });

  @override
  State<RecentPayments> createState() => _RecentPaymentsState();
}

class _RecentPaymentsState extends State<RecentPayments> {
  late List<OperationSummary> _payments;
  StreamSubscription<List<OperationSummary>>? _subscription;

  /// Payments present at seed time render without the entry animation; only
  /// payments appearing after the screen opened grow in.
  late final Set<String> _initialIds;

  @override
  void initState() {
    super.initState();
    // Seeded synchronously so the first frame renders the truth — list and
    // empty state alike are facts, not defaults rendered while the
    // stream's first snapshot is in flight.
    _payments = widget.pico.recentOperations().reversed.toList();
    _initialIds = _payments.map((p) => p.operation.display()).toSet();
    _subscription = widget.stream.listen(_onSnapshot);
  }

  void _onSnapshot(List<OperationSummary> snapshot) {
    if (!mounted) return;

    setState(() => _payments = snapshot.reversed.toList());
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _openHistory() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => PaymentHistoryScreen(
              pico: widget.pico,
              operations: widget.pico.listOperations().reversed.toList(),
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final payments = _payments;

    // A BleedColumn so a hosting BleedColumn passes this through uninset:
    // the rows carry their own content padding and must reach the screen
    // edges, while the header and empty-state text take the standard inset.
    if (payments.isEmpty) {
      return BleedColumn(
        children: [
          const SizedBox(height: 64),
          Text(
            'You have no payments yet.',
            textAlign: TextAlign.center,
            style: smallStyle.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );
    }

    return BleedColumn(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SectionHeader(
          title: 'Recent Payments',
          action: 'History',
          onAction: _openHistory,
        ),
        BorderedList.column(
          children: [
            for (final payment in payments)
              KeyedSubtree(
                key: ValueKey(payment.operation.display()),
                child: AnimatedEntry(
                  animate: !_initialIds.contains(payment.operation.display()),
                  child: PaymentCard(
                    pico: widget.pico,
                    event: payment,
                    onTap: () => widget.onTransactionTap(payment),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
