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
import 'stickers.dart';
import 'templates.dart';
import 'stroke_painter.dart';

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
    this.onOpenPage,
    super.key,
  });

  final String pageId;

  /// Opens another page of the notebook (when a template link is tapped).
  final ValueChanged<String>? onOpenPage;

  /// View only: no drawing (used on the web).
  final bool readOnly;

  @override
  ConsumerState<PageCanvas> createState() => _PageCanvasState();
}

class _PageCanvasState extends ConsumerState<PageCanvas>
    with SingleTickerProviderStateMixin {
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

  /// When the current stroke began, to tell a palm that landed just before
  /// the Pencil from a real finger stroke.
  Duration? _drawStartedAt;

  /// A finger stroke younger than this when the Pencil touches down is a
  /// palm, and is dropped.
  static const _palmWindow = Duration(milliseconds: 300);

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
    _coast.dispose();
    _zoomBadge.dispose();
    _zoomBadgeTimer?.cancel();
    _holdTimer?.cancel();
    super.dispose();
  }

  Offset _toPage(Offset screen) => (screen - _offset) / _scale;

  void _fitWidth(Size viewport) {
    _scale = ((viewport.width - 2 * _margin) / _pageSize.width).clamp(
      _minScale,
      _maxScale,
    );
    _offset = Offset((viewport.width - _pageSize.width * _scale) / 2, _margin);
  }

  /// Keeps at least part of the page on screen.
  void _clampOffset() {
    final viewport = _viewport;
    if (viewport == null) return;
    final w = _pageSize.width * _scale;
    final h = _pageSize.height * _scale;
    double clampAxis(double value, double content, double view) {
      if (content + 2 * _margin <= view) return (view - content) / 2;
      return value.clamp(view - content - _margin, _margin);
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
  bool get _penDown => _drawPointer != null && _isStylus(_drawKind!);

  bool _canDraw(PointerDownEvent e) {
    if (widget.readOnly || _drawPointer != null) return false;
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

    if (_selectWith(e)) return;

    if (_canDraw(e)) {
      _drawPointer = e.pointer;
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
      if (_drawPointer != null && _drawKind == PointerDeviceKind.touch) {
        _cancelDrawing();
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
    if (e.pointer == _drag?.pointer) {
      setState(() => _dragTo(_toPage(e.localPosition)));
      return;
    }
    if (e.pointer == _drawPointer) {
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
    if (e.pointer == _drag?.pointer) _finishDrag();
    _checkTwoFingerTap(e);
    final tracker = _velocity.remove(e.pointer);
    if (tracker != null && _navPointers.length == 1) {
      final start = _navStarts[e.pointer];
      final moved =
          start != null && (e.localPosition - start.$1).distance >= 10;
      if (moved) _startCoast(tracker.getVelocity().pixelsPerSecond);
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
    final page = ref.read(pageProvider(widget.pageId)).value;
    final template = page?.template;
    final image = template == null ? null : _templateImage(template);
    if (page == null || template == null || image == null) return false;
    final links = ref.read(templateLinksProvider(template)).value ?? [];
    final drawn = _templateRect(image);
    final point = _toPage(screen);
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
    _velocity.remove(e.pointer);
    _navStarts.remove(e.pointer);
    if (e.pointer == _drag?.pointer) setState(() => _drag = null);
    if (e.pointer == _drawPointer) _cancelDrawing();
    _navPointers.remove(e.pointer);
  }

  void _onPointerSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
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
    var color = colors[tool.colorIndex.clamp(0, colors.length - 1)];
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
    );
  }

  void _extendStroke(PointerMoveEvent e) {
    final stroke = _live.value;
    if (stroke == null) return;
    _live.value = Stroke(
      id: stroke.id,
      tool: stroke.tool,
      color: stroke.color,
      width: stroke.width,
      points: [...stroke.points, _inkPoint(e)],
      createdAt: stroke.createdAt,
      pressureSensitive: stroke.pressureSensitive,
    );
  }

  void _finishStroke() {
    final stroke = _live.value;
    final kind = _drawKind;
    _drawPointer = null;
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
    _live.value = null;
    if (_pendingErase.isNotEmpty) setState(_pendingErase.clear);
  }

  // Erasing

  void _eraseAt(Offset screen) {
    final strokes = ref.read(strokesProvider(widget.pageId)).value ?? [];
    final point = _toPage(screen);
    final radius = ref.read(inkToolProvider).kind == InkToolKind.eraser
        ? ref.read(inkToolProvider).size / _scale
        : InkToolState.eraserSizes[1] / _scale;
    final hits = [
      for (final s in strokes)
        if (!s.deleted &&
            !_pendingErase.contains(s.id) &&
            s.hitTest(point, radius))
          s.id,
    ];
    if (hits.isNotEmpty) setState(() => _pendingErase.addAll(hits));
  }

  void _finishErasing() {
    _drawPointer = null;
    if (_pendingErase.isEmpty) return;
    final ids = _pendingErase.toList();
    // They stay hidden until the saved copies arrive as deleted (see build).
    ref.read(inkHistoryProvider(widget.pageId).notifier).erase(ids);
  }

  // Stickers

  /// The page's stickers as shown: not removed, with frames being moved.
  List<PageElement> _shownElements() => [
    for (final e in ref.read(elementsProvider(widget.pageId)).value ?? [])
      if (!e.deleted)
        e.copyWith(
          frame: _drag?.elementId == e.id
              ? _drag!.frame
              : _frameOverrides[e.id] ?? e.frame,
        ),
  ];

  /// With the select tool, a pointer on a sticker or one of its handles
  /// selects, moves, resizes, rotates or removes it. Returns whether the
  /// pointer was used.
  bool _selectWith(PointerDownEvent e) {
    if (widget.readOnly ||
        ref.read(inkToolProvider).kind != InkToolKind.select ||
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
        setState(() {
          _selectedId = el.id;
          _drag = _ElementDrag(e.pointer, el, _DragMode.move, point);
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

  /// Places the sticker picked in the tray in the middle of the view.
  void _placeRequested() {
    final request = ref
        .read(stickerRequestProvider(widget.pageId).notifier)
        .take();
    final viewport = _viewport;
    if (request == null || viewport == null) return;
    final middle = _toPage(viewport.center(Offset.zero));
    const width = 240.0;
    final height = width / request.aspect;
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
      itemId: request.itemId,
      file: request.file,
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
      (id) => _drawPointer == null && (saved[id]?.deleted ?? true),
    );
    if (!liveSaved && erased.isEmpty) return;
    final erasedIds = erased.toList();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
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
    final visible = [
      for (final s in strokes)
        if (!s.deleted && !_pendingErase.contains(s.id) && s.id != liveId) s,
    ];
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
    final selectedId = tool == InkToolKind.select
        ? _selectedId
        : _drag?.elementId; // a finger holding a sticker in pen mode
    final selected = widget.readOnly
        ? null
        : elements.where((e) => e.id == selectedId).firstOrNull;
    ref.listen(stickerRequestProvider(widget.pageId), (_, next) {
      if (next != null) _placeRequested();
    });

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = constraints.biggest;
        if (_viewport == null) _fitWidth(viewport);
        _viewport = viewport;

        return ClipRect(
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
                    ? PopIn(
                        key: ValueKey(e.id),
                        child: StickerView(itemId: e.itemId, file: e.file),
                      )
                    : StickerView(itemId: e.itemId, file: e.file),
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
        ],
      ),
    );
  }
}

enum _DragMode { move, resize, rotate }

/// A sticker being moved, resized or rotated by one pointer.
class _ElementDrag {
  _ElementDrag(this.pointer, PageElement element, this.mode, this.startPoint)
    : elementId = element.id,
      start = element.frame,
      frame = element.frame;

  final int pointer;
  final String elementId;
  final _DragMode mode;
  final ElementFrame start;
  final Offset startPoint;

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
