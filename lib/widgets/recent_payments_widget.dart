import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pico/bridge_generated.dart/events.dart';
import 'package:pico/bridge_generated.dart/factory.dart';
import 'package:pico/widgets/animated_entry_widget.dart';
import 'package:pico/widgets/bordered_list_widget.dart';
import 'package:pico/widgets/payment_card_widget.dart';
import 'package:pico/utils/styles.dart';
import 'package:pico/screens/payment_history_screen.dart';

class RecentPayments extends StatefulWidget {
  final PicoClientFactory clientFactory;
  final Stream<List<OperationSummary>> stream;
  final void Function(OperationSummary) onTransactionTap;

  const RecentPayments({
    super.key,
    required this.clientFactory,
    required this.stream,
    required this.onTransactionTap,
  });

  @override
  State<RecentPayments> createState() => _RecentPaymentsState();
}

class _RecentPaymentsState extends State<RecentPayments> {
  List<OperationSummary> _payments = [];
  StreamSubscription<List<OperationSummary>>? _subscription;
  // Off until after the first frame paints — children built before the
  // flip render statically; later insertions get the entry animation.
  bool _initialBuildDone = false;

  @override
  void initState() {
    super.initState();
    _subscription = widget.stream.listen((snapshot) {
      if (!mounted) return;
      final wasFirst = !_initialBuildDone;
      setState(() => _payments = snapshot.reversed.toList());
      // Wait for the first emission to actually paint before flipping
      // the flag — otherwise the initial batch lands after animations
      // are already enabled and every payment animates on app launch.
      if (wasFirst) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _initialBuildDone = true);
        });
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_payments.isEmpty) {
      return Column(
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

    return Column(
      children: [
        for (var i = 0; i < _payments.length; i++)
          KeyedSubtree(
            key: ValueKey(_payments[i].operationId),
            child: BorderedList.decorateItem(
              context: context,
              child: AnimatedEntry(
                animate: _initialBuildDone,
                child: PaymentCard(
                  clientFactory: widget.clientFactory,
                  event: _payments[i],
                  onTap: () => widget.onTransactionTap(_payments[i]),
                ),
              ),
              isFirst: i == 0,
              isLast: i == _payments.length - 1,
            ),
          ),
        Center(
          child: TextButton(
            onPressed: () async {
              final operations = await widget.clientFactory.listOperations();

              if (!context.mounted) return;

              Navigator.of(context).push(
                MaterialPageRoute(
                  builder:
                      (_) => PaymentHistoryScreen(
                        clientFactory: widget.clientFactory,
                        operations: operations.reversed.toList(),
                      ),
                ),
              );
            },
            child: Text(
              'Payment History',
              style: mediumStyle.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

