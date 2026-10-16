import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Where a Pencil sample falls in its touch.
enum PencilPhase { began, moved, ended, cancelled }

/// One of the samples the Apple Pencil reports, at full precision: more
/// of them, and more precise, than Flutter's touch events carry.
@immutable
class PencilSample {
  const PencilSample({
    required this.phase,
    required this.time,
    required this.position,
    required this.pressure,
  });

  final PencilPhase phase;

  /// Since the device started, as touch events' time stamps are.
  final Duration time;

  /// In the app's logical pixels, from its top left (global).
  final Offset position;

  /// 0–1 of the Pencil's full force.
  final double pressure;
}

/// Reads a batch from the device: six numbers a sample (phase, time in
/// seconds, x, y, force, maximum force).
List<PencilSample> decodePencilSamples(Float64List data) => [
  for (var i = 0; i + 5 < data.length; i += 6)
    PencilSample(
      phase: PencilPhase.values[data[i].round().clamp(0, 3)],
      time: Duration(microseconds: (data[i + 1] * 1e6).round()),
      position: Offset(data[i + 2], data[i + 3]),
      pressure: data[i + 5] > 0
          ? (data[i + 4] / data[i + 5]).clamp(0.0, 1.0)
          : 0.5,
    ),
];

/// Batches of Pencil samples from the device, as the Pencil reports them.
/// Empty off iOS. Replaced in tests.
final pencilSamplesProvider = Provider<Stream<List<PencilSample>>>((ref) {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
    return const Stream.empty();
  }
  final samples = StreamController<List<PencilSample>>.broadcast();
  const channel = BasicMessageChannel<Object?>(
    'notely/pencil-samples',
    StandardMessageCodec(),
  );
  channel.setMessageHandler((message) async {
    if (message is Float64List) samples.add(decodePencilSamples(message));
    return null;
  });
  // Ask the device to start watching the Pencil.
  unawaited(
    const MethodChannel('notely/pencil')
        .invokeMethod<bool>('listenForSamples')
        .then((_) {}, onError: (_) {}),
  );
  ref.onDispose(() {
    channel.setMessageHandler(null);
    samples.close();
  });
  return samples.stream;
});
