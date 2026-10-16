import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router.dart';
import 'document_import.dart';

/// Files other apps sent to Jotswift ("Open in Jotswift" in the share
/// sheet or Files), waiting for Home to import them.
class IncomingFiles extends Notifier<List<ImportFile>> {
  @override
  List<ImportFile> build() => const [];

  void add(List<ImportFile> files) {
    if (files.isNotEmpty) state = [...state, ...files];
  }

  /// The waiting files, which are then no longer waiting.
  List<ImportFile> take() {
    final files = state;
    state = const [];
    return files;
  }
}

final incomingFilesProvider = NotifierProvider<IncomingFiles, List<ImportFile>>(
  IncomingFiles.new,
);

/// Files sent by the platform as a list of {name, data} maps.
List<ImportFile> incomingFilesFrom(Object? arguments) => [
  if (arguments is List)
    for (final f in arguments)
      if (f case {'name': final String name, 'data': final Uint8List data})
        ImportFile(name, data),
];

/// Listens for files sent from other apps (iOS), and goes Home to import
/// them. Watched by the app.
final openInListenerProvider = Provider<void>((ref) {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
  const channel = MethodChannel('notely/open');
  void receive(Object? arguments) {
    final files = incomingFilesFrom(arguments);
    if (files.isEmpty) return;
    ref.read(incomingFilesProvider.notifier).add(files);
    ref.read(routerProvider).go(homePath);
  }

  channel.setMethodCallHandler((call) async {
    if (call.method == 'open') receive(call.arguments);
  });
  ref.onDispose(() => channel.setMethodCallHandler(null));
  // Files that opened the app before Dart was listening.
  unawaited(
    channel
        .invokeMethod<Object?>('takePending')
        .then(receive)
        .catchError((Object _) {}),
  );
});
