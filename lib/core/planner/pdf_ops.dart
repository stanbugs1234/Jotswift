/// The drawing layer of the planner engine: pages of raw PDF operators in
/// the built-in fonts, with links between pages, written as one PDF.
///
/// A port of tool/make_planner.py (Page, the style and write_pdf), kept
/// close to it line by line: numbers print as Python prints them (ints as
/// ints, `.1f` for coordinates), so the same planner comes out the same.
library;

import 'dart:convert';
import 'dart:io' show ZLibEncoder;
import 'dart:math' as math;
import 'dart:typed_data';

/// An RGB colour, each part 0-1.
typedef Rgb = (num, num, num);

Rgb hexRgb(String hex) {
  final h = hex.replaceFirst('#', '');
  int part(int i) => int.parse(h.substring(i, i + 2), radix: 16);
  return (part(0) / 255, part(2) / 255, part(4) / 255);
}

String rgbHex(Rgb c) =>
    '#${[c.$1, c.$2, c.$3].map((v) => (v * 255).round().toRadixString(16).padLeft(2, '0')).join().toUpperCase()}';

/// [rgb] mixed toward white by [amount] (0-1).
Rgb tint(Rgb rgb, num amount) => (
  rgb.$1 + (1 - rgb.$1) * amount,
  rgb.$2 + (1 - rgb.$2) * amount,
  rgb.$3 + (1 - rgb.$3) * amount,
);

/// The look of a planner: colours, and a page colour, border, header
/// style, motif and font. The default is Jotswift's plain look.
class PlannerStyle {
  const PlannerStyle({
    this.ink = (0.12, 0.14, 0.19),
    this.soft = (0.55, 0.6, 0.68),
    this.rule = (0.79, 0.84, 0.92),
    this.accent = (0.17, 0.29, 0.49),
    this.tab = (0.93, 0.95, 0.98),
    this.onAccent = (1, 1, 1),
    this.paper,
    this.border = 'none',
    this.header = 'plain',
    this.motif = 'none',
    this.serif = false,
  });

  /// As tool/make_life_planners.py's style(): hex colours, white paper
  /// drawn as nothing.
  factory PlannerStyle.hex({
    required String accent,
    required String tab,
    String paper = '#FFFFFF',
    String ink = '#1F2430',
    String soft = '#8A919C',
    String rule = '#D5D9DF',
    String onAccent = '#FFFFFF',
    String border = 'none',
    String header = 'plain',
    String motif = 'none',
    bool serif = false,
  }) => PlannerStyle(
    ink: hexRgb(ink),
    soft: hexRgb(soft),
    rule: hexRgb(rule),
    accent: hexRgb(accent),
    tab: hexRgb(tab),
    onAccent: onAccent == '#FFFFFF' ? (1, 1, 1) : hexRgb(onAccent),
    paper: paper.toUpperCase() == '#FFFFFF' ? null : hexRgb(paper),
    border: border,
    header: header,
    motif: motif,
    serif: serif,
  );

  factory PlannerStyle.fromMap(Map<String, Object?> m) => PlannerStyle.hex(
    accent: m['accent'] as String? ?? '#2B4A7D',
    tab: m['tab'] as String? ?? '#EDF2FA',
    paper: m['paper'] as String? ?? '#FFFFFF',
    ink: m['ink'] as String? ?? '#1F2430',
    soft: m['soft'] as String? ?? '#8A919C',
    rule: m['rule'] as String? ?? '#D5D9DF',
    onAccent: m['onAccent'] as String? ?? '#FFFFFF',
    border: m['border'] as String? ?? 'none',
    header: m['header'] as String? ?? 'plain',
    motif: m['motif'] as String? ?? 'none',
    serif: m['serif'] == true,
  );

  final Rgb ink, soft, rule, accent, tab, onAccent;

  /// The page colour; null for white, drawn as nothing.
  final Rgb? paper;

  /// none, double, dashed, stitched or hand.
  final String border;

  /// plain, banner, underline or swash.
  final String header;

  /// none, leaves, stars, hearts, dots, sun, waves or moons.
  final String motif;

  /// Times instead of Helvetica.
  final bool serif;

  Map<String, Object?> toMap() => {
    'accent': rgbHex(accent),
    'tab': rgbHex(tab),
    'paper': paper == null ? '#FFFFFF' : rgbHex(paper!),
    'ink': rgbHex(ink),
    'soft': rgbHex(soft),
    'rule': rgbHex(rule),
    'onAccent': rgbHex(onAccent),
    'border': border,
    'header': header,
    'motif': motif,
    'serif': serif,
  };
}

/// A number as Python's str() prints it: ints without a point, floats
/// shortest (1.0, 0.8, 7.4799999999999995).
String py(num n) => n is int ? '$n' : n.toDouble().toString();

/// `{x:.1f}`.
String f1(num n) => _fixed(n, 1);

/// `%.3f`.
String f3(num n) => _fixed(n, 3);

/// [n] to [digits] places, an exact half rounded to even as Python does
/// (45.25 is 45.2), where Dart would round it up.
String _fixed(num n, int digits) {
  final d = n.toDouble();
  final s = d.toStringAsFixed(digits);
  final t = d.abs() * (digits == 1 ? 10 : 1000);
  if ((t - t.floorToDouble() - 0.5).abs() > 1e-6) return s;
  final exact = d.toStringAsFixed(20);
  final cut = exact.indexOf('.') + 1 + digits;
  if (!RegExp(r'^50*$').hasMatch(exact.substring(cut))) return s;
  final kept = exact.substring(0, cut);
  // The digit kept is even: Python rounds the half away (down).
  return int.parse(kept[kept.length - 1]).isEven ? kept : s;
}

const _narrow = "iljtfrI.,:;'!|() ";
const _wide = 'mwMW@%';

/// Helvetica's width of [s] at [size], roughly: enough to centre and fit.
double textWidth(String s, num size) {
  var total = 0;
  for (final ch in s.split('')) {
    total += _narrow.contains(ch)
        ? 278
        : _wide.contains(ch)
        ? 889
        : ch.toLowerCase() != ch
        ? 667
        : 556;
  }
  return total * size / 1000;
}

/// A run of operators drawn the same on many pages (tabs, a day's
/// layout): written once, as a form.
class SharedBlock {
  SharedBlock(this.ops) : key = ops.join('\n');

  final List<String> ops;
  final String key;
}

/// A link area (PDF points, from the bottom left) to the page [target].
typedef PageLinkOut = ({num x0, num y0, num x1, num y1, int target});

/// One page of operators. Made in [style] at [w] x [h] points, with its
/// background, border and corner motifs.
class PlannerPage {
  PlannerPage(this.style, this.w, this.h) {
    _decorate();
  }

  final PlannerStyle style;
  final num w, h;

  /// Operators: strings, or [SharedBlock]s.
  final ops = <Object>[];
  final links = <PageLinkOut>[];

  bool get landscape => w > h;

  void color(Rgb rgb, {bool stroke = false}) => ops.add(
    '${f3(rgb.$1)} ${f3(rgb.$2)} ${f3(rgb.$3)} ${stroke ? 'RG' : 'rg'}',
  );

  void line(num x0, num y0, num x1, num y1, {Rgb? rgb, num width = 0.8}) {
    color(rgb ?? style.rule, stroke: true);
    ops.add('${py(width)} w ${f1(x0)} ${f1(y0)} m ${f1(x1)} ${f1(y1)} l S');
  }

  void rect(
    num x,
    num y,
    num w,
    num h, {
    Rgb? fill,
    Rgb? stroke,
    num width = 0.8,
  }) {
    if (fill != null) color(fill);
    if (stroke != null) {
      color(stroke, stroke: true);
      ops.add('${py(width)} w');
    }
    final op = fill != null && stroke != null
        ? 'B'
        : fill != null
        ? 'f'
        : 'S';
    ops.add('${f1(x)} ${f1(y)} ${f1(w)} ${f1(h)} re $op');
  }

  void text(
    num x,
    num y,
    String s,
    num size, {
    Rgb? rgb,
    bool bold = false,
    bool center = false,
    bool right = false,
  }) {
    if (center) {
      x -= textWidth(s, size) / 2;
    } else if (right) {
      x -= textWidth(s, size);
    }
    final escaped = s
        .replaceAll(r'\', r'\\')
        .replaceAll('(', r'\(')
        .replaceAll(')', r'\)');
    color(rgb ?? style.ink);
    ops.add(
      'BT /${bold ? 'F2' : 'F1'} ${py(size)} Tf ${f1(x)} ${f1(y)} Td ($escaped) Tj ET',
    );
  }

  /// Links the area to page [target]; nothing if there's no such page.
  void link(num x, num y, num w, num h, int? target) {
    if (target == null) return;
    links.add((x0: x, y0: y, x1: x + w, y1: y + h, target: target));
  }

  /// Runs [draw] and keeps what it drew as one block.
  void shared(void Function() draw) {
    final start = ops.length;
    draw();
    final drawn = ops.sublist(start);
    ops.removeRange(start, ops.length);
    if (drawn.isEmpty) return;
    ops.add(
      SharedBlock([
        for (final op in drawn)
          if (op is SharedBlock) ...op.ops else op as String,
      ]),
    );
  }

  void _decorate() {
    if (style.paper case final paper?) rect(0, 0, w, h, fill: paper);
    if (style.border != 'none') _border(16);
    if (style.motif != 'none') {
      final light = tint(style.accent, 0.35);
      for (final (x, y, size) in [
        (w - 30, 30, 16),
        (w - 52, 24, 9),
        (30, h - 30, 12),
      ]) {
        motifShape(this, style.motif, x, y, size, light);
      }
    }
  }

  void _border(num inset) {
    final (x0, y0, x1, y1) = (inset, inset, w - inset, h - inset);
    final rgb = tint(style.accent, 0.45);
    switch (style.border) {
      case 'double':
        rect(x0, y0, x1 - x0, y1 - y0, stroke: rgb, width: 1.4);
        rect(
          x0 + 5,
          y0 + 5,
          x1 - x0 - 10,
          y1 - y0 - 10,
          stroke: rgb,
          width: 0.6,
        );
      case 'dashed' || 'stitched':
        final dash = style.border == 'dashed' ? '[6 4] 0 d' : '[3 3] 0 d';
        color(rgb, stroke: true);
        ops.add(
          '$dash 1 w ${f1(x0)} ${f1(y0)} ${f1(x1 - x0)} ${f1(y1 - y0)} re S [] 0 d',
        );
      case 'hand':
        // A slightly wobbly line, like a pen-drawn frame; repeatable.
        final rnd = math.Random(ops.length);
        num wobble() => rnd.nextDouble() * 2.4 - 1.2;
        final corners = [(x0, y0), (x1, y0), (x1, y1), (x0, y1), (x0, y0)];
        final pts = <(num, num)>[];
        for (var k = 0; k + 1 < corners.length; k++) {
          final (ax, ay) = corners[k];
          final (bx, by) = corners[k + 1];
          for (var i = 0; i < 12; i++) {
            final t = i / 12;
            pts.add((
              ax + (bx - ax) * t + wobble(),
              ay + (by - ay) * t + wobble(),
            ));
          }
        }
        polygon(this, pts, rgb, fill: false, width: 1.1);
    }
  }
}

/// A path through Bezier segments: [start], then (c1, c2, end) each.
void curve(
  PlannerPage p,
  (num, num) start,
  List<((num, num), (num, num), (num, num))> segments,
  Rgb rgb,
  num width, {
  bool fill = false,
  bool close = false,
}) {
  p.color(rgb, stroke: !fill);
  final ops = ['${f1(start.$1)} ${f1(start.$2)} m'];
  for (final (c1, c2, end) in segments) {
    ops.add(
      '${f1(c1.$1)} ${f1(c1.$2)} ${f1(c2.$1)} ${f1(c2.$2)} '
      '${f1(end.$1)} ${f1(end.$2)} c',
    );
  }
  if (fill) {
    p.ops.add('${ops.join(' ')} f');
  } else {
    p.ops.add('${py(width)} w 1 J ${ops.join(' ')}${close ? ' h S' : ' S'}');
  }
}

void circle(
  PlannerPage p,
  num x,
  num y,
  num r,
  Rgb rgb, {
  bool fill = true,
  num width = 1,
}) {
  final k = 0.5523 * r;
  curve(
    p,
    (x + r, y),
    [
      ((x + r, y + k), (x + k, y + r), (x, y + r)),
      ((x - k, y + r), (x - r, y + k), (x - r, y)),
      ((x - r, y - k), (x - k, y - r), (x, y - r)),
      ((x + k, y - r), (x + r, y - k), (x + r, y)),
    ],
    rgb,
    width,
    fill: fill,
    close: true,
  );
}

void polygon(
  PlannerPage p,
  List<(num, num)> pts,
  Rgb rgb, {
  bool fill = true,
  num width = 1,
}) {
  p.color(rgb, stroke: !fill);
  final path = [
    for (final (i, (x, y)) in pts.indexed)
      '${f1(x)} ${f1(y)} ${i == 0 ? 'm' : 'l'}',
  ].join(' ');
  p.ops.add(fill ? '$path h f' : '${py(width)} w 1 j $path h S');
}

/// One decorative shape centred on (x, y).
void motifShape(PlannerPage p, String kind, num x, num y, num size, Rgb rgb) {
  final r = size / 2;
  switch (kind) {
    case 'stars':
      polygon(p, [
        for (var i = 0; i < 10; i++)
          (
            x +
                (i.isEven ? r : r * 0.45) *
                    math.cos(math.pi / 2 + i * math.pi / 5),
            y +
                (i.isEven ? r : r * 0.45) *
                    math.sin(math.pi / 2 + i * math.pi / 5),
          ),
      ], rgb);
    case 'hearts':
      curve(
        p,
        (x, y - r * 0.9),
        [
          (
            (x - r * 1.2, y + r * 0.1),
            (x - r * 0.6, y + r * 1.1),
            (x, y + r * 0.45),
          ),
          (
            (x + r * 0.6, y + r * 1.1),
            (x + r * 1.2, y + r * 0.1),
            (x, y - r * 0.9),
          ),
        ],
        rgb,
        1,
        fill: true,
      );
    case 'leaves':
      curve(
        p,
        (x - r, y - r),
        [
          (
            (x - r * 0.2, y - r * 0.9),
            (x + r * 0.9, y + r * 0.2),
            (x + r, y + r),
          ),
          (
            (x + r * 0.2, y + r * 0.9),
            (x - r * 0.9, y - r * 0.2),
            (x - r, y - r),
          ),
        ],
        rgb,
        1,
        fill: true,
      );
      p.line(
        x - r,
        y - r,
        x + r * 0.7,
        y + r * 0.7,
        rgb: tint(rgb, 0.55),
        width: 0.6,
      );
    case 'sun':
      circle(p, x, y, r * 0.45, rgb);
      for (var i = 0; i < 8; i++) {
        final a = i * math.pi / 4;
        p.line(
          x + r * 0.62 * math.cos(a),
          y + r * 0.62 * math.sin(a),
          x + r * math.cos(a),
          y + r * math.sin(a),
          rgb: rgb,
          width: 1.2,
        );
      }
    case 'waves':
      for (var k = 0; k < 3; k++) {
        final yy = y - r * 0.6 + k * r * 0.6;
        curve(
          p,
          (x - r, yy),
          [
            ((x - r / 2, yy + r * 0.3), (x - r / 2, yy - r * 0.3), (x, yy)),
            ((x + r / 2, yy + r * 0.3), (x + r / 2, yy - r * 0.3), (x + r, yy)),
          ],
          rgb,
          1.1,
        );
      }
    case 'dots':
      for (final (dx, dy) in [(-0.5, -0.5), (0.5, -0.5), (0, 0.4)]) {
        circle(p, x + dx * r, y + dy * r, r * 0.28, rgb);
      }
    case 'moons':
      circle(p, x, y, r * 0.7, rgb);
      circle(p, x + r * 0.32, y + r * 0.2, r * 0.6, p.style.paper ?? (1, 1, 1));
  }
}

/// A page title in the style's header look.
void header(PlannerPage p, num x, num y, String title, num size) {
  final s = p.style;
  if (s.header == 'banner') {
    final w = textWidth(title, size) + size;
    p.rect(x - size * 0.4, y - size * 0.32, w, size * 1.25, fill: s.accent);
    p.text(x + size * 0.1, y, title, size, rgb: s.onAccent, bold: true);
    return;
  }
  p.text(x, y, title, size, rgb: s.accent, bold: true);
  if (s.header == 'underline') {
    p.line(
      x,
      y - size * 0.3,
      x + textWidth(title, size),
      y - size * 0.3,
      rgb: s.accent,
      width: 2,
    );
  } else if (s.header == 'swash') {
    final w = textWidth(title, size);
    curve(
      p,
      (x, y - size * 0.32),
      [
        (
          (x + w * 0.35, y - size * 0.6),
          (x + w * 0.7, y - size * 0.05),
          (x + w + 10, y - size * 0.35),
        ),
      ],
      tint(s.accent, 0.2),
      1.6,
    );
    if (s.motif != 'none') {
      motifShape(
        p,
        s.motif,
        x + w + 22,
        y + size * 0.3,
        size * 0.45,
        tint(s.accent, 0.3),
      );
    }
  }
}

const _cp1252 = {
  0x20AC: 0x80, 0x201A: 0x82, 0x0192: 0x83, 0x201E: 0x84, 0x2026: 0x85, //
  0x2020: 0x86, 0x2021: 0x87, 0x02C6: 0x88, 0x2030: 0x89, 0x0160: 0x8A,
  0x2039: 0x8B, 0x0152: 0x8C, 0x017D: 0x8E, 0x2018: 0x91, 0x2019: 0x92,
  0x201C: 0x93, 0x201D: 0x94, 0x2022: 0x95, 0x2013: 0x96, 0x2014: 0x97,
  0x02DC: 0x98, 0x2122: 0x99, 0x0161: 0x9A, 0x203A: 0x9B, 0x0153: 0x9C,
  0x017E: 0x9E, 0x0178: 0x9F,
};

/// [s] in the fonts' WinAnsi encoding; characters it hasn't (emoji, most
/// scripts) become "?".
List<int> winAnsi(String s) => [
  for (final r in s.runes) r <= 0xFF ? r : _cp1252[r] ?? 0x3F,
];

/// [pages] as one PDF, blocks drawn the same on many pages stored once (as
/// Form XObjects). Link targets are page indexes.
Uint8List writePdf(List<PlannerPage> pages, PlannerStyle style) {
  final forms = <String, int>{};
  final formOps = <String>[];
  for (final p in pages) {
    for (final op in p.ops) {
      if (op is SharedBlock && !forms.containsKey(op.key)) {
        forms[op.key] = forms.length;
        formOps.add(op.key);
      }
    }
  }
  final objs = <int, List<int>>{};
  void put(int id, String s) => objs[id] = winAnsi(s);
  const firstForm = 5;
  final firstPage = firstForm + forms.length;
  final pageIds = [for (var i = 0; i < pages.length; i++) firstPage + 2 * i];
  final annotIds = <List<int>>[];
  var nextId = firstPage + 2 * pages.length;
  for (final p in pages) {
    annotIds.add([for (var k = 0; k < p.links.length; k++) nextId + k]);
    nextId += p.links.length;
  }
  final zlib = ZLibEncoder(level: 9);
  List<int> stream(String text, [String head = '']) {
    final data = zlib.convert(winAnsi(text));
    return [
      ...latin1.encode(
        '<< $head/Length ${data.length} /Filter /FlateDecode >>\nstream\n',
      ),
      ...data,
      ...latin1.encode('\nendstream'),
    ];
  }

  const fonts = '/Font << /F1 3 0 R /F2 4 0 R >>';
  put(1, '<< /Type /Catalog /Pages 2 0 R >>');
  put(
    2,
    '<< /Type /Pages /Kids [${pageIds.map((id) => '$id 0 R').join(' ')}] '
    '/Count ${pages.length} >>',
  );
  final (regular, bold) = style.serif
      ? ('Times-Roman', 'Times-Bold')
      : ('Helvetica', 'Helvetica-Bold');
  put(
    3,
    '<< /Type /Font /Subtype /Type1 /BaseFont /$regular /Encoding /WinAnsiEncoding >>',
  );
  put(
    4,
    '<< /Type /Font /Subtype /Type1 /BaseFont /$bold /Encoding /WinAnsiEncoding >>',
  );
  final (w, h) = pages.isEmpty ? (612, 792) : (pages.first.w, pages.first.h);
  for (final (k, ops) in formOps.indexed) {
    objs[firstForm + k] = stream(
      ops,
      '/Type /XObject /Subtype /Form /BBox [-20 -20 ${py(w + 20)} ${py(h + 20)}] '
      '/Resources << $fonts >> ',
    );
  }
  for (final (i, p) in pages.indexed) {
    final pid = pageIds[i];
    final annots = annotIds[i].map((a) => '$a 0 R').join(' ');
    final used = {
      for (final op in p.ops)
        if (op is SharedBlock) forms[op.key]!,
    }.toList()..sort();
    final xo = used.isEmpty
        ? ''
        : ' /XObject << ${used.map((k) => '/X$k ${firstForm + k} 0 R').join(' ')} >>';
    put(
      pid,
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${py(p.w)} ${py(p.h)}] '
      '/Resources << $fonts$xo >> /Contents ${pid + 1} 0 R /Annots [$annots] >>',
    );
    objs[pid + 1] = stream(
      p.ops
          .map(
            (op) => op is SharedBlock ? '/X${forms[op.key]} Do' : op as String,
          )
          .join('\n'),
    );
    for (final (k, l) in p.links.indexed) {
      put(
        annotIds[i][k],
        '<< /Type /Annot /Subtype /Link /Rect [${f1(l.x0)} ${f1(l.y0)} ${f1(l.x1)} ${f1(l.y1)}] '
        '/Border [0 0 0] /Dest [${pageIds[l.target]} 0 R /Fit] >>',
      );
    }
  }

  final out = BytesBuilder(copy: false)
    ..add(latin1.encode('%PDF-1.4\n'))
    ..add([0x25, 0xe2, 0xe3, 0xcf, 0xd3, 0x0a]);
  final ids = objs.keys.toList()..sort();
  final offsets = <int, int>{};
  for (final id in ids) {
    offsets[id] = out.length;
    out
      ..add(latin1.encode('$id 0 obj\n'))
      ..add(objs[id]!)
      ..add(latin1.encode('\nendobj\n'));
  }
  final xref = out.length;
  final count = ids.last + 1;
  final table = StringBuffer('xref\n0 $count\n0000000000 65535 f \n');
  for (var id = 1; id < count; id++) {
    table.write('${offsets[id].toString().padLeft(10, '0')} 00000 n \n');
  }
  table.write(
    'trailer\n<< /Size $count /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n',
  );
  out.add(latin1.encode(table.toString()));
  return out.takeBytes();
}
