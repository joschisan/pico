import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pico/utils/styles.dart';

class FeePreview extends StatelessWidget {
  final Future<int> fee;

  const FeePreview({super.key, required this.fee});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = smallStyle.copyWith(color: scheme.onSurfaceVariant);

    return FutureBuilder<int>(
      future: fee,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text('Querying fee…', style: muted),
            ],
          );
        }

        if (snapshot.hasError) {
          return Text('Fee unavailable', style: muted);
        }

        final sats = snapshot.data ?? 0;
        return Text(
          'Fee: ${NumberFormat('#,###').format(sats)} sat',
          style: muted,
        );
      },
    );
  }
}
