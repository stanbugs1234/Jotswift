import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/input/finger_drawing.dart';
import '../../core/skins/skin_providers.dart';
import '../../core/skins/widgets/page_style.dart';
import '../canvas/page_canvas.dart';
import 'notes_providers.dart';

/// How a notebook's pages are shown: one at a time, turning like a book,
/// or one under another, scrolling.
enum PageScroll { pages, vertical }

/// The chosen [PageScroll], kept on this device.
class PageScrollController extends Notifier<PageScroll> {
  static const _prefsKey = 'pageScroll';

  @override
  PageScroll build() =>
      PageScroll.values.asNameMap()[ref
          .watch(sharedPreferencesProvider)
          .getString(_prefsKey)] ??
      PageScroll.pages;

  Future<void> set(PageScroll scroll) async {
    state = scroll;
    await ref.read(sharedPreferencesProvider).setString(_prefsKey, scroll.name);
  }
}

final pageScrollProvider = NotifierProvider<PageScrollController, PageScroll>(
  PageScrollController.new,
);

/// The page most in view while scrolling a notebook's pages, which the
/// toolbar and title follow. Null until it has scrolled.
class VisiblePage extends Notifier<String?> {
  VisiblePage(this.notebookId);

  final String notebookId;

  @override
  String? build() => null;

  void show(String pageId) {
    if (state != pageId) state = pageId;
  }
}

final visiblePageProvider = NotifierProvider.autoDispose
    .family<VisiblePage, String?, String>(VisiblePage.new);

/// Asks the scrolling list of a notebook's pages to scroll to a page.
class PageJump extends Notifier<(String, int)?> {
  PageJump(this.notebookId);

  final String notebookId;

  @override
  (String, int)? build() => null;

  void to(String pageId) => state = (pageId, (state?.$2 ?? 0) + 1);
}

final pageJumpProvider = NotifierProvider.autoDispose
    .family<PageJump, (String, int)?, String>(PageJump.new);

/// A notebook's pages one under another, each as wide as the screen.
/// The pen writes on the page it touches. One finger scrolls, or two when
/// fingers draw; so does the mouse.
class VerticalPages extends ConsumerStatefulWidget {
  const VerticalPages({
    required this.notebookId,
    required this.order,
    required this.startPageId,
    this.readOnly = false,
    this.inkEnabled = true,
    super.key,
  });

  final String notebookId;

  /// Every page id, in reading order.
  final List<String> order;
  final String startPageId;
  final bool readOnly;
  final bool inkEnabled;

  @override
  ConsumerState<VerticalPages> createState() => _VerticalPagesState();
}

class _VerticalPagesState extends ConsumerState<VerticalPages> {
  static const _gap = 16.0;

  ScrollController? _scroll;
  double _extent = 0;

  /// The pen is writing, so the list holds still under a resting palm.
  bool _writing = false;

  @override
  void dispose() {
    _scroll?.dispose();
    super.dispose();
  }

  void _onScroll() {
    final scroll = _scroll;
    if (scroll == null || !scroll.hasClients || _extent == 0) return;
    final view = scroll.position.viewportDimension;
    final i = ((scroll.offset + view / 3) / _extent).floor().clamp(
      0,
      widget.order.length - 1,
    );
    ref
        .read(visiblePageProvider(widget.notebookId).notifier)
        .show(widget.order[i]);
  }

  /// Two fingers moved by [delta] (when fingers draw).
  void _scrollBy(Offset delta) {
    final scroll = _scroll;
    if (scroll == null || !scroll.hasClients) return;
    scroll.jumpTo(
      (scroll.offset - delta.dy).clamp(0, scroll.position.maxScrollExtent),
    );
  }

  void _jumpTo(String pageId) {
    final i = widget.order.indexOf(pageId);
    final scroll = _scroll;
    if (i == -1 || scroll == null || !scroll.hasClients) return;
    scroll.animateTo(
      (i * _extent).clamp(0, scroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(pageJumpProvider(widget.notebookId), (_, jump) {
      if (jump != null) _jumpTo(jump.$1);
    });
    final fingersDraw = ref.watch(fingersDrawProvider);
    final order = widget.order;
    if (order.isEmpty) return const SizedBox.shrink();
    final size = ref.watch(pageDimensionsProvider(order.first));
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth - 2 * _gap;
        final pageHeight = width * size.height / size.width;
        final extent = pageHeight + _gap;
        if (_scroll == null) {
          final start = order
              .indexOf(widget.startPageId)
              .clamp(0, order.length);
          _scroll = ScrollController(initialScrollOffset: start * extent)
            ..addListener(_onScroll);
        }
        _extent = extent;
        return ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            // The pen always writes; fingers scroll unless they draw.
            dragDevices: {
              if (!fingersDraw) PointerDeviceKind.touch,
              PointerDeviceKind.mouse,
              PointerDeviceKind.trackpad,
            },
          ),
          child: Scrollbar(
            controller: _scroll,
            interactive: true,
            child: ListView.builder(
              controller: _scroll,
              physics: _writing
                  ? const NeverScrollableScrollPhysics()
                  : const ClampingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: _gap),
              itemExtent: extent,
              itemCount: order.length,
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.only(top: _gap),
                child: PageStyle(
                  style: ref.watch(pageStyleProvider(order[i])),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 12,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: PageCanvas(
                      key: ValueKey(order[i]),
                      pageId: order[i],
                      readOnly: widget.readOnly,
                      inkEnabled: widget.inkEnabled,
                      embedded: true,
                      onOpenPage: _jumpTo,
                      onScroll: _scrollBy,
                      onWriting: (writing) {
                        if (writing != _writing && mounted) {
                          setState(() => _writing = writing);
                        }
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
