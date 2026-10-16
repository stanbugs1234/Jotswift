import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/synced_setting.dart';
import 'motion.dart';
import 'page_curl.dart';
import 'transition_frames.dart';

enum TurnDirection { forward, backward }

/// How a notebook's pages change, chosen in Settings.
enum PageTurnStyle {
  /// The corner lifts and the page peels away across a fold.
  curl('Curl'),

  /// The page swings away around its left edge.
  book('Book turn'),

  /// Pages slide side by side.
  slide('Slide'),

  /// The next page slides over the current one, like a dealt card.
  stack('Stack'),

  /// A quick crossfade.
  fade('Fade'),

  /// The page changes at once.
  none('None');

  const PageTurnStyle(this.label);

  final String label;
}

/// The chosen [PageTurnStyle], kept on this device.
class PageTurnStyleController extends Notifier<PageTurnStyle> {
  static const _prefsKey = 'pageTurnStyle';

  @override
  PageTurnStyle build() =>
      PageTurnStyle.values.asNameMap()[ref
          .watch(sharedPreferencesProvider)
          .getString(_prefsKey)] ??
      PageTurnStyle.curl;

  Future<void> set(PageTurnStyle style) async {
    state = style;
    await ref.read(sharedPreferencesProvider).setString(_prefsKey, style.name);
  }
}

final pageTurnStyleProvider =
    NotifierProvider<PageTurnStyleController, PageTurnStyle>(
      PageTurnStyleController.new,
    );

/// Turning a page by hand: what the page being shown calls as a finger
/// drags from the screen's edge.
abstract interface class PageTurnDrag {
  /// A drag began from the right edge (forward) or the left (backward).
  /// False when there's no page that way.
  bool start(TurnDirection direction);

  /// The finger has moved [dx] across since the drag began.
  void update(double dx);

  /// The finger lifted moving at [velocityX] (pixels a second); the page
  /// finishes turning or falls back.
  void end(double velocityX);
}

/// Gives the page inside a [PageTurnSwitcher] its [PageTurnDrag].
class PageTurnScope extends InheritedWidget {
  const PageTurnScope({required this.drag, required super.child, super.key});

  final PageTurnDrag drag;

  static PageTurnDrag? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<PageTurnScope>()?.drag;

  @override
  bool updateShouldNotify(PageTurnScope old) => old.drag != drag;
}

/// Shows [child] and, when [pageKey] changes, turns from the old page to the
/// new one in [style]: forward when the new page comes later in [order],
/// backward otherwise.
///
/// With [pageBuilder] and [onTurned], a finger dragging from the page's edge
/// turns it by hand (see [PageTurnScope]).
///
/// While turning, both pages are drawn once and moved as still pictures,
/// and the page that's leaving ignores touches. Reduced animations
/// crossfade and Off swaps at once, whatever the style. A turn asked for
/// while one is underway goes at double speed, so tapping through pages
/// riffles them.
class PageTurnSwitcher extends StatefulWidget {
  const PageTurnSwitcher({
    required this.pageKey,
    required this.order,
    required this.child,
    this.style = PageTurnStyle.book,
    this.pageBuilder,
    this.onTurned,
    super.key,
  });

  /// Identifies the page being shown; a new value starts a turn.
  final Object pageKey;

  /// Page keys in reading order, which decides the direction of a turn.
  /// Keys not in it turn forward.
  final List<Object> order;
  final Widget child;
  final PageTurnStyle style;

  /// Builds a neighbouring page, shown underneath while turning by hand.
  final Widget Function(Object pageKey)? pageBuilder;

  /// A page was turned to by hand; show it (by changing [pageKey]).
  final ValueChanged<Object>? onTurned;

  @override
  State<PageTurnSwitcher> createState() => _PageTurnSwitcherState();
}

class _PageTurnSwitcherState extends State<PageTurnSwitcher>
    with SingleTickerProviderStateMixin
    implements PageTurnDrag {
  late final _controller = AnimationController(vsync: this);
  final _snapshots = SnapshotController();

  /// One key per page shown, so a page keeps its state when it moves in
  /// or out of the turn (and a page dragged by hand keeps its finger).
  final _keys = <Object, GlobalKey>{};

  Object? _leavingKey;
  Widget? _leaving;
  TurnDirection _direction = TurnDirection.forward;

  /// Turning by hand: the page underneath, and where it is.
  Object? _dragKey;
  Widget? _dragPage;

  /// Moved by a finger or a spring, so not eased again.
  bool _byHand = false;

  /// A hand turn finished here; [PageTurnSwitcher.pageKey] will follow.
  Object? _arrived;

  double _width = 1;

  PageTurnStyle _styleFor(Motion motion) {
    if (motion.off) return PageTurnStyle.none;
    if (!motion.full) return PageTurnStyle.fade;
    return widget.style;
  }

  @override
  void didUpdateWidget(PageTurnSwitcher old) {
    super.didUpdateWidget(old);
    if (old.pageKey == widget.pageKey) return;
    if (_arrived == widget.pageKey) {
      _arrived = null;
      _settle();
      return;
    }
    _dragKey = _dragPage = null;
    _byHand = false;

    final motion = Motion.of(context);
    if (_styleFor(motion) == PageTurnStyle.none) {
      _controller.stop();
      _settle();
      return;
    }
    final busy = _controller.isAnimating;
    _leavingKey = old.pageKey;
    _leaving = old.child;
    _direction = directionBetween(widget.order, old.pageKey, widget.pageKey);
    _snapshots.allowSnapshotting = true;
    final duration = motion.duration(MotionTokens.pageTurn);
    _controller
      ..duration = busy ? duration ~/ 2 : duration
      ..forward(from: 0).whenCompleteOrCancel(() {
        if (mounted && _controller.isCompleted && _dragPage == null) {
          setState(_settle);
        }
      });
  }

  /// Back to just the page being shown.
  void _settle() {
    _leaving = _leavingKey = _dragPage = _dragKey = null;
    _byHand = false;
    _snapshots.allowSnapshotting = false;
    _keys.removeWhere((key, _) => key != widget.pageKey);
  }

  // Turning by hand

  @override
  bool start(TurnDirection direction) {
    final builder = widget.pageBuilder;
    if (builder == null || widget.onTurned == null || _dragPage != null) {
      return false;
    }
    if (_styleFor(Motion.of(context)) == PageTurnStyle.none) return false;
    final i = widget.order.indexOf(widget.pageKey);
    final j = direction == TurnDirection.forward ? i + 1 : i - 1;
    if (i < 0 || j < 0 || j >= widget.order.length) return false;
    _controller.stop();
    setState(() {
      _leaving = _leavingKey = null;
      _dragKey = widget.order[j];
      _dragPage = builder(widget.order[j]);
      _direction = direction;
      _byHand = true;
      _controller.value = 0;
      _snapshots.allowSnapshotting = true;
    });
    return true;
  }

  double _signed(double dx) =>
      (_direction == TurnDirection.forward ? -dx : dx) / _width;

  @override
  void update(double dx) {
    if (_dragPage == null) return;
    // Never quite all the way while held: the finger's page stays put.
    _controller.value = _signed(dx).clamp(0.0, 0.97);
  }

  @override
  void end(double velocityX) {
    final to = _dragKey;
    if (_dragPage == null || to == null) return;
    final speed = _signed(velocityX);
    final p = _controller.value;
    final turn = speed > 0.9 || (p > 0.5 && speed > -0.9);
    final spring = SpringSimulation(
      SpringDescription.withDampingRatio(mass: 1, stiffness: 420, ratio: 1),
      p,
      turn ? 1 : 0,
      speed,
    )..tolerance = const Tolerance(distance: 0.002, velocity: 0.05);
    _controller.animateWith(spring).whenCompleteOrCancel(() {
      if (!mounted || _dragKey != to) return;
      if (turn) {
        _arrived = to;
        widget.onTurned?.call(to);
      } else {
        setState(_settle);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _snapshots.dispose();
    super.dispose();
  }

  Widget _page(Object key, Widget child, {bool still = false}) {
    final page = KeyedSubtree(
      key: _keys.putIfAbsent(key, GlobalKey.new),
      child: SnapshotWidget(
        controller: _snapshots,
        mode: SnapshotMode.permissive,
        child: child,
      ),
    );
    return still ? IgnorePointer(child: page) : page;
  }

  @override
  Widget build(BuildContext context) {
    final current = _page(widget.pageKey, widget.child);
    final style = _styleFor(Motion.of(context));

    final Widget old;
    final Widget incoming;
    if (_dragPage case final drag?) {
      old = current;
      incoming = _page(_dragKey!, drag, still: true);
    } else if (_leaving case final leaving?
        when _leavingKey != widget.pageKey) {
      old = _page(_leavingKey!, leaving, still: true);
      incoming = current;
    } else {
      return PageTurnScope(drag: this, child: current);
    }

    return PageTurnScope(
      drag: this,
      child: LayoutBuilder(
        builder: (context, constraints) {
          _width = constraints.maxWidth;
          return AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final raw = _controller.value;
              final t = _byHand ? raw : MotionTokens.move.transform(raw);
              return _frame(style, t, constraints.biggest, old, incoming);
            },
          );
        },
      ),
    );
  }

  Widget _frame(
    PageTurnStyle style,
    double t,
    Size size,
    Widget old,
    Widget incoming,
  ) {
    final forward = _direction == TurnDirection.forward;
    // Backward, the earlier page comes back over the current one: the
    // forward turn run in reverse.
    final turning = forward ? old : incoming;
    final under = forward ? incoming : old;
    final p = forward ? t : 1 - t;
    return switch (style) {
      PageTurnStyle.curl => PageCurl(peel: p, page: turning, under: under),
      PageTurnStyle.book => Stack(
        fit: StackFit.expand,
        children: [
          // The page underneath darkens slightly while covered.
          shade(under, 0.18 * (1 - p)),
          hinged(
            turning,
            p,
            alignment: Alignment.centerLeft,
            rotate: (m, a) => m..rotateY(-a),
          ),
        ],
      ),
      PageTurnStyle.slide => ClipRect(
        child: slideFrame(t, size, old, incoming, forward: forward, full: true),
      ),
      PageTurnStyle.stack => ClipRect(
        child: stackFrame(
          t,
          size,
          old,
          incoming,
          forward: forward,
          from: AxisDirection.left,
        ),
      ),
      PageTurnStyle.fade || PageTurnStyle.none => fadeFrame(t, old, incoming),
    };
  }
}

/// Backward when [to] comes before [from] in [order]; otherwise forward.
TurnDirection directionBetween(List<Object> order, Object from, Object to) {
  final a = order.indexOf(from);
  final b = order.indexOf(to);
  return a >= 0 && b >= 0 && b < a
      ? TurnDirection.backward
      : TurnDirection.forward;
}
