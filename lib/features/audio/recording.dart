import 'package:flutter/foundation.dart';

/// A sound recording made while writing in a notebook. Strokes written
/// during it remember when (see `Stroke.audioId` and `Stroke.audioAt`), so
/// playing it back shows the writing as it was written.
@immutable
class Recording {
  const Recording({
    required this.id,
    required this.path,
    required this.durationMs,
    required this.createdAt,
    this.pageId,
  });

  static Recording? fromMap(String id, Map<String, dynamic> map) {
    final path = map['path'], duration = map['durationMs'];
    if (path is! String || duration is! num) return null;
    return Recording(
      id: id,
      path: path,
      durationMs: duration.toInt(),
      createdAt: map['createdAt'] as int? ?? 0,
      pageId: map['pageId'] as String?,
    );
  }

  final String id;

  /// Where the sound is kept (in Cloud Storage).
  final String path;
  final int durationMs;
  final int createdAt;

  /// The page it was started on.
  final String? pageId;

  Duration get duration => Duration(milliseconds: durationMs);

  Map<String, Object?> toMap() => {
    'path': path,
    'durationMs': durationMs,
    'createdAt': createdAt,
    'pageId': ?pageId,
  };
}
