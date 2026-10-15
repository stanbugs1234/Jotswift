import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'motion.dart';

/// Plays once when first shown: [child] fades in while rising a little.
/// Give items in a row increasing [index]es so they arrive one after
/// another (the stagger stops growing after a few items).
///
/// Reduced animations only fade, without the stagger; Off shows it at once.
class RiseIn extends StatefulWidget {
  const RiseIn({required this.child, this.index = 0, super.key});

  final Widget child;
  final int index;

  /// Delay between consecutive items, and how many items it applies to.
  static const step = Duration(milliseconds: 45);
  static const maxStagger = 6;

  @override
  State<RiseIn> createState() => _RiseInState();
}

class _RiseInState extends State<RiseIn> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, value: 1);
  bool _started = false;
  bool _full = false;
  Timer? _delay;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final motion = Motion.of(context);
    _full = motion.full;
    if (motion.off) return;
    _controller
      ..duration = motion.duration(MotionTokens.standard)
      ..value = 0;
    final wait = _full
        ? RiseIn.step * math.min(widget.index, RiseIn.maxStagger)
        : Duration.zero;
    if (wait == Duration.zero) {
      _controller.forward();
    } else {
      _delay = Timer(wait, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final t = MotionTokens.enter.transform(_controller.value);
        if (t >= 1) return child!;
        return Opacity(
          opacity: t,
          child: _full
              ? Transform.translate(
                  offset: Offset(0, 16 * (1 - t)),
                  child: child,
                )
              : child,
        );
      },
    );
  }
}
