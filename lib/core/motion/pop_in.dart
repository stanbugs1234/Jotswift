import 'package:flutter/material.dart';

import 'motion.dart';

/// Plays once when first shown: [child] grows from small with a slight
/// overshoot, like something dropped onto the page.
///
/// Reduced animations fade in instead; Off shows it at once.
class PopIn extends StatefulWidget {
  const PopIn({required this.child, super.key});

  final Widget child;

  @override
  State<PopIn> createState() => _PopInState();
}

class _PopInState extends State<PopIn> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, value: 1);
  bool _full = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Only the first time: later theme or setting changes mustn't replay it.
    if (_started) return;
    _started = true;
    final motion = Motion.of(context);
    _full = motion.full;
    if (motion.off) return;
    _controller
      ..duration = motion.duration(MotionTokens.standard)
      ..forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final t = _controller.value;
        if (t >= 1) return child!;
        return Opacity(
          opacity: Curves.easeOut.transform(t),
          child: _full
              ? Transform.scale(
                  scale: 0.6 + 0.4 * MotionTokens.bounce.transform(t),
                  child: child,
                )
              : child,
        );
      },
    );
  }
}
