import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/paper/paper_style.dart';
import '../../core/skins/notely_skin.dart';
import '../../core/skins/widgets/paper.dart';
import '../notebooks/notes_providers.dart';
import 'domain/stroke.dart';
import 'ink_tools.dart';
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
  const PageCanvas({required this.pageId, this.readOnly = false, super.key});

  final String pageId;

  /// View only: no drawing (used on the web).
  final bool readOnly;

  @override
  ConsumerState<PageCanvas> createState() => _PageCanvasState();
}

class _PageCanvasState extends ConsumerState<PageCanvas> {
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
  bool _stylusSeen = false;

  // Scrolling and zooming: screen positions of the non-drawing pointers.
  final _navPointers = <int, Offset>{};

  @override
  void dispose() {
    _live.dispose();
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

  bool _canDraw(PointerDownEvent e) {
    if (widget.readOnly || _drawPointer != null || _navPointers.isNotEmpty) {
      return false;
    }
    final draw = ref.read(inkToolProvider).drawMode;
    return switch (e.kind) {
      PointerDeviceKind.stylus || PointerDeviceKind.invertedStylus => true,
      PointerDeviceKind.mouse => draw && e.buttons == kPrimaryMouseButton,
      PointerDeviceKind.touch => draw && !_stylusSeen,
      _ => false,
    };
  }

  void _onPointerDown(PointerDownEvent e) {
    final isStylus =
        e.kind == PointerDeviceKind.stylus ||
        e.kind == PointerDeviceKind.invertedStylus;
    if (isStylus) _stylusSeen = true;

    if (_canDraw(e)) {
      _drawPointer = e.pointer;
      _drawKind = e.kind;
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
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
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
    setState(() {
      if (_navPointers.length == 1) {
        _offset += e.localPosition - before[e.pointer]!;
      } else {
        _pinch(before, _navPointers);
      }
      _clampOffset();
    });
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
    if (e.pointer == _drawPointer) {
      if (_erasing) {
        _finishErasing();
      } else {
        _finishStroke();
      }
    }
    _navPointers.remove(e.pointer);
  }

  void _onPointerCancel(PointerEvent e) {
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
    _drawPointer = null;
    if (stroke == null) return;
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
                      strokes: visible,
                      live: _live,
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
    required this.strokes,
    required this.live,
  });

  final Size size;
  final PaperStyle paper;
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
          RepaintBoundary(
            child: CustomPaint(
              painter: PaperPainter(paper, scale: _paperScale),
            ),
          ),
          RepaintBoundary(child: CustomPaint(painter: StrokesPainter(strokes))),
          CustomPaint(painter: LiveStrokePainter(live)),
        ],
      ),
    );
  }
}
