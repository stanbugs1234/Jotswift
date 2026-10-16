import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/input/finger_drawing.dart';
import '../../core/motion/page_turn.dart';
import '../../core/motion/pop_in.dart';
import '../../core/settings/synced_setting.dart';
import '../../core/paper/paper_style.dart';
import '../../core/skins/notely_skin.dart';
import '../../core/skins/widgets/paper.dart';
import '../notebooks/domain/notebook_models.dart';
import '../notebooks/notes_providers.dart';
import 'domain/page_element.dart';
import 'domain/stroke.dart';
import 'ink_tools.dart';
import 'lasso.dart';
import 'page_items.dart';
import 'pen_prediction.dart';
import 'ruler.dart';
import 'shapes.dart';
import 'stickers.dart';
import 'stroke_painter.dart';
import 'tape.dart';
import 'templates.dart';
import 'zoom_window.dart';
import '../notebooks/page_jumper.dart';
import '../../core/motion/motion.dart';

/// Ruling on full-size pages is drawn larger than on the small previews.
const _paperScale = 1.6;

/// One page of handwriting with zoom and pan.
///
/// Input rules:
/// - A stylus always draws (or erases, with the eraser tool or the pen's
///   eraser end).
/// - Once a stylus has been used, fingers never draw, so a resting palm
///   can't leave marks; fingers scroll and pinch-zoom instead.
/// - Without a stylus (most phones), one finger draws in draw mode and
///   scrolls in hand mode. Two fingers always scroll and zoom.
/// - A mouse draws in draw mode and drags the page in hand mode; the wheel
///   scrolls, and Ctrl + wheel zooms.
class PageCanvas extends ConsumerStatefulWidget {
  const PageCanvas({
    required this.pageId,
    this.readOnly = false,
    this.inkEnabled = true,
    this.onOpenPage,
    this.embedded = false,
    this.onWriting,
    this.onScroll,
    this.window,
    this.onStroke,
    super.key,
  });

  final String pageId;

  /// Shows just this part of the page (page units), magnified to the
  /// width, for writing in the zoom window. Fingers don't scroll it.
  final Rect? window;

  /// Hears each stroke written, by its bounds (to move the zoom window on).
  final ValueChanged<Rect>? onStroke;

  /// One of a scrolling list of pages: always fitted to the width, with no
  /// panning or zooming of its own, so fingers scroll the list.
  final bool embedded;

  /// Hears when the pen starts (true) and stops (false) writing, so a list
  /// of pages can hold still under a resting palm.
  final ValueChanged<bool>? onWriting;

  /// When [embedded] and fingers draw: two fingers moved by this much, to
  /// scroll the list of pages (one finger scrolls it directly otherwise).
  final ValueChanged<Offset>? onScroll;

  /// Opens another page of the notebook (when a template link is tapped).
  final ValueChanged<String>? onOpenPage;

  /// View only: no drawing and no changes to stickers, photos or text.
  final bool readOnly;

  /// Whether ink can be drawn. Off on the web, where the page always acts
  /// as with the select tool: stickers, photos and text boxes can still be
  /// added, moved and edited.
  final bool inkEnabled;

  @override
  ConsumerState<PageCanvas> createState() => _PageCanvasState();
}

class _PageCanvasState extends ConsumerState<PageCanvas>
    with TickerProviderStateMixin {
  static const _minScale = 0.2;
  static const _maxScale = 6.0;
  static const _margin = 16.0;

  // Page-to-screen transform: screen = page * _scale + _offset.
  double _scale = 1;
  Offset _offset = Offset.zero;
  Size? _viewport;

  /// This page's size in page units, from its notebook.
  Size _pageSize = pageSize;

  // Drawing.
  int? _drawPointer;
  PointerDeviceKind? _drawKind;
  bool _erasing = false;
  final _live = ValueNotifier<Stroke?>(null);
  final _pendingErase = <String>{};

  /// A guess at where the pen is by the time the frame shows, drawn just
  /// past the live stroke to hide the screen's delay (as the predicted
  /// touches in other note apps do). Never saved.
  final _predicted = ValueNotifier<List<InkPoint>>(const []);

  /// The pen's last few positions (time, page point), to make that guess.
  final _penTrail = <(Duration, Offset)>[];
  Timer? _predictionTimer;
  static const _predictAhead = Duration(milliseconds: 12);

  /// Partial erasing: saved strokes cut so far, and the pieces left (kept
  /// in [_pendingAdd] until saved).
  final _cutStrokes = <String>{};
  final _cutPieces = <String>{};

  /// Whole strokes the eraser has touched in this gesture.
  final _erased = <String>{};

  /// When the current stroke began, to tell a palm that landed just before
  /// the Pencil from a real finger stroke.
  Duration? _drawStartedAt;

  /// A finger stroke younger than this when the Pencil touches down is a
  /// palm, and is dropped.
  static const _palmWindow = Duration(milliseconds: 300);

  /// Holding still this long while drawing turns the stroke into the shape
  /// it looks like (a line, circle, rectangle...).
  static const _holdToSnap = Duration(milliseconds: 550);
  Timer? _snapTimer;

  /// Where the pen last stopped, in screen pixels.
  Offset? _snapAnchor;

  /// What the stroke snapped to, if it did. A snapped line keeps following
  /// the pen to place its end.
  ShapeKind? _snapped;

  // Scrolling and zooming: screen positions of the non-drawing pointers.
  final _navPointers = <int, Offset>{};

  /// Where and when each scrolling pointer went down, to tell taps (which
  /// follow template links) from drags.
  final _navStarts = <int, (Offset, Duration)>{};

  /// Finger speeds, so a flicked page keeps moving after the finger lifts.
  final _velocity = <int, VelocityTracker>{};
  late final Ticker _coast = createTicker(_onCoast);
  FrictionSimulation? _coastX;
  FrictionSimulation? _coastY;

  /// A quick pinch fits the page to the width: when two fingers went down
  /// and how far apart.
  Duration? _twoDownAt;
  double _twoSpan = 0;

  /// Fingers tapping the page together (two undo, three redo): when the
  /// first went down, how many were down at once, and how far they moved.
  Duration? _tapStart;
  int _tapFingers = 0;
  double _tapTravel = 0;

  /// The zoom shown briefly while pinching, e.g. "125%".
  final _zoomBadge = ValueNotifier<String?>(null);
  Timer? _zoomBadgeTimer;

  /// A finger resting on a sticker picks it up after [_holdToMove], unless
  /// it moves first (then it scrolls).
  Timer? _holdTimer;

  /// A finger dragging from the screen's left or right edge turns the page
  /// (inside a [PageTurnSwitcher]); this wide.
  static const _turnEdge = 28.0;

  /// A finger down at the edge that hasn't moved far enough yet to tell a
  /// turn from a scroll.
  (PointerDownEvent, TurnDirection)? _turnCandidate;
  int? _turnPointer;
  double _turnStartX = 0;
  VelocityTracker? _turnVelocity;
  PageTurnDrag? _turnDrag;
  static const _holdToMove = Duration(milliseconds: 280);

  /// Template pages are drawn this many pixels wide: sharp at fit-to-width
  /// on a tablet, without holding a huge image.
  static const _templateWidth = 1600;

  // Stickers (select tool).
  String? _selectedId;

  /// Stickers placed during this visit, which pop onto the page. Kept for
  /// the visit so they aren't rebuilt (and replayed) later.
  final _poppingIn = <String>{};
  _ElementDrag? _drag;

  /// Frames shown until the saved copies catch up, so a moved sticker
  /// doesn't jump back for a moment.
  final _frameOverrides = <String, ElementFrame>{};

  /// Handles are this many screen pixels across at any zoom.
  static const _handleSize = 28.0;

  // Ruler: where it is, the fingers moving it (screen positions), its
  // angle before snapping while it turns, and which edge the pen follows.
  Ruler? _ruler;
  final _rulerPointers = <int, Offset>{};
  double _rulerTurn = 0;
  int? _rulerSide;

  /// Where a hovering Pencil (or mouse) is, in screen pixels, to show
  /// the size and color of the mark it would make.
  final _hover = ValueNotifier<Offset?>(null);

  /// A finger moving the zoom window's box, and where it last was.
  int? _boxPointer;
  Offset? _boxAt;

  /// The zoom window's box is shown on this page (not in the window).
  bool get _showsZoomBox =>
      widget.window == null &&
      !widget.embedded &&
      !widget.readOnly &&
      widget.inkEnabled &&
      ref.read(zoomWindowProvider);

  // Tape: the strip being laid (page units), from where, by which pointer;
  // and strips the eraser has touched, hidden until they're removed.
  PageElement? _tapeDraft;
  Offset? _tapeFrom;
  int? _tapePointer;
  final _erasedTapes = <String>{};

  // Laser pointer: recent points (page units) with when they were added.
  final _laser = ValueNotifier<List<(Offset, Duration)>>(const []);
  int? _laserPointer;
  final _laserClock = Stopwatch()..start();
  late final Ticker _laserFade = createTicker((_) => _fadeLaser());

  // Lasso.
  /// The loop being drawn, in page units, and the pointer drawing it.
  final _lassoPoints = ValueNotifier<List<Offset>>(const []);
  int? _lassoPointer;

  /// What the lasso holds, and a drag moving, resizing or rotating it.
  _LassoSelection? _lasso;
  _LassoDrag? _lassoDrag;

  /// Strokes made by the lasso (moved, recolored, pasted), shown until the
  /// saved copies arrive.
  final _pendingAdd = <String, Stroke>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowHint());
  }

  static const _hintKey = 'fingerHintShown';

  /// Once per device, the first time a page opens with fingers scrolling,
  /// say so: otherwise a finger that doesn't draw looks broken.
  void _maybeShowHint() {
    if (!mounted ||
        widget.readOnly ||
        widget.window != null ||
        ref.read(fingersDrawProvider)) {
      return;
    }
    final prefs = ref.read(sharedPreferencesProvider);
    if (prefs.getBool(_hintKey) ?? false) return;
    prefs.setBool(_hintKey, true);
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text(
          'Write with your Apple Pencil. Fingers scroll and zoom; '
          'hold a sticker to move it.',
        ),
        duration: Duration(seconds: 5),
      ),
    );
  }

  @override
  void dispose() {
    _live.dispose();
    _hover.dispose();
    _predicted.dispose();
    _predictionTimer?.cancel();
    _lassoPoints.dispose();
    _laser.dispose();
    _laserFade.dispose();
    _coast.dispose();
    _zoomBadge.dispose();
    _zoomBadgeTimer?.cancel();
    _holdTimer?.cancel();
    _snapTimer?.cancel();
    super.dispose();
  }

  Offset _toPage(Offset screen) => (screen - _offset) / _scale;

  void _fitWidth(Size viewport) {
    if (widget.embedded) {
      _scale = viewport.width / _pageSize.width;
      _offset = Offset.zero;
      return;
    }
    _scale = ((viewport.width - 2 * _margin) / _pageSize.width).clamp(
      _minScale,
      _maxScale,
    );
    // A page shorter than the screen (a landscape page on an upright
    // tablet) sits in the middle rather than at the top.
    final height = _pageSize.height * _scale;
    _offset = Offset(
      (viewport.width - _pageSize.width * _scale) / 2,
      math.max(_margin, (viewport.height - height) / 2),
    );
  }

  /// Lets the page move freely, but keeps at least a quarter of the
  /// screen's worth of it in view (or all of it, when it's smaller).
  void _clampOffset() {
    final viewport = _viewport;
    if (viewport == null || widget.embedded) return;
    final w = _pageSize.width * _scale;
    final h = _pageSize.height * _scale;
    double clampAxis(double value, double content, double view) {
      final keep = math.min(content, view / 4);
      return value.clamp(keep - content, view - keep);
    }

    _offset = Offset(
      clampAxis(_offset.dx, w, viewport.width),
      clampAxis(_offset.dy, h, viewport.height),
    );
  }

  static bool _isStylus(PointerDeviceKind kind) =>
      kind == PointerDeviceKind.stylus ||
      kind == PointerDeviceKind.invertedStylus;

  /// The Pencil is writing or erasing right now.
  /// Where the drawing pointer is now.
  Offset _drawPosition = Offset.zero;

  bool get _penDown => _drawPointer != null && _isStylus(_drawKind!);

  bool _canDraw(PointerDownEvent e) {
    if (widget.readOnly || !widget.inkEnabled || _drawPointer != null) {
      return false;
    }
    // Fingers already on the page block other fingers and the mouse, but
    // never the Pencil (see _yieldToPencil).
    if (!_isStylus(e.kind) && _navPointers.isNotEmpty) return false;
    if (ref.read(inkToolProvider).kind == InkToolKind.select &&
        e.kind != PointerDeviceKind.invertedStylus) {
      return false;
    }
    return switch (e.kind) {
      PointerDeviceKind.stylus || PointerDeviceKind.invertedStylus => true,
      PointerDeviceKind.mouse =>
        ref.read(inkToolProvider).drawMode && e.buttons == kPrimaryMouseButton,
      PointerDeviceKind.touch => ref.read(fingersDrawProvider),
      _ => false,
    };
  }

  /// The Pencil touched down: fingers on the page are a resting palm. A
  /// finger stroke that only just began is dropped, an older one is kept,
  /// and scrolling stops.
  void _yieldToPencil(Duration now) {
    if (_drawPointer != null && _drawKind == PointerDeviceKind.touch) {
      final started = _drawStartedAt;
      if (started != null && now - started < _palmWindow) {
        _cancelDrawing();
      } else if (_erasing) {
        _finishErasing();
      } else {
        _finishStroke();
      }
    }
    _holdTimer?.cancel();
    _turnCandidate = null;
    _endTurn(0);
    _navPointers.clear();
    _navStarts.clear();
    _velocity.clear();
    _twoDownAt = null;
    _tapStart = null;
  }

  void _onPointerHover(PointerHoverEvent e) {
    if (e.kind == PointerDeviceKind.touch || widget.readOnly) return;
    _hover.value = e.localPosition;
  }

  void _onPointerDown(PointerDownEvent e) {
    _stopCoasting();
    _hover.value = null;
    if (_isStylus(e.kind)) {
      ref.read(devicePencilProvider.notifier).stylusSeen();
      _yieldToPencil(e.timeStamp);
    } else if (e.kind == PointerDeviceKind.touch && _penDown) {
      // A palm while the Pencil writes: no ink, no scrolling, no zoom.
      return;
    } else if (_turnPointer != null || _turnCandidate != null) {
      // One finger turns the page; others wait.
      return;
    }

    if (_pickColorWith(e)) return;
    if (_zoomBoxWith(e)) return;
    if (_rulerWith(e)) return;
    if (_lassoWith(e)) return;
    if (_selectWith(e)) return;

    if (_canDraw(e) &&
        ref.read(inkToolProvider).kind == InkToolKind.tape &&
        e.kind != PointerDeviceKind.invertedStylus) {
      _tapePointer = e.pointer;
      _tapeFrom = _toPage(e.localPosition);
      return;
    }

    if (_canDraw(e) &&
        ref.read(inkToolProvider).kind == InkToolKind.laser &&
        e.kind != PointerDeviceKind.invertedStylus) {
      _laserPointer = e.pointer;
      _addLaserPoint(e.localPosition);
      return;
    }

    if (_canDraw(e)) {
      _drawPointer = e.pointer;
      _drawPosition = e.localPosition;
      widget.onWriting?.call(true);
      _drawKind = e.kind;
      _drawStartedAt = e.timeStamp;
      _erasing =
          e.kind == PointerDeviceKind.invertedStylus ||
          ref.read(inkToolProvider).kind == InkToolKind.eraser;
      if (_erasing) {
        _eraseAt(e.localPosition);
      } else {
        _startStroke(e);
      }
      return;
    }

    if (e.kind == PointerDeviceKind.touch ||
        e.kind == PointerDeviceKind.mouse) {
      if (_drawPointer == null && _navPointers.isEmpty) {
        if (_turnEdgeAt(e.localPosition) case final direction?) {
          _turnCandidate = (e, direction);
          return;
        }
      }
      if (_navPointers.isEmpty) {
        // Perhaps the start of a tap with two or three fingers.
        _tapStart = e.kind == PointerDeviceKind.touch ? e.timeStamp : null;
        _tapFingers = 0;
        _tapTravel = 0;
      }
      // A second finger while a finger is drawing means "zoom", not "draw".
      if (_drawPointer case final first?
          when _drawKind == PointerDeviceKind.touch) {
        _tapStart = _drawStartedAt;
        _cancelDrawing();
        // The drawing finger is now one of the two.
        _navPointers[first] = _drawPosition;
      }
      _navPointers[e.pointer] = e.localPosition;
      _tapFingers = math.max(_tapFingers, _navPointers.length);
      _navStarts[e.pointer] = (e.localPosition, e.timeStamp);
      _velocity[e.pointer] = VelocityTracker.withKind(e.kind)
        ..addPosition(e.timeStamp, e.localPosition);
      if (_navPointers.length == 2) {
        _twoDownAt = e.timeStamp;
        _twoSpan = _span();
      } else if (_navPointers.length > 2) {
        _twoDownAt = null;
      }
      if (e.kind == PointerDeviceKind.touch && _navPointers.length == 1) {
        _maybeHoldSticker(e);
      }
    }
  }

  /// With the pen tools, when fingers don't draw, a finger resting on a
  /// sticker picks it up after a moment, so it can be dragged without the
  /// Select tool. Moving first scrolls instead.
  void _maybeHoldSticker(PointerDownEvent e) {
    _holdTimer?.cancel();
    if (widget.readOnly ||
        ref.read(fingersDrawProvider) ||
        ref.read(inkToolProvider).kind == InkToolKind.select) {
      return;
    }
    final point = _toPage(e.localPosition);
    final hit = _shownElements().reversed
        .where((el) => el.frame.contains(point, slop: 4 / _scale))
        .firstOrNull;
    if (hit == null) return;
    _holdTimer = Timer(_holdToMove, () {
      final at = _navPointers[e.pointer];
      if (!mounted || at == null || _navPointers.length != 1) return;
      if ((at - e.localPosition).distance > 10) return;
      HapticFeedback.selectionClick();
      _navPointers.remove(e.pointer);
      _navStarts.remove(e.pointer);
      _velocity.remove(e.pointer);
      setState(
        () => _drag = _ElementDrag(e.pointer, hit, _DragMode.move, _toPage(at)),
      );
    });
  }

  /// With the eyedropper out, a touch takes the color of the ink under it:
  /// writing over highlighting, and the newest first.
  bool _pickColorWith(PointerDownEvent e) {
    if (!ref.read(eyedropperProvider) || widget.readOnly) return false;
    if (_drawPointer != null || _navPointers.isNotEmpty) return false;
    ref.read(eyedropperProvider.notifier).put();
    final point = _toPage(e.localPosition);
    final hits = [
      for (final s in _currentStrokes())
        if (s.hitTest(point, 8 / _scale)) s,
    ];
    final ink =
        hits.where((s) => s.tool == InkTool.pen).lastOrNull ?? hits.lastOrNull;
    if (ink == null) {
      _showZoom('No ink there');
      return true;
    }
    HapticFeedback.selectionClick();
    ref.read(inkToolProvider.notifier).pickColorOf(ink);
    return true;
  }

  /// A finger (or the mouse) on the zoom window's box moves it. The pen
  /// writes through it.
  bool _zoomBoxWith(PointerDownEvent e) {
    if (!_showsZoomBox || _isStylus(e.kind) || _drawPointer != null) {
      return false;
    }
    if (_navPointers.isNotEmpty) return false;
    final box = ref.read(zoomBoxProvider(widget.pageId)).rect;
    if (!box.inflate(8 / _scale).contains(_toPage(e.localPosition))) {
      return false;
    }
    _stopCoasting();
    _boxPointer = e.pointer;
    _boxAt = e.localPosition;
    return true;
  }

  /// Which way a drag starting at [point] would turn the page, if it's at
  /// the screen's edge and the page can be turned.
  TurnDirection? _turnEdgeAt(Offset point) {
    final viewport = _viewport;
    if (widget.embedded ||
        widget.window != null ||
        viewport == null ||
        PageTurnScope.maybeOf(context) == null) {
      return null;
    }
    if (point.dx <= _turnEdge) return TurnDirection.backward;
    if (point.dx >= viewport.width - _turnEdge) return TurnDirection.forward;
    return null;
  }

  /// A finger at the edge moved: across and inwards turns the page;
  /// anything else scrolls as usual. False while it's too soon to tell.
  bool _resolveTurn(PointerMoveEvent e) {
    final (down, direction) = _turnCandidate!;
    final moved = e.localPosition - down.localPosition;
    if (moved.distance < 10) return false;
    _turnCandidate = null;
    final inwards = direction == TurnDirection.forward
        ? moved.dx < 0
        : moved.dx > 0;
    final drag = PageTurnScope.maybeOf(context);
    if (inwards &&
        moved.dx.abs() > moved.dy.abs() &&
        drag != null &&
        drag.start(direction)) {
      _turnPointer = e.pointer;
      _turnDrag = drag;
      _turnStartX = down.localPosition.dx;
      _turnVelocity = VelocityTracker.withKind(e.kind)
        ..addPosition(e.timeStamp, e.localPosition);
      drag.update(e.localPosition.dx - _turnStartX);
      return false;
    }
    _navPointers[e.pointer] = down.localPosition;
    _navStarts[e.pointer] = (down.localPosition, down.timeStamp);
    _velocity[e.pointer] = VelocityTracker.withKind(e.kind)
      ..addPosition(down.timeStamp, down.localPosition);
    return true;
  }

  void _endTurn(double velocityX) {
    final drag = _turnDrag;
    _turnPointer = null;
    _turnDrag = null;
    _turnVelocity = null;
    drag?.end(velocityX);
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (_turnCandidate?.$1.pointer == e.pointer && !_resolveTurn(e)) return;
    if (e.pointer == _turnPointer) {
      _turnVelocity?.addPosition(e.timeStamp, e.localPosition);
      _turnDrag?.update(e.localPosition.dx - _turnStartX);
      return;
    }
    if (_rulerPointers.containsKey(e.pointer)) return _moveRuler(e);
    if (e.pointer == _laserPointer) return _addLaserPoint(e.localPosition);
    if (e.pointer == _tapePointer) return _stretchTape(e.localPosition);
    if (e.pointer == _boxPointer) {
      final last = _boxAt!;
      _boxAt = e.localPosition;
      ref
          .read(zoomBoxProvider(widget.pageId).notifier)
          .moveBy((e.localPosition - last) / _scale);
      return;
    }
    if (e.pointer == _lassoPointer) {
      _lassoPoints.value = [..._lassoPoints.value, _toPage(e.localPosition)];
      return;
    }
    if (e.pointer == _lassoDrag?.pointer) {
      setState(() => _lassoDragTo(_toPage(e.localPosition)));
      return;
    }
    if (e.pointer == _drag?.pointer) {
      setState(() => _dragTo(_toPage(e.localPosition)));
      return;
    }
    if (e.pointer == _drawPointer) {
      _drawPosition = e.localPosition;
      if (_erasing) {
        _eraseAt(e.localPosition);
      } else {
        _extendStroke(e);
      }
      return;
    }
    if (!_navPointers.containsKey(e.pointer)) return;

    final before = Map.of(_navPointers);
    _navPointers[e.pointer] = e.localPosition;
    _tapTravel += (e.localPosition - before[e.pointer]!).distance;
    if (widget.window != null) return; // The window holds still.
    // The list of pages scrolls instead.
    if (widget.embedded) {
      if (_navPointers.length == 2 && ref.read(fingersDrawProvider)) {
        widget.onScroll?.call((e.localPosition - before[e.pointer]!) / 2);
      }
      return;
    }
    _velocity[e.pointer]?.addPosition(e.timeStamp, e.localPosition);
    setState(() {
      if (_navPointers.length == 1) {
        _offset += e.localPosition - before[e.pointer]!;
      } else {
        _pinch(before, _navPointers);
        _showZoom();
      }
      _clampOffset();
    });
  }

  /// Scrolls just enough to show [rect] (page units), with a margin.
  void _reveal(Rect rect) {
    final viewport = _viewport;
    if (viewport == null) return;
    final shown = Rect.fromLTWH(
      rect.left * _scale + _offset.dx,
      rect.top * _scale + _offset.dy,
      rect.width * _scale,
      rect.height * _scale,
    ).inflate(24);
    var dx = 0.0, dy = 0.0;
    if (shown.left < 0) dx = -shown.left;
    if (shown.right > viewport.width) dx = viewport.width - shown.right;
    if (shown.top < 0) dy = -shown.top;
    if (shown.bottom > viewport.height) dy = viewport.height - shown.bottom;
    if (dx == 0 && dy == 0) return;
    setState(() {
      _offset += Offset(dx, dy);
      _clampOffset();
    });
  }

  /// The zoom as a share of fit-to-width.
  String _zoomLabel() {
    final viewport = _viewport;
    if (viewport == null) return '';
    final fit = (viewport.width - 2 * _margin) / _pageSize.width;
    return '${(_scale / fit * 100).round()}%';
  }

  void _showZoom([String? text]) {
    _zoomBadge.value = text ?? _zoomLabel();
    _zoomBadgeTimer?.cancel();
    _zoomBadgeTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) _zoomBadge.value = null;
    });
  }

  // Momentum

  void _startCoast(Offset velocity) {
    if (velocity.distance < 250) return;
    _coastX = FrictionSimulation(0.135, _offset.dx, velocity.dx);
    _coastY = FrictionSimulation(0.135, _offset.dy, velocity.dy);
    _coast
      ..stop()
      ..start();
  }

  void _onCoast(Duration elapsed) {
    final x = _coastX, y = _coastY;
    if (x == null || y == null) return _stopCoasting();
    final t = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    final before = _offset;
    setState(() {
      _offset = Offset(x.x(t), y.x(t));
      _clampOffset();
    });
    final stuck = t > 0.05 && (_offset - before).distance < 0.1;
    if ((x.isDone(t) && y.isDone(t)) || stuck) _stopCoasting();
  }

  void _stopCoasting() {
    if (_coast.isActive) _coast.stop();
    _coastX = _coastY = null;
  }

  /// Zooms and pans using the first two pointers.
  void _pinch(Map<int, Offset> before, Map<int, Offset> after) {
    final ids = after.keys.take(2).toList();
    final a0 = before[ids[0]]!, b0 = before[ids[1]]!;
    final a1 = after[ids[0]]!, b1 = after[ids[1]]!;
    final oldDistance = (a0 - b0).distance;
    if (oldDistance < 1) return;
    final newScale = (_scale * (a1 - b1).distance / oldDistance).clamp(
      _minScale,
      _maxScale,
    );
    final oldFocal = (a0 + b0) / 2;
    final newFocal = (a1 + b1) / 2;
    final pageFocal = (oldFocal - _offset) / _scale;
    _scale = newScale;
    _offset = newFocal - pageFocal * _scale;
  }

  void _onPointerUp(PointerEvent e) {
    _holdTimer?.cancel();
    if (_turnCandidate?.$1.pointer == e.pointer) {
      // A tap at the edge.
      _turnCandidate = null;
      if (!_toggleTapeAt(e.localPosition)) _followLinkAt(e.localPosition);
      return;
    }
    if (e.pointer == _turnPointer) {
      return _endTurn(_turnVelocity?.getVelocity().pixelsPerSecond.dx ?? 0);
    }
    if (_rulerPointers.remove(e.pointer) != null) return;
    if (e.pointer == _laserPointer) {
      _laserPointer = null;
      return;
    }
    if (e.pointer == _tapePointer) return _finishTape(e.localPosition);
    if (e.pointer == _boxPointer) {
      _boxPointer = null;
      return;
    }
    if (e.pointer == _lassoPointer) return _finishLasso();
    if (e.pointer == _lassoDrag?.pointer) return _finishLassoDrag();
    if (e.pointer == _drag?.pointer) _finishDrag();
    _checkQuickPinch(e);
    if (_navPointers.length == 1 && _navPointers.containsKey(e.pointer)) {
      _checkFingerTap(e.timeStamp);
    }
    final tracker = _velocity.remove(e.pointer);
    if (tracker != null && _navPointers.length == 1) {
      final start = _navStarts[e.pointer];
      final moved =
          start != null && (e.localPosition - start.$1).distance >= 10;
      if (moved && !widget.embedded && widget.window == null) {
        _startCoast(tracker.getVelocity().pixelsPerSecond);
      }
    }
    final start = _navStarts.remove(e.pointer);
    if (start != null &&
        _navPointers.length == 1 &&
        (e.localPosition - start.$1).distance < 10 &&
        e.timeStamp - start.$2 < const Duration(milliseconds: 400)) {
      if (!_toggleTapeAt(e.localPosition)) _followLinkAt(e.localPosition);
    }
    if (e.pointer == _drawPointer) {
      if (_erasing) {
        _finishErasing();
      } else {
        _finishStroke();
      }
    }
    _navPointers.remove(e.pointer);
  }

  // Tape

  /// The strip from where the pen went down to [screen]: level, upright or
  /// diagonal when it's near one, as wide as the tool's tape.
  void _stretchTape(Offset screen) {
    final from = _tapeFrom;
    if (from == null) return;
    final to = snapLine(from, _toPage(screen));
    final tool = ref.read(inkToolProvider);
    final along = to - from;
    setState(
      () => _tapeDraft = PageElement(
        id:
            _tapeDraft?.id ??
            ref.read(elementRepositoryProvider).newElementId(),
        content: TapeContent(color: tool.tapeColor, pattern: tool.tapePattern),
        frame: ElementFrame(
          center: (from + to) / 2,
          width: math.max(along.distance, 1),
          height: tool.tapeWidth,
          rotation: math.atan2(along.dy, along.dx),
        ),
        z: 0,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  /// The pen lifted: lay the strip, or if it barely moved, it was a tap.
  void _finishTape(Offset screen) {
    final draft = _tapeDraft;
    setState(() {
      _tapePointer = null;
      _tapeDraft = null;
      _tapeFrom = null;
    });
    if (draft == null || draft.frame.width * _scale < 10) {
      _toggleTapeAt(screen);
      return;
    }
    final top = _shownElements().fold(0.0, (z, e) => math.max(z, e.z));
    ref
        .read(inkHistoryProvider(widget.pageId).notifier)
        .addElement(
          PageElement(
            id: draft.id,
            content: draft.content,
            frame: draft.frame,
            z: top + 1,
            createdAt: draft.createdAt,
          ),
        );
  }

  /// Peels back the tape at [screen], or puts it back. Returns whether
  /// there was tape there.
  bool _toggleTapeAt(Offset screen) {
    if (widget.readOnly) return false;
    final point = _toPage(screen);
    final tape = _shownElements().reversed
        .where(
          (e) =>
              e.content is TapeContent &&
              e.frame.contains(point, slop: 4 / _scale),
        )
        .firstOrNull;
    if (tape == null) return false;
    HapticFeedback.selectionClick();
    ref
        .read(inkHistoryProvider(widget.pageId).notifier)
        .editElement(
          tape,
          tape.copyWith(content: (tape.content as TapeContent).toggled()),
        );
    return true;
  }

  /// Opens the page a template link at [screen] points to, if any.
  /// Returns whether [screen] was on a link.
  bool _followLinkAt(Offset screen) {
    // A link the user made, on top of anything else.
    final point = _toPage(screen);
    for (final e in _shownElements().reversed) {
      if (e.content case LinkContent(:final pageId)
          when e.frame.contains(point)) {
        widget.onOpenPage?.call(pageId);
        return true;
      }
    }
    final page = ref.read(pageProvider(widget.pageId)).value;
    final template = page?.template;
    final image = template == null ? null : _templateImage(template);
    if (page == null || template == null || image == null) return false;
    final links = ref.read(templateLinksProvider(template)).value ?? [];
    final drawn = _templateRect(image);
    final at = Offset(
      (point.dx - drawn.left) / drawn.width,
      (point.dy - drawn.top) / drawn.height,
    );
    for (final link in links) {
      if (!link.area.contains(at)) continue;
      final key = (template.itemId, link.targetPage);
      final target = ref
          .read(notebookTemplatePagesProvider(page.notebookId))
          .value?[key];
      if (target != null) {
        if (target != widget.pageId) widget.onOpenPage?.call(target);
      } else {
        _openWhenFound(
          page.notebookId,
          key,
          PageTemplate(
            itemId: template.itemId,
            version: template.version,
            pdfPage: link.targetPage,
            pack: template.pack,
            sha256: template.sha256,
            bytes: template.bytes,
            file: template.file,
          ),
        );
      }
      return true;
    }
    return false;
  }

  /// Just after the app starts, the notebook's list of pages can come from
  /// the device's cache and miss pages not opened before. Waits a moment
  /// for the full list, then opens the page a link points to. If it's
  /// still missing (left out when the planner was made, or deleted),
  /// offers to add [target] to the notebook.
  Future<void> _openWhenFound(
    String notebookId,
    (String, int) key,
    PageTemplate target,
  ) async {
    String? found(List<NotePage> pages) => pages
        .where(
          (p) => (p.template?.itemId, p.template?.pdfPage) == (key.$1, key.$2),
        )
        .firstOrNull
        ?.id;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final pages = ref
        .read(notebookRepositoryProvider)
        .watchNotebookPages(notebookId)
        .map(found)
        .firstWhere((id) => id != null);
    // A quick look first, so a page that isn't there is offered at once.
    var offered = false;
    String? id;
    try {
      id = await pages.timeout(const Duration(milliseconds: 1200));
    } on TimeoutException {
      offered = true;
      _offerToAdd(messenger, notebookId, target);
      try {
        id = await ref
            .read(notebookRepositoryProvider)
            .watchNotebookPages(notebookId)
            .map(found)
            .firstWhere((id) => id != null)
            .timeout(const Duration(seconds: 3));
        messenger?.hideCurrentSnackBar();
      } on Object {
        return;
      }
    } on Object {
      return;
    }
    if (mounted && id != null && id != widget.pageId) {
      widget.onOpenPage?.call(id);
    } else if (offered) {
      messenger?.hideCurrentSnackBar();
    }
  }

  /// "(Page) isn't in this notebook", with Add it to make the page and
  /// open it.
  Future<void> _offerToAdd(
    ScaffoldMessengerState? messenger,
    String notebookId,
    PageTemplate target,
  ) async {
    if (messenger == null) return;
    String? title;
    try {
      title = await ref.read(templatePageTitleProvider)(target);
    } on Object {
      return;
    }
    if (title == null || !mounted) return;
    final add = ref.read(addTemplatePageProvider);
    final open = widget.onOpenPage;
    messenger.showSnackBar(
      SnackBar(
        content: Text('$title isn\'t in this notebook.'),
        action: SnackBarAction(
          label: 'Add it',
          onPressed: () async {
            final id = await add(notebookId, target);
            if (id != null) open?.call(id);
          },
        ),
      ),
    );
  }

  ui.Image? _templateImage(PageTemplate template) => ref
      .read(templateImageProvider((template: template, width: _templateWidth)))
      .value;

  /// Where a template page's image sits on the page: as large as fits,
  /// centered.
  Rect _templateRect(ui.Image image) {
    final fitted = applyBoxFit(
      BoxFit.contain,
      Size(image.width.toDouble(), image.height.toDouble()),
      _pageSize,
    ).destination;
    return Alignment.center.inscribe(fitted, Offset.zero & _pageSize);
  }

  /// Two fingers tapped together (briefly, without moving), twice in a
  /// row: fit the page to the width again.
  /// Distance between the first two scrolling pointers.
  double _span() {
    final points = _navPointers.values.take(2).toList();
    return points.length < 2 ? 0 : (points[0] - points[1]).distance;
  }

  /// Two fingers pinched in quickly: fit the page to the width, as a quick
  /// pinch fits the canvas in Procreate.
  void _checkQuickPinch(PointerEvent e) {
    final down = _twoDownAt;
    if (down == null ||
        _navPointers.length != 2 ||
        !_navPointers.containsKey(e.pointer)) {
      return;
    }
    _twoDownAt = null;
    final quick = e.timeStamp - down < const Duration(milliseconds: 350);
    if (!quick || widget.embedded || _span() > _twoSpan * 0.6) return;
    final viewport = _viewport;
    if (viewport == null) return;
    setState(() => _fitWidth(viewport));
    _showZoom('Fit width');
  }

  /// The last of two or three fingers lifted: if they only tapped, undo
  /// (two) or redo (three), as in most drawing and note apps.
  void _checkFingerTap(Duration now) {
    final start = _tapStart;
    _tapStart = null;
    if (start == null ||
        widget.readOnly ||
        _tapFingers < 2 ||
        _tapFingers > 3 ||
        now - start > const Duration(milliseconds: 350) ||
        _tapTravel > 12.0 * _tapFingers ||
        !ref.read(fingerTapUndoProvider)) {
      return;
    }
    final undo = _tapFingers == 2;
    final history = ref.read(inkHistoryProvider(widget.pageId));
    final notifier = ref.read(inkHistoryProvider(widget.pageId).notifier);
    if (undo ? history.canUndo : history.canRedo) {
      HapticFeedback.selectionClick();
      undo ? notifier.undo() : notifier.redo();
      _showZoom(undo ? 'Undo' : 'Redo');
    } else {
      _showZoom(undo ? 'Nothing to undo' : 'Nothing to redo');
    }
  }

  void _onPointerCancel(PointerEvent e) {
    _holdTimer?.cancel();
    if (_turnCandidate?.$1.pointer == e.pointer) _turnCandidate = null;
    if (e.pointer == _turnPointer) return _endTurn(0);
    if (_rulerPointers.remove(e.pointer) != null) return;
    if (e.pointer == _laserPointer) _laserPointer = null;
    if (e.pointer == _boxPointer) _boxPointer = null;
    if (e.pointer == _tapePointer) {
      setState(() {
        _tapePointer = null;
        _tapeDraft = null;
      });
    }
    if (e.pointer == _lassoPointer) {
      _lassoPointer = null;
      _lassoPoints.value = const [];
    }
    if (e.pointer == _lassoDrag?.pointer) {
      setState(() {
        _lasso = _lasso?.withTransform(_lassoDrag!.start);
        _lassoDrag = null;
      });
    }
    _velocity.remove(e.pointer);
    _navStarts.remove(e.pointer);
    _tapStart = null;
    if (e.pointer == _drag?.pointer) setState(() => _drag = null);
    if (e.pointer == _drawPointer) _cancelDrawing();
    _navPointers.remove(e.pointer);
  }

  void _onPointerSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent || widget.embedded) return;
    setState(() {
      if (HardwareKeyboard.instance.isControlPressed) {
        final pageAtPointer = _toPage(e.localPosition);
        final factor = math.exp(-e.scrollDelta.dy / 300);
        _scale = (_scale * factor).clamp(_minScale, _maxScale);
        _offset = e.localPosition - pageAtPointer * _scale;
      } else {
        _offset -= e.scrollDelta;
      }
      _clampOffset();
    });
  }

  // Strokes

  InkPoint _inkPoint(PointerEvent e) {
    final p = _toPage(e.localPosition);
    final range = e.pressureMax - e.pressureMin;
    final pressure = range > 0
        ? ((e.pressure - e.pressureMin) / range).clamp(0.0, 1.0)
        : 0.5;
    return InkPoint(p.dx, p.dy, pressure);
  }

  void _startStroke(PointerDownEvent e) {
    final tool = ref.read(inkToolProvider);
    final colors = NotelySkin.of(context).inkColors;
    var color = tool.colorFrom(colors);
    final shape = tool.kind == InkToolKind.shape;
    if (tool.kind == InkToolKind.highlighter) {
      color = color.withValues(alpha: 0.35);
    } else if (tool.penOpacity < 1 && !shape) {
      color = color.withValues(alpha: color.a * tool.penOpacity);
    }
    _live.value = Stroke(
      id: ref.read(strokeRepositoryProvider).newStrokeId(),
      tool: tool.kind == InkToolKind.highlighter
          ? InkTool.highlighter
          : InkTool.pen,
      color: color.toARGB32(),
      width: tool.size,
      points: [_inkPoint(e)],
      createdAt: DateTime.now().millisecondsSinceEpoch,
      pressureSensitive:
          e.kind == PointerDeviceKind.stylus && e.pressureMax > e.pressureMin,
      style: switch (tool.kind) {
        InkToolKind.highlighter => PenStyle.fountain,
        // Shapes are drawn evenly, like with a fineliner.
        InkToolKind.shape => PenStyle.ballpoint,
        _ => tool.penStyle,
      },
      followsPen: e.kind == PointerDeviceKind.stylus,
      dash: shape ? tool.lineDash : LineDash.solid,
    );
    _clearPrediction();
    _penTrail
      ..clear()
      ..add((e.timeStamp, _live.value!.points.first.offset));
    _snapped = null;
    final ruler = _ruler;
    final first = _live.value!.points.first;
    _rulerSide = ruler?.edgeNear(first.offset);
    if (_rulerSide != null) {
      _live.value = _live.value!.withPoints([_guided(first)]);
      return; // Following the ruler: no shapes.
    }
    if (tool.kind == InkToolKind.highlighter && tool.straightHighlighter) {
      // A straight line from the start to the pen, as a snapped line.
      _snapped = ShapeKind.line;
      return;
    }
    _waitForHold(e.localPosition);
  }

  /// (Re)starts the hold-to-snap timer unless the pen has only wobbled.
  void _waitForHold(Offset screen) {
    final anchor = _snapAnchor;
    if (anchor != null &&
        _snapTimer != null &&
        (screen - anchor).distance < 4) {
      return;
    }
    _snapAnchor = screen;
    _snapTimer?.cancel();
    _snapTimer = Timer(_holdToSnap, _snapToShape);
  }

  void _stopWaitingForHold() {
    _snapTimer?.cancel();
    _snapTimer = null;
    _snapAnchor = null;
  }

  /// The pen held still: redraw the stroke as the shape it looks like.
  void _snapToShape() {
    _snapTimer = null;
    final stroke = _live.value;
    if (!mounted || _drawPointer == null || _erasing || stroke == null) return;
    if (_snapped != null) return;
    final shape = recognizeShape([for (final p in stroke.points) p.offset]);
    if (shape == null) return;
    HapticFeedback.mediumImpact();
    _clearPrediction();
    _snapped = shape.kind;
    _live.value = _filled(_shapeStroke(stroke, shape.outline), shape.kind);
  }

  /// [stroke] with the shape tool's fill, when it's a closed shape drawn
  /// with the shape tool.
  Stroke _filled(Stroke stroke, ShapeKind kind) {
    final tool = ref.read(inkToolProvider);
    if (tool.kind != InkToolKind.shape ||
        kind == ShapeKind.line ||
        tool.shapeFill == ShapeFill.none) {
      return stroke;
    }
    final color = Color(stroke.color);
    final fill = color.withValues(
      alpha: tool.shapeFill == ShapeFill.light ? 0.22 : 1,
    );
    return Stroke(
      id: stroke.id,
      tool: stroke.tool,
      color: stroke.color,
      width: stroke.width,
      points: stroke.points,
      createdAt: stroke.createdAt,
      pressureSensitive: stroke.pressureSensitive,
      style: stroke.style,
      followsPen: stroke.followsPen,
      dash: stroke.dash,
      fill: fill.toARGB32(),
    );
  }

  /// [stroke] redrawn along [outline], evenly and at its full width.
  static Stroke _shapeStroke(Stroke stroke, List<Offset> outline) => Stroke(
    id: stroke.id,
    tool: stroke.tool,
    color: stroke.color,
    width: stroke.width,
    points: [for (final p in densify(outline)) InkPoint(p.dx, p.dy)],
    createdAt: stroke.createdAt,
    pressureSensitive: true,
    style: stroke.style,
    followsPen: stroke.followsPen,
    dash: stroke.dash,
    fill: stroke.fill,
  );

  /// [p] moved onto the ruler edge the stroke follows.
  InkPoint _guided(InkPoint p) {
    final q = _ruler!.project(p.offset, _rulerSide!, _live.value!.width);
    return InkPoint(q.dx, q.dy, p.pressure);
  }

  void _extendStroke(PointerMoveEvent e) {
    final stroke = _live.value;
    if (stroke == null) return;
    if (_rulerSide != null && _ruler != null) {
      _clearPrediction();
      _live.value = stroke.withPoints([
        ...stroke.points,
        _guided(_inkPoint(e)),
      ]);
      return;
    }
    switch (_snapped) {
      case null:
        _waitForHold(e.localPosition);
      case ShapeKind.line:
        final start = stroke.points.first.offset;
        _live.value = _shapeStroke(stroke, [
          start,
          snapLine(start, _toPage(e.localPosition)),
        ]);
        return;
      default:
        return;
    }
    final point = _inkPoint(e);
    _predict(e, point);
    _live.value = stroke.withPoints([...stroke.points, point]);
  }

  /// Guesses where the pen is heading from its last ~30 ms, and draws the
  /// live stroke up to [_predictAhead] past [at]: never more than a few
  /// points on screen, and gone once the pen stops or lifts.
  void _predict(PointerMoveEvent e, InkPoint at) {
    _predictionTimer?.cancel();
    if (e.kind != PointerDeviceKind.stylus) return;
    _penTrail.add((e.timeStamp, at.offset));
    while (_penTrail.length > 2 &&
        e.timeStamp - _penTrail.first.$1 > const Duration(milliseconds: 30)) {
      _penTrail.removeAt(0);
    }
    final tip = predictPen(
      _penTrail,
      ahead: _predictAhead,
      most: 16 / _scale,
      least: 0.5 / _scale,
    );
    if (tip == null) {
      if (_predicted.value.isNotEmpty) _predicted.value = const [];
      return;
    }
    _predicted.value = [InkPoint(tip.dx, tip.dy, at.pressure)];
    // No news from the pen: it has stopped, so the guess is wrong.
    _predictionTimer = Timer(
      const Duration(milliseconds: 40),
      _clearPrediction,
    );
  }

  void _clearPrediction() {
    _predictionTimer?.cancel();
    _predictionTimer = null;
    if (_predicted.value.isNotEmpty) _predicted.value = const [];
  }

  void _finishStroke() {
    var stroke = _live.value;
    // The shape tool makes what was drawn neat on lifting (a scribble that
    // isn't a shape stays as drawn).
    if (stroke != null &&
        _snapped == null &&
        _rulerSide == null &&
        ref.read(inkToolProvider).kind == InkToolKind.shape) {
      if (recognizeShape([for (final p in stroke.points) p.offset])
          case final shape?) {
        stroke = _filled(_shapeStroke(stroke, shape.outline), shape.kind);
        _snapped = shape.kind;
        _live.value = stroke;
      }
    }
    final kind = _drawKind;
    _drawPointer = null;
    widget.onWriting?.call(false);
    _rulerSide = null;
    _stopWaitingForHold();
    _clearPrediction();
    if (stroke == null) return;
    // A quick finger or mouse tap on a template link follows the link
    // instead of leaving a dot. (A stylus always writes.) Any quick tap on
    // tape peels it back or puts it back.
    final bounds = stroke.bounds;
    final first = stroke.points.first;
    if (bounds.longestSide * _scale < 10 &&
        DateTime.now().millisecondsSinceEpoch - stroke.createdAt < 400 &&
        _toggleTapeAt(Offset(first.x, first.y) * _scale + _offset)) {
      _live.value = null;
      return;
    }
    if (kind != PointerDeviceKind.stylus &&
        kind != PointerDeviceKind.invertedStylus &&
        bounds.longestSide * _scale < 10 &&
        DateTime.now().millisecondsSinceEpoch - stroke.createdAt < 400 &&
        _followLinkAt(Offset(first.x, first.y) * _scale + _offset)) {
      _live.value = null;
      return;
    }
    if (_scribbledOut(stroke) case final ids when ids.isNotEmpty) {
      // Scribbled over writing: it goes, and the scribble with it.
      HapticFeedback.mediumImpact();
      _live.value = null;
      setState(() => _pendingErase.addAll(ids));
      ref.read(inkHistoryProvider(widget.pageId).notifier).erase(ids);
      _showZoom('Scribbled out');
      return;
    }
    // The live stroke stays on screen until the saved copy arrives (see
    // build), so it doesn't flicker.
    ref.read(inkHistoryProvider(widget.pageId).notifier).addStroke(stroke);
    widget.onStroke?.call(stroke.bounds);
  }

  /// The ink a pen [stroke] scribbles out, if it's a scribble over some.
  List<String> _scribbledOut(Stroke stroke) {
    if (stroke.tool != InkTool.pen ||
        _snapped != null ||
        ref.read(inkToolProvider).kind != InkToolKind.pen ||
        !ref.read(scribbleEraseProvider)) {
      return const [];
    }
    return scribbledOut(
      [for (final p in stroke.points) p.offset],
      stroke.width,
      [
        for (final s in _currentStrokes())
          if (s.id != stroke.id) (id: s.id, bounds: s.bounds, hits: s.hitTest),
      ],
    );
  }

  void _cancelDrawing() {
    _drawPointer = null;
    widget.onWriting?.call(false);
    _rulerSide = null;
    _stopWaitingForHold();
    _clearPrediction();
    _live.value = null;
    final undo = {..._erased, ..._cutStrokes, ..._cutPieces};
    if (_erasedTapes.isNotEmpty) setState(_erasedTapes.clear);
    if (undo.isEmpty) return;
    setState(() {
      _pendingErase.removeAll(undo);
      _cutPieces.forEach(_pendingAdd.remove);
      _cutPieces.clear();
      _cutStrokes.clear();
      _erased.clear();
    });
  }

  // Erasing

  void _eraseAt(Offset screen) {
    final tool = ref.read(inkToolProvider);
    final point = _toPage(screen);
    final radius = tool.kind == InkToolKind.eraser
        ? tool.size / _scale
        : InkToolState.eraserSizes[1] / _scale;
    bool erasable(Stroke s) =>
        !tool.eraseHighlighterOnly || s.tool == InkTool.highlighter;
    if (!tool.eraseHighlighterOnly) {
      final tapes = [
        for (final t in _shownElements())
          if (t.content is TapeContent && t.frame.contains(point, slop: radius))
            t.id,
      ];
      if (tapes.isNotEmpty) setState(() => _erasedTapes.addAll(tapes));
    }
    if (tool.eraserMode == EraserMode.partial) {
      return _cutAt(point, radius, erasable);
    }
    final hits = [
      for (final s in _currentStrokes())
        if (erasable(s) && s.hitTest(point, radius)) s.id,
    ];
    if (hits.isNotEmpty) {
      setState(() {
        _pendingErase.addAll(hits);
        _erased.addAll(hits);
      });
    }
  }

  /// Partial erasing: cuts the ink under the eraser out of every stroke it
  /// touches, showing the pieces at once.
  void _cutAt(Offset point, double radius, bool Function(Stroke) erasable) {
    final repo = ref.read(strokeRepositoryProvider);
    var changed = false;
    for (final s in _currentStrokes()) {
      if (!erasable(s)) continue;
      final pieces = eraseFromStroke(s, point, radius, repo.newStrokeId);
      if (pieces == null) continue;
      changed = true;
      _pendingErase.add(s.id);
      if (_cutPieces.remove(s.id)) {
        _pendingAdd.remove(s.id);
      } else {
        _cutStrokes.add(s.id);
      }
      for (final piece in pieces) {
        _pendingAdd[piece.id] = piece;
        _cutPieces.add(piece.id);
      }
    }
    if (changed) setState(() {});
  }

  void _finishErasing() {
    _drawPointer = null;
    widget.onWriting?.call(false);
    if (_erasedTapes.isNotEmpty) {
      // Tape and ink erased together, undone together.
      final tapes = _erasedTapes.toList();
      final pieces = [for (final id in _cutPieces) ?_pendingAdd[id]];
      ref
          .read(inkHistoryProvider(widget.pageId).notifier)
          .lassoEdit(
            removeStrokes: [..._cutStrokes, ..._erased],
            addStrokes: pieces,
            removeElements: tapes,
          )
          .then((_) {
            if (mounted) setState(() => _erasedTapes.removeAll(tapes));
          });
      _cutStrokes.clear();
      _cutPieces.clear();
      _erased.clear();
    } else if (_cutStrokes.isNotEmpty) {
      final pieces = [for (final id in _cutPieces) ?_pendingAdd[id]];
      ref
          .read(inkHistoryProvider(widget.pageId).notifier)
          .lassoEdit(removeStrokes: _cutStrokes.toList(), addStrokes: pieces);
      _cutStrokes.clear();
      _cutPieces.clear();
    } else if (_erased.isNotEmpty) {
      // They stay hidden until the saved copies arrive as deleted (see
      // build).
      ref
          .read(inkHistoryProvider(widget.pageId).notifier)
          .erase(_erased.toList());
      _erased.clear();
    }
    if (_drawKind != PointerDeviceKind.invertedStylus) {
      ref.read(inkToolProvider.notifier).erased();
    }
  }

  // Ruler

  /// Fingers (or the mouse) on the ruler move it; two turn it. Returns
  /// whether the pointer was used.
  bool _rulerWith(PointerDownEvent e) {
    final ruler = _ruler;
    if (ruler == null ||
        widget.readOnly ||
        _isStylus(e.kind) ||
        _drawPointer != null) {
      return false;
    }
    final onRuler = ruler.contains(_toPage(e.localPosition));
    // A second finger anywhere turns a ruler that's being held.
    if (!onRuler && _rulerPointers.isEmpty) return false;
    if (_rulerPointers.length >= 2) return true;
    _stopCoasting();
    _rulerPointers[e.pointer] = e.localPosition;
    _rulerTurn = ruler.angle;
    return true;
  }

  void _moveRuler(PointerMoveEvent e) {
    final ruler = _ruler;
    if (ruler == null) return;
    final before = Map.of(_rulerPointers);
    _rulerPointers[e.pointer] = e.localPosition;
    setState(() {
      if (_rulerPointers.length == 1) {
        _ruler = ruler.copyWith(
          center:
              ruler.center + (e.localPosition - before[e.pointer]!) / _scale,
        );
        return;
      }
      final ids = _rulerPointers.keys.take(2).toList();
      final a0 = before[ids[0]]!, b0 = before[ids[1]]!;
      final a1 = _rulerPointers[ids[0]]!, b1 = _rulerPointers[ids[1]]!;
      final turn =
          math.atan2(b1.dy - a1.dy, b1.dx - a1.dx) -
          math.atan2(b0.dy - a0.dy, b0.dx - a0.dx);
      _rulerTurn += turn;
      _ruler = ruler.copyWith(
        center: ruler.center + ((a1 + b1) / 2 - (a0 + b0) / 2) / _scale,
        angle: snapRulerAngle(_rulerTurn),
      );
    });
  }

  // Laser pointer

  /// How long the laser's trail lasts.
  static const _laserLife = Duration(milliseconds: 900);

  void _addLaserPoint(Offset screen) {
    _laser.value = [..._laser.value, (_toPage(screen), _laserClock.elapsed)];
    if (!_laserFade.isActive) _laserFade.start();
  }

  /// Drops points older than [_laserLife] and repaints so the tail keeps
  /// fading; stops once the trail is gone.
  void _fadeLaser() {
    final now = _laserClock.elapsed;
    _laser.value = [
      for (final p in _laser.value)
        if (now - p.$2 < _laserLife) p,
    ];
    if (_laser.value.isEmpty && _laserPointer == null) _laserFade.stop();
  }

  // Lasso

  /// With the lasso tool: a pointer on the selection or its handles moves,
  /// resizes or rotates it; elsewhere it lets go and, if it can draw,
  /// starts a new loop. Returns whether the pointer was used.
  bool _lassoWith(PointerDownEvent e) {
    if (widget.readOnly ||
        !widget.inkEnabled ||
        ref.read(inkToolProvider).kind != InkToolKind.lasso ||
        e.kind == PointerDeviceKind.invertedStylus ||
        _lassoPointer != null ||
        _lassoDrag != null ||
        _drawPointer != null ||
        (e.kind == PointerDeviceKind.mouse &&
            e.buttons != kPrimaryMouseButton)) {
      return false;
    }
    final point = _toPage(e.localPosition);
    final lasso = _lasso;
    if (lasso != null && _navPointers.isEmpty) {
      final t = lasso.transform;
      final unit = 1 / _scale;
      final reach = LassoSelectionPainter.handleRadius * 1.4 * unit;
      final mode = (t.apply(lasso.box.bottomRight) - point).distance <= reach
          ? _DragMode.resize
          : (LassoSelectionPainter.rotateHandle(lasso.box, t, unit) - point)
                    .distance <=
                reach
          ? _DragMode.rotate
          : lasso.box.inflate(8 * unit / t.scale).contains(t.invert(point))
          ? _DragMode.move
          : null;
      if (mode != null) {
        setState(() => _lassoDrag = _LassoDrag(e.pointer, mode, t, point));
        return true;
      }
      setState(() => _lasso = null);
    }
    if (!_canDraw(e)) return false;
    _lassoPointer = e.pointer;
    _lassoPoints.value = [point];
    return true;
  }

  /// The loop is closed: take the strokes and items inside it.
  void _finishLasso() {
    final polygon = _lassoPoints.value;
    _lassoPointer = null;
    _lassoPoints.value = const [];
    if (polygon.length < 3) return;
    final strokes = [
      for (final s in _currentStrokes())
        if (lassoTakesStroke(polygon, s)) s,
    ];
    final elements = [
      for (final e in _restingElements())
        if (lassoTakesElement(polygon, e)) e,
    ];
    if (strokes.isEmpty && elements.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() => _lasso = _LassoSelection.of(strokes, elements));
  }

  /// The page's strokes as shown: saved, plus those waiting to be saved,
  /// without erased ones.
  List<Stroke> _currentStrokes() {
    final saved = ref.read(strokesProvider(widget.pageId)).value ?? [];
    final ids = {for (final s in saved) s.id};
    return [
      for (final s in [
        ...saved,
        for (final s in _pendingAdd.values)
          if (!ids.contains(s.id)) s,
      ])
        if (!s.deleted && !_pendingErase.contains(s.id)) s,
    ];
  }

  List<Stroke> _heldStrokes() {
    final ids = _lasso?.strokeIds.toSet() ?? const {};
    return [
      for (final s in _currentStrokes())
        if (ids.contains(s.id)) s,
    ];
  }

  List<PageElement> _heldElements() {
    final ids = _lasso?.elementIds.toSet() ?? const {};
    return [
      for (final e in _restingElements())
        if (ids.contains(e.id)) e,
    ];
  }

  void _lassoDragTo(Offset point) {
    final drag = _lassoDrag!;
    final start = drag.start;
    final middle = start.pivot + start.translate;
    _lasso = _lasso!.withTransform(switch (drag.mode) {
      _DragMode.move => start.copyWith(
        translate: start.translate + (point - drag.startPoint),
      ),
      _DragMode.resize => () {
        final from = (drag.startPoint - middle).distance;
        final factor = from < 1 ? 1.0 : (point - middle).distance / from;
        return start.copyWith(scale: (start.scale * factor).clamp(0.1, 10.0));
      }(),
      _DragMode.rotate => start.copyWith(
        rotation: _snapAngle(
          math.atan2(point.dy - middle.dy, point.dx - middle.dx) + math.pi / 2,
        ),
      ),
    });
  }

  /// Saves a move, resize or rotation: the strokes are replaced by moved
  /// copies, and items get their new frames.
  void _finishLassoDrag() {
    final t = _lasso!.transform;
    setState(() => _lassoDrag = null);
    if (t.isIdentity) return;
    final repo = ref.read(strokeRepositoryProvider);
    final strokes = _heldStrokes();
    final moved = [
      for (final s in strokes) t.applyToStroke(s, repo.newStrokeId()),
    ];
    final elements = _heldElements();
    final frames = [
      for (final e in elements) (e.id, e.frame, t.applyToFrame(e.frame)),
    ];
    _replaceHeld(strokes, moved, frames: frames);
  }

  /// Shows [added] in place of [removed] at once, keeps them selected, and
  /// saves the change as one undo step.
  void _replaceHeld(
    List<Stroke> removed,
    List<Stroke> added, {
    List<(String, ElementFrame, ElementFrame)> frames = const [],
    List<PageElement> addElements = const [],
  }) {
    final lasso = _lasso;
    setState(() {
      _pendingErase.addAll(removed.map((s) => s.id));
      for (final s in added) {
        _pendingAdd[s.id] = s;
      }
      for (final (id, _, after) in frames) {
        _frameOverrides[id] = after;
      }
      // Moved or recolored: the same items. Pasted: only the new ones.
      final kept = addElements.isEmpty ? lasso?.elementIds ?? const [] : [];
      final elements = [
        for (final e in _restingElements())
          if (kept.contains(e.id)) e,
        ...addElements,
      ];
      _lasso = _LassoSelection.of(added, elements);
      if (added.isEmpty && elements.isEmpty) _lasso = null;
    });
    ref
        .read(inkHistoryProvider(widget.pageId).notifier)
        .lassoEdit(
          removeStrokes: [for (final s in removed) s.id],
          addStrokes: added,
          frames: frames,
          addElements: addElements,
        );
  }

  void _lassoAction(LassoAction action) {
    final lasso = _lasso;
    if (lasso == null || widget.readOnly) return;
    final strokes = _heldStrokes();
    final elements = _heldElements();
    final history = ref.read(inkHistoryProvider(widget.pageId).notifier);
    switch (action) {
      case LassoAction.copy || LassoAction.cut:
        ref
            .read(inkClipboardProvider.notifier)
            .copy(InkClip(strokes: strokes, elements: elements));
        if (action == LassoAction.copy) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            const SnackBar(
              content: Text('Copied. Paste it on any page.'),
              duration: Duration(seconds: 2),
            ),
          );
          return;
        }
        continue delete;
      delete:
      case LassoAction.delete:
        setState(() {
          _pendingErase.addAll(strokes.map((s) => s.id));
          _lasso = null;
        });
        history.lassoEdit(
          removeStrokes: [for (final s in strokes) s.id],
          removeElements: [for (final e in elements) e.id],
        );
      case LassoAction.duplicate:
        _place(
          InkClip(strokes: strokes, elements: elements),
          by: const Offset(40, 40),
        );
      case LassoAction.link:
        _linkSelection(selectionBounds(strokes, elements));
      case LassoAction.color:
        break;
    }
  }

  /// Asks for a page of this notebook and makes [box] a link to it.
  Future<void> _linkSelection(Rect box) async {
    final page = ref.read(pageProvider(widget.pageId)).value;
    if (page == null) return;
    final to = await showPageJumper(
      context,
      notebookId: page.notebookId,
      currentPageId: widget.pageId,
      title: 'Link to page',
      choosing: true,
    );
    if (to is! JumpToPage || !mounted) return;
    final area = box.inflate(12);
    final top = (ref.read(elementsProvider(widget.pageId)).value ?? [])
        .fold<double>(0.0, (z, e) => math.max(z, e.z));
    final link = PageElement(
      id: ref.read(elementRepositoryProvider).newElementId(),
      content: LinkContent(to.pageId),
      frame: ElementFrame(
        center: area.center,
        width: area.width,
        height: area.height,
      ),
      z: top + 1,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    setState(() => _lasso = null);
    await ref
        .read(inkHistoryProvider(widget.pageId).notifier)
        .lassoEdit(addElements: [link]);
  }

  /// Recolors the held handwriting. Highlighter keeps its see-through ink.
  void _recolor(Color color) {
    final repo = ref.read(strokeRepositoryProvider);
    final strokes = _heldStrokes();
    if (strokes.isEmpty) return;
    const identity = LassoTransform(pivot: Offset.zero);
    final recolored = [
      for (final s in strokes)
        identity.applyToStroke(
          s,
          repo.newStrokeId(),
          color:
              (s.tool == InkTool.highlighter
                      ? color.withValues(alpha: 0.35)
                      : color)
                  .toARGB32(),
        ),
    ];
    _replaceHeld(strokes, recolored);
  }

  /// Pastes the clipboard in the middle of the view, selected.
  void _paste() {
    final clip = ref.read(inkClipboardProvider);
    final viewport = _viewport;
    if (clip == null || viewport == null || widget.readOnly) return;
    if (!widget.inkEnabled && clip.strokes.isNotEmpty) return;
    final middle = _toPage(viewport.center(Offset.zero));
    _place(clip, by: middle - clip.bounds.center);
    if (ref.read(inkToolProvider).kind != InkToolKind.lasso) {
      ref.read(inkToolProvider.notifier).selectTool(InkToolKind.lasso);
    }
  }

  /// Adds copies of [clip] moved [by], on top of everything, and selects
  /// them.
  void _place(InkClip clip, {required Offset by}) {
    final strokeRepo = ref.read(strokeRepositoryProvider);
    final elementRepo = ref.read(elementRepositoryProvider);
    final t = LassoTransform(pivot: Offset.zero, translate: by);
    final now = DateTime.now().millisecondsSinceEpoch;
    final ordered = [...clip.strokes]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final strokes = [
      for (final (i, s) in ordered.indexed)
        t.applyToStroke(s, strokeRepo.newStrokeId(), createdAt: now + i),
    ];
    final top = (ref.read(elementsProvider(widget.pageId)).value ?? [])
        .fold<double>(0.0, (z, e) => math.max(z, e.z));
    final elements = [
      for (final (i, e) in clip.elements.indexed)
        PageElement(
          id: elementRepo.newElementId(),
          content: e.content,
          frame: t.applyToFrame(e.frame),
          z: top + 1 + i,
          createdAt: now + i,
        ),
    ];
    _poppingIn.addAll(elements.map((e) => e.id));
    _replaceHeld(const [], strokes, addElements: elements);
  }

  /// The bar over the selection, kept on screen.
  Widget _lassoBar(_LassoSelection lasso, bool hasInk, Size viewport) {
    final corners = [
      lasso.box.topLeft,
      lasso.box.topRight,
      lasso.box.bottomRight,
      lasso.box.bottomLeft,
    ].map((c) => lasso.transform.apply(c) * _scale + _offset).toList();
    final top = corners.map((c) => c.dy).reduce(math.min);
    final bottom = corners.map((c) => c.dy).reduce(math.max);
    final middle = corners.map((c) => c.dx).reduce((a, b) => a + b) / 4;
    const barHeight = 44.0, gap = 64.0;
    final y = top - gap - barHeight >= 8
        ? top - gap - barHeight
        : math.min(bottom + 28, viewport.height - barHeight - 8);
    const width = 300.0;
    final x = (middle - width / 2)
        .clamp(8.0, math.max(8.0, viewport.width - width - 8))
        .toDouble();
    return Positioned(
      left: x,
      top: y,
      width: width,
      height: barHeight,
      child: Center(
        child: LassoActionBar(
          colors: NotelySkin.of(context).inkColors,
          canRecolor: hasInk,
          onAction: _lassoAction,
          onColor: _recolor,
        ),
      ),
    );
  }

  // Stickers

  /// The page's stickers as shown: not removed, with frames being moved.
  List<PageElement> _shownElements() {
    final lasso = _lasso;
    return [
      for (final e in ref.read(elementsProvider(widget.pageId)).value ?? [])
        if (!e.deleted && !_erasedTapes.contains(e.id))
          () {
            final frame = _drag?.elementId == e.id
                ? _drag!.frame
                : _frameOverrides[e.id] ?? e.frame;
            final moving =
                lasso != null &&
                !lasso.transform.isIdentity &&
                lasso.elementIds.contains(e.id);
            return e.copyWith(
              frame: moving ? lasso.transform.applyToFrame(frame) : frame,
            );
          }(),
    ];
  }

  /// Elements as saved, with frames being shown until they're saved, but
  /// not the lasso's live transform.
  List<PageElement> _restingElements() => [
    for (final e in ref.read(elementsProvider(widget.pageId)).value ?? [])
      if (!e.deleted) e.copyWith(frame: _frameOverrides[e.id] ?? e.frame),
  ];

  /// Whether pointers select and move items rather than draw.
  bool _selecting(InkToolKind tool) =>
      !widget.inkEnabled || tool == InkToolKind.select;

  /// Removes the selected item (the Delete key).
  void _deleteSelected() {
    if (_lasso != null) return _lassoAction(LassoAction.delete);
    final id = _selectedId;
    if (id == null || widget.readOnly) return;
    ref.read(inkHistoryProvider(widget.pageId).notifier).removeElement(id);
    setState(() => _selectedId = null);
  }

  /// With the select tool, a pointer on a sticker or one of its handles
  /// selects, moves, resizes, rotates or removes it. Returns whether the
  /// pointer was used.
  bool _selectWith(PointerDownEvent e) {
    if (widget.readOnly ||
        !_selecting(ref.read(inkToolProvider).kind) ||
        _drag != null ||
        _drawPointer != null ||
        _navPointers.isNotEmpty ||
        (e.kind == PointerDeviceKind.mouse &&
            e.buttons != kPrimaryMouseButton)) {
      return false;
    }
    final point = _toPage(e.localPosition);
    final elements = _shownElements();
    final handle = _handleSize / _scale;

    final selected = elements.where((el) => el.id == _selectedId).firstOrNull;
    if (selected != null) {
      final f = selected.frame;
      bool near(Offset local) => (f.toPage(local) - point).distance <= handle;
      if (near(_deleteHandle(f))) {
        ref
            .read(inkHistoryProvider(widget.pageId).notifier)
            .removeElement(selected.id);
        setState(() => _selectedId = null);
        return true;
      }
      final mode = near(_resizeHandle(f))
          ? _DragMode.resize
          : near(_rotateHandle(f, _scale))
          ? _DragMode.rotate
          : null;
      if (mode != null) {
        setState(() => _drag = _ElementDrag(e.pointer, selected, mode, point));
        return true;
      }
    }

    // The topmost sticker under the pointer.
    for (final el in elements.reversed) {
      if (el.frame.contains(point, slop: 4 / _scale)) {
        final wasSelected = el.id == _selectedId;
        setState(() {
          _selectedId = el.id;
          _drag = _ElementDrag(
            e.pointer,
            el,
            _DragMode.move,
            point,
            wasSelected: wasSelected,
          );
        });
        return true;
      }
    }
    if (_selectedId != null) setState(() => _selectedId = null);
    // A stylus that misses does nothing; fingers and the mouse scroll.
    return e.kind == PointerDeviceKind.stylus;
  }

  static Offset _deleteHandle(ElementFrame f) =>
      Offset(-f.width / 2, -f.height / 2);
  static Offset _resizeHandle(ElementFrame f) =>
      Offset(f.width / 2, f.height / 2);
  static Offset _rotateHandle(ElementFrame f, double scale) =>
      Offset(0, -f.height / 2 - 40 / scale);

  void _dragTo(Offset point) {
    final drag = _drag!;
    final start = drag.start;
    drag.frame = switch (drag.mode) {
      _DragMode.move => start.copyWith(
        center: start.center + (point - drag.startPoint),
      ),
      _DragMode.resize => () {
        final from = (drag.startPoint - start.center).distance;
        final factor = from < 1 ? 1.0 : (point - start.center).distance / from;
        final width = math.max(start.width * factor, _minElementSize);
        return start.copyWith(
          width: width,
          height: width * start.height / start.width,
        );
      }(),
      _DragMode.rotate => start.copyWith(
        rotation: _snapAngle(
          math.atan2(point.dy - start.center.dy, point.dx - start.center.dx) +
              math.pi / 2,
        ),
      ),
    };
  }

  static const _minElementSize = 40.0;

  /// Snaps to straight (0, 90, 180, 270 degrees) when within 4 degrees.
  static double _snapAngle(double angle) {
    const quarter = math.pi / 2;
    final nearest = (angle / quarter).roundToDouble() * quarter;
    final snapped = (angle - nearest).abs() < 4 * math.pi / 180
        ? nearest
        : angle;
    // Keep it in (-pi, pi].
    return math.atan2(math.sin(snapped), math.cos(snapped));
  }

  void _finishDrag() {
    final drag = _drag!;
    // A tap (no move) on a text box that was already selected edits it.
    if (drag.wasSelected &&
        drag.mode == _DragMode.move &&
        drag.frame == drag.start) {
      setState(() => _drag = null);
      final element = _shownElements()
          .where((e) => e.id == drag.elementId)
          .firstOrNull;
      if (element != null && element.content is TextContent) {
        _editText(element);
      }
      return;
    }
    setState(() {
      _drag = null;
      if (drag.frame != drag.start) {
        _frameOverrides[drag.elementId] = drag.frame;
      }
    });
    ref
        .read(inkHistoryProvider(widget.pageId).notifier)
        .setElementFrame(drag.elementId, drag.start, drag.frame);
  }

  /// Edits a text box's text; emptying it removes the box.
  Future<void> _editText(PageElement element) async {
    final before = element.content as TextContent;
    final after = await showTextBoxEditor(context, initial: before);
    if (after == null || !mounted || after == before) return;
    final history = ref.read(inkHistoryProvider(widget.pageId).notifier);
    if (after.text.trim().isEmpty) {
      await history.removeElement(element.id);
      if (mounted) setState(() => _selectedId = null);
      return;
    }
    await history.editElement(
      element,
      element.copyWith(
        content: after,
        frame: reframeText(element.frame, before, after),
      ),
    );
  }

  /// Places the waiting sticker, photo or text box in the middle of the
  /// view.
  void _placeRequested() {
    final request = ref
        .read(placementRequestProvider(widget.pageId).notifier)
        .take();
    final viewport = _viewport;
    if (request == null || viewport == null) return;
    final middle = _toPage(viewport.center(Offset.zero));
    // Fits on the page, keeping its shape.
    final fit = math.min(
      1.0,
      math.min(
        _pageSize.width * 0.9 / request.width,
        _pageSize.height * 0.9 / request.height,
      ),
    );
    final width = request.width * fit, height = request.height * fit;
    final center = Offset(
      middle.dx.clamp(
        width / 2,
        math.max(width / 2, _pageSize.width - width / 2),
      ),
      middle.dy.clamp(
        height / 2,
        math.max(height / 2, _pageSize.height - height / 2),
      ),
    );
    final existing = ref.read(elementsProvider(widget.pageId)).value ?? [];
    final element = PageElement(
      id: ref.read(elementRepositoryProvider).newElementId(),
      content: request.content,
      frame: ElementFrame(center: center, width: width, height: height),
      z: existing.fold(0.0, (z, e) => math.max(z, e.z)) + 1,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    ref.read(inkHistoryProvider(widget.pageId).notifier).addElement(element);
    setState(() {
      _selectedId = element.id;
      _poppingIn.add(element.id);
    });
  }

  /// Drops frame stand-ins once the saved frames match them.
  void _reconcileElements(List<PageElement> saved) {
    final caughtUp = [
      for (final MapEntry(key: id, value: frame) in _frameOverrides.entries)
        if (saved.where((e) => e.id == id).firstOrNull?.frame == frame) id,
    ];
    if (caughtUp.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => caughtUp.forEach(_frameOverrides.remove));
    });
  }

  /// Drops local stand-ins once the saved data has caught up: the live
  /// stroke once it's saved, and pending erasures once they're deleted.
  void _reconcile(List<Stroke> strokes) {
    final liveId = _drawPointer == null ? _live.value?.id : null;
    final saved = {for (final s in strokes) s.id: s};
    final liveSaved = liveId != null && saved.containsKey(liveId);
    final erased = _pendingErase.where(
      (id) =>
          _drawPointer == null &&
          (saved[id]?.deleted ?? !_pendingAdd.containsKey(id)),
    );
    final added = [
      for (final id in _pendingAdd.keys)
        if (saved.containsKey(id)) id,
    ];
    // Undo took away everything the lasso held: let go of it.
    final lasso = _lasso;
    final lassoGone =
        lasso != null &&
        _lassoDrag == null &&
        lasso.elementIds.isEmpty &&
        lasso.strokeIds.isNotEmpty &&
        lasso.strokeIds.every(
          (id) => !_pendingAdd.containsKey(id) && (saved[id]?.deleted ?? true),
        );
    if (!liveSaved && erased.isEmpty && added.isEmpty && !lassoGone) return;
    final erasedIds = erased.toList();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (added.isNotEmpty || lassoGone) {
        setState(() {
          added.forEach(_pendingAdd.remove);
          if (lassoGone && identical(_lasso, lasso)) _lasso = null;
        });
      }
      if (liveSaved && _live.value?.id == liveId) {
        // Rebuild too: build hides the saved copy while the live one shows.
        setState(() => _live.value = null);
      }
      if (erasedIds.isNotEmpty) {
        setState(() => _pendingErase.removeAll(erasedIds));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final skin = NotelySkin.of(context);
    final paper = ref.watch(pagePaperProvider(widget.pageId)) ?? skin.paper;
    final size = ref.watch(pageDimensionsProvider(widget.pageId));
    if (size != _pageSize) {
      _pageSize = size;
      // Refit once the notebook (and so the page size) has loaded.
      _viewport = null;
    }
    final strokes = ref.watch(strokesProvider(widget.pageId)).value ?? [];
    _reconcile(strokes);
    final liveId = _live.value?.id;
    final lasso = _lasso;
    final held = lasso?.strokeIds.toSet() ?? const <String>{};
    final savedIds = {for (final s in strokes) s.id};
    final shown = [
      ...strokes,
      for (final s in _pendingAdd.values)
        if (!savedIds.contains(s.id)) s,
    ];
    final visible = [
      for (final s in shown)
        if (!s.deleted &&
            !_pendingErase.contains(s.id) &&
            s.id != liveId &&
            !held.contains(s.id))
          s,
    ];
    final heldStrokes = [
      for (final s in shown)
        if (held.contains(s.id) && !s.deleted) s,
    ];
    ref.listen(inkToolProvider, (_, next) {
      if (next.kind != InkToolKind.lasso && _lasso != null) {
        setState(() => _lasso = null);
      }
    });
    ref.listen(pasteRequestProvider(widget.pageId), (_, _) => _paste());
    ref.watch(zoomWindowProvider);
    final zoomBox = _showsZoomBox
        ? ref.watch(zoomBoxProvider(widget.pageId)).rect
        : null;
    if (_showsZoomBox) {
      // Keep the box in view as the writing moves it on.
      ref.listen(zoomBoxProvider(widget.pageId), (_, next) {
        if (_boxPointer == null) _reveal(next.rect);
      });
    }
    final rulerOut = ref.watch(rulerVisibleProvider) && widget.inkEnabled;
    if (!rulerOut) {
      _ruler = null;
      _rulerPointers.clear();
    }
    // Keep the history notifier alive while the page is open.
    ref.watch(inkHistoryProvider(widget.pageId));

    final template = ref.watch(pageProvider(widget.pageId)).value?.template;
    final templateImage = template == null
        ? null
        : ref
              .watch(
                templateImageProvider((
                  template: template,
                  width: _templateWidth,
                )),
              )
              .value;
    if (template != null) {
      // Load links and the notebook's pages now, so taps answer at once.
      ref.watch(templateLinksProvider(template));
      final notebookId = ref
          .watch(pageProvider(widget.pageId))
          .value!
          .notebookId;
      ref.watch(notebookTemplatePagesProvider(notebookId));
    }

    final saved = ref.watch(elementsProvider(widget.pageId)).value ?? [];
    _reconcileElements(saved);
    final elements = [..._shownElements(), ?_tapeDraft];
    final tool = ref.watch(inkToolProvider).kind;
    final selectedId = _selecting(tool)
        ? _selectedId
        : _drag?.elementId; // a finger holding a sticker in pen mode
    final selected = widget.readOnly
        ? null
        : elements.where((e) => e.id == selectedId).firstOrNull;
    ref.listen(placementRequestProvider(widget.pageId), (_, next) {
      if (next != null) _placeRequested();
    });

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = constraints.biggest;
        if (widget.window case final window?) {
          // The window's part of the page, edge to edge.
          _scale = viewport.width / window.width;
          _offset = -window.topLeft * _scale;
        } else if (_viewport == null ||
            (widget.embedded && _viewport != viewport)) {
          _fitWidth(viewport);
        }
        _viewport = viewport;
        if (rulerOut) {
          _ruler ??= Ruler(center: _toPage(viewport.center(Offset.zero)));
        }

        final history = ref.read(inkHistoryProvider(widget.pageId).notifier);
        return CallbackShortcuts(
          bindings: {
            for (final meta in [false, true]) ...{
              SingleActivator(
                LogicalKeyboardKey.keyC,
                meta: meta,
                control: !meta,
              ): () =>
                  _lassoAction(LassoAction.copy),
              SingleActivator(
                LogicalKeyboardKey.keyX,
                meta: meta,
                control: !meta,
              ): () =>
                  _lassoAction(LassoAction.cut),
              SingleActivator(
                LogicalKeyboardKey.keyD,
                meta: meta,
                control: !meta,
              ): () =>
                  _lassoAction(LassoAction.duplicate),
              SingleActivator(
                LogicalKeyboardKey.keyV,
                meta: meta,
                control: !meta,
              ): _paste,
            },
            const SingleActivator(LogicalKeyboardKey.delete): _deleteSelected,
            const SingleActivator(LogicalKeyboardKey.backspace):
                _deleteSelected,
            const SingleActivator(LogicalKeyboardKey.keyZ, control: true):
                history.undo,
            const SingleActivator(LogicalKeyboardKey.keyZ, meta: true):
                history.undo,
            const SingleActivator(
              LogicalKeyboardKey.keyZ,
              control: true,
              shift: true,
            ): history.redo,
            const SingleActivator(
              LogicalKeyboardKey.keyZ,
              meta: true,
              shift: true,
            ): history.redo,
          },
          child: Focus(
            autofocus: true,
            child: ClipRect(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerHover: _onPointerHover,
                      onPointerDown: _onPointerDown,
                      onPointerMove: _onPointerMove,
                      onPointerUp: _onPointerUp,
                      onPointerCancel: _onPointerCancel,
                      onPointerSignal: _onPointerSignal,
                      child: Stack(
                        children: [
                          Positioned(
                            left: _offset.dx,
                            top: _offset.dy,
                            child: Transform.scale(
                              scale: _scale,
                              alignment: Alignment.topLeft,
                              child: _PageSurface(
                                size: _pageSize,
                                paper: paper,
                                hasTemplate: template != null,
                                templateImage: templateImage,
                                templateRect: templateImage == null
                                    ? null
                                    : _templateRect(templateImage),
                                elements: elements,
                                poppingIn: _poppingIn,
                                selected: selected?.frame,
                                handleScale: _handleSize / _scale,
                                strokes: visible,
                                live: _live,
                                predicted: _predicted,
                                overlays: [
                                  if (zoomBox != null)
                                    IgnorePointer(
                                      child: CustomPaint(
                                        painter: _ZoomBoxPainter(
                                          zoomBox,
                                          Theme.of(context).colorScheme.primary,
                                          1 / _scale,
                                        ),
                                      ),
                                    ),
                                  if (lasso != null)
                                    IgnorePointer(
                                      child: CustomPaint(
                                        painter: LassoSelectionPainter(
                                          paths: [
                                            for (final s in heldStrokes)
                                              (
                                                StrokeRenderer.pathFor(s),
                                                StrokeRenderer.paintFor(s),
                                              ),
                                          ],
                                          box: lasso.box,
                                          transform: lasso.transform,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                          unit: 1 / _scale,
                                        ),
                                      ),
                                    ),
                                  if (_ruler case final ruler?)
                                    IgnorePointer(
                                      child: CustomPaint(
                                        painter: RulerPainter(
                                          ruler,
                                          Theme.of(context).colorScheme.primary,
                                        ),
                                      ),
                                    ),
                                  IgnorePointer(
                                    child: CustomPaint(
                                      painter: _LaserPainter(
                                        _laser,
                                        _laserClock,
                                        _laserLife,
                                        1 / _scale,
                                      ),
                                    ),
                                  ),
                                  IgnorePointer(
                                    child: CustomPaint(
                                      painter: LassoPathPainter(
                                        _lassoPoints,
                                        Theme.of(context).colorScheme.primary,
                                        1 / _scale,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (widget.inkEnabled && !widget.readOnly)
                            Positioned.fill(
                              child: MouseRegion(
                                opaque: false,
                                hitTestBehavior: HitTestBehavior.translucent,
                                onExit: (_) => _hover.value = null,
                                child: IgnorePointer(
                                  child: CustomPaint(
                                    painter: _HoverPainter(
                                      _hover,
                                      tool: ref.read(inkToolProvider),
                                      ink: ref
                                          .read(inkToolProvider)
                                          .colorFrom(skin.inkColors),
                                      scale: _scale,
                                      outline: Theme.of(context)
                                          .colorScheme
                                          .onSurface,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          Positioned(
                            top: 12,
                            left: 0,
                            right: 0,
                            child: IgnorePointer(
                              child: ValueListenableBuilder<String?>(
                                valueListenable: _zoomBadge,
                                builder: (context, text, _) => AnimatedOpacity(
                                  opacity: text == null ? 0 : 1,
                                  duration: Motion.of(context)
                                      .duration(MotionTokens.fade),
                                  child: Center(child: _ZoomBadge(text ?? '')),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Outside the Listener, so tapping it doesn't count as
                  // tapping the page.
                  if (lasso != null && _lassoDrag == null)
                    _lassoBar(lasso, heldStrokes.isNotEmpty, viewport),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PageSurface extends StatelessWidget {
  const _PageSurface({
    required this.size,
    required this.paper,
    required this.hasTemplate,
    required this.templateImage,
    required this.templateRect,
    required this.elements,
    required this.poppingIn,
    required this.selected,
    required this.handleScale,
    required this.strokes,
    required this.live,
    required this.predicted,
    this.overlays = const [],
  });

  final Size size;
  final PaperStyle paper;

  /// The page shows a template page instead of paper.
  final bool hasTemplate;

  /// The template page's image (null while it loads) and where it goes.
  final ui.Image? templateImage;
  final Rect? templateRect;
  final List<PageElement> elements;

  /// Ids of [elements] that pop in when they first appear.
  final Set<String> poppingIn;

  /// The selected sticker's frame, to draw its outline and handles.
  final ElementFrame? selected;

  /// Handle size in page units.
  final double handleScale;
  final List<Stroke> strokes;
  final ValueNotifier<Stroke?> live;
  final ValueNotifier<List<InkPoint>> predicted;

  /// Drawn over everything else (the lasso).
  final List<Widget> overlays;

  @override
  Widget build(BuildContext context) {
    Widget placed(PageElement e) => Positioned(
      left: e.frame.center.dx - e.frame.width / 2,
      top: e.frame.center.dy - e.frame.height / 2,
      width: e.frame.width,
      height: e.frame.height,
      child: Transform.rotate(
        angle: e.frame.rotation,
        child: poppingIn.contains(e.id)
            ? PopIn(key: ValueKey(e.id), child: _ElementView(e))
            : _ElementView(e),
      ),
    );
    return Container(
      width: size.width,
      height: size.height,
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (!hasTemplate)
            RepaintBoundary(
              child: CustomPaint(
                painter: PaperPainter(paper, scale: _paperScale),
              ),
            )
          else ...[
            const ColoredBox(color: Colors.white),
            if ((templateImage, templateRect) case (final image?, final rect?))
              Positioned.fromRect(
                rect: rect,
                child: RawImage(image: image, fit: BoxFit.fill),
              )
            else
              const Center(child: CircularProgressIndicator()),
          ],
          for (final e in elements)
            if (e.content is! TapeContent) placed(e),
          RepaintBoundary(child: CustomPaint(painter: StrokesPainter(strokes))),
          // Its own layer: the pen repaints only the ink it's drawing.
          RepaintBoundary(
            child: CustomPaint(painter: LiveStrokePainter(live, predicted)),
          ),
          // Tape goes over the ink: it's there to hide it.
          for (final e in elements)
            if (e.content is TapeContent) placed(e),
          if (selected case final frame?)
            IgnorePointer(
              child: CustomPaint(
                painter: _SelectionPainter(
                  frame,
                  handleScale,
                  Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ...overlays,
        ],
      ),
    );
  }
}

enum _DragMode { move, resize, rotate }

/// A sticker being moved, resized or rotated by one pointer.
class _ElementDrag {
  _ElementDrag(
    this.pointer,
    PageElement element,
    this.mode,
    this.startPoint, {
    this.wasSelected = false,
  }) : elementId = element.id,
       start = element.frame,
       frame = element.frame;

  final int pointer;
  final String elementId;
  final _DragMode mode;
  final ElementFrame start;
  final Offset startPoint;

  /// It was already selected when touched (so a tap on text edits it).
  final bool wasSelected;

  /// The frame now, shown while dragging and saved at the end.
  ElementFrame frame;
}

/// A placed sticker's image (blank while it downloads).
class StickerView extends ConsumerWidget {
  const StickerView({required this.itemId, required this.file, super.key});

  final String itemId;
  final String file;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final image = ref
        .watch(stickerImageProvider((itemId: itemId, file: file)))
        .value;
    return image == null
        ? const SizedBox.expand()
        : Image(image: image, fit: BoxFit.fill, gaplessPlayback: true);
  }
}

/// The selected sticker's outline and its handles: remove (top left),
/// resize (bottom right) and rotate (above).
class _SelectionPainter extends CustomPainter {
  _SelectionPainter(this.frame, this.handle, this.color);

  final ElementFrame frame;

  /// Handle diameter in page units.
  final double handle;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = handle / 28;
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * unit;
    final fill = Paint()..color = color;
    final white = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5 * unit
      ..strokeCap = StrokeCap.round;

    canvas
      ..save()
      ..translate(frame.center.dx, frame.center.dy)
      ..rotate(frame.rotation);
    final w = frame.width / 2, h = frame.height / 2;
    canvas.drawRect(Rect.fromLTRB(-w, -h, w, h), line);

    // Rotate: a stalk and a round handle above the top edge.
    final rotate = Offset(0, -h - 40 * unit);
    canvas
      ..drawLine(Offset(0, -h), rotate, line)
      ..drawCircle(rotate, handle / 2, fill)
      ..drawArc(
        Rect.fromCircle(center: rotate, radius: handle / 4),
        -math.pi / 2,
        math.pi * 1.5,
        false,
        white,
      );

    // Resize: bottom right, with a diagonal arrow.
    final resize = Offset(w, h);
    canvas
      ..drawCircle(resize, handle / 2, fill)
      ..drawLine(
        resize - Offset(handle / 5, handle / 5),
        resize + Offset(handle / 5, handle / 5),
        white,
      );

    // Remove: top left, red with a cross.
    final remove = Offset(-w, -h);
    final d = handle / 6;
    canvas
      ..drawCircle(remove, handle / 2, Paint()..color = const Color(0xFFB3261E))
      ..drawLine(remove - Offset(d, d), remove + Offset(d, d), white)
      ..drawLine(remove + Offset(-d, d), remove + Offset(d, -d), white)
      ..restore();
  }

  @override
  bool shouldRepaint(_SelectionPainter old) =>
      old.frame != frame || old.handle != handle || old.color != color;
}

/// "125%" over the page while zooming.
class _ZoomBadge extends StatelessWidget {
  const _ZoomBadge(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.inverseSurface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text(
          text,
          style: TextStyle(color: scheme.onInverseSurface, fontSize: 13),
        ),
      ),
    );
  }
}

/// What a page item shows: a sticker, a photo or a text box.
/// How wide (in pixels) template pages are drawn, on screen and in print.
const templateDrawWidth = _PageCanvasState._templateWidth;

/// A page as it's exported or printed: its paper or template, items and
/// ink, with nothing to edit. Laid out in page units.
class PagePrint extends ConsumerWidget {
  const PagePrint({
    required this.pageId,
    this.templateWidth = templateDrawWidth,
    super.key,
  });

  final String pageId;

  /// How wide (in pixels) to draw a template page: smaller for thumbnails.
  final int templateWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = ref.watch(pageDimensionsProvider(pageId));
    final paper =
        ref.watch(pagePaperProvider(pageId)) ?? NotelySkin.of(context).paper;
    final template = ref.watch(pageProvider(pageId)).value?.template;
    final image = template == null
        ? null
        : ref
              .watch(
                templateImageProvider((
                  template: template,
                  width: templateWidth,
                )),
              )
              .value;
    final strokes = [
      for (final s in ref.watch(strokesProvider(pageId)).value ?? <Stroke>[])
        if (!s.deleted) s,
    ];
    final elements = [
      for (final e
          in ref.watch(elementsProvider(pageId)).value ?? <PageElement>[])
        if (!e.deleted && e.content is! LinkContent) e,
    ];
    Widget placed(PageElement e) => Positioned(
      left: e.frame.center.dx - e.frame.width / 2,
      top: e.frame.center.dy - e.frame.height / 2,
      width: e.frame.width,
      height: e.frame.height,
      child: Transform.rotate(angle: e.frame.rotation, child: _ElementView(e)),
    );
    return SizedBox.fromSize(
      size: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (template == null)
            CustomPaint(painter: PaperPainter(paper, scale: _paperScale))
          else ...[
            const ColoredBox(color: Colors.white),
            if (image != null)
              Positioned.fromRect(
                rect: Alignment.center.inscribe(
                  applyBoxFit(
                    BoxFit.contain,
                    Size(image.width.toDouble(), image.height.toDouble()),
                    size,
                  ).destination,
                  Offset.zero & size,
                ),
                child: RawImage(image: image, fit: BoxFit.fill),
              ),
          ],
          for (final e in elements)
            if (e.content is! TapeContent) placed(e),
          CustomPaint(painter: StrokesPainter(strokes)),
          // Tape over the ink, as on the page.
          for (final e in elements)
            if (e.content is TapeContent) placed(e),
        ],
      ),
    );
  }
}

class _ElementView extends StatelessWidget {
  const _ElementView(this.element);

  final PageElement element;

  @override
  Widget build(BuildContext context) => switch (element.content) {
    StickerContent(:final itemId, :final file) => StickerView(
      itemId: itemId,
      file: file,
    ),
    ImageContent(:final path) => PageImageView(path: path),
    LinkContent() => const LinkView(),
    final TextContent text => TextBoxView(content: text),
    final TapeContent tape => TapeView(content: tape),
  };
}

/// What the lasso holds: strokes and items, the box around them before
/// [transform], and how they're being moved.
@immutable
class _LassoSelection {
  const _LassoSelection({
    required this.strokeIds,
    required this.elementIds,
    required this.box,
    required this.transform,
  });

  factory _LassoSelection.of(List<Stroke> strokes, List<PageElement> elements) {
    final box = selectionBounds(strokes, elements);
    return _LassoSelection(
      strokeIds: [for (final s in strokes) s.id],
      elementIds: [for (final e in elements) e.id],
      box: box,
      transform: LassoTransform(pivot: box.center),
    );
  }

  final List<String> strokeIds;
  final List<String> elementIds;
  final Rect box;
  final LassoTransform transform;

  _LassoSelection withTransform(LassoTransform t) => _LassoSelection(
    strokeIds: strokeIds,
    elementIds: elementIds,
    box: box,
    transform: t,
  );
}

/// One pointer moving, resizing or rotating the lasso selection.
class _LassoDrag {
  _LassoDrag(this.pointer, this.mode, this.start, this.startPoint);

  final int pointer;
  final _DragMode mode;
  final LassoTransform start;
  final Offset startPoint;
}

/// The laser pointer's trail: a red glow with a bright core, fading along
/// its length as points age.
/// The zoom window's box on the page, with its margin marked.
class _ZoomBoxPainter extends CustomPainter {
  _ZoomBoxPainter(this.box, this.color, this.unit);

  final Rect box;
  final Color color;

  /// One screen pixel, in page units.
  final double unit;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(box, Radius.circular(6 * unit));
    canvas
      ..drawRRect(r, Paint()..color = color.withValues(alpha: 0.06))
      ..drawRRect(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 * unit
          ..color = color.withValues(alpha: 0.8),
      );
    final x = box.left + box.width * ZoomBoxController.advanceAt;
    canvas.drawLine(
      Offset(x, box.top),
      Offset(x, box.bottom),
      Paint()
        ..strokeWidth = 1.5 * unit
        ..color = color.withValues(alpha: 0.35),
    );
  }

  @override
  bool shouldRepaint(_ZoomBoxPainter old) =>
      old.box != box || old.color != color || old.unit != unit;
}

/// Under a hovering Pencil: a ring the size of the mark the pen,
/// highlighter or eraser would make, in the ink's color.
class _HoverPainter extends CustomPainter {
  _HoverPainter(
    this.hover, {
    required this.tool,
    required this.ink,
    required this.scale,
    required this.outline,
  }) : super(repaint: hover);

  final ValueNotifier<Offset?> hover;
  final InkToolState tool;
  final Color ink;
  final double scale;
  final Color outline;

  @override
  void paint(Canvas canvas, Size size) {
    final at = hover.value;
    if (at == null) return;
    final radius = switch (tool.kind) {
      InkToolKind.pen ||
      InkToolKind.highlighter ||
      InkToolKind.shape => tool.size * scale / 2,
      InkToolKind.eraser => tool.size,
      _ => 0.0,
    };
    if (radius <= 0) return;
    final r = math.max(radius, 2.5);
    if (tool.kind != InkToolKind.eraser) {
      canvas.drawCircle(
        at,
        r,
        Paint()
          ..color = ink.withValues(
            alpha: tool.kind == InkToolKind.highlighter
                ? 0.35
                : 0.55 * tool.penOpacity,
          ),
      );
    }
    // Light then dark, so the ring shows on any paper or ink.
    canvas
      ..drawCircle(
        at,
        r + 1,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0xCCFFFFFF),
      )
      ..drawCircle(
        at,
        r + 1,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = outline.withValues(alpha: 0.7),
      );
  }

  @override
  bool shouldRepaint(_HoverPainter old) =>
      old.hover != hover ||
      old.tool != tool ||
      old.ink != ink ||
      old.scale != scale ||
      old.outline != outline;
}

class _LaserPainter extends CustomPainter {
  _LaserPainter(this.points, this.clock, this.life, this.unit)
    : super(repaint: points);

  final ValueNotifier<List<(Offset, Duration)>> points;
  final Stopwatch clock;
  final Duration life;

  /// One screen pixel in page units.
  final double unit;

  @override
  void paint(Canvas canvas, Size size) {
    final pts = points.value;
    if (pts.isEmpty) return;
    final now = clock.elapsed;
    double alpha((Offset, Duration) p) =>
        (1 - (now - p.$2).inMicroseconds / life.inMicroseconds).clamp(0.0, 1.0);
    final glow = Paint()
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14 * unit
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 * unit);
    final core = Paint()
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4 * unit;
    for (var i = 0; i + 1 < pts.length; i++) {
      final a = alpha(pts[i + 1]);
      if (a <= 0) continue;
      glow.color = const Color(0xFFFF2D2D).withValues(alpha: 0.55 * a);
      core.color = const Color(0xFFFFE5E5).withValues(alpha: a);
      canvas
        ..drawLine(pts[i].$1, pts[i + 1].$1, glow)
        ..drawLine(pts[i].$1, pts[i + 1].$1, core);
    }
    // The tip.
    final tip = pts.last;
    final a = alpha(tip);
    if (a > 0) {
      canvas.drawCircle(
        tip.$1,
        7 * unit,
        Paint()..color = const Color(0xFFFF2D2D).withValues(alpha: a),
      );
    }
  }

  @override
  bool shouldRepaint(_LaserPainter old) =>
      old.points != points || old.unit != unit;
}
