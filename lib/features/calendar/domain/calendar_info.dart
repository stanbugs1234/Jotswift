import 'package:flutter/foundation.dart';

import '../../notebooks/domain/notebook_models.dart' show notebookColors;

/// The calendar every event belongs to unless it says otherwise. It can be
/// renamed and recoloured but not deleted.
const personalCalendarId = 'personal';

/// Colours a calendar can have.
const calendarColors = [
  ...notebookColors,
  0xFF4A90D9, // sky
  0xFFE07B39, // orange
  0xFFD9558A, // pink
  0xFF7A8B3A, // olive
];

/// Suggestions for a new calendar's name, with a colour each.
const calendarPresets = [
  ('Work', 0xFF1F8A99),
  ('Family', 0xFFE07B39),
  ('School', 0xFF7B4FA0),
  ('Health', 0xFF2E7D5B),
  ('Birthdays', 0xFFD9558A),
];

/// A colour-coded group of events, such as Work or Family, that can be
/// shown or hidden.
@immutable
class CalendarInfo {
  const CalendarInfo({
    required this.id,
    required this.name,
    required this.color,
    this.visible = true,
    this.order = 0,
  });

  /// Personal, as it is before the user changes it.
  static const personal = CalendarInfo(
    id: personalCalendarId,
    name: 'Personal',
    color: 0xFF2C4A7C,
  );

  static CalendarInfo? fromMap(String id, Map<String, dynamic> map) {
    final name = map['name'];
    final color = map['color'];
    if (name is! String || color is! int) return null;
    return CalendarInfo(
      id: id,
      name: name,
      color: color,
      visible: map['visible'] as bool? ?? true,
      order: (map['order'] as num?)?.toDouble() ?? 0,
    );
  }

  final String id;
  final String name;

  /// ARGB.
  final int color;

  /// Whether its events show in the Calendar and the Planner. Reminders go
  /// off either way.
  final bool visible;

  /// Position in the list; Personal comes first unless moved.
  final double order;

  Map<String, Object?> toMap() => {
    'name': name,
    'color': color,
    'visible': visible,
    'order': order,
  };

  CalendarInfo copyWith({
    String? name,
    int? color,
    bool? visible,
    double? order,
  }) => CalendarInfo(
    id: id,
    name: name ?? this.name,
    color: color ?? this.color,
    visible: visible ?? this.visible,
    order: order ?? this.order,
  );

  @override
  bool operator ==(Object other) =>
      other is CalendarInfo &&
      other.id == id &&
      other.name == name &&
      other.color == color &&
      other.visible == visible &&
      other.order == order;

  @override
  int get hashCode => Object.hash(id, name, color, visible, order);
}
