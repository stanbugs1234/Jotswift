import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../notebooks/notes_providers.dart';
import 'page_canvas.dart';

/// Whether pages show the zoom window: a magnified strip at the bottom of
/// the screen to write in large, landing small in a box on the page (as in
/// GoodNotes and Noteshelf). Stays on from page to page.
class ZoomWindowController extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
  void close() => state = false;
}

final zoomWindowProvider = NotifierProvider<ZoomWindowController, bool>(
  ZoomWindowController.new,
);

/// Where the zoom window's box is on a page (page units), and where its
/// line started, to come back to on a new line.
@immutable
class ZoomBox {
  const ZoomBox(this.rect, {required this.lineStart});

  final Rect rect;
  final double lineStart;
}

/// The box on one page. Starts near the top left, as wide as a few words;
/// its height follows the window's shape (see [fitAspect]).
class ZoomBoxController extends Notifier<ZoomBox> {
  ZoomBoxController(this.pageId);

  final String pageId;

  /// When the pen writes past this share of the box, it moves on.
  static const advanceAt = 0.75;

  Size get _page => ref.read(pageDimensionsProvider(pageId));

  @override
  ZoomBox build() {
    final page = ref.watch(pageDimensionsProvider(pageId));
    final width = page.width * 0.4;
    final left = page.width * 0.08;
    return ZoomBox(
      Rect.fromLTWH(left, page.height * 0.15, width, width * 0.3),
      lineStart: left,
    );
  }

  /// Keeps the box the shape of the window ([aspect] is height / width).
  void fitAspect(double aspect) {
    final r = state.rect;
    final height = r.width * aspect;
    if ((r.height - height).abs() < 0.5) return;
    state = ZoomBox(
      Rect.fromLTWH(r.left, r.top, r.width, height),
      lineStart: state.lineStart,
    );
  }

  /// Moves the box by [delta] (dragged on the page); a new line starts
  /// where it's put.
  void moveBy(Offset delta) {
    final r = _clamp(state.rect.shift(delta));
    state = ZoomBox(r, lineStart: r.left);
  }

  /// The pen finished a stroke covering [bounds]: past the box's margin,
  /// the box moves on.
  void wrote(Rect bounds) {
    final r = state.rect;
    if (bounds.right > r.left + r.width * advanceAt) forward();
  }

  /// Half a box to the right, or on to the next line at the page's edge.
  void forward() {
    final r = state.rect;
    final page = _page;
    if (r.right + r.width / 2 > page.width * 0.97) return newLine();
    state = ZoomBox(
      _clamp(r.shift(Offset(r.width / 2, 0))),
      lineStart: state.lineStart,
    );
  }

  /// Half a box back to the left.
  void back() {
    final r = state.rect;
    state = ZoomBox(
      _clamp(r.shift(Offset(-r.width / 2, 0))),
      lineStart: state.lineStart,
    );
  }

  /// Down a line, back where the line started.
  void newLine() {
    final r = state.rect;
    state = ZoomBox(
      _clamp(Rect.fromLTWH(state.lineStart, r.bottom, r.width, r.height)),
      lineStart: state.lineStart,
    );
  }

  Rect _clamp(Rect r) {
    final page = _page;
    return Rect.fromLTWH(
      r.left.clamp(0, math.max(0, page.width - r.width)),
      r.top.clamp(0, math.max(0, page.height - r.height)),
      r.width,
      r.height,
    );
  }
}

final zoomBoxProvider = NotifierProvider.autoDispose
    .family<ZoomBoxController, ZoomBox, String>(ZoomBoxController.new);

/// The zoom window: the box's part of the page, magnified to the width of
/// the screen, to write in. The box moves on as the writing reaches its
/// margin; the buttons move it by hand.
class ZoomWindowPanel extends ConsumerWidget {
  const ZoomWindowPanel({required this.pageId, super.key});

  final String pageId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final box = ref.watch(zoomBoxProvider(pageId));
    final boxes = ref.read(zoomBoxProvider(pageId).notifier);

    Widget button(IconData icon, String tooltip, VoidCallback onPressed) =>
        IconButton(
          tooltip: tooltip,
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          icon: Icon(icon),
          onPressed: onPressed,
        );

    return Material(
      color: scheme.surfaceContainer,
      child: Column(
        children: [
          const Divider(height: 1),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final aspect =
                          constraints.maxHeight / constraints.maxWidth;
                      if ((box.rect.height / box.rect.width - aspect).abs() >
                          0.001) {
                        WidgetsBinding.instance.addPostFrameCallback(
                          (_) => boxes.fitAspect(aspect),
                        );
                      }
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          PageCanvas(
                            pageId: pageId,
                            window: box.rect,
                            onStroke: boxes.wrote,
                          ),
                          // Where writing moves the box on.
                          Positioned(
                            left:
                                constraints.maxWidth *
                                ZoomBoxController.advanceAt,
                            top: 0,
                            bottom: 0,
                            child: IgnorePointer(
                              child: Container(
                                width: 1.5,
                                color: scheme.primary.withValues(alpha: 0.35),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const VerticalDivider(width: 1),
                SizedBox(
                  width: 56,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      button(
                        Icons.close,
                        'Close zoom window',
                        ref.read(zoomWindowProvider.notifier).close,
                      ),
                      button(Icons.arrow_back, 'Move box back', boxes.back),
                      button(Icons.arrow_forward, 'Move box on', boxes.forward),
                      button(Icons.keyboard_return, 'Next line', boxes.newLine),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
