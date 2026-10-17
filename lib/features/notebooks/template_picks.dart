import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/synced_setting.dart';

/// A page of a catalog template, remembered by the New page sheet.
@immutable
class TemplatePick {
  const TemplatePick({
    required this.itemId,
    required this.pdfPage,
    required this.title,
  });

  static TemplatePick? fromMap(Object? map) => switch (map) {
    {'i': final String i, 'p': final int p, 't': final String t} =>
      TemplatePick(itemId: i, pdfPage: p, title: t),
    _ => null,
  };

  final String itemId;
  final int pdfPage;
  final String title;

  Map<String, Object> toMap() => {'i': itemId, 'p': pdfPage, 't': title};

  @override
  bool operator ==(Object other) =>
      other is TemplatePick &&
      other.itemId == itemId &&
      other.pdfPage == pdfPage;

  @override
  int get hashCode => Object.hash(itemId, pdfPage);
}

List<TemplatePick> _decode(String json) {
  try {
    return [for (final m in jsonDecode(json) as List) ?TemplatePick.fromMap(m)];
  } on Object {
    return const [];
  }
}

String _encode(List<TemplatePick> picks) =>
    jsonEncode([for (final p in picks) p.toMap()]);

/// Template pages the user starred, newest first. Saved on the account.
class FavoriteTemplatePages extends SyncedSetting {
  @override
  String get key => 'favoriteTemplatePages';

  @override
  String get defaultValue => '[]';

  List<TemplatePick> get picks => _decode(state);

  bool isFavorite(TemplatePick pick) => picks.contains(pick);

  Future<void> toggle(TemplatePick pick) {
    final now = picks;
    return save(
      _encode(
        now.contains(pick) ? [...now.where((p) => p != pick)] : [pick, ...now],
      ),
    );
  }
}

final favoriteTemplatePagesProvider =
    NotifierProvider<FavoriteTemplatePages, String>(FavoriteTemplatePages.new);

/// Template pages added most recently, newest first, at most [max].
class RecentTemplatePages extends SyncedSetting {
  static const max = 12;

  @override
  String get key => 'recentTemplatePages';

  @override
  String get defaultValue => '[]';

  List<TemplatePick> get picks => _decode(state);

  Future<void> add(TemplatePick pick) => save(
    _encode([pick, ...picks.where((p) => p != pick)].take(max).toList()),
  );
}

final recentTemplatePagesProvider =
    NotifierProvider<RecentTemplatePages, String>(RecentTemplatePages.new);
