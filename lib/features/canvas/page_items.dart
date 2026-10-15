import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/skins/notely_skin.dart';
import '../notebooks/data/cover_photos.dart';
import '../notebooks/notes_providers.dart';
import 'domain/page_element.dart';
import 'ink_tools.dart';
import 'stickers.dart';

/// Space between a text box's edge and its text, in layout units.
const _textPadding = 12.0;

/// The longest a new text box's lines get before wrapping (page units; a
/// page is about 1400 wide).
const _maxTextWidth = 700.0;

/// Text box sizes: small, medium, large (page units).
const textSizes = [28.0, 40.0, 60.0];

TextStyle _textStyle(TextContent c) =>
    TextStyle(fontSize: c.fontSize, color: Color(c.color), height: 1.3);

/// A text box's size before its frame scales it: [TextContent.layoutWidth]
/// wide and as tall as the wrapped text.
Size textNaturalSize(TextContent c) {
  final painter = TextPainter(
    text: TextSpan(text: c.text, style: _textStyle(c)),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: math.max(1, c.layoutWidth - 2 * _textPadding));
  final size = Size(c.layoutWidth, painter.height + 2 * _textPadding);
  painter.dispose();
  return size;
}

/// [c] with a layout width that fits its longest line (up to
/// [_maxTextWidth]), so short text gets a snug box.
TextContent fitTextWidth(TextContent c) {
  final painter = TextPainter(
    text: TextSpan(text: c.text, style: _textStyle(c)),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: _maxTextWidth - 2 * _textPadding);
  final width = painter.maxIntrinsicWidth.ceilToDouble().clamp(
    40.0,
    _maxTextWidth - 2 * _textPadding,
  );
  painter.dispose();
  return TextContent(
    text: c.text,
    fontSize: c.fontSize,
    color: c.color,
    layoutWidth: width + 2 * _textPadding,
  );
}

/// The frame for edited text: same scale and rotation, the same top-left
/// corner, and the size the new text needs.
ElementFrame reframeText(ElementFrame old, TextContent before, TextContent c) {
  final scale = old.width / before.layoutWidth;
  final natural = textNaturalSize(c);
  final w = natural.width * scale, h = natural.height * scale;
  final topLeft = old.toPage(Offset(-old.width / 2, -old.height / 2));
  final anchor = ElementFrame(
    center: topLeft,
    width: 0,
    height: 0,
    rotation: old.rotation,
  );
  return old.copyWith(
    center: anchor.toPage(Offset(w / 2, h / 2)),
    width: w,
    height: h,
  );
}

/// A text box as drawn on the page.
class TextBoxView extends StatelessWidget {
  const TextBoxView({required this.content, super.key});

  final TextContent content;

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.fill,
    alignment: Alignment.topLeft,
    child: SizedBox(
      width: content.layoutWidth,
      child: Padding(
        padding: const EdgeInsets.all(_textPadding),
        // Its own style, so it measures the same as textNaturalSize.
        child: DefaultTextStyle(
          style: const TextStyle(),
          child: Text(content.text, style: _textStyle(content)),
        ),
      ),
    ),
  );
}

/// A photo on a page (blank while it loads).
class PageImageView extends ConsumerWidget {
  const PageImageView({required this.path, super.key});

  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final image = ref.watch(coverPhotoProvider(path)).value;
    return image == null
        ? ColoredBox(color: Colors.black.withValues(alpha: 0.06))
        : Image(image: image, fit: BoxFit.fill, gaplessPlayback: true);
  }
}

/// Asks for a text box's text, size and color. Returns null if cancelled;
/// text that's empty after trimming means "remove it".
Future<TextContent?> showTextBoxEditor(
  BuildContext context, {
  TextContent? initial,
}) {
  final inks = NotelySkin.of(context).inkColors;
  return showDialog<TextContent>(
    context: context,
    builder: (context) => _TextBoxEditor(
      initial:
          initial ??
          TextContent(
            text: '',
            fontSize: textSizes[1],
            color: inks.first.toARGB32(),
          ),
      colors: inks,
    ),
  );
}

class _TextBoxEditor extends StatefulWidget {
  const _TextBoxEditor({required this.initial, required this.colors});

  final TextContent initial;
  final List<Color> colors;

  @override
  State<_TextBoxEditor> createState() => _TextBoxEditorState();
}

class _TextBoxEditorState extends State<_TextBoxEditor> {
  late final _text = TextEditingController(text: widget.initial.text);
  late double _size = widget.initial.fontSize;
  late int _color = widget.initial.color;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.initial.text.isEmpty;
    return AlertDialog(
      title: Text(isNew ? 'Add text' : 'Edit text'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _text,
              autofocus: true,
              minLines: 3,
              maxLines: 10,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Type here',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            SegmentedButton<double>(
              showSelectedIcon: false,
              segments: [
                for (final (i, size) in textSizes.indexed)
                  ButtonSegment(
                    value: size,
                    label: Text(const ['Small', 'Medium', 'Large'][i]),
                  ),
              ],
              selected: {textSizes.contains(_size) ? _size : textSizes[1]},
              onSelectionChanged: (s) => setState(() => _size = s.first),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              children: [
                for (final (i, c) in widget.colors.indexed)
                  Semantics(
                    button: true,
                    selected: c.toARGB32() == _color,
                    label: 'Text color ${i + 1}',
                    excludeSemantics: true,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => setState(() => _color = c.toARGB32()),
                      child: CircleAvatar(
                        radius: 14,
                        backgroundColor: c,
                        child: c.toARGB32() == _color
                            ? Icon(
                                Icons.check,
                                size: 16,
                                color:
                                    ThemeData.estimateBrightnessForColor(c) ==
                                        Brightness.dark
                                    ? Colors.white
                                    : Colors.black,
                              )
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            widget.initial.copyWith(
              text: _text.text.trimRight(),
              fontSize: _size,
              color: _color,
            ),
          ),
          child: Text(isNew ? 'Add' : 'Done'),
        ),
      ],
    );
  }
}

/// Asks for new text and places it on [pageId] (in view), then switches to
/// the select tool so it can be moved.
Future<void> addTextBox(
  BuildContext context,
  WidgetRef ref,
  String pageId,
) async {
  final content = await showTextBoxEditor(context);
  if (content == null || content.text.trim().isEmpty) return;
  final fitted = fitTextWidth(content);
  final size = textNaturalSize(fitted);
  ref.read(placementRequestProvider(pageId).notifier).request((
    content: fitted,
    width: size.width,
    height: size.height,
  ));
  ref.read(inkToolProvider.notifier).selectTool(InkToolKind.select);
}

/// Lets the user pick a photo, saves it to their account and places it on
/// [pageId].
Future<void> addPhoto(
  BuildContext context,
  WidgetRef ref,
  String pageId,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final placement = ref.read(placementRequestProvider(pageId).notifier);
  final bytes = await ref.read(photoPickerProvider)(
    maxSize: const Size(2048, 2048),
  );
  if (bytes == null) return;
  messenger.showSnackBar(const SnackBar(content: Text('Adding photo…')));
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final image = (await codec.getNextFrame()).image;
    final aspect = image.width / image.height;
    image.dispose();
    final path = await ref
        .read(coverPhotoStoreProvider)
        .upload(ref.read(currentUidProvider), bytes, folder: 'images');
    const width = 600.0;
    placement.request((
      content: ImageContent(path),
      width: width,
      height: width / aspect,
    ));
    ref.read(inkToolProvider.notifier).selectTool(InkToolKind.select);
    messenger.hideCurrentSnackBar();
  } catch (e) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            'Couldn\'t add the photo. Check your connection and try again.',
          ),
        ),
      );
  }
}
