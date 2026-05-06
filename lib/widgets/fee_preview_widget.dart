import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pico/utils/styles.dart';

class FeePreview extends StatelessWidget {
  // Exactly one of these reflects the state. `feeSats` set → success;
  // `failed` true → error; otherwise → loading.
  final int? feeSats;
  final bool failed;
  // What the fee is — onchain shows "network fee", LN shows "gateway
  // fee". Used in all three states for consistency.
  final String label;

  const FeePreview.value(
    int this.feeSats, {
    this.label = 'network fee',
    super.key,
  }) : failed = false;

  const FeePreview.loading({this.label = 'network fee', super.key})
    : feeSats = null,
      failed = false;

  const FeePreview.error({this.label = 'network fee', super.key})
    : feeSats = null,
      failed = true;

  /// Convenience for one-shot fetches (onchain, invoice drawer): drives
  /// the three states off a `Future<int>`.
  static Widget fromFuture(
    Future<int> fee, {
    String label = 'network fee',
    Key? key,
  }) {
    return FutureBuilder<int>(
      key: key,
      future: fee,
      builder: (_, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return FeePreview.loading(label: label);
        }
        if (snapshot.hasError) return FeePreview.error(label: label);
        return FeePreview.value(snapshot.data ?? 0, label: label);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tinted = mediumStyle.copyWith(color: scheme.primary);

    final Widget child;
    if (failed) {
      child = Text('$label not available', style: tinted);
    } else {
      final sats = feeSats;
      if (sats == null) {
        child = Row(
          mainAxisSize: MainAxisSize.min,
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
            Text('querying $label…', style: tinted),
          ],
        );
      } else {
        child = Text(
          '${NumberFormat('#,###').format(sats)} sat $label',
          style: tinted,
        );
      }
    }

    return Center(child: child);
  }
}
