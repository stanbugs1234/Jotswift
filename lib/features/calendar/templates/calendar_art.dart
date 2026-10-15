import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/motion/motion.dart';
import 'calendar_template.dart';

/// Repeats a slow 0–1 clock for gently moving art (falling snow, drifting
/// leaves, waves). Still when animations aren't full, and paused off
/// screen by [TickerMode].
class ArtClock extends StatefulWidget {
  const ArtClock({required this.builder, super.key});

  final Widget Function(BuildContext context, double t) builder;

  @override
  State<ArtClock> createState() => _ArtClockState();
}

class _ArtClockState extends State<ArtClock>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.of(context).full) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) => widget.builder(context, _controller.value),
  );
}

/// The illustration above a month for Wall Calendar (a scene per month)
/// and Seasons (a scene per season), with a spiral binding for Wall.
class MonthArtHeader extends StatelessWidget {
  const MonthArtHeader({
    required this.template,
    required this.month,
    super.key,
  });

  final CalendarTemplate template;

  /// 1–12.
  final int month;

  @override
  Widget build(BuildContext context) => ArtClock(
    builder: (context, t) => CustomPaint(
      painter: template.art == CalendarArt.wall
          ? WallScene(month, t)
          : SeasonScene(seasonOf(month), t),
      child: const SizedBox.expand(),
    ),
  );
}

/// Corner decorations drawn over the month grid (Botanical leaves,
/// Chalkboard doodles).
class GridArtOverlay extends StatelessWidget {
  const GridArtOverlay({required this.template, super.key});

  final CalendarTemplate template;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ArtClock(
      builder: (context, t) => CustomPaint(
        painter: switch (template.art) {
          CalendarArt.botanical => BotanicalCorners(t),
          CalendarArt.chalk => ChalkDoodles(t),
          _ => null,
        },
        child: const SizedBox.expand(),
      ),
    ),
  );
}

enum Season { winter, spring, summer, autumn }

Season seasonOf(int month) => switch (month) {
  12 || 1 || 2 => Season.winter,
  3 || 4 || 5 => Season.spring,
  6 || 7 || 8 => Season.summer,
  _ => Season.autumn,
};

/// Seasons' colours: the template recoloured for [month].
CalendarTemplate seasonalTemplate(CalendarTemplate base, int month) {
  if (base.art != CalendarArt.seasons) return base;
  final (accent, background) = switch (seasonOf(month)) {
    Season.winter => (const Color(0xFF3A6EA5), const Color(0xFFF2F6FA)),
    Season.spring => (const Color(0xFFD9558A), const Color(0xFFFBF5F7)),
    Season.summer => (const Color(0xFFE0892B), const Color(0xFFFFF9EE)),
    Season.autumn => (const Color(0xFFA84E2A), const Color(0xFFF8F1E7)),
  };
  return base.copyWith(accent: accent, background: background);
}

// Shapes

Path _star(Offset c, double r, [double inner = 0.45]) {
  final path = Path();
  for (var i = 0; i < 10; i++) {
    final rr = i.isEven ? r : r * inner;
    final a = -math.pi / 2 + i * math.pi / 5;
    final p = c + Offset(rr * math.cos(a), rr * math.sin(a));
    i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
  }
  return path..close();
}

Path _heart(Offset c, double r) {
  final path = Path();
  for (var i = 0; i <= 40; i++) {
    final t = i / 40 * 2 * math.pi;
    final x = 16 * math.pow(math.sin(t), 3);
    final y =
        13 * math.cos(t) -
        5 * math.cos(2 * t) -
        2 * math.cos(3 * t) -
        math.cos(4 * t);
    final p = c + Offset(x * r / 17, -y * r / 17);
    i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
  }
  return path..close();
}

Path _leaf(Offset c, double r, double angle) {
  final path = Path();
  for (var i = 0; i <= 30; i++) {
    final t = i / 30 * 2 * math.pi;
    final x = r * math.cos(t);
    final y = r * 0.45 * math.sin(t) * (1 - 0.3 * math.cos(t));
    final p =
        c +
        Offset(
          x * math.cos(angle) - y * math.sin(angle),
          x * math.sin(angle) + y * math.cos(angle),
        );
    i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
  }
  return path..close();
}

void _snowflake(Canvas canvas, Offset c, double r, Paint paint) {
  for (var k = 0; k < 6; k++) {
    final a = k * math.pi / 3;
    canvas.drawLine(c, c + Offset(r * math.cos(a), r * math.sin(a)), paint);
  }
}

/// Things that fall or drift through the scene: [count] of them, each at
/// a stable place, moving with [t].
Iterable<Offset> _drift(
  Size size,
  int count,
  double t, {
  required int seed,
  double fall = 1,
  double sway = 8,
}) sync* {
  final rnd = math.Random(seed);
  for (var i = 0; i < count; i++) {
    final x0 = rnd.nextDouble() * size.width;
    final y0 = rnd.nextDouble() * size.height;
    final speed = 0.6 + rnd.nextDouble() * 0.8;
    final y = (y0 + t * size.height * fall * speed) % (size.height + 20) - 10;
    final x = x0 + sway * math.sin((t * 2 * math.pi * speed) + i);
    yield Offset(x, y);
  }
}

/// A month scene for Wall Calendar.
class WallScene extends CustomPainter {
  WallScene(this.month, this.t, {this.binding = true});

  final int month;
  final double t;

  /// The spiral binding along the top (Wall Calendar only).
  final bool binding;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    canvas.clipRect(Offset.zero & size);
    final sky = switch (month) {
      1 || 12 => const [Color(0xFF9CC3E6), Color(0xFFE4F0FA)],
      2 => const [Color(0xFFF6C1CF), Color(0xFFFCE8EE)],
      3 => const [Color(0xFF8FA3B8), Color(0xFFD9E2EA)],
      4 => const [Color(0xFFBFE0F2), Color(0xFFF3F9FC)],
      5 => const [Color(0xFF9FD6F0), Color(0xFFEAF7FB)],
      6 => const [Color(0xFFFFD27A), Color(0xFFFFF1CF)],
      7 => const [Color(0xFF7FC7E8), Color(0xFFDDF2FA)],
      8 => const [Color(0xFFF7A35C), Color(0xFFFDE3C4)],
      9 => const [Color(0xFFB9D7A8), Color(0xFFEFF6E8)],
      10 => const [Color(0xFF3B2F5C), Color(0xFF6A5A8F)],
      _ => const [Color(0xFFD9B98C), Color(0xFFF4E9D8)],
    };
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: sky,
        ).createShader(Offset.zero & size),
    );
    final ground = Paint();
    void hills(Color color, double top, double amp, double phase) {
      final path = Path()..moveTo(0, h);
      for (var x = 0.0; x <= w; x += 8) {
        path.lineTo(x, top + amp * math.sin(x / w * 2 * math.pi + phase));
      }
      canvas.drawPath(
        path
          ..lineTo(w, h)
          ..close(),
        ground..color = color,
      );
    }

    final fill = Paint();
    switch (month) {
      case 1 || 12:
        hills(const Color(0xFFF7FAFD), h * 0.72, 8, 0.5);
        for (final x in [0.18, 0.3, 0.74, 0.86]) {
          final base = Offset(w * x, h * 0.78);
          for (var k = 0; k < 3; k++) {
            final tw = h * (0.16 - k * 0.04);
            final top = base.dy - h * (0.12 + k * 0.1);
            canvas.drawPath(
              Path()
                ..moveTo(base.dx, top - tw * 0.6)
                ..lineTo(base.dx + tw * 0.7, top + tw * 0.5)
                ..lineTo(base.dx - tw * 0.7, top + tw * 0.5)
                ..close(),
              fill..color = const Color(0xFF3F7A5E),
            );
          }
        }
        if (month == 12) {
          for (final (i, p) in _drift(size, 6, 0, seed: 3).indexed) {
            canvas.drawCircle(
              Offset(p.dx, h * 0.5 + (i % 3) * 8),
              3,
              fill
                ..color = [
                  const Color(0xFFE63946),
                  const Color(0xFFF1C40F),
                ][i % 2],
            );
          }
        }
        final snow = Paint()
          ..color = Colors.white
          ..strokeWidth = 1.4
          ..strokeCap = StrokeCap.round;
        for (final p in _drift(size, 28, t, seed: 1, fall: 2, sway: 10)) {
          _snowflake(canvas, p, 3.5, snow);
        }
      case 2:
        for (final (i, p) in _drift(size, 16, t, seed: 2, fall: -1).indexed) {
          canvas.drawPath(
            _heart(p, 7 + (i % 3) * 4),
            fill
              ..color = [
                const Color(0xFFE63946),
                const Color(0xFFF48FB1),
                Colors.white,
              ][i % 3],
          );
        }
      case 3:
        hills(const Color(0xFF7A9A6A), h * 0.75, 6, 1);
        final rain = Paint()
          ..color = const Color(0xFF5B7A99)
          ..strokeWidth = 1.5;
        for (final p in _drift(size, 40, t, seed: 4, fall: 4, sway: 0)) {
          canvas.drawLine(p, p + const Offset(-3, 9), rain);
        }
        final c = Offset(w * 0.7, h * 0.62);
        canvas.drawArc(
          Rect.fromCenter(center: c, width: h * 0.5, height: h * 0.4),
          math.pi,
          math.pi,
          true,
          fill..color = const Color(0xFFE76F51),
        );
        canvas.drawLine(
          c,
          c + Offset(0, h * 0.25),
          Paint()
            ..color = const Color(0xFF333333)
            ..strokeWidth = 2.5,
        );
      case 4 || 5:
        hills(const Color(0xFF8CC084), h * 0.7, 10, 2);
        if (month == 4) {
          final branch = Paint()
            ..color = const Color(0xFF6B4A3A)
            ..strokeWidth = 4
            ..style = PaintingStyle.stroke;
          canvas.drawPath(
            Path()
              ..moveTo(0, h * 0.15)
              ..quadraticBezierTo(w * 0.3, h * 0.05, w * 0.55, h * 0.25),
            branch,
          );
          for (final (i, p) in _drift(size, 22, t, seed: 5, sway: 14).indexed) {
            canvas.drawCircle(
              p,
              3 + (i % 2),
              fill..color = const Color(0xFFF7B7C8),
            );
          }
        } else {
          for (var i = 0; i < 9; i++) {
            final x = w * (0.08 + i * 0.105);
            final sway = 3 * math.sin(t * 2 * math.pi + i);
            final top = Offset(x + sway, h * 0.55);
            canvas.drawLine(
              Offset(x, h),
              top,
              Paint()
                ..color = const Color(0xFF3F7A3F)
                ..strokeWidth = 2,
            );
            canvas.drawOval(
              Rect.fromCenter(center: top, width: 14, height: 18),
              fill
                ..color = [
                  const Color(0xFFE63946),
                  const Color(0xFFF4A261),
                  const Color(0xFFE76FA8),
                ][i % 3],
            );
          }
        }
      case 6:
        final sun = Offset(w * 0.5, h * 0.62);
        final ray = Paint()
          ..color = const Color(0xFFF4A300)
          ..strokeWidth = 3;
        for (var k = 0; k < 16; k++) {
          final a = k * math.pi / 8 + t * 2 * math.pi / 8;
          canvas.drawLine(
            sun + Offset(math.cos(a), math.sin(a)) * h * 0.24,
            sun + Offset(math.cos(a), math.sin(a)) * h * 0.36,
            ray,
          );
        }
        canvas.drawCircle(sun, h * 0.2, fill..color = const Color(0xFFFFC233));
        hills(const Color(0xFF9CC57A), h * 0.8, 6, 0);
      case 7:
        for (var k = 0; k < 4; k++) {
          final top = h * (0.45 + k * 0.14);
          final path = Path()..moveTo(0, h);
          for (var x = 0.0; x <= w; x += 6) {
            path.lineTo(
              x,
              top +
                  6 * math.sin(x / 40 + t * 2 * math.pi * (k.isEven ? 1 : -1)),
            );
          }
          canvas.drawPath(
            path
              ..lineTo(w, h)
              ..close(),
            fill
              ..color = [
                const Color(0xFF9ED8DB),
                const Color(0xFF5CB8C4),
                const Color(0xFF2F8FA3),
                const Color(0xFF1F6F8B),
              ][k],
          );
        }
      case 8:
        canvas.drawCircle(
          Offset(w * 0.5, h * 0.8),
          h * 0.32,
          fill..color = const Color(0xFFFF7B54),
        );
        hills(const Color(0xFF2F4858), h * 0.82, 4, 0);
        for (var k = 0; k < 3; k++) {
          canvas.drawLine(
            Offset(w * 0.2 + k * 30, h * 0.25 + 4 * math.sin(t * 6 + k)),
            Offset(w * 0.2 + k * 30 + 10, h * 0.22 + 4 * math.sin(t * 6 + k)),
            Paint()
              ..color = const Color(0xFF2F4858)
              ..strokeWidth = 2,
          );
        }
      case 9 || 10 || 11:
        if (month == 10) {
          canvas.drawCircle(
            Offset(w * 0.8, h * 0.28),
            h * 0.14,
            fill..color = const Color(0xFFF7E7A1),
          );
          hills(const Color(0xFF2A2140), h * 0.78, 6, 0);
          for (final x in [0.2, 0.36, 0.55]) {
            final c = Offset(w * x, h * 0.84);
            for (final dx in [-9.0, 9.0, 0.0]) {
              canvas.drawOval(
                Rect.fromCenter(
                  center: c + Offset(dx, 0),
                  width: 22,
                  height: 20,
                ),
                fill..color = const Color(0xFFF28C28),
              );
            }
          }
        } else {
          hills(
            month == 9 ? const Color(0xFF8FBF6A) : const Color(0xFFB98A4E),
            h * 0.74,
            8,
            1,
          );
        }
        for (final (i, p) in _drift(size, 18, t, seed: 6, sway: 16).indexed) {
          canvas.drawPath(
            _leaf(p, 7, t * 6 + i),
            fill
              ..color = [
                const Color(0xFFC8553D),
                const Color(0xFFF28F3B),
                const Color(0xFFE9B44C),
              ][i % 3],
          );
        }
    }
    if (!binding) return;
    // The spiral binding along the top.
    final ring = Paint()
      ..color = const Color(0xFF4A4A4A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (var x = 14.0; x < w - 8; x += 22) {
      canvas.drawCircle(
        Offset(x, 4),
        3,
        Paint()..color = const Color(0xFF333333),
      );
      canvas.drawArc(
        Rect.fromCenter(center: Offset(x, 0), width: 10, height: 16),
        0,
        math.pi,
        false,
        ring,
      );
    }
  }

  @override
  bool shouldRepaint(WallScene old) => old.month != month || old.t != t;
}

/// A season scene for the Seasons template.
class SeasonScene extends CustomPainter {
  SeasonScene(this.season, this.t);

  final Season season;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final month = switch (season) {
      Season.winter => 1,
      Season.spring => 4,
      Season.summer => 7,
      Season.autumn => 11,
    };
    WallScene(month, t, binding: false).paint(canvas, size);
  }

  @override
  bool shouldRepaint(SeasonScene old) => old.season != season || old.t != t;
}

/// Leafy sprigs in two corners, swaying a little.
class BotanicalCorners extends CustomPainter {
  BotanicalCorners(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final sway = 0.05 * math.sin(t * 2 * math.pi);
    void sprig(Offset base, double angle, double scale) {
      final stem = Paint()
        ..color = const Color(0xFF4F7B5A).withValues(alpha: 0.55)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      final dir = Offset(math.cos(angle + sway), math.sin(angle + sway));
      final tip = base + dir * 90 * scale;
      canvas.drawLine(base, tip, stem);
      for (var i = 1; i <= 4; i++) {
        final p = Offset.lerp(base, tip, i / 5)!;
        for (final side in [-1.0, 1.0]) {
          canvas.drawPath(
            _leaf(
              p + Offset(-dir.dy, dir.dx) * side * 10 * scale,
              11 * scale,
              angle + sway + side * 0.9,
            ),
            Paint()
              ..color =
                  (i.isEven ? const Color(0xFF7FA67A) : const Color(0xFFD98E73))
                      .withValues(alpha: 0.35),
          );
        }
      }
    }

    sprig(Offset(size.width, 0), math.pi * 0.75, 1);
    sprig(Offset(0, size.height), -math.pi * 0.25, 1.1);
  }

  @override
  bool shouldRepaint(BotanicalCorners old) => old.t != t;
}

/// Chalk doodles: a twinkling star, a swirl and a small sun in the corners,
/// with chalk dust.
class ChalkDoodles extends CustomPainter {
  ChalkDoodles(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final chalk = Paint()
      ..color = const Color(0xFFF1EFE6).withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final twinkle = 0.7 + 0.3 * math.sin(t * 2 * math.pi * 3);
    canvas.drawPath(_star(Offset(size.width - 28, 26), 14 * twinkle), chalk);
    final swirl = Path();
    for (var i = 0; i <= 60; i++) {
      final a = i / 60 * 4 * math.pi;
      final r = 2 + i * 0.35;
      final p =
          Offset(30, size.height - 34) +
          Offset(r * math.cos(a), r * math.sin(a));
      i == 0 ? swirl.moveTo(p.dx, p.dy) : swirl.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(swirl, chalk);
    final sun = Offset(size.width - 34, size.height - 34);
    canvas.drawCircle(sun, 9, chalk);
    for (var k = 0; k < 8; k++) {
      final a = k * math.pi / 4 + t * math.pi;
      canvas.drawLine(
        sun + Offset(math.cos(a), math.sin(a)) * 13,
        sun + Offset(math.cos(a), math.sin(a)) * 19,
        chalk,
      );
    }
    final dust = Paint()..color = Colors.white.withValues(alpha: 0.06);
    final rnd = math.Random(9);
    for (var i = 0; i < 160; i++) {
      canvas.drawCircle(
        Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height),
        rnd.nextDouble() * 1.6,
        dust,
      );
    }
  }

  @override
  bool shouldRepaint(ChalkDoodles old) => old.t != t;
}
