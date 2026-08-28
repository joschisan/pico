import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pico/utils/styles.dart';
import 'package:pico/widgets/amount_entry_widget.dart';

/// The app bar's Max action: fades in once the screen's max has been priced,
/// and taps through to the amount entry to fill the figure and arm max mode.
///
/// A max known at first build renders in place; one priced over the network
/// arrives while the user is looking, and fading in is what says it is an
/// answer rather than a glitch. Invisible is also untappable, so the fade
/// never offers a max that isn't there.
class MaxAction extends StatelessWidget {
  final ValueListenable<int?> maxAmount;
  // The screen's amount entry, reached by key because this action lives in
  // the app bar and the figure lives in the body. Tapping through to it is
  // this widget's whole job, so it takes the key rather than a callback.
  final GlobalKey<AmountEntryWidgetState> entry;

  const MaxAction({super.key, required this.maxAmount, required this.entry});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int?>(
      valueListenable: maxAmount,
      builder: (context, sats, _) {
        final offered = sats != null && sats > 0;

        return AnimatedOpacity(
          opacity: offered ? 1 : 0,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
          child: TextButton(
            onPressed: offered ? () => entry.currentState?.enterMax() : null,
            child: Text(
              'Max',
              style: mediumStyle.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        );
      },
    );
  }
}
