import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/input/finger_drawing.dart';
import '../../core/settings/synced_setting.dart';
import 'ink_tools.dart';

/// What an Apple Pencil double-tap or squeeze does. Chosen per device.
enum PencilAction {
  /// What the iPad's Settings → Apple Pencil says.
  system,

  /// Switch between the current tool and the eraser.
  switchEraser,

  /// Switch to the tool used before this one.
  switchPrevious,

  /// Open the colors and pen options.
  showColors,

  /// Nothing.
  off,
}

/// The two Pencil gestures: double-tap (2nd generation and Pro) and squeeze
/// (Pro).
enum PencilGesture { tap, squeeze }

class PencilActionController extends Notifier<PencilAction> {
  PencilActionController(this.gesture);

  final PencilGesture gesture;

  String get _prefsKey => switch (gesture) {
    PencilGesture.tap => 'pencilTapAction',
    PencilGesture.squeeze => 'pencilSqueezeAction',
  };

  @override
  PencilAction build() =>
      PencilAction.values.asNameMap()[ref
          .watch(sharedPreferencesProvider)
          .getString(_prefsKey)] ??
      PencilAction.system;

  Future<void> set(PencilAction action) async {
    state = action;
    await ref.read(sharedPreferencesProvider).setString(_prefsKey, action.name);
  }
}

final pencilActionProvider =
    NotifierProvider.family<
      PencilActionController,
      PencilAction,
      PencilGesture
    >(PencilActionController.new);

/// Asks the toolbar to open the pen options (from a Pencil gesture).
class PenOptionsRequest extends Notifier<int> {
  @override
  int build() => 0;

  void request() => state++;
}

final penOptionsRequestProvider = NotifierProvider<PenOptionsRequest, int>(
  PenOptionsRequest.new,
);

/// What to do for a Pencil gesture: the user's [choice], or when that's
/// [PencilAction.system], the iPad's preferred action ([system], a
/// UIPencilPreferredAction name).
PencilAction resolvePencilAction(PencilAction choice, String system) =>
    choice != PencilAction.system
    ? choice
    : switch (system) {
        'switchEraser' => PencilAction.switchEraser,
        'switchPrevious' => PencilAction.switchPrevious,
        'showColorPalette' || 'showInkAttributes' => PencilAction.showColors,
        _ => PencilAction.off,
      };

/// Listens for Pencil double-taps and squeezes while a page is open (iOS
/// only).
final pencilGesturesProvider = Provider.autoDispose<void>((ref) {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
  const channel = DevicePencilController.channel;
  channel.setMethodCallHandler((call) async {
    if (call.method != 'pencilAction') return;
    final args = (call.arguments as Map).cast<String, Object?>();
    final gesture = args['gesture'] == 'squeeze'
        ? PencilGesture.squeeze
        : PencilGesture.tap;
    final action = resolvePencilAction(
      ref.read(pencilActionProvider(gesture)),
      args['action'] as String? ?? 'ignore',
    );
    final tools = ref.read(inkToolProvider.notifier);
    switch (action) {
      case PencilAction.switchEraser:
        tools.toggleEraser();
      case PencilAction.switchPrevious:
        tools.switchToPrevious();
      case PencilAction.showColors:
        ref.read(penOptionsRequestProvider.notifier).request();
      case PencilAction.system || PencilAction.off:
        break;
    }
  });
  ref.onDispose(() => channel.setMethodCallHandler(null));
  unawaited(
    channel.invokeMethod<bool>('listenForTaps').catchError((Object _) => false),
  );
});
