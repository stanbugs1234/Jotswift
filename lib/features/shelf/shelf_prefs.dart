import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/synced_setting.dart';
import 'shelf_view.dart';

/// How the shelf is shown. Saved on this device only: a phone and a tablet
/// can sensibly differ.
@immutable
class ShelfPrefs {
  const ShelfPrefs({
    this.sort = ShelfSort.custom,
    this.layout = ShelfLayout.grid,
    this.size = ShelfSize.large,
  });

  final ShelfSort sort;
  final ShelfLayout layout;
  final ShelfSize size;

  ShelfPrefs copyWith({
    ShelfSort? sort,
    ShelfLayout? layout,
    ShelfSize? size,
  }) => ShelfPrefs(
    sort: sort ?? this.sort,
    layout: layout ?? this.layout,
    size: size ?? this.size,
  );
}

class ShelfPrefsController extends Notifier<ShelfPrefs> {
  static const _sortKey = 'shelfSort';
  static const _layoutKey = 'shelfLayout';
  static const _sizeKey = 'shelfSize';

  @override
  ShelfPrefs build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    T read<T extends Enum>(String key, List<T> values, T fallback) =>
        values.where((v) => v.name == prefs.getString(key)).firstOrNull ??
        fallback;
    return ShelfPrefs(
      sort: read(_sortKey, ShelfSort.values, ShelfSort.custom),
      layout: read(_layoutKey, ShelfLayout.values, ShelfLayout.grid),
      size: read(_sizeKey, ShelfSize.values, ShelfSize.large),
    );
  }

  void setSort(ShelfSort sort) =>
      _set(_sortKey, sort, state.copyWith(sort: sort));

  void setLayout(ShelfLayout layout) =>
      _set(_layoutKey, layout, state.copyWith(layout: layout));

  void setSize(ShelfSize size) =>
      _set(_sizeKey, size, state.copyWith(size: size));

  void _set(String key, Enum value, ShelfPrefs next) {
    state = next;
    ref.read(sharedPreferencesProvider).setString(key, value.name);
  }
}

final shelfPrefsProvider = NotifierProvider<ShelfPrefsController, ShelfPrefs>(
  ShelfPrefsController.new,
);
