import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/ui/tokens.dart';
import 'audio_controllers.dart';
import 'recording.dart';

String _clock(Duration d) {
  final s = d.inSeconds;
  final h = s ~/ 3600, m = (s ~/ 60) % 60, sec = s % 60;
  final mm = h > 0 ? m.toString().padLeft(2, '0') : '$m';
  return '${h > 0 ? '$h:' : ''}$mm:${sec.toString().padLeft(2, '0')}';
}

/// Starts recording in [notebookId], or stops and keeps the recording,
/// saying what went wrong if anything does.
Future<void> toggleRecording(
  BuildContext context,
  WidgetRef ref, {
  required String notebookId,
  required String pageId,
}) async {
  final session = ref.read(recordingSessionProvider.notifier);
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    if (ref.read(recordingSessionProvider) == null) {
      // Playing and recording at once would record the playback.
      await ref.read(playbackProvider.notifier).close();
      await session.start(notebookId: notebookId, pageId: pageId);
    } else {
      final kept = await session.stop();
      if (kept != null) {
        messenger?.showSnackBar(
          SnackBar(
            content: Text(
              'Recording saved (${_clock(kept.duration)}). Tap Recordings '
              'to play it back with your writing.',
            ),
          ),
        );
      }
    }
  } on RecordingException catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text(e.message)));
  }
}

/// Opens [notebookId]'s latest recording to play, or closes the player.
Future<void> togglePlayer(
  BuildContext context,
  WidgetRef ref,
  String notebookId,
) async {
  final playback = ref.read(playbackProvider.notifier);
  if (ref.read(playbackProvider)?.notebookId == notebookId) {
    return playback.close();
  }
  final recordings = ref.read(recordingsProvider(notebookId)).value ?? [];
  if (recordings.isEmpty) return;
  await _open(context, ref, notebookId, recordings.last);
}

Future<void> _open(
  BuildContext context,
  WidgetRef ref,
  String notebookId,
  Recording recording,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await ref.read(playbackProvider.notifier).open(notebookId, recording);
  } on RecordingException catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text(e.message)));
  }
}

/// Under the page toolbar: the recording being made, or the player.
class AudioBar extends ConsumerWidget {
  const AudioBar({required this.notebookId, super.key});

  final String notebookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recording = ref.watch(recordingSessionProvider);
    final playback = ref.watch(playbackProvider);
    final Widget? bar = recording != null
        ? _RecordingBar(recording: recording)
        : playback != null && playback.notebookId == notebookId
        ? _PlayerBar(playback: playback)
        : null;
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      alignment: Alignment.topCenter,
      child: bar ?? const SizedBox(width: double.infinity),
    );
  }
}

class _RecordingBar extends ConsumerWidget {
  const _RecordingBar({required this.recording});

  final ActiveRecording recording;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Insets.lg,
          vertical: Insets.xs,
        ),
        child: Row(
          children: [
            Icon(Icons.fiber_manual_record, color: scheme.error, size: 16),
            const SizedBox(width: Insets.sm),
            Text('Recording', style: TextStyle(color: scheme.onErrorContainer)),
            const SizedBox(width: Insets.md),
            // The time, each second.
            StreamBuilder<void>(
              stream: Stream<void>.periodic(const Duration(seconds: 1)),
              builder: (context, _) => Text(
                _clock(recording.elapsed),
                style: TextStyle(
                  color: scheme.onErrorContainer,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: Insets.md),
            // A word on what it's for, where there's room.
            Expanded(
              child: MediaQuery.sizeOf(context).width < 700
                  ? const SizedBox.shrink()
                  : Text(
                      'Writing now is kept in time with the sound.',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: scheme.onErrorContainer),
                    ),
            ),
            const SizedBox(width: Insets.md),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
              ),
              icon: const Icon(Icons.stop),
              label: const Text('Stop'),
              onPressed: () => toggleRecording(
                context,
                ref,
                notebookId: recording.notebookId,
                pageId: recording.pageId,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerBar extends ConsumerWidget {
  const _PlayerBar({required this.playback});

  final Playback playback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final controls = ref.read(playbackProvider.notifier);
    final recordings =
        ref.watch(recordingsProvider(playback.notebookId)).value ??
        const <Recording>[];
    final length = playback.recording.duration;
    final at = playback.position > length ? length : playback.position;
    final small = Theme.of(context).textTheme.labelMedium
        ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    return Material(
      color: scheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Insets.sm),
        child: Row(
          children: [
            IconButton(
              tooltip: playback.playing ? 'Pause' : 'Play',
              icon: Icon(playback.playing ? Icons.pause : Icons.play_arrow),
              onPressed: playback.playing ? controls.pause : controls.play,
            ),
            Text(_clock(at), style: small),
            Expanded(
              child: Slider(
                max: length.inMilliseconds.toDouble().clamp(1, double.infinity),
                value: at.inMilliseconds.toDouble(),
                onChanged: (ms) =>
                    controls.seek(Duration(milliseconds: ms.round())),
              ),
            ),
            Text(_clock(length), style: small),
            PopupMenuButton<double>(
              tooltip: 'Speed',
              initialValue: playback.speed,
              onSelected: controls.setSpeed,
              itemBuilder: (context) => [
                for (final s in const [0.75, 1.0, 1.25, 1.5, 2.0])
                  PopupMenuItem(value: s, child: Text('$s×')),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Insets.sm),
                child: Text('${playback.speed}×', style: small),
              ),
            ),
            if (recordings.length > 1)
              PopupMenuButton<Recording>(
                tooltip: 'Recordings',
                icon: const Icon(Icons.queue_music),
                onSelected: (r) => _open(context, ref, playback.notebookId, r),
                itemBuilder: (context) => [
                  for (final (i, r) in recordings.indexed)
                    CheckedPopupMenuItem(
                      value: r,
                      checked: r.id == playback.recording.id,
                      child: Text('Recording ${i + 1} · ${_clock(r.duration)}'),
                    ),
                ],
              ),
            IconButton(
              tooltip: 'Close player',
              icon: const Icon(Icons.close),
              onPressed: controls.close,
            ),
          ],
        ),
      ),
    );
  }
}
