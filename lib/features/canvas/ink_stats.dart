import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/synced_setting.dart';

/// Whether pages show how the Pencil's ink is keeping up (for testers):
/// samples a second and the time to draw the stroke being written.
class InkStatsController extends Notifier<bool> {
  static const _prefsKey = 'inkStats';

  @override
  bool build() =>
      ref.watch(sharedPreferencesProvider).getBool(_prefsKey) ?? false;

  Future<void> set(bool on) async {
    state = on;
    await ref.read(sharedPreferencesProvider).setBool(_prefsKey, on);
  }
}

final inkStatsProvider = NotifierProvider<InkStatsController, bool>(
  InkStatsController.new,
);

/// Counts, while a stroke is written: pen events from Flutter and samples
/// from the device, each a second, and how long drawing the live stroke
/// takes. Cheap enough to always count.
class InkStats {
  InkStats._();

  static final instance = InkStats._();

  final _events = <Duration>[];
  final _samples = <Duration>[];
  final _clock = Stopwatch()..start();

  /// The latest figures, for the readout.
  final shown = ValueNotifier<String>('');

  double _drawMs = 0;

  void penEvent() => _count(_events);

  /// [n] samples from the device at once.
  void samples(int n) {
    for (var i = 0; i < n; i++) {
      _count(_samples);
    }
  }

  /// One frame of the live stroke took [ms] to draw.
  void drew(double ms) {
    _drawMs = _drawMs == 0 ? ms : _drawMs * 0.8 + ms * 0.2;
  }

  void _count(List<Duration> list) {
    final now = _clock.elapsed;
    list.add(now);
    while (list.isNotEmpty && now - list.first > const Duration(seconds: 1)) {
      list.removeAt(0);
    }
    _update();
  }

  void _update() {
    shown.value =
        'Pen ${_events.length}/s · samples ${_samples.length}/s · '
        'draw ${_drawMs.toStringAsFixed(1)} ms';
  }
}

/// The figures, in a corner of the page.
class InkStatsReadout extends ConsumerWidget {
  const InkStatsReadout({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(inkStatsProvider)) return const SizedBox.shrink();
    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomRight,
        child: Container(
          margin: const EdgeInsets.all(8),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(6),
          ),
          child: ValueListenableBuilder<String>(
            valueListenable: InkStats.instance.shown,
            builder: (context, text, _) => Text(
              text.isEmpty ? 'Write to see ink stats' : text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
