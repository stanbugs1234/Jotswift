import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/entitlements/entitlements.dart';
import '../../../core/settings/synced_setting.dart';
import '../../../core/settings/user_settings_repository.dart';
import '../../../core/skins/skin_providers.dart';
import 'calendar_template.dart';

/// Whether [template] may be used: free, in Pro, or bought on its own or
/// in the bundle.
bool canUseCalendarTemplate(Entitlements e, CalendarTemplate template) =>
    template.free ||
    e.pro ||
    e.owns(template.productId!) ||
    e.owns(calendarTemplatesBundle);

/// The Calendar template chosen on the account.
class CalendarTemplateController extends SyncedSetting {
  @override
  String get key => SettingKeys.calendarTemplate;

  @override
  String get defaultValue => classicCalendar.id;

  Future<void> select(CalendarTemplate template) => save(template.id);
}

final calendarTemplateSettingProvider =
    NotifierProvider<CalendarTemplateController, String>(
      CalendarTemplateController.new,
    );

/// The template the Calendar uses: the chosen one if it's unlocked,
/// otherwise Classic (so a lapsed purchase never breaks the Calendar).
final calendarTemplateProvider = Provider<CalendarTemplate>((ref) {
  final chosen = calendarTemplateById(
    ref.watch(calendarTemplateSettingProvider),
  );
  return canUseCalendarTemplate(ref.watch(entitlementsProvider), chosen)
      ? chosen
      : classicCalendar;
});

/// Puts [template] where Calendar views can read its details, and themes
/// [child] with its colours and fonts.
class CalendarLook extends ConsumerWidget {
  const CalendarLook({required this.template, required this.child, super.key});

  final CalendarTemplate template;
  final Widget child;

  /// The template in effect, or Classic outside a [CalendarLook].
  static CalendarTemplate of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_LookScope>()?.template ??
      classicCalendar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final base = Theme.of(context);
    final look =
        identical(template, classicCalendar) &&
            base.brightness == Brightness.dark
        ? classicDarkCalendar
        : template;
    return Theme(
      data: look.theme(base, ref.watch(fontResolverProvider)),
      child: _LookScope(template: look, child: child),
    );
  }
}

class _LookScope extends InheritedWidget {
  const _LookScope({required this.template, required super.child});

  final CalendarTemplate template;

  @override
  // Not ==, which compares ids: Seasons recolours the same template.
  bool updateShouldNotify(_LookScope old) => !identical(old.template, template);
}

/// A day number marked as today in the template's way.
class TodayMark extends StatelessWidget {
  const TodayMark({
    required this.text,
    required this.style,
    this.size = 22,
    super.key,
  });

  final String text;
  final TextStyle? style;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = CalendarLook.of(context);
    final filled = switch (t.today) {
      TodayMarker.pill ||
      TodayMarker.circle ||
      TodayMarker.square ||
      TodayMarker.star => true,
      _ => false,
    };
    // Shrinks to fit small markers, such as in previews.
    final label = FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        text,
        maxLines: 1,
        style: style?.copyWith(
          color: filled ? t.onAccent : t.accent,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    return switch (t.today) {
      TodayMarker.pill => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5),
        decoration: BoxDecoration(
          color: t.accent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: label,
      ),
      TodayMarker.circle || TodayMarker.square => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: t.accent,
          shape: t.today == TodayMarker.circle
              ? BoxShape.circle
              : BoxShape.rectangle,
        ),
        child: label,
      ),
      TodayMarker.underline => Container(
        padding: const EdgeInsets.only(bottom: 1),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: t.accent, width: 2)),
        ),
        child: label,
      ),
      TodayMarker.ring => CustomPaint(
        painter: _HandRing(t.accent),
        child: SizedBox(
          width: size + 4,
          height: size,
          child: Center(child: label),
        ),
      ),
      TodayMarker.star => CustomPaint(
        painter: _Star(t.accent),
        child: SizedBox(
          width: size + 6,
          height: size + 6,
          child: Center(child: label),
        ),
      ),
    };
  }
}

class _HandRing extends CustomPainter {
  _HandRing(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final c = size.center(Offset.zero);
    final path = Path();
    // A little more than a full turn, slightly wobbly, like a pen circle.
    for (var i = 0; i <= 64; i++) {
      final a = -math.pi / 2 + i / 56 * 2 * math.pi;
      final r = 1 + 0.06 * math.sin(i * 0.9);
      final p =
          c +
          Offset(
            size.width / 2 * r * math.cos(a),
            size.height / 2 * r * math.sin(a),
          );
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_HandRing old) => old.color != color;
}

class _Star extends CustomPainter {
  _Star(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final rr = i.isEven ? r : r * 0.55;
      final a = -math.pi / 2 + i * math.pi / 5;
      final p = c + Offset(rr * math.cos(a), rr * math.sin(a));
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path..close(), Paint()..color = color);
  }

  @override
  bool shouldRepaint(_Star old) => old.color != color;
}

/// The edges of a day cell in the template's line style.
class CellEdges extends CustomPainter {
  CellEdges(this.style, this.color, {this.seed = 0});

  final CalendarGridLines style;
  final Color color;

  /// Varies the wobble of hand-drawn lines from cell to cell.
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    if (style == CalendarGridLines.none) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = style == CalendarGridLines.hand ? 0.9 : 0.5
      ..style = PaintingStyle.stroke;
    final edges = [
      (Offset(size.width, 0), Offset(size.width, size.height)),
      (Offset(0, size.height), Offset(size.width, size.height)),
    ];
    for (final (a, b) in edges) {
      switch (style) {
        case CalendarGridLines.thin:
          canvas.drawLine(a, b, paint);
        case CalendarGridLines.dashed:
          final length = (b - a).distance;
          final dir = (b - a) / length;
          for (var d = 0.0; d < length; d += 7) {
            canvas.drawLine(
              a + dir * d,
              a + dir * math.min(d + 4, length),
              paint,
            );
          }
        case CalendarGridLines.hand:
          final rnd = math.Random(seed * 2 + (a.dx == 0 ? 1 : 0));
          final path = Path()..moveTo(a.dx, a.dy);
          for (var i = 1; i <= 6; i++) {
            final p = Offset.lerp(a, b, i / 6)!;
            path.lineTo(
              p.dx + rnd.nextDouble() - 0.5,
              p.dy + rnd.nextDouble() - 0.5,
            );
          }
          canvas.drawPath(path, paint);
        case CalendarGridLines.none:
          break;
      }
    }
  }

  @override
  bool shouldRepaint(CellEdges old) =>
      old.style != style || old.color != color || old.seed != seed;
}
