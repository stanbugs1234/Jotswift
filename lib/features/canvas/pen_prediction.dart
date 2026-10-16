import 'dart:ui';

/// Where the pen will probably be [ahead] of its newest position, from its
/// [trail] of (time, point), oldest first: straight on at its recent speed,
/// but never more than [most] away. Null when there's nothing to go on or
/// the guess would be under [least] away.
Offset? predictPen(
  List<(Duration, Offset)> trail, {
  required Duration ahead,
  required double most,
  double least = 0,
}) {
  if (trail.length < 2) return null;
  final (since, from) = trail.first;
  final (now, at) = trail.last;
  final elapsed = (now - since).inMicroseconds;
  if (elapsed <= 0) return null;
  var step = (at - from) * (ahead.inMicroseconds / elapsed);
  if (step.distance > most) step = step * (most / step.distance);
  if (step.distance < least || step.distance == 0) return null;
  return at + step;
}
