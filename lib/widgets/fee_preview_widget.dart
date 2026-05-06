import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pico/utils/styles.dart';

class FeePreview extends StatelessWidget {
  // Exactly one of these reflects the state. `feeSats` set → success;
  // `failed` true → error; otherwise → loading.
  final int? feeSats;
  final bool failed;

  const FeePreview.value(int this.feeSats, {super.key}) : failed = false;
  const FeePreview.loading({super.key}) : feeSats = null, failed = false;
  const FeePreview.error({super.key}) : feeSats = null, failed = true;

  /// Convenience for one-shot fetches (onchain, invoice drawer): drives
  /// the three states off a `Future<int>`.
  static Widget fromFuture(Future<int> fee, {Key? key}) {
    return FutureBuilder<int>(
      key: key,
      future: fee,
      builder: (_, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const FeePreview.loading();
        }
        if (snapshot.hasError) return const FeePreview.error();
        return FeePreview.value(snapshot.data ?? 0);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tinted = mediumStyle.copyWith(color: scheme.primary);

    if (failed) return Text('network fee not available', style: tinted);

    final sats = feeSats;
    if (sats == null) {
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
          Text('querying network fee…', style: tinted),
        ],
      );
    }

    return Text(
      '${NumberFormat('#,###').format(sats)} sat network fee',
      style: tinted,
    );
  }
}
