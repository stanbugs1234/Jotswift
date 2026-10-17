import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'motion.dart';

/// Where each notebook's cover is on the shelf, so opening it can grow
/// from there and closing it can shrink back. Covers register by wrapping
/// themselves in [CoverAnchor].
abstract final class CoverAnchors {
  static final _anchors = <String, _CoverAnchorState>{};

  /// The notebook whose cover is flying, hidden on the shelf meanwhile.
  static final flying = ValueNotifier<String?>(null);

  /// [id]'s cover on screen (global coordinates), when it's showing.
  static Rect? rectOf(String id) {
    final box = _anchors[id]?.context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }
}

/// Marks [child] as notebook [id]'s cover on the shelf.
class CoverAnchor extends StatefulWidget {
  const CoverAnchor({required this.id, required this.child, super.key});

  final String id;
  final Widget child;

  @override
  State<CoverAnchor> createState() => _CoverAnchorState();
}

class _CoverAnchorState extends State<CoverAnchor> {
  @override
  void initState() {
    super.initState();
    CoverAnchors._anchors[widget.id] = this;
  }

  @override
  void didUpdateWidget(CoverAnchor old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id) {
      if (CoverAnchors._anchors[old.id] == this) {
        CoverAnchors._anchors.remove(old.id);
      }
      CoverAnchors._anchors[widget.id] = this;
    }
  }

  @override
  void dispose() {
    if (CoverAnchors._anchors[widget.id] == this) {
      CoverAnchors._anchors.remove(widget.id);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String?>(
    valueListenable: CoverAnchors.flying,
    child: widget.child,
    builder: (context, flying, child) =>
        Opacity(opacity: flying == widget.id ? 0 : 1, child: child),
  );
}

/// A route page that opens notebook [id] like picking it off the shelf:
/// its [cover] grows from where it sits to fill the screen, and [child]
/// shows through as it does. Going back shrinks it into its place again;
/// with [closeInPlace], going back fades instead (for a page that closes
/// onto its notebook rather than the shelf).
///
/// Reduced animations fade instead; Off shows the screen at once.
CustomTransitionPage<void> bookOpenPage({
  required BuildContext context,
  required LocalKey key,
  required String id,
  required Widget cover,
  required Widget child,
  bool closeInPlace = false,
}) {
  final motion = Motion.of(context);
  final duration = motion.duration(MotionTokens.emphasized);
  return CustomTransitionPage<void>(
    key: key,
    child: child,
    transitionDuration: duration,
    reverseTransitionDuration: closeInPlace
        ? motion.duration(MotionTokens.standard)
        : duration,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (!motion.full) {
        return FadeTransition(opacity: animation, child: child);
      }
      return BookOpenTransition(
        animation: animation,
        id: id,
        cover: cover,
        closeInPlace: closeInPlace,
        child: child,
      );
    },
  );
}

class BookOpenTransition extends StatefulWidget {
  const BookOpenTransition({
    required this.animation,
    required this.id,
    required this.cover,
    required this.child,
    this.closeInPlace = false,
    super.key,
  });

  final Animation<double> animation;
  final String id;
  final Widget cover;
  final Widget child;
  final bool closeInPlace;

  @override
  State<BookOpenTransition> createState() => _BookOpenTransitionState();
}

class _BookOpenTransitionState extends State<BookOpenTransition> {
  /// Where the cover started, for when it's no longer on screen.
  Rect? _from;

  @override
  void initState() {
    super.initState();
    widget.animation.addStatusListener(_status);
    _status(widget.animation.status);
  }

  @override
  void didUpdateWidget(BookOpenTransition old) {
    super.didUpdateWidget(old);
    if (old.animation != widget.animation) {
      old.animation.removeStatusListener(_status);
      widget.animation.addStatusListener(_status);
    }
  }

  @override
  void dispose() {
    widget.animation.removeStatusListener(_status);
    if (CoverAnchors.flying.value == widget.id) {
      CoverAnchors.flying.value = null;
    }
    super.dispose();
  }

  bool get _closingInPlace =>
      widget.closeInPlace && widget.animation.status == AnimationStatus.reverse;

  void _status(AnimationStatus status) {
    final moving = status.isAnimating && !_closingInPlace;
    if (moving) {
      CoverAnchors.flying.value = widget.id;
    } else if (CoverAnchors.flying.value == widget.id) {
      CoverAnchors.flying.value = null;
    }
  }

  /// [global] in this route's own coordinates.
  Rect? _local(Rect? global) {
    if (global == null) return null;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return global;
    return box.globalToLocal(global.topLeft) & global.size;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.animation,
      child: widget.child,
      builder: (context, child) {
        final t = widget.animation.value;
        // The same widgets throughout, so the screen keeps its state.
        final inPlace = _closingInPlace;
        return LayoutBuilder(
          builder: (context, constraints) {
            final full = Offset.zero & constraints.biggest;
            final from =
                _local(CoverAnchors.rectOf(widget.id)) ??
                _from ??
                // Not on the shelf (a link, a quick note): grow gently
                // from the middle.
                Rect.fromCenter(
                  center: full.center,
                  width: full.width * 0.8,
                  height: full.height * 0.8,
                );
            _from = from;
            final grow = inPlace
                ? 1.0
                : Curves.easeInOutCubicEmphasized.transform(t);
            final rect = Rect.lerp(from, full, grow)!;
            final radius = lerpDouble(8, 0, grow)!;
            // The cover fades out, then the notebook fades in: one after
            // the other, so the two never blur together.
            final coverFade = inPlace
                ? 0.0
                : 1 - const Interval(0.25, 0.5).transform(t);
            final screenFade = inPlace
                ? t
                : const Interval(0.45, 0.8).transform(t);
            return Stack(
              children: [
                // The shelf dims a little behind it.
                Positioned.fill(
                  child: IgnorePointer(
                    child: ColoredBox(
                      color: Colors.black.withValues(
                        alpha: inPlace ? 0 : 0.18 * grow,
                      ),
                    ),
                  ),
                ),
                Positioned.fromRect(
                  rect: rect,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(radius),
                    clipBehavior: grow < 1 ? Clip.antiAlias : Clip.none,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ColoredBox(
                          color: inPlace
                              ? Colors.transparent
                              : Theme.of(context).colorScheme.surface,
                        ),
                        // The notebook, laid out full size and scaled to
                        // fit, so nothing reflows as it grows.
                        Opacity(
                          opacity: screenFade,
                          child: FittedBox(
                            fit: BoxFit.cover,
                            alignment: Alignment.topCenter,
                            child: SizedBox.fromSize(
                              size: full.size,
                              child: child,
                            ),
                          ),
                        ),
                        if (coverFade > 0)
                          IgnorePointer(
                            child: Opacity(
                              opacity: coverFade,
                              child: FittedBox(
                                fit: BoxFit.cover,
                                child: widget.cover,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
