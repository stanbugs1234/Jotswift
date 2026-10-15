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

/// Something placed on a page besides ink. Stickers for now; images and text
/// boxes later. Drawn under the ink, so you can write over it.
@immutable
class PageElement {
  const PageElement({
    required this.id,
    required this.itemId,
    required this.file,
    required this.frame,
    required this.z,
    required this.createdAt,
    this.deleted = false,
  });

  /// Reads a saved element. Returns null for kinds this version doesn't
  /// know, or if it's damaged.
  static PageElement? fromMap(String id, Map<String, dynamic> map) {
    if (map['kind'] != 'sticker') return null;
    final itemId = map['itemId'], file = map['file'];
    final x = map['x'], y = map['y'], w = map['w'], h = map['h'];
    if (itemId is! String ||
        file is! String ||
        x is! num ||
        y is! num ||
        w is! num ||
        h is! num) {
      return null;
    }
    return PageElement(
      id: id,
      itemId: itemId,
      file: file,
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

  /// The sticker pack (catalog item) and the file in it.
  final String itemId;
  final String file;
  final ElementFrame frame;

  /// Stacking order; higher is on top.
  final double z;
  final int createdAt;

  /// Removed (kept so undo and other devices see it go).
  final bool deleted;

  Map<String, Object?> toMap() => {
    'kind': 'sticker',
    'itemId': itemId,
    'file': file,
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

  PageElement copyWith({ElementFrame? frame, bool? deleted}) => PageElement(
    id: id,
    itemId: itemId,
    file: file,
    frame: frame ?? this.frame,
    z: z,
    createdAt: createdAt,
    deleted: deleted ?? this.deleted,
  );
}
