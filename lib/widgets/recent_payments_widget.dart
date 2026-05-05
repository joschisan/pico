import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pico/bridge_generated.dart/client.dart';
import 'package:pico/bridge_generated.dart/events.dart';
import 'package:pico/widgets/bordered_list_widget.dart';
import 'package:pico/widgets/payment_card_widget.dart';
import 'package:pico/utils/styles.dart';
import 'package:pico/screens/payment_history_screen.dart';

class RecentPayments extends StatefulWidget {
  final PicoClient client;
  final Stream<List<OperationSummary>> stream;
  final void Function(OperationSummary) onTransactionTap;

  const RecentPayments({
    super.key,
    required this.client,
    required this.stream,
    required this.onTransactionTap,
  });

  @override
  State<RecentPayments> createState() => _RecentPaymentsState();
}

class _RecentPaymentsState extends State<RecentPayments> {
  List<OperationSummary> _payments = [];
  StreamSubscription<List<OperationSummary>>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = widget.stream.listen((snapshot) {
      if (!mounted) return;
      setState(() => _payments = snapshot.reversed.toList());
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
              child: _AnimatedEntry(
                child: PaymentCard(
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
              final operations = await widget.client.listOperations();

              if (!context.mounted) return;

              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PaymentHistoryScreen(
                    client: widget.client,
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

class _AnimatedEntry extends StatefulWidget {
  final Widget child;
  const _AnimatedEntry({required this.child});

  @override
  State<_AnimatedEntry> createState() => _AnimatedEntryState();
}

class _AnimatedEntryState extends State<_AnimatedEntry>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    duration: const Duration(milliseconds: 500),
    vsync: this,
  )..forward();

  late final Animation<double> _animation = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOut,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizeTransition(sizeFactor: _animation, child: widget.child);
  }
}
