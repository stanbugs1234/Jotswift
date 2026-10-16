import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../notebooks/notes_providers.dart';
import 'audio_services.dart';
import 'recording.dart';

/// A recording being made, in a notebook.
@immutable
class ActiveRecording {
  ActiveRecording({
    required this.id,
    required this.notebookId,
    required this.pageId,
  }) : _clock = Stopwatch()..start();

  final String id;
  final String notebookId;
  final String pageId;
  final Stopwatch _clock;

  /// How far into the recording it is now.
  Duration get elapsed => _clock.elapsed;
}

/// Why a recording couldn't be made or kept.
class RecordingException implements Exception {
  const RecordingException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Records sound while writing. One recording at a time.
class RecordingSession extends Notifier<ActiveRecording?> {
  @override
  ActiveRecording? build() => null;

  /// Starts recording in [notebookId], from [pageId].
  Future<void> start({
    required String notebookId,
    required String pageId,
  }) async {
    if (state != null) return;
    final started = await ref.read(audioCaptureProvider).start();
    if (!started) {
      throw const RecordingException(
        'Jotswift can\'t use the microphone. Allow it in Settings → '
        'Jotswift.',
      );
    }
    state = ActiveRecording(
      id: ref.read(notebookRepositoryProvider).newRecordingId(),
      notebookId: notebookId,
      pageId: pageId,
    );
  }

  /// Stops and keeps the recording with its notebook.
  Future<Recording?> stop() async {
    final active = state;
    if (active == null) return null;
    state = null;
    final sound = await ref.read(audioCaptureProvider).stop();
    if (sound == null || sound.bytes.isEmpty) return null;
    final uid = ref.read(currentUidProvider);
    try {
      final path = await ref
          .read(audioStoreProvider)
          .upload(uid, active.id, sound.bytes);
      final recording = Recording(
        id: active.id,
        path: path,
        durationMs: sound.length.inMilliseconds,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        pageId: active.pageId,
      );
      await ref
          .read(notebookRepositoryProvider)
          .addRecording(active.notebookId, recording);
      return recording;
    } catch (_) {
      throw const RecordingException(
        'The recording couldn\'t be saved. Check your connection.',
      );
    }
  }
}

final recordingSessionProvider =
    NotifierProvider<RecordingSession, ActiveRecording?>(RecordingSession.new);

/// A notebook's recordings.
final recordingsProvider = StreamProvider.family<List<Recording>, String>(
  (ref, notebookId) =>
      ref.watch(notebookRepositoryProvider).watchRecordings(notebookId),
);

/// The recording open to play, where it's up to, and whether it's playing.
@immutable
class Playback {
  const Playback({
    required this.notebookId,
    required this.recording,
    this.position = Duration.zero,
    this.playing = false,
    this.speed = 1,
  });

  final String notebookId;
  final Recording recording;
  final Duration position;
  final bool playing;
  final double speed;

  Playback copyWith({Duration? position, bool? playing, double? speed}) =>
      Playback(
        notebookId: notebookId,
        recording: recording,
        position: position ?? this.position,
        playing: playing ?? this.playing,
        speed: speed ?? this.speed,
      );
}

/// Plays a notebook's recordings back. While one is open, its writing
/// appears as it was written, and tapping writing plays from there.
class PlaybackController extends Notifier<Playback?> {
  AudioPlayback? _player;
  final _subscriptions = <StreamSubscription<Object?>>[];

  @override
  Playback? build() {
    ref.onDispose(_close);
    return null;
  }

  Future<void> open(String notebookId, Recording recording) async {
    await _close();
    final player = ref.read(audioPlaybackFactoryProvider)();
    _player = player;
    state = Playback(notebookId: notebookId, recording: recording);
    _subscriptions
      ..add(
        player.position.listen((p) {
          final s = state;
          if (s != null) state = s.copyWith(position: p);
        }),
      )
      ..add(
        player.playing.listen((playing) {
          final s = state;
          if (s != null) state = s.copyWith(playing: playing);
        }),
      )
      ..add(
        player.finished.listen((_) async {
          await player.pause();
          await player.seek(Duration.zero);
        }),
      );
    try {
      final uri = await ref.read(audioStoreProvider).url(recording.path);
      await player.open(uri);
    } catch (_) {
      await close();
      throw const RecordingException(
        'The recording couldn\'t be played. Check your connection.',
      );
    }
  }

  Future<void> play() async => _player?.play();
  Future<void> pause() async => _player?.pause();

  Future<void> seek(Duration position) async {
    final s = state;
    if (s == null) return;
    state = s.copyWith(position: position);
    await _player?.seek(position);
  }

  /// Plays from [position].
  Future<void> playFrom(Duration position) async {
    await seek(position);
    await play();
  }

  Future<void> setSpeed(double speed) async {
    final s = state;
    if (s == null) return;
    state = s.copyWith(speed: speed);
    await _player?.setSpeed(speed);
  }

  Future<void> close() async {
    await _close();
    state = null;
  }

  Future<void> _close() async {
    for (final s in _subscriptions) {
      await s.cancel();
    }
    _subscriptions.clear();
    final player = _player;
    _player = null;
    await player?.dispose();
  }
}

final playbackProvider = NotifierProvider<PlaybackController, Playback?>(
  PlaybackController.new,
);
