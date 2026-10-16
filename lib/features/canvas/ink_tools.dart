import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/synced_setting.dart';
import '../../core/settings/user_settings_repository.dart';

import '../notebooks/notes_providers.dart';
import '../notebooks/data/notes_repository.dart';
import 'domain/page_element.dart';
import 'domain/stroke.dart';

enum InkToolKind {
  pen,
  highlighter,
  eraser,

  /// Selects stickers, photos and text boxes to move, resize, rotate,
  /// remove or (text) edit.
  select,

  /// Draws a loop around handwriting (and items) to move, resize, rotate,
  /// recolor, copy or delete it.
  lasso,

  /// A glowing trail that fades away: for pointing at things while
  /// presenting. Never saved.
  laser,
}

/// What the eraser takes: whole strokes it touches, or only the ink under
/// it.
enum EraserMode { stroke, partial }

/// The selected drawing tool and pen. Shared by all pages, so it sticks
/// when the user moves between pages, and remembered on the device.
@immutable
class InkToolState {
  const InkToolState({
    this.kind = InkToolKind.pen,
    this.colorIndex = 0,
    this.sizeIndex = 1,
    this.drawMode = true,
    this.customColor,
    this.penWidth,
    this.highlighterWidth,
    this.penStyle = PenStyle.fountain,
    this.eraserMode = EraserMode.stroke,
    this.eraseHighlighterOnly = false,
    this.eraserReturns = false,
  });

  factory InkToolState.fromJson(Map<String, dynamic> json) {
    double? width(Object? v) => v is num ? v.toDouble() : null;
    final kind = InkToolKind.values.asNameMap()[json['kind']];
    return InkToolState(
      // The select, lasso and laser tools aren't kept: a page opens ready
      // to write.
      kind:
          kind == InkToolKind.select ||
              kind == InkToolKind.lasso ||
              kind == InkToolKind.laser
          ? InkToolKind.pen
          : kind ?? InkToolKind.pen,
      colorIndex: (json['colorIndex'] as num?)?.toInt() ?? 0,
      sizeIndex: ((json['sizeIndex'] as num?)?.toInt() ?? 1).clamp(0, 2),
      customColor: (json['customColor'] as num?)?.toInt(),
      penWidth: width(json['penWidth']),
      highlighterWidth: width(json['highlighterWidth']),
      penStyle:
          PenStyle.values.asNameMap()[json['penStyle']] ?? PenStyle.fountain,
      eraserMode:
          EraserMode.values.asNameMap()[json['eraserMode']] ??
          EraserMode.stroke,
      eraseHighlighterOnly: json['eraseHighlighterOnly'] == true,
      eraserReturns: json['eraserReturns'] == true,
    );
  }

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'colorIndex': colorIndex,
    'sizeIndex': sizeIndex,
    'customColor': ?customColor,
    'penWidth': ?penWidth,
    'highlighterWidth': ?highlighterWidth,
    'penStyle': penStyle.name,
    'eraserMode': eraserMode.name,
    'eraseHighlighterOnly': eraseHighlighterOnly,
    'eraserReturns': eraserReturns,
  };

  final InkToolKind kind;

  /// Index into the active skin's ink colors, unless [customColor] is set.
  final int colorIndex;

  /// A color picked from the full palette (ARGB), used instead of the
  /// skin's colors.
  final int? customColor;

  /// Index into [penSizes] / [highlighterSizes] / [eraserSizes].
  final int sizeIndex;

  /// Widths chosen with the slider, used instead of the [sizeIndex] preset.
  final double? penWidth;
  final double? highlighterWidth;

  /// How the pen draws.
  final PenStyle penStyle;

  final EraserMode eraserMode;

  /// The eraser leaves pen strokes alone.
  final bool eraseHighlighterOnly;

  /// After each erase, go back to the tool used before the eraser.
  final bool eraserReturns;

  /// When false ("hand" mode), one finger scrolls instead of drawing. A
  /// stylus always draws.
  final bool drawMode;

  /// Widths in page units (a page is 1404 units wide).
  static const penSizes = [3.0, 6.0, 12.0];
  static const highlighterSizes = [18.0, 30.0, 48.0];

  /// What the width slider covers.
  static const penRange = (min: 1.5, max: 30.0);
  static const highlighterRange = (min: 8.0, max: 80.0);

  /// Eraser radius in screen pixels, so it feels the same at any zoom.
  static const eraserSizes = [8.0, 16.0, 32.0];

  double get size => switch (kind) {
    InkToolKind.pen ||
    InkToolKind.select ||
    InkToolKind.lasso ||
    InkToolKind.laser => penWidth ?? penSizes[sizeIndex],
    InkToolKind.highlighter => highlighterWidth ?? highlighterSizes[sizeIndex],
    InkToolKind.eraser => eraserSizes[sizeIndex],
  };

  /// The ink color, from the skin's [palette] unless a custom one is set.
  Color colorFrom(List<Color> palette) => customColor != null
      ? Color(customColor!)
      : palette[colorIndex.clamp(0, palette.length - 1)];

  InkToolState copyWith({
    InkToolKind? kind,
    int? colorIndex,
    int? sizeIndex,
    bool? drawMode,
    Object? customColor = _keep,
    Object? penWidth = _keep,
    Object? highlighterWidth = _keep,
    PenStyle? penStyle,
    EraserMode? eraserMode,
    bool? eraseHighlighterOnly,
    bool? eraserReturns,
  }) => InkToolState(
    kind: kind ?? this.kind,
    colorIndex: colorIndex ?? this.colorIndex,
    sizeIndex: sizeIndex ?? this.sizeIndex,
    drawMode: drawMode ?? this.drawMode,
    customColor: customColor == _keep ? this.customColor : customColor as int?,
    penWidth: penWidth == _keep ? this.penWidth : penWidth as double?,
    highlighterWidth: highlighterWidth == _keep
        ? this.highlighterWidth
        : highlighterWidth as double?,
    penStyle: penStyle ?? this.penStyle,
    eraserMode: eraserMode ?? this.eraserMode,
    eraseHighlighterOnly: eraseHighlighterOnly ?? this.eraseHighlighterOnly,
    eraserReturns: eraserReturns ?? this.eraserReturns,
  );

  static const _keep = Object();
}

class InkToolController extends Notifier<InkToolState> {
  static const _prefsKey = 'inkTool';

  @override
  InkToolState build() {
    final saved = ref.read(sharedPreferencesProvider).getString(_prefsKey);
    if (saved == null) return const InkToolState();
    try {
      return InkToolState.fromJson(jsonDecode(saved) as Map<String, dynamic>);
    } catch (_) {
      return const InkToolState();
    }
  }

  void _set(InkToolState next) {
    state = next;
    ref
        .read(sharedPreferencesProvider)
        .setString(_prefsKey, jsonEncode(next.toJson()));
  }

  /// The tool before the eraser, to go back to (see
  /// [InkToolState.eraserReturns]).
  InkToolKind? _beforeEraser;

  /// The tool before the current one (for a Pencil double-tap).
  InkToolKind? _previous;

  void selectTool(InkToolKind kind) {
    if (kind == InkToolKind.eraser && state.kind != InkToolKind.eraser) {
      _beforeEraser = state.kind;
    }
    if (kind != state.kind) _previous = state.kind;
    _set(state.copyWith(kind: kind, drawMode: true));
  }

  /// Eraser and back (an Apple Pencil double-tap).
  void toggleEraser() => selectTool(
    state.kind == InkToolKind.eraser
        ? _beforeEraser ?? InkToolKind.pen
        : InkToolKind.eraser,
  );

  /// The tool used before this one.
  void switchToPrevious() => selectTool(_previous ?? InkToolKind.pen);

  /// An erase finished: go back to the previous tool if the user asked.
  void erased() {
    final back = _beforeEraser;
    if (!state.eraserReturns ||
        state.kind != InkToolKind.eraser ||
        back == null) {
      return;
    }
    _set(state.copyWith(kind: back));
  }

  void setEraserMode(EraserMode mode) => _set(state.copyWith(eraserMode: mode));
  void setEraseHighlighterOnly(bool only) =>
      _set(state.copyWith(eraseHighlighterOnly: only));
  void setEraserReturns(bool returns) =>
      _set(state.copyWith(eraserReturns: returns));
  void selectColor(int index) =>
      _set(state.copyWith(colorIndex: index, customColor: null));
  void selectCustomColor(Color color) =>
      _set(state.copyWith(customColor: color.toARGB32()));

  /// Picks a preset size; the slider's width is forgotten.
  void selectSize(int index) => _set(
    state.copyWith(
      sizeIndex: index,
      penWidth: state.kind == InkToolKind.highlighter ? state.penWidth : null,
      highlighterWidth: state.kind == InkToolKind.highlighter
          ? null
          : state.highlighterWidth,
    ),
  );

  /// Sets the current pen's (or highlighter's) width from the slider.
  void setWidth(double width) => _set(
    state.kind == InkToolKind.highlighter
        ? state.copyWith(highlighterWidth: width)
        : state.copyWith(penWidth: width),
  );

  void selectPenStyle(PenStyle style) => _set(
    state.copyWith(
      penStyle: style,
      kind: state.kind == InkToolKind.highlighter ? null : InkToolKind.pen,
    ),
  );

  void setDrawMode(bool drawMode) => state = state.copyWith(drawMode: drawMode);

  /// Picks up a saved pen.
  void useFavorite(PenFavorite pen) => _set(
    pen.tool == InkTool.highlighter
        ? state.copyWith(
            kind: InkToolKind.highlighter,
            customColor: pen.color,
            highlighterWidth: pen.width,
            drawMode: true,
          )
        : state.copyWith(
            kind: InkToolKind.pen,
            customColor: pen.color,
            penWidth: pen.width,
            penStyle: pen.style,
            drawMode: true,
          ),
  );
}

final inkToolProvider = NotifierProvider<InkToolController, InkToolState>(
  InkToolController.new,
);

/// A saved pen: tool, style, color and width.
@immutable
class PenFavorite {
  const PenFavorite({
    required this.tool,
    required this.style,
    required this.color,
    required this.width,
  });

  static PenFavorite? fromJson(Object? json) {
    if (json is! Map) return null;
    final tool = InkTool.values.asNameMap()[json['tool']];
    final color = json['color'], width = json['width'];
    if (tool == null || color is! num || width is! num) return null;
    return PenFavorite(
      tool: tool,
      style: PenStyle.values.asNameMap()[json['style']] ?? PenStyle.fountain,
      color: color.toInt(),
      width: width.toDouble(),
    );
  }

  final InkTool tool;
  final PenStyle style;

  /// ARGB, without the highlighter's see-through.
  final int color;
  final double width;

  Map<String, Object> toJson() => {
    'tool': tool.name,
    'style': style.name,
    'color': color,
    'width': (width * 10).round() / 10,
  };

  @override
  bool operator ==(Object other) =>
      other is PenFavorite &&
      other.tool == tool &&
      other.style == style &&
      other.color == color &&
      (other.width - width).abs() < 0.05;

  @override
  int get hashCode => Object.hash(tool, style, color, (width * 10).round());
}

/// The user's saved pens, on the account so they follow them to every
/// device.
class PenFavoritesController extends SyncedSetting {
  static const max = 12;

  @override
  String get key => SettingKeys.penFavorites;

  @override
  String get defaultValue => '[]';

  Future<void> add(PenFavorite pen) {
    final pens = _parse(state);
    if (pens.contains(pen)) return Future.value();
    return _save([...pens, pen].reversed.take(max).toList().reversed.toList());
  }

  Future<void> remove(PenFavorite pen) => _save([
    for (final p in _parse(state))
      if (p != pen) p,
  ]);

  Future<void> _save(List<PenFavorite> pens) =>
      save(jsonEncode([for (final p in pens) p.toJson()]));

  static List<PenFavorite> _parse(String json) {
    try {
      final list = jsonDecode(json);
      if (list is! List) return const [];
      return [for (final item in list) ?PenFavorite.fromJson(item)];
    } catch (_) {
      return const [];
    }
  }
}

final penFavoritesSettingProvider =
    NotifierProvider<PenFavoritesController, String>(
      PenFavoritesController.new,
    );

final penFavoritesProvider = Provider<List<PenFavorite>>(
  (ref) =>
      PenFavoritesController._parse(ref.watch(penFavoritesSettingProvider)),
);

/// Something that can be undone on a page.
sealed class InkCommand {
  const InkCommand();
}

class AddStrokeCommand extends InkCommand {
  const AddStrokeCommand(this.strokeId);
  final String strokeId;
}

class EraseCommand extends InkCommand {
  const EraseCommand(this.strokeIds);
  final List<String> strokeIds;
}

/// A sticker was placed ([added]) or removed.
class ElementPresenceCommand extends InkCommand {
  const ElementPresenceCommand(this.elementId, {required this.added});
  final String elementId;
  final bool added;
}

/// A text box's text (and so its frame) changed.
class ElementEditCommand extends InkCommand {
  const ElementEditCommand(this.before, this.after);
  final PageElement before;
  final PageElement after;
}

/// A sticker was moved, resized or rotated.
class ElementFrameCommand extends InkCommand {
  const ElementFrameCommand(this.elementId, this.before, this.after);
  final String elementId;
  final ElementFrame before;
  final ElementFrame after;
}

/// Strokes were moved, recolored, pasted or deleted with the lasso: the
/// [removed] ones were erased and the [added] ones saved in their place.
class ReplaceStrokesCommand extends InkCommand {
  const ReplaceStrokesCommand(this.removed, this.added);
  final List<String> removed;
  final List<String> added;
}

/// Several changes undone and redone as one step.
class CompositeCommand extends InkCommand {
  const CompositeCommand(this.commands);
  final List<InkCommand> commands;
}

@immutable
class InkHistoryState {
  const InkHistoryState({this.undo = const [], this.redo = const []});

  final List<InkCommand> undo;
  final List<InkCommand> redo;

  bool get canUndo => undo.isNotEmpty;
  bool get canRedo => redo.isNotEmpty;
}

/// Adds and erases strokes, and places, changes and removes stickers, on
/// one page, with undo and redo. Undo works by flipping `deleted` flags and
/// restoring frames, so it syncs like any other edit.
class InkHistory extends Notifier<InkHistoryState> {
  InkHistory(this.pageId);

  final String pageId;

  static const _maxUndo = 100;

  @override
  InkHistoryState build() => const InkHistoryState();

  Future<void> addStroke(Stroke stroke) async {
    await ref.read(strokeRepositoryProvider).addStroke(pageId, stroke);
    _push(AddStrokeCommand(stroke.id));
    _touchNotebook();
  }

  Future<void> erase(List<String> strokeIds) async {
    if (strokeIds.isEmpty) return;
    await ref
        .read(strokeRepositoryProvider)
        .setDeleted(pageId, strokeIds, true);
    _push(EraseCommand(strokeIds));
    _touchNotebook();
  }

  /// Marks the notebook as modified, at most once a minute while writing.
  void _touchNotebook() {
    final now = DateTime.now();
    if (now.difference(_lastTouch) < const Duration(minutes: 1)) return;
    final notebookId = ref.read(pageProvider(pageId)).value?.notebookId;
    if (notebookId == null) return;
    _lastTouch = now;
    ref.read(notebookRepositoryProvider).touchNotebook(notebookId);
  }

  var _lastTouch = DateTime(0);

  Future<void> addElement(PageElement element) async {
    await ref.read(elementRepositoryProvider).addElement(pageId, element);
    _push(ElementPresenceCommand(element.id, added: true));
    _touchNotebook();
  }

  Future<void> removeElement(String elementId) async {
    await _elements.setElementDeleted(pageId, elementId, deleted: true);
    _push(ElementPresenceCommand(elementId, added: false));
    _touchNotebook();
  }

  Future<void> setElementFrame(
    String elementId,
    ElementFrame before,
    ElementFrame after,
  ) async {
    if (before == after) return;
    await _elements.setElementFrame(pageId, elementId, after);
    _push(ElementFrameCommand(elementId, before, after));
    _touchNotebook();
  }

  /// Saves [after]'s content and frame (editing a text box).
  Future<void> editElement(PageElement before, PageElement after) async {
    await _elements.setElementContent(
      pageId,
      after.id,
      after.content,
      after.frame,
    );
    _push(ElementEditCommand(before, after));
    _touchNotebook();
  }

  /// One lasso edit, undone as one step: strokes replaced, items moved
  /// ([frames] is id, before, after), added or removed.
  Future<void> lassoEdit({
    List<String> removeStrokes = const [],
    List<Stroke> addStrokes = const [],
    List<(String, ElementFrame, ElementFrame)> frames = const [],
    List<PageElement> addElements = const [],
    List<String> removeElements = const [],
  }) async {
    final commands = <InkCommand>[];
    if (removeStrokes.isNotEmpty || addStrokes.isNotEmpty) {
      await ref
          .read(strokeRepositoryProvider)
          .replaceStrokes(pageId, remove: removeStrokes, add: addStrokes);
      commands.add(
        ReplaceStrokesCommand(removeStrokes, [
          for (final s in addStrokes) s.id,
        ]),
      );
    }
    for (final (id, before, after) in frames) {
      if (before == after) continue;
      await _elements.setElementFrame(pageId, id, after);
      commands.add(ElementFrameCommand(id, before, after));
    }
    for (final e in addElements) {
      await _elements.addElement(pageId, e);
      commands.add(ElementPresenceCommand(e.id, added: true));
    }
    for (final id in removeElements) {
      await _elements.setElementDeleted(pageId, id, deleted: true);
      commands.add(ElementPresenceCommand(id, added: false));
    }
    if (commands.isEmpty) return;
    _push(commands.length == 1 ? commands.single : CompositeCommand(commands));
    _touchNotebook();
  }

  ElementRepository get _elements => ref.read(elementRepositoryProvider);

  void _push(InkCommand command) {
    final undo = [...state.undo, command];
    state = InkHistoryState(
      undo: undo.length > _maxUndo ? undo.sublist(1) : undo,
    );
  }

  Future<void> undo() async {
    if (!state.canUndo) return;
    final command = state.undo.last;
    state = InkHistoryState(
      undo: state.undo.sublist(0, state.undo.length - 1),
      redo: [...state.redo, command],
    );
    await _apply(command, reverse: true);
  }

  Future<void> redo() async {
    if (!state.canRedo) return;
    final command = state.redo.last;
    state = InkHistoryState(
      undo: [...state.undo, command],
      redo: state.redo.sublist(0, state.redo.length - 1),
    );
    await _apply(command, reverse: false);
  }

  Future<void> _apply(InkCommand command, {required bool reverse}) async {
    final strokes = ref.read(strokeRepositoryProvider);
    // Undoing an add hides it; undoing a removal brings it back.
    return switch (command) {
      AddStrokeCommand(:final strokeId) => strokes.setDeleted(pageId, [
        strokeId,
      ], reverse),
      EraseCommand(:final strokeIds) => strokes.setDeleted(
        pageId,
        strokeIds,
        !reverse,
      ),
      ElementPresenceCommand(:final elementId, :final added) =>
        _elements.setElementDeleted(
          pageId,
          elementId,
          deleted: added == reverse,
        ),
      ElementFrameCommand(:final elementId, :final before, :final after) =>
        _elements.setElementFrame(pageId, elementId, reverse ? before : after),
      ElementEditCommand(:final before, :final after) => () {
        final e = reverse ? before : after;
        return _elements.setElementContent(pageId, e.id, e.content, e.frame);
      }(),
      ReplaceStrokesCommand(:final removed, :final added) => () async {
        await strokes.setDeleted(pageId, added, reverse);
        await strokes.setDeleted(pageId, removed, !reverse);
      }(),
      CompositeCommand(:final commands) => () async {
        for (final c in reverse ? commands.reversed : commands) {
          await _apply(c, reverse: reverse);
        }
      }(),
    };
  }
}

final inkHistoryProvider = NotifierProvider.autoDispose
    .family<InkHistory, InkHistoryState, String>(InkHistory.new);
