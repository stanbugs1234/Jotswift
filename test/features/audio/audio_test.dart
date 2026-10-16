import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notely/core/skins/skin_manifest.dart';
import 'package:notely/features/audio/audio_services.dart';
import 'package:notely/features/auth/auth_repository.dart';
import 'package:notely/features/canvas/page_canvas.dart';
import 'package:notely/features/canvas/stroke_painter.dart';
import 'package:notely/features/notebooks/data/in_memory_notes_backend.dart';
import 'package:notely/features/notebooks/domain/notebook_models.dart';
import 'package:notely/features/notebooks/notes_providers.dart';
import 'package:notely/features/notebooks/page_screen.dart';

import '../../helpers.dart';

class _FakeCapture implements AudioCapture {
  var recording = false;

  @override
  Future<bool> start() async => recording = true;

  @override
  Future<({Uint8List bytes, Duration length})?> stop() async {
    recording = false;
    return (
      bytes: Uint8List.fromList([1, 2, 3]),
      length: const Duration(seconds: 12),
    );
  }

  @override
  Future<void> cancel() async => recording = false;
}

class _FakePlayback implements AudioPlayback {
  final positions = StreamController<Duration>.broadcast();
  final playings = StreamController<bool>.broadcast();
  final seeks = <Duration>[];
  Uri? opened;

  @override
  Future<Duration?> open(Uri uri) async {
    opened = uri;
    return const Duration(seconds: 12);
  }

  @override
  Future<void> play() async => playings.add(true);

  @override
  Future<void> pause() async => playings.add(false);

  @override
  Future<void> seek(Duration position) async {
    seeks.add(position);
    positions.add(position);
  }

  @override
  Future<void> setSpeed(double speed) async {}

  @override
  Stream<Duration> get position => positions.stream;

  @override
  Stream<bool> get playing => playings.stream;

  @override
  Stream<void> get finished => const Stream.empty();

  @override
  Future<void> dispose() async {}
}

void main() {
  late List<SkinManifest> skins;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    skins = await loadTestSkins();
  });

  testWidgets('writing while recording plays back as it was written', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(800, 1000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final auth = DevAuthRepository();
    await auth.signInWithEmail('sam@example.com', 'secret1');
    final uid = auth.currentUser!.uid;
    final backend = InMemoryNotesBackend();
    final repo = backend.notebooks(uid);
    final nb = await repo.createNotebook(
      const NewNotebook(title: 'Lecture', cover: NotebookCover.color(0)),
    );
    final section = (await repo.watchSections(nb.id).first).single;
    final page = await repo.createPage(nb.id, section.id);
    final capture = _FakeCapture();
    final player = _FakePlayback();
    final store = InMemoryAudioStore();
    final container = await makeContainer(
      skins,
      prefs: {'penPanelSide': 'toolbar'},
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        notesBackendProvider.overrideWithValue(backend),
        audioCaptureProvider.overrideWithValue(capture),
        audioStoreProvider.overrideWithValue(store),
        audioPlaybackFactoryProvider.overrideWithValue(() => player),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: themed(skinById(skins, 'classic'), PageScreen(pageId: page.id)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Recordings'), findsNothing, reason: 'none yet');

    await tester.ensureVisible(find.byTooltip('Record audio'));
    await tester.tap(find.byTooltip('Record audio'));
    await tester.pump();
    await tester.pump();
    expect(capture.recording, isTrue);
    expect(find.text('Recording'), findsOneWidget);

    // Write something, a moment in.
    await tester.pump(const Duration(milliseconds: 300));
    final c = tester.getCenter(find.byType(PageCanvas));
    final pen = await tester.startGesture(c, kind: PointerDeviceKind.stylus);
    for (var i = 1; i <= 6; i++) {
      await pen.moveTo(c + Offset(i * 20.0, 0));
    }
    await pen.up();
    await tester.pump();
    final stroke =
        (await backend.strokes(uid).watchStrokes(page.id).first).single;
    expect(stroke.audioId, isNotNull);
    expect(stroke.audioAt, isNotNull);

    await tester.tap(find.widgetWithText(FilledButton, 'Stop'));
    await tester.pump();
    await tester.pump();
    final recording = (await repo.watchRecordings(nb.id).first).single;
    expect(recording.id, stroke.audioId);
    expect(recording.durationMs, 12000);
    expect(store.files.keys.single, endsWith('.m4a'));
    await tester.pumpAndSettle();

    // Play it back: writing not yet reached is faint.
    await tester.ensureVisible(find.byTooltip('Recordings'));
    await tester.tap(find.byTooltip('Recordings'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Play'), findsOneWidget);
    StrokesPainter painter() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((p) => p.painter)
        .whereType<StrokesPainter>()
        .first;
    expect(painter().faded, {stroke.id});

    player.positions.add(Duration(milliseconds: stroke.audioAt! + 500));
    await tester.pumpAndSettle();
    expect(painter().faded, isEmpty);

    // Tapping the writing plays from just before it was written.
    await tester.tapAt(c + const Offset(60, 0));
    await tester.pumpAndSettle();
    expect(player.seeks.last, Duration.zero);
    expect(find.byTooltip('Pause'), findsOneWidget);
    expect(
      (await backend.strokes(uid).watchStrokes(page.id).first),
      hasLength(1),
      reason: 'the tap left no dot',
    );
  });
}
