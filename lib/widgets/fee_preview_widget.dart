import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pico/utils/styles.dart';

class FeePreview extends StatelessWidget {
  final Future<int> fee;

  const FeePreview({super.key, required this.fee});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tinted = mediumStyle.copyWith(color: scheme.primary);

    return FutureBuilder<int>(
      future: fee,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
                ),
              ),
              const SizedBox(width: 8),
              Text('querying fee…', style: tinted),
            ],
          );
        }

        if (snapshot.hasError) {
          return Text('fee unavailable', style: tinted);
        }

        final sats = snapshot.data ?? 0;
        return Text(
          '+${NumberFormat('#,###').format(sats)} sat',
          style: tinted,
        );
      },
    );
  }
}
