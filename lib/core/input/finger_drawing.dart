import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/synced_setting.dart';

/// Whether a finger draws on a page. Chosen per device in Settings.
enum FingerDrawing {
  /// Follow the device: the iPad's "Only Draw with Apple Pencil", or on
  /// Android, whether a stylus has ever been used here.
  device,

  /// Fingers always draw.
  on,

  /// Fingers never draw; they scroll, zoom and move stickers.
  off,
}

class FingerDrawingController extends Notifier<FingerDrawing> {
  static const _prefsKey = 'fingerDrawing';

  @override
  FingerDrawing build() {
    final saved = ref.watch(sharedPreferencesProvider).getString(_prefsKey);
    return FingerDrawing.values.asNameMap()[saved] ?? FingerDrawing.device;
  }

  Future<void> set(FingerDrawing value) async {
    state = value;
    await ref.read(sharedPreferencesProvider).setString(_prefsKey, value.name);
  }
}

final fingerDrawingProvider =
    NotifierProvider<FingerDrawingController, FingerDrawing>(
      FingerDrawingController.new,
    );

/// What the device says about Pencil-only drawing.
@immutable
class DevicePencil {
  const DevicePencil({required this.pencilOnly, required this.stylusUsed});

  /// iPad Settings → Apple Pencil → Only Draw with Apple Pencil. Always
  /// false off iOS.
  final bool pencilOnly;

  /// A stylus has been used on this device at least once (remembered).
  final bool stylusUsed;
}

/// Reads the iPad's Pencil setting over the `notely/pencil` channel, again
/// each time the app comes back to the front, and remembers once a stylus
/// has been used on this device.
class DevicePencilController extends Notifier<DevicePencil> {
  static const channel = MethodChannel('notely/pencil');
  static const _stylusKey = 'stylusUsed';

  AppLifecycleListener? _lifecycle;

  @override
  DevicePencil build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    if (_isIOS) {
      unawaited(_refresh());
      _lifecycle ??= AppLifecycleListener(onResume: _refresh);
      ref.onDispose(() {
        _lifecycle?.dispose();
        _lifecycle = null;
      });
    }
    return DevicePencil(
      pencilOnly: false,
      stylusUsed: prefs.getBool(_stylusKey) ?? false,
    );
  }

  static bool get _isIOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> _refresh() async {
    try {
      final value = await channel.invokeMethod<bool>(
        'prefersPencilOnlyDrawing',
      );
      if (value != null && value != state.pencilOnly) {
        state = DevicePencil(pencilOnly: value, stylusUsed: state.stylusUsed);
      }
    } on PlatformException {
      // Unknown: keep the last value.
    } on MissingPluginException {
      // Not available (e.g. in tests): keep the last value.
    }
  }

  /// Called when a stylus touches a page.
  void stylusSeen() {
    if (state.stylusUsed) return;
    state = DevicePencil(pencilOnly: state.pencilOnly, stylusUsed: true);
    unawaited(ref.read(sharedPreferencesProvider).setBool(_stylusKey, true));
  }
}

final devicePencilProvider =
    NotifierProvider<DevicePencilController, DevicePencil>(
      DevicePencilController.new,
    );

/// Whether a finger touching a page draws (true) or scrolls (false).
final fingersDrawProvider = Provider<bool>((ref) {
  final device = ref.watch(devicePencilProvider);
  return fingersDraw(
    ref.watch(fingerDrawingProvider),
    device,
    isIOS: !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS,
  );
});

/// The rule, separate for testing.
bool fingersDraw(
  FingerDrawing setting,
  DevicePencil device, {
  required bool isIOS,
}) => switch (setting) {
  FingerDrawing.on => true,
  FingerDrawing.off => false,
  // iOS has its own setting; Android has none, so a stylus once used
  // there means the person writes with it.
  FingerDrawing.device => isIOS ? !device.pencilOnly : !device.stylusUsed,
};
