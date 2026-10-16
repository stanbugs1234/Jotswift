import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

/// Where an element sits on a page, in page units: its center, size and
/// rotation (radians, clockwise).
@immutable
class ElementFrame {
  const ElementFrame({
    required this.center,
    required this.width,
    required this.height,
    this.rotation = 0,
  });

  final Offset center;
  final double width;
  final double height;
  final double rotation;

  /// [page] in the element's own coordinates (origin at its center, axes
  /// along its sides).
  Offset toLocal(Offset page) {
    final d = page - center;
    final c = math.cos(-rotation), s = math.sin(-rotation);
    return Offset(d.dx * c - d.dy * s, d.dx * s + d.dy * c);
  }

  /// A point in the element's own coordinates, on the page.
  Offset toPage(Offset local) {
    final c = math.cos(rotation), s = math.sin(rotation);
    return center +
        Offset(local.dx * c - local.dy * s, local.dx * s + local.dy * c);
  }

  bool contains(Offset page, {double slop = 0}) {
    final p = toLocal(page);
    return p.dx.abs() <= width / 2 + slop && p.dy.abs() <= height / 2 + slop;
  }

  ElementFrame copyWith({
    Offset? center,
    double? width,
    double? height,
    double? rotation,
  }) => ElementFrame(
    center: center ?? this.center,
    width: width ?? this.width,
    height: height ?? this.height,
    rotation: rotation ?? this.rotation,
  );

  @override
  bool operator ==(Object other) =>
      other is ElementFrame &&
      other.center == center &&
      other.width == width &&
      other.height == height &&
      other.rotation == rotation;

  @override
  int get hashCode => Object.hash(center, width, height, rotation);
}

/// What an element shows.
sealed class ElementContent {
  const ElementContent();

  /// Reads the content of a saved element; null for kinds this version
  /// doesn't know, or if it's damaged.
  static ElementContent? fromMap(Map<String, dynamic> map) {
    switch (map['kind']) {
      case 'sticker':
        final itemId = map['itemId'], file = map['file'];
        if (itemId is! String || file is! String) return null;
        return StickerContent(itemId: itemId, file: file);
      case 'image':
        final path = map['path'];
        if (path is! String) return null;
        return ImageContent(path);
      case 'link':
        final pageId = map['pageId'];
        if (pageId is! String) return null;
        return LinkContent(pageId);
      case 'tape':
        final color = map['color'];
        if (color is! int) return null;
        return TapeContent(
          color: color,
          pattern:
              TapePattern.values.asNameMap()[map['pattern']] ??
              TapePattern.solid,
          revealed: map['revealed'] == true,
        );
      case 'text':
        final text = map['text'];
        if (text is! String) return null;
        return TextContent(
          text: text,
          fontSize: (map['fontSize'] as num?)?.toDouble() ?? 36,
          color: map['color'] as int? ?? 0xFF000000,
          layoutWidth: (map['layoutWidth'] as num?)?.toDouble() ?? 600,
        );
    }
    return null;
  }

  Map<String, Object?> toMap();
}

/// A sticker from a sticker pack (catalog item).
@immutable
class StickerContent extends ElementContent {
  const StickerContent({required this.itemId, required this.file});

  final String itemId;
  final String file;

  @override
  Map<String, Object?> toMap() => {
    'kind': 'sticker',
    'itemId': itemId,
    'file': file,
  };

  @override
  bool operator ==(Object other) =>
      other is StickerContent && other.itemId == itemId && other.file == file;

  @override
  int get hashCode => Object.hash(itemId, file);
}

/// A photo the user added, kept in Cloud Storage at [path].
@immutable
class ImageContent extends ElementContent {
  const ImageContent(this.path);

  final String path;

  @override
  Map<String, Object?> toMap() => {'kind': 'image', 'path': path};

  @override
  bool operator ==(Object other) => other is ImageContent && other.path == path;

  @override
  int get hashCode => path.hashCode;
}

/// A link to another page of the notebook: an area that opens [pageId]
/// when tapped. Not printed.
@immutable
class LinkContent extends ElementContent {
  const LinkContent(this.pageId);

  final String pageId;

  @override
  Map<String, Object?> toMap() => {'kind': 'link', 'pageId': pageId};

  @override
  bool operator ==(Object other) =>
      other is LinkContent && other.pageId == pageId;

  @override
  int get hashCode => pageId.hashCode;
}

/// How a strip of tape is printed.
enum TapePattern { solid, stripes, dots, grid }

/// A strip of tape over the page, hiding what's under it until it's
/// tapped (for answers to test yourself on). Drawn over the ink.
@immutable
class TapeContent extends ElementContent {
  const TapeContent({
    required this.color,
    this.pattern = TapePattern.solid,
    this.revealed = false,
  });

  /// ARGB.
  final int color;
  final TapePattern pattern;

  /// Peeled back: what's under it shows, with the tape's outline.
  final bool revealed;

  TapeContent toggled() =>
      TapeContent(color: color, pattern: pattern, revealed: !revealed);

  @override
  Map<String, Object?> toMap() => {
    'kind': 'tape',
    'color': color,
    'pattern': pattern.name,
    'revealed': revealed,
  };

  @override
  bool operator ==(Object other) =>
      other is TapeContent &&
      other.color == color &&
      other.pattern == pattern &&
      other.revealed == revealed;

  @override
  int get hashCode => Object.hash(color, pattern, revealed);
}

/// Typed text. It wraps at [layoutWidth] page units with [fontSize], and the
/// frame scales the result, so resizing a text box scales its text.
@immutable
class TextContent extends ElementContent {
  const TextContent({
    required this.text,
    required this.fontSize,
    required this.color,
    this.layoutWidth = 600,
  });

  final String text;
  final double fontSize;

  /// ARGB.
  final int color;
  final double layoutWidth;

  TextContent copyWith({String? text, double? fontSize, int? color}) =>
      TextContent(
        text: text ?? this.text,
        fontSize: fontSize ?? this.fontSize,
        color: color ?? this.color,
        layoutWidth: layoutWidth,
      );

  @override
  Map<String, Object?> toMap() => {
    'kind': 'text',
    'text': text,
    'fontSize': fontSize,
    'color': color,
    'layoutWidth': layoutWidth,
  };

  @override
  bool operator ==(Object other) =>
      other is TextContent &&
      other.text == text &&
      other.fontSize == fontSize &&
      other.color == color &&
      other.layoutWidth == layoutWidth;

  @override
  int get hashCode => Object.hash(text, fontSize, color, layoutWidth);
}

/// Something placed on a page besides ink: a sticker, a photo or a text
/// box. Drawn under the ink, so you can write over it.
@immutable
class PageElement {
  const PageElement({
    required this.id,
    required this.content,
    required this.frame,
    required this.z,
    required this.createdAt,
    this.deleted = false,
  });

  /// Reads a saved element. Returns null for kinds this version doesn't
  /// know, or if it's damaged.
  static PageElement? fromMap(String id, Map<String, dynamic> map) {
    final content = ElementContent.fromMap(map);
    final x = map['x'], y = map['y'], w = map['w'], h = map['h'];
    if (content == null || x is! num || y is! num || w is! num || h is! num) {
      return null;
    }
    return PageElement(
      id: id,
      content: content,
      frame: ElementFrame(
        center: Offset(x.toDouble(), y.toDouble()),
        width: w.toDouble(),
        height: h.toDouble(),
        rotation: (map['rotation'] as num?)?.toDouble() ?? 0,
      ),
      z: (map['z'] as num?)?.toDouble() ?? 0,
      createdAt: map['createdAt'] as int? ?? 0,
      deleted: map['deleted'] == true,
    );
  }

  final String id;
  final ElementContent content;
  final ElementFrame frame;

  /// Stacking order; higher is on top.
  final double z;
  final int createdAt;

  /// Removed (kept so undo and other devices see it go).
  final bool deleted;

  Map<String, Object?> toMap() => {
    ...content.toMap(),
    ...frameToMap(frame),
    'z': z,
    'createdAt': createdAt,
    'deleted': deleted,
  };

  static Map<String, Object?> frameToMap(ElementFrame f) => {
    'x': f.center.dx,
    'y': f.center.dy,
    'w': f.width,
    'h': f.height,
    'rotation': f.rotation,
  };

  PageElement copyWith({
    ElementContent? content,
    ElementFrame? frame,
    bool? deleted,
  }) => PageElement(
    id: id,
    content: content ?? this.content,
    frame: frame ?? this.frame,
    z: z,
    createdAt: createdAt,
    deleted: deleted ?? this.deleted,
  );
}
