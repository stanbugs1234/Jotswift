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
import 'ruler.dart';
import 'shapes.dart';
import 'stickers.dart';
import 'stroke_painter.dart';
import 'templates.dart';
import '../notebooks/page_jumper.dart';

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
    super.key,
  });

  final String pageId;

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

  /// Two-finger double-tap (fit the page to the width): when two fingers
  /// went down, how far they've moved, and when the last two-finger tap was.
  Duration? _twoDownAt;
  double _twoTravel = 0;
  Duration? _lastTwoTap;

  /// The zoom shown briefly while pinching, e.g. "125%".
  final _zoomBadge = ValueNotifier<String?>(null);
  Timer? _zoomBadgeTimer;

  /// A finger resting on a sticker picks it up after [_holdToMove], unless
  /// it moves first (then it scrolls).
  Timer? _holdTimer;
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
    if (!mounted || widget.readOnly || ref.read(fingersDrawProvider)) return;
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
    _offset = Offset((viewport.width - _pageSize.width * _scale) / 2, _margin);
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
    _navPointers.clear();
    _navStarts.clear();
    _velocity.clear();
    _twoDownAt = null;
  }

  void _onPointerDown(PointerDownEvent e) {
    _stopCoasting();
    if (_isStylus(e.kind)) {
      ref.read(devicePencilProvider.notifier).stylusSeen();
      _yieldToPencil(e.timeStamp);
    } else if (e.kind == PointerDeviceKind.touch && _penDown) {
      // A palm while the Pencil writes: no ink, no scrolling, no zoom.
      return;
    }

    if (_rulerWith(e)) return;
    if (_lassoWith(e)) return;
    if (_selectWith(e)) return;

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
      // A second finger while a finger is drawing means "zoom", not "draw".
      if (_drawPointer case final first?
          when _drawKind == PointerDeviceKind.touch) {
        _cancelDrawing();
        // The drawing finger is now one of the two.
        _navPointers[first] = _drawPosition;
      }
      _navPointers[e.pointer] = e.localPosition;
      _navStarts[e.pointer] = (e.localPosition, e.timeStamp);
      _velocity[e.pointer] = VelocityTracker.withKind(e.kind)
        ..addPosition(e.timeStamp, e.localPosition);
      if (_navPointers.length == 2) {
        _twoDownAt = e.timeStamp;
        _twoTravel = 0;
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

  void _onPointerMove(PointerMoveEvent e) {
    if (_rulerPointers.containsKey(e.pointer)) return _moveRuler(e);
    if (e.pointer == _laserPointer) return _addLaserPoint(e.localPosition);
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
    // The list of pages scrolls instead.
    if (widget.embedded) {
      if (_navPointers.length == 2 && ref.read(fingersDrawProvider)) {
        widget.onScroll?.call((e.localPosition - before[e.pointer]!) / 2);
      }
      return;
    }
    _velocity[e.pointer]?.addPosition(e.timeStamp, e.localPosition);
    if (_navPointers.length == 2) {
      _twoTravel += (e.localPosition - before[e.pointer]!).distance;
    }
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
    if (_rulerPointers.remove(e.pointer) != null) return;
    if (e.pointer == _laserPointer) {
      _laserPointer = null;
      return;
    }
    if (e.pointer == _lassoPointer) return _finishLasso();
    if (e.pointer == _lassoDrag?.pointer) return _finishLassoDrag();
    if (e.pointer == _drag?.pointer) _finishDrag();
    _checkTwoFingerTap(e);
    final tracker = _velocity.remove(e.pointer);
    if (tracker != null && _navPointers.length == 1) {
      final start = _navStarts[e.pointer];
      final moved =
          start != null && (e.localPosition - start.$1).distance >= 10;
      if (moved && !widget.embedded) {
        _startCoast(tracker.getVelocity().pixelsPerSecond);
      }
    }
    final start = _navStarts.remove(e.pointer);
    if (start != null &&
        _navPointers.length == 1 &&
        (e.localPosition - start.$1).distance < 10 &&
        e.timeStamp - start.$2 < const Duration(milliseconds: 400)) {
      _followLinkAt(e.localPosition);
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
      final target = ref
          .read(notebookTemplatePagesProvider(page.notebookId))
          .value?[(template.itemId, link.targetPage)];
      if (target != null && target != widget.pageId) {
        widget.onOpenPage?.call(target);
      }
      return true;
    }
    return false;
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
  void _checkTwoFingerTap(PointerEvent e) {
    final down = _twoDownAt;
    if (down == null ||
        _navPointers.length != 2 ||
        !_navPointers.containsKey(e.pointer)) {
      return;
    }
    _twoDownAt = null;
    final quick = e.timeStamp - down < const Duration(milliseconds: 300);
    if (!quick || _twoTravel > 24) return;
    final last = _lastTwoTap;
    if (last != null &&
        e.timeStamp - last < const Duration(milliseconds: 450)) {
      _lastTwoTap = null;
      final viewport = _viewport;
      if (viewport != null) {
        setState(() => _fitWidth(viewport));
        _showZoom('Fit width');
      }
    } else {
      _lastTwoTap = e.timeStamp;
    }
  }

  void _onPointerCancel(PointerEvent e) {
    _holdTimer?.cancel();
    if (_rulerPointers.remove(e.pointer) != null) return;
    if (e.pointer == _laserPointer) _laserPointer = null;
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
    if (tool.kind == InkToolKind.highlighter) {
      color = color.withValues(alpha: 0.35);
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
      style: tool.kind == InkToolKind.highlighter
          ? PenStyle.fountain
          : tool.penStyle,
    );
    _snapped = null;
    final ruler = _ruler;
    final first = _live.value!.points.first;
    _rulerSide = ruler?.edgeNear(first.offset);
    if (_rulerSide != null) {
      _live.value = _live.value!.withPoints([_guided(first)]);
      return; // Following the ruler: no shapes.
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
    _snapped = shape.kind;
    _live.value = _shapeStroke(stroke, shape.outline);
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
    _live.value = Stroke(
      id: stroke.id,
      tool: stroke.tool,
      color: stroke.color,
      width: stroke.width,
      points: [...stroke.points, _inkPoint(e)],
      createdAt: stroke.createdAt,
      pressureSensitive: stroke.pressureSensitive,
      style: stroke.style,
    );
  }

  void _finishStroke() {
    final stroke = _live.value;
    final kind = _drawKind;
    _drawPointer = null;
    widget.onWriting?.call(false);
    _rulerSide = null;
    _stopWaitingForHold();
    if (stroke == null) return;
    // A quick finger or mouse tap on a template link follows the link
    // instead of leaving a dot. (A stylus always writes.)
    final bounds = stroke.bounds;
    final first = stroke.points.first;
    if (kind != PointerDeviceKind.stylus &&
        kind != PointerDeviceKind.invertedStylus &&
        bounds.longestSide * _scale < 10 &&
        DateTime.now().millisecondsSinceEpoch - stroke.createdAt < 400 &&
        _followLinkAt(Offset(first.x, first.y) * _scale + _offset)) {
      _live.value = null;
      return;
    }
    // The live stroke stays on screen until the saved copy arrives (see
    // build), so it doesn't flicker.
    ref.read(inkHistoryProvider(widget.pageId).notifier).addStroke(stroke);
  }

  void _cancelDrawing() {
    _drawPointer = null;
    widget.onWriting?.call(false);
    _rulerSide = null;
    _stopWaitingForHold();
    _live.value = null;
    final undo = {..._erased, ..._cutStrokes, ..._cutPieces};
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
    if (_cutStrokes.isNotEmpty) {
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
        if (!e.deleted)
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
    final elements = _shownElements();
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
        if (_viewport == null || (widget.embedded && _viewport != viewport)) {
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
                                overlays: [
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
                          Positioned(
                            top: 12,
                            left: 0,
                            right: 0,
                            child: IgnorePointer(
                              child: ValueListenableBuilder<String?>(
                                valueListenable: _zoomBadge,
                                builder: (context, text, _) => AnimatedOpacity(
                                  opacity: text == null ? 0 : 1,
                                  duration: const Duration(milliseconds: 150),
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

  /// Drawn over everything else (the lasso).
  final List<Widget> overlays;

  @override
  Widget build(BuildContext context) {
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
            Positioned(
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
            ),
          RepaintBoundary(child: CustomPaint(painter: StrokesPainter(strokes))),
          CustomPaint(painter: LiveStrokePainter(live)),
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
            Positioned(
              left: e.frame.center.dx - e.frame.width / 2,
              top: e.frame.center.dy - e.frame.height / 2,
              width: e.frame.width,
              height: e.frame.height,
              child: Transform.rotate(
                angle: e.frame.rotation,
                child: _ElementView(e),
              ),
            ),
          CustomPaint(painter: StrokesPainter(strokes)),
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
