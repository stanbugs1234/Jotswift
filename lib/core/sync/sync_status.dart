import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/notebooks/notes_providers.dart';

/// Whether the user's changes have reached their account.
enum SyncStatus {
  /// Everything is saved to the account.
  saved,

  /// Changes are uploading.
  saving,

  /// No connection, and nothing is waiting to upload.
  offline,

  /// No connection; changes are kept on this device until it's back.
  offlineWithChanges;

  bool get isOffline => this == offline || this == offlineWithChanges;

  static SyncStatus of({required bool online, required bool pending}) =>
      switch ((online, pending)) {
        (true, false) => saved,
        (true, true) => saving,
        (false, false) => offline,
        (false, true) => offlineWithChanges,
      };
}

/// Reports the signed-in user's [SyncStatus].
abstract interface class SyncMonitor {
  Stream<SyncStatus> watch(String uid);
}

/// For builds without a server (tests, dev sign-in): always saved.
class AlwaysSaved implements SyncMonitor {
  const AlwaysSaved();

  @override
  Stream<SyncStatus> watch(String uid) => Stream.value(SyncStatus.saved);
}

/// Works out the status from Firestore's own signals:
///
/// * [fromCache]: whether a watched document is being served from the
///   device's copy (true while there's no connection).
/// * [changes]: fires when local data changes, which is when new writes may
///   be waiting.
/// * [waitForWrites]: completes once every write made so far is saved.
///
/// Short blips are ignored: "saving" shows only if writes take longer than
/// [settle], and "offline" only after [offlineAfter] without a connection
/// (Firestore also reports the device copy briefly while starting up).
Stream<SyncStatus> trackSync({
  required Stream<bool> fromCache,
  required Stream<void> changes,
  required Future<void> Function() waitForWrites,
  Duration settle = const Duration(milliseconds: 800),
  Duration offlineAfter = const Duration(seconds: 3),
  Duration recheck = const Duration(seconds: 5),
}) {
  late final StreamController<SyncStatus> out;
  final subs = <StreamSubscription<Object?>>[];
  Timer? offlineTimer, recheckTimer;
  final settleTimers = <Timer>{};
  var online = true, pending = false, check = 0;
  SyncStatus? last;

  void emit() {
    final next = SyncStatus.of(online: online, pending: pending);
    if (next != last && !out.isClosed) out.add(last = next);
  }

  // At most one check runs while changes are known to be waiting, so a
  // long time offline doesn't pile up checks.
  var waiting = false;

  void checkWrites() {
    if (pending && waiting) return;
    final id = ++check;
    var done = false;
    waiting = true;
    waitForWrites().then(
      (_) {
        done = true;
        if (id != check) return;
        waiting = false;
        if (pending) {
          pending = false;
          emit();
          // Writes made while this check ran may still be waiting.
          checkWrites();
        }
      },
      // The account changed or the app is closing; nothing to report.
      onError: (Object _) {
        done = true;
        if (id == check) waiting = false;
      },
    );
    // Writes that take a while to save mean "saving", even if a newer
    // check has started since.
    late final Timer timer;
    timer = Timer(settle, () {
      settleTimers.remove(timer);
      if (!done && !pending) {
        pending = true;
        emit();
      }
    });
    settleTimers.add(timer);
  }

  out = StreamController<SyncStatus>(
    onListen: () {
      emit();
      subs
        ..add(
          fromCache.listen((cached) {
            if (!cached) {
              offlineTimer?.cancel();
              offlineTimer = null;
              if (!online) {
                online = true;
                emit();
                checkWrites();
              }
            } else if (online) {
              offlineTimer ??= Timer(offlineAfter, () {
                online = false;
                emit();
              });
            }
          }, onError: (Object _) {}),
        )
        ..add(changes.listen((_) => checkWrites(), onError: (Object _) {}));
      // Writes to data nothing on screen watches don't fire [changes].
      recheckTimer = Timer.periodic(recheck, (_) => checkWrites());
      checkWrites();
    },
    onCancel: () {
      offlineTimer?.cancel();
      for (final t in settleTimers) {
        t.cancel();
      }
      recheckTimer?.cancel();
      for (final s in subs) {
        s.cancel();
      }
    },
  );
  return out.stream;
}

class FirestoreSyncMonitor implements SyncMonitor {
  const FirestoreSyncMonitor(this._db);

  final FirebaseFirestore _db;

  @override
  Stream<SyncStatus> watch(String uid) => trackSync(
    fromCache: _db
        .doc('users/$uid')
        .snapshots(includeMetadataChanges: true)
        .map((s) => s.metadata.isFromCache),
    changes: _db.snapshotsInSync(),
    waitForWrites: _db.waitForPendingWrites,
  );
}

final syncMonitorProvider = Provider<SyncMonitor>((_) => const AlwaysSaved());

final syncStatusProvider = StreamProvider.autoDispose<SyncStatus>(
  (ref) => ref.watch(syncMonitorProvider).watch(ref.watch(currentUidProvider)),
);
