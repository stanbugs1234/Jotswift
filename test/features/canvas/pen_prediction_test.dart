import 'package:flutter_test/flutter_test.dart';
import 'package:notely/features/canvas/pen_prediction.dart';

void main() {
  const ms = Duration(milliseconds: 1);

  test('the pen carries on at its recent speed', () {
    // 10 points per 8 ms to the right; 12 ms ahead is 15 more.
    final tip = predictPen(
      [(Duration.zero, const Offset(0, 0)), (ms * 8, const Offset(10, 0))],
      ahead: ms * 12,
      most: 100,
    );
    expect(tip, const Offset(25, 0));
  });

  test('a fast pen is never guessed more than so far ahead', () {
    final tip = predictPen(
      [(Duration.zero, const Offset(0, 0)), (ms * 2, const Offset(0, 50))],
      ahead: ms * 12,
      most: 16,
    );
    expect(tip, const Offset(0, 66));
  });

  test('no guess without motion, time or history', () {
    final still = [
      (Duration.zero, const Offset(5, 5)),
      (ms * 8, const Offset(5, 5)),
    ];
    expect(predictPen(still, ahead: ms * 12, most: 16), isNull);
    final sameTime = [(ms, const Offset(0, 0)), (ms, const Offset(9, 9))];
    expect(predictPen(sameTime, ahead: ms * 12, most: 16), isNull);
    expect(
      predictPen([(ms, const Offset(1, 1))], ahead: ms * 12, most: 16),
      isNull,
    );
    final creeping = [
      (Duration.zero, const Offset(0, 0)),
      (ms * 30, const Offset(0.5, 0)),
    ];
    expect(predictPen(creeping, ahead: ms * 12, most: 16, least: 0.5), isNull);
  });
}
