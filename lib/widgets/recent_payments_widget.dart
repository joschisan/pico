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
  /// Null until the stream's first snapshot: rendering nothing then keeps
  /// the empty-state text from flashing on every mount before the answer
  /// arrives — an empty list is a fact, not a default.
  List<OperationSummary>? _payments;
  StreamSubscription<List<OperationSummary>>? _subscription;

  /// Payments in the first snapshot render without the entry animation; only
  /// payments appearing after the screen opened grow in.
  Set<String>? _initialIds;

  @override
  void initState() {
    super.initState();
    _subscription = widget.stream.listen(_onSnapshot);
  }

  void _onSnapshot(List<OperationSummary> snapshot) {
    if (!mounted) return;

    setState(() {
      final payments = snapshot.reversed.toList();
      _payments = payments;
      _initialIds ??= payments.map((p) => p.operation.display()).toSet();
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _openHistory() async {
    final operations = await widget.pico.listOperations();

    if (!mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => PaymentHistoryScreen(
              pico: widget.pico,
              operations: operations.reversed.toList(),
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final payments = _payments;

    if (payments == null) {
      return const SizedBox.shrink();
    }

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
                  animate: !_initialIds!.contains(payment.operation.display()),
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
