import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// The objects of a PDF written by the planner engine (or
/// tool/make_planner.py), streams inflated: id to text.
Map<int, String> pdfObjects(Uint8List bytes) {
  final out = <int, String>{};
  final head = RegExp(r'(\d+) 0 obj\n');
  final text = latin1.decode(bytes);
  for (final m in head.allMatches(text)) {
    final id = int.parse(m.group(1)!);
    final start = m.end;
    final end = text.indexOf('\nendobj\n', start);
    var body = text.substring(start, end);
    final s = body.indexOf('stream\n');
    if (s >= 0) {
      final dict = body.substring(0, s);
      final len = int.parse(RegExp(r'/Length (\d+)').firstMatch(dict)!.group(1)!);
      final data = bytes.sublist(start + s + 7, start + s + 7 + len);
      body = '${dict.replaceFirst(RegExp(r'/Length \d+ '), '')}stream\n'
          '${latin1.decode(ZLibDecoder().convert(data))}';
    }
    out[id] = body;
  }
  return out;
}
