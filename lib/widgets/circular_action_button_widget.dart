import 'package:flutter/material.dart';
import 'package:pico/utils/async_button_mixin.dart';
import 'package:pico/utils/styles.dart';

/// One of the round home actions. Most handlers push a screen or open a
/// drawer straight away; the onchain one first waits on the mint for a fresh
/// deposit address. While a handler is pending the icon gives way to the
/// shared spinner and further taps are ignored, so the address is in hand
/// before its screen ever opens. A handler that throws surfaces the error as
/// a notification, the same way every other async button does.
class CircularActionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final Future<void> Function() onTap;

  const CircularActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  State<CircularActionButton> createState() => _CircularActionButtonState();
}

class _CircularActionButtonState extends State<CircularActionButton>
    with AsyncButtonMixin {
  @override
  Future<void> Function() get onPressed => widget.onTap;

  @override
  Widget build(BuildContext context) {
    final onPrimary = Theme.of(context).colorScheme.onPrimary;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Theme.of(context).colorScheme.primary,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: switch (buttonState) {
              AsyncButtonState.idle => handlePress,
              AsyncButtonState.loading => null,
            },
            child: SizedBox(
              width: 64,
              height: 64,
              child: Center(
                child: switch (buttonState) {
                  AsyncButtonState.loading => SizedBox(
                    width: mediumIconSize,
                    height: mediumIconSize,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: onPrimary,
                    ),
                  ),
                  AsyncButtonState.idle => Icon(
                    widget.icon,
                    size: mediumIconSize,
                    color: onPrimary,
                  ),
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          widget.label,
          style: smallStyle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
