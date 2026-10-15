import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../notebooks/notes_providers.dart';
import '../notebooks/data/notes_repository.dart';
import 'domain/page_element.dart';
import 'domain/stroke.dart';

enum InkToolKind {
  pen,
  highlighter,
  eraser,

  /// Selects stickers to move, resize, rotate or remove.
  select,
}

/// The selected drawing tool. Shared by all pages, so it sticks when the
/// user moves between pages.
@immutable
class InkToolState {
  const InkToolState({
    this.kind = InkToolKind.pen,
    this.colorIndex = 0,
    this.sizeIndex = 1,
    this.drawMode = true,
  });

  final InkToolKind kind;

  /// Index into the active skin's ink colors.
  final int colorIndex;

  /// Index into [penSizes] / [highlighterSizes] / [eraserSizes].
  final int sizeIndex;

  /// When false ("hand" mode), one finger scrolls instead of drawing. A
  /// stylus always draws.
  final bool drawMode;

  /// Widths in page units (a page is 1404 units wide).
  static const penSizes = [3.0, 6.0, 12.0];
  static const highlighterSizes = [18.0, 30.0, 48.0];

  /// Eraser radius in screen pixels, so it feels the same at any zoom.
  static const eraserSizes = [8.0, 16.0, 32.0];

  double get size => switch (kind) {
    InkToolKind.pen || InkToolKind.select => penSizes[sizeIndex],
    InkToolKind.highlighter => highlighterSizes[sizeIndex],
    InkToolKind.eraser => eraserSizes[sizeIndex],
  };

  InkToolState copyWith({
    InkToolKind? kind,
    int? colorIndex,
    int? sizeIndex,
    bool? drawMode,
  }) => InkToolState(
    kind: kind ?? this.kind,
    colorIndex: colorIndex ?? this.colorIndex,
    sizeIndex: sizeIndex ?? this.sizeIndex,
    drawMode: drawMode ?? this.drawMode,
  );
}

class InkToolController extends Notifier<InkToolState> {
  @override
  InkToolState build() => const InkToolState();

  void selectTool(InkToolKind kind) =>
      state = state.copyWith(kind: kind, drawMode: true);
  void selectColor(int index) => state = state.copyWith(colorIndex: index);
  void selectSize(int index) => state = state.copyWith(sizeIndex: index);
  void setDrawMode(bool drawMode) => state = state.copyWith(drawMode: drawMode);
}

final inkToolProvider = NotifierProvider<InkToolController, InkToolState>(
  InkToolController.new,
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

/// A sticker was moved, resized or rotated.
class ElementFrameCommand extends InkCommand {
  const ElementFrameCommand(this.elementId, this.before, this.after);
  final String elementId;
  final ElementFrame before;
  final ElementFrame after;
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

  Future<void> _apply(InkCommand command, {required bool reverse}) {
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
    };
  }
}

final inkHistoryProvider = NotifierProvider.autoDispose
    .family<InkHistory, InkHistoryState, String>(InkHistory.new);
