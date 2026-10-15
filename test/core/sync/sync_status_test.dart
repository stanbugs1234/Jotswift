import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notely/core/skins/skin_manifest.dart';
import 'package:notely/core/sync/sync_indicator.dart';
import 'package:notely/core/sync/sync_status.dart';

import '../../helpers.dart';

/// Stands in for Firestore: writes are saved when [save] is called.
class _FakeServer {
  final fromCache = StreamController<bool>.broadcast();
  final changes = StreamController<void>.broadcast();
  final _waiting = <Completer<void>>[];
  var pendingWrites = false;
  var checks = 0;

  Future<void> waitForWrites() {
    checks++;
    if (!pendingWrites) return Future.value();
    return (_waiting..add(Completer())).last.future;
  }

  /// A local write: Firestore tells its listeners right away.
  void write() {
    pendingWrites = true;
    changes.add(null);
  }

  void save() {
    pendingWrites = false;
    for (final c in _waiting) {
      c.complete();
    }
    _waiting.clear();
  }

  Stream<SyncStatus> track() => trackSync(
    fromCache: fromCache.stream,
    changes: changes.stream,
    waitForWrites: waitForWrites,
  );
}

class _Monitor implements SyncMonitor {
  _Monitor(this.server);

  final _FakeServer server;

  @override
  Stream<SyncStatus> watch(String uid) => server.track();
}

void main() {
  group('trackSync', () {
    // testWidgets for its fake clock.
    testWidgets('quick saves never show "saving"', (tester) async {
      final server = _FakeServer();
      final seen = <SyncStatus>[];
      final sub = server.track().listen(seen.add);
      await tester.pump();

      server.write();
      await tester.pump(const Duration(milliseconds: 300));
      server.save();
      await tester.pump(const Duration(seconds: 2));
      expect(seen, [SyncStatus.saved]);
      unawaited(sub.cancel());
    });

    testWidgets('slow saves show "saving" until they finish', (tester) async {
      final server = _FakeServer();
      final seen = <SyncStatus>[];
      final sub = server.track().listen(seen.add);
      await tester.pump();

      server.write();
      await tester.pump(const Duration(seconds: 1));
      expect(seen.last, SyncStatus.saving);
      server.save();
      await tester.pump();
      expect(seen, [SyncStatus.saved, SyncStatus.saving, SyncStatus.saved]);
      unawaited(sub.cancel());
    });

    testWidgets('offline only after a few seconds without a connection', (
      tester,
    ) async {
      final server = _FakeServer();
      final seen = <SyncStatus>[];
      final sub = server.track().listen(seen.add);
      await tester.pump();

      // Starting up: the device copy shows first, then the server answers.
      server.fromCache.add(true);
      await tester.pump(const Duration(seconds: 1));
      server.fromCache.add(false);
      await tester.pump(const Duration(seconds: 5));
      expect(seen, [SyncStatus.saved]);

      server.fromCache.add(true);
      await tester.pump(const Duration(seconds: 4));
      expect(seen.last, SyncStatus.offline);

      server.write();
      await tester.pump(const Duration(seconds: 1));
      expect(seen.last, SyncStatus.offlineWithChanges);

      // Back online: the waiting changes upload.
      server.fromCache.add(false);
      await tester.pump();
      expect(seen.last, SyncStatus.saving);
      server.save();
      await tester.pump();
      expect(seen.last, SyncStatus.saved);
      unawaited(sub.cancel());
    });

    testWidgets('a long time offline doesn\'t pile up checks', (tester) async {
      final server = _FakeServer();
      final sub = server.track().listen((_) {});
      await tester.pump();
      server.fromCache.add(true);
      server.write();
      await tester.pump(const Duration(seconds: 4));
      final before = server.checks;

      for (var i = 0; i < 20; i++) {
        server.write();
        await tester.pump(const Duration(seconds: 5));
      }
      expect(server.checks, before);
      unawaited(sub.cancel());
    });
  });

  group('on screen', () {
    late List<SkinManifest> skins;

    setUpAll(() async {
      skins = await loadTestSkins();
    });

    testWidgets('offline shows a strip and the cloud says changes wait', (
      tester,
    ) async {
      final server = _FakeServer();
      await pumpApp(
        tester,
        skins,
        size: const Size(1200, 900),
        overrides: [syncMonitorProvider.overrideWithValue(_Monitor(server))],
      );
      expect(find.byType(SyncIndicator), findsOneWidget);
      expect(find.byTooltip('All changes saved'), findsOneWidget);
      expect(find.textContaining('offline'), findsNothing);

      server.fromCache.add(true);
      await tester.pump(const Duration(seconds: 4));
      expect(find.textContaining('You\'re offline'), findsOneWidget);
      expect(find.byTooltip('Offline'), findsOneWidget);

      server.write();
      await tester.pump(const Duration(seconds: 1));
      expect(
        find.byTooltip(syncMessage(SyncStatus.offlineWithChanges)),
        findsOneWidget,
      );

      server.fromCache.add(false);
      server.save();
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('offline'), findsNothing);
      expect(find.byTooltip('All changes saved'), findsOneWidget);

      // Stop the status checks before the test ends.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SyncIndicator)),
      );
      await tester.pumpWidget(const SizedBox());
      container.dispose();
    });
  });
}
