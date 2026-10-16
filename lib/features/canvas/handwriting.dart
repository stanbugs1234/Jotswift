import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'domain/stroke.dart';

/// Reads handwriting in a PNG of dark ink on white: its lines of text, top
/// to bottom. Empty when nothing could be read.
typedef HandwritingReader = Future<List<String>> Function(Uint8List png);

const _channel = MethodChannel('notely/handwriting');

/// The device's handwriting reader, or null where there isn't one (it
/// uses Apple's on-device Vision, so iPhone and iPad only). Replaced in
/// tests.
final handwritingReaderProvider = Provider<HandwritingReader?>((ref) {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return null;
  return (png) async =>
      await _channel.invokeListMethod<String>('recognize', {'png': png}) ??
      const [];
});

/// [strokes] drawn dark on white, with a margin, large enough to read:
/// the way a handwriting reader sees writing best. Highlighting is left
/// out.
Future<Uint8List> inkToPng(List<Stroke> strokes) async {
  final ink = [
    for (final s in strokes)
      if (s.tool == InkTool.pen) s,
  ];
  final bounds = ink
      .map((s) => s.bounds.inflate(s.width))
      .reduce((a, b) => a.expandToInclude(b))
      .inflate(24);
  // About 2000 pixels across at most, and never smaller than written.
  final scale = math.min(2.0, 2000 / bounds.width).clamp(0.5, 2.0);
  final width = (bounds.width * scale).ceil();
  final height = (bounds.height * scale).ceil();
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)
    ..drawRect(
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    )
    ..scale(scale)
    ..translate(-bounds.left, -bounds.top);
  // Drawn as even, bold lines: a reader takes thin, tapering ink for
  // noise. About a tenth of a line's height, never thinner than the ink.
  final tallest = ink.map((s) => s.bounds.height).reduce(math.max);
  final black = ui.Paint()
    ..color = const ui.Color(0xFF000000)
    ..style = ui.PaintingStyle.stroke
    ..strokeCap = ui.StrokeCap.round
    ..strokeJoin = ui.StrokeJoin.round;
  for (final s in ink) {
    black.strokeWidth = math.max(s.width, tallest / 10);
    if (s.points.length == 1) {
      canvas.drawCircle(s.points.first.offset, black.strokeWidth / 2, black);
      continue;
    }
    canvas.drawPath(
      ui.Path()..addPolygon([for (final p in s.points) p.offset], false),
      black,
    );
  }
  final image = await recorder.endRecording().toImage(width, height);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

/// Shows the [text] read from handwriting, to correct, then copy or put on
/// the page. Returns the text to put on the page, or null.
Future<String?> showConvertedText(BuildContext context, String text) =>
    showDialog<String>(
      context: context,
      builder: (context) => _ConvertedText(text: text),
    );

class _ConvertedText extends StatefulWidget {
  const _ConvertedText({required this.text});

  final String text;

  @override
  State<_ConvertedText> createState() => _ConvertedTextState();
}

class _ConvertedTextState extends State<_ConvertedText> {
  late final _text = TextEditingController(text: widget.text);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Convert to text'),
    content: SizedBox(
      width: 420,
      child: TextField(
        controller: _text,
        autofocus: false,
        minLines: 2,
        maxLines: 8,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          helperText: 'Fix anything that was misread.',
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      TextButton(
        onPressed: () async {
          final messenger = ScaffoldMessenger.maybeOf(context);
          final navigator = Navigator.of(context);
          await Clipboard.setData(ClipboardData(text: _text.text));
          navigator.pop();
          messenger?.showSnackBar(
            const SnackBar(content: Text('Text copied.')),
          );
        },
        child: const Text('Copy'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(_text.text),
        child: const Text('Replace handwriting'),
      ),
    ],
  );
}
