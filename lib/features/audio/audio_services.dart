import 'dart:async';
import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Where recordings are kept.
abstract interface class AudioStore {
  /// Saves [m4a] as recording [id]; returns its path.
  Future<String> upload(String uid, String id, Uint8List m4a);

  /// Where to play the recording at [path] from.
  Future<Uri> url(String path);
}

class FirebaseAudioStore implements AudioStore {
  FirebaseAudioStore(this._storage);

  final FirebaseStorage _storage;

  @override
  Future<String> upload(String uid, String id, Uint8List m4a) async {
    final path = 'users/$uid/audio/$id.m4a';
    await _storage
        .ref(path)
        .putData(m4a, SettableMetadata(contentType: 'audio/mp4'));
    return path;
  }

  @override
  Future<Uri> url(String path) async =>
      Uri.parse(await _storage.ref(path).getDownloadURL());
}

/// Keeps recordings in memory. Used in tests and without Firebase.
class InMemoryAudioStore implements AudioStore {
  final files = <String, Uint8List>{};

  @override
  Future<String> upload(String uid, String id, Uint8List m4a) async {
    final path = 'users/$uid/audio/$id.m4a';
    files[path] = m4a;
    return path;
  }

  @override
  Future<Uri> url(String path) async => Uri(scheme: 'memory', path: path);
}

/// Overridden in `main()` with Cloud Storage when Firebase is set up.
final audioStoreProvider = Provider<AudioStore>((ref) => InMemoryAudioStore());

/// Records sound from the microphone.
abstract interface class AudioCapture {
  /// Asks for the microphone if need be, and starts. False if it can't.
  Future<bool> start();

  /// Stops, and returns the sound (AAC in an .m4a) and how long it is.
  Future<({Uint8List bytes, Duration length})?> stop();

  /// Stops and throws the sound away.
  Future<void> cancel();
}

class RecordAudioCapture implements AudioCapture {
  final _recorder = AudioRecorder();
  final _clock = Stopwatch();
  String? _file;

  @override
  Future<bool> start() async {
    if (!await _recorder.hasPermission()) return false;
    final dir = await getTemporaryDirectory();
    final file =
        '${dir.path}/recording-${DateTime.now().millisecondsSinceEpoch}.m4a';
    // Speech, not music: mono at a modest rate keeps files small.
    await _recorder.start(
      const RecordConfig(bitRate: 64000, numChannels: 1),
      path: file,
    );
    _file = file;
    _clock
      ..reset()
      ..start();
    return true;
  }

  @override
  Future<({Uint8List bytes, Duration length})?> stop() async {
    final path = await _recorder.stop() ?? _file;
    _clock.stop();
    _file = null;
    if (path == null) return null;
    final file = File(path);
    final bytes = await file.readAsBytes();
    unawaited(file.delete().then((_) {}, onError: (_) {}));
    return (bytes: bytes, length: _clock.elapsed);
  }

  @override
  Future<void> cancel() async {
    await _recorder.cancel();
    _clock.stop();
    _file = null;
  }
}

/// The microphone. Replaced in tests.
final audioCaptureProvider = Provider<AudioCapture>((ref) {
  final capture = RecordAudioCapture();
  ref.onDispose(capture._recorder.dispose);
  return capture;
});

/// Plays one recording.
abstract interface class AudioPlayback {
  Future<Duration?> open(Uri uri);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setSpeed(double speed);
  Stream<Duration> get position;
  Stream<bool> get playing;

  /// Stopped at the end.
  Stream<void> get finished;
  Future<void> dispose();
}

class JustAudioPlayback implements AudioPlayback {
  final _player = AudioPlayer();

  @override
  Future<Duration?> open(Uri uri) => _player.setUrl(uri.toString());

  @override
  Future<void> play() async {
    // play() completes when playback stops; don't wait for that.
    unawaited(_player.play());
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  @override
  Stream<Duration> get position => _player.positionStream;

  @override
  Stream<bool> get playing => _player.playingStream;

  @override
  Stream<void> get finished => _player.processingStateStream
      .where((s) => s == ProcessingState.completed)
      .map((_) {});

  @override
  Future<void> dispose() => _player.dispose();
}

/// Makes a player for each recording opened. Replaced in tests.
final audioPlaybackFactoryProvider = Provider<AudioPlayback Function()>(
  (ref) => JustAudioPlayback.new,
);
