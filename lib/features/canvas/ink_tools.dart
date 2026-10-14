import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../notebooks/notes_providers.dart';
import 'domain/stroke.dart';

enum InkToolKind { pen, highlighter, eraser }

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
    InkToolKind.pen => penSizes[sizeIndex],
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
  const InkCommand(this.strokeIds);
  final List<String> strokeIds;
}

class AddStrokeCommand extends InkCommand {
  AddStrokeCommand(String strokeId) : super([strokeId]);
}

class EraseCommand extends InkCommand {
  const EraseCommand(super.strokeIds);
}

@immutable
class InkHistoryState {
  const InkHistoryState({this.undo = const [], this.redo = const []});

  final List<InkCommand> undo;
  final List<InkCommand> redo;

  bool get canUndo => undo.isNotEmpty;
  bool get canRedo => redo.isNotEmpty;
}

/// Adds and erases strokes on one page, with undo and redo. Undo works by
/// flipping the strokes' `deleted` flag, so it syncs like any other edit.
class InkHistory extends Notifier<InkHistoryState> {
  InkHistory(this.pageId);

  final String pageId;

  static const _maxUndo = 100;

  @override
  InkHistoryState build() => const InkHistoryState();

  Future<void> addStroke(Stroke stroke) async {
    await ref.read(strokeRepositoryProvider).addStroke(pageId, stroke);
    _push(AddStrokeCommand(stroke.id));
  }

  Future<void> erase(List<String> strokeIds) async {
    if (strokeIds.isEmpty) return;
    await ref
        .read(strokeRepositoryProvider)
        .setDeleted(pageId, strokeIds, true);
    _push(EraseCommand(strokeIds));
  }

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
    // Undoing an add hides the stroke; undoing an erase brings strokes back.
    final deleted = switch (command) {
      AddStrokeCommand() => reverse,
      EraseCommand() => !reverse,
    };
    return ref
        .read(strokeRepositoryProvider)
        .setDeleted(pageId, command.strokeIds, deleted);
  }
}

final inkHistoryProvider = NotifierProvider.autoDispose
    .family<InkHistory, InkHistoryState, String>(InkHistory.new);
