import 'package:flutter/material.dart';

import 'motion.dart';

/// Swaps between views at different zoom levels, like a calendar going
/// from a year to a month to a day.
///
/// When [level] grows (zooming in), the new view grows out of [origin] (in
/// global coordinates, such as the tapped month) while the old one swells
/// and fades. When it shrinks, the old view shrinks back into [origin] and
/// the new one settles from slightly larger. Views at the same level
/// crossfade. Reduced animations crossfade; Off swaps at once.
class ZoomSwitcher extends StatefulWidget {
  const ZoomSwitcher({
    required this.view,
    required this.level,
    required this.child,
    this.origin,
    super.key,
  });

  /// Identifies the view; a change starts a transition.
  final Object view;

  /// How far in this view is: higher is closer (year 0, month 1, day 2).
  final int level;

  /// Where the closer view sits inside the wider one, in global
  /// coordinates. Without it, the zoom centres on the screen.
  final Rect? origin;
  final Widget child;

  @override
  State<ZoomSwitcher> createState() => _ZoomSwitcherState();
}

class _ZoomSwitcherState extends State<ZoomSwitcher>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this);
  Widget? _leaving;

  /// 1 zooming in, -1 zooming out, 0 crossfading.
  int _direction = 0;
  Rect? _origin;

  @override
  void didUpdateWidget(ZoomSwitcher old) {
    super.didUpdateWidget(old);
    if (old.view == widget.view) return;
    final motion = Motion.of(context);
    if (motion.off) {
      _leaving = null;
      return;
    }
    _leaving = KeyedSubtree(key: ValueKey(old.view), child: old.child);
    _direction = motion.full ? widget.level.compareTo(old.level) : 0;
    _origin = widget.origin;
    _controller
      ..duration = motion.duration(
        _direction == 0 ? MotionTokens.standard : MotionTokens.emphasized,
      )
      ..forward(from: 0).whenCompleteOrCancel(() {
        if (mounted) setState(() => _leaving = null);
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// A transform that maps the whole view onto [rect] (local coordinates).
  static Matrix4 _onto(Rect rect, Size size) => Matrix4.identity()
    ..translateByDouble(rect.left, rect.top, 0, 1)
    ..scaleByDouble(rect.width / size.width, rect.height / size.height, 1, 1);

  @override
  Widget build(BuildContext context) {
    final current = KeyedSubtree(
      key: ValueKey(widget.view),
      child: widget.child,
    );
    final leaving = _leaving;
    if (leaving == null) return current;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        // The origin in this widget's own coordinates, or a centred third.
        var rect = Rect.fromCenter(
          center: size.center(Offset.zero),
          width: size.width / 3,
          height: size.height / 3,
        );
        final box = context.findRenderObject();
        if (_origin != null && box is RenderBox && box.hasSize) {
          final topLeft = box.globalToLocal(_origin!.topLeft);
          rect = topLeft & _origin!.size;
        }
        final onto = _onto(rect, size);
        final leavingPage = IgnorePointer(child: leaving);
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = MotionTokens.move.transform(_controller.value);
            if (_direction == 0) {
              return Stack(
                fit: StackFit.expand,
                children: [
                  Opacity(opacity: 1 - t, child: leavingPage),
                  Opacity(opacity: t, child: current),
                ],
              );
            }
            Widget grow(Widget child, double amount) => Transform(
              transform: Matrix4Tween(
                begin: onto,
                end: Matrix4.identity(),
              ).transform(amount),
              child: child,
            );
            Widget swell(Widget child, double amount) => Transform.scale(
              scale: 1 + 0.12 * amount,
              origin: rect.center - size.center(Offset.zero),
              child: child,
            );
            if (_direction > 0) {
              // In: the old view swells away; the new one grows from the
              // origin on top.
              return Stack(
                fit: StackFit.expand,
                children: [
                  Opacity(opacity: 1 - t, child: swell(leavingPage, t)),
                  Opacity(
                    opacity: (t * 1.6).clamp(0, 1),
                    child: grow(current, t),
                  ),
                ],
              );
            }
            // Out: the new (wider) view settles from slightly larger; the
            // old one shrinks back into the origin on top.
            return Stack(
              fit: StackFit.expand,
              children: [
                Opacity(opacity: t, child: swell(current, 1 - t)),
                Opacity(
                  opacity: (1 - t * 1.4).clamp(0, 1),
                  child: grow(leavingPage, 1 - t),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
