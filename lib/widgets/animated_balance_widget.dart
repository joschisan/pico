import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Tweens between balance values when `sats` changes — smooth counter
/// animation instead of a jarring text swap. Style-agnostic so the
/// same widget works for the hero balance, federation row cards, etc.
class AnimatedBalance extends StatefulWidget {
  final int sats;
  final TextStyle style;
  final Duration duration;

  const AnimatedBalance({
    super.key,
    required this.sats,
    required this.style,
    this.duration = const Duration(milliseconds: 1000),
  });

  @override
  State<AnimatedBalance> createState() => _AnimatedBalanceState();
}

class _AnimatedBalanceState extends State<AnimatedBalance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<int> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: widget.duration, vsync: this);
    _animation = AlwaysStoppedAnimation(widget.sats);
  }

  @override
  void didUpdateWidget(AnimatedBalance oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sats != widget.sats) {
      _animation = IntTween(begin: _animation.value, end: widget.sats).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic),
      );
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (_, _) => Text(
        '${NumberFormat('#,###').format(_animation.value)} sat',
        style: widget.style,
      ),
    );
  }
}
