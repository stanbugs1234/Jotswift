import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/synced_setting.dart';

/// How much the app animates. Chosen per device in Settings, and capped by
/// the device's own Reduce Motion setting.
enum AnimationLevel {
  /// Page turns, notebook opening, celebrations.
  full,

  /// Short fades only: no movement, flips or bounces.
  reduced,

  /// Nothing animates.
  off,
}

class AnimationLevelController extends Notifier<AnimationLevel> {
  static const _prefsKey = 'animationLevel';

  @override
  AnimationLevel build() {
    final saved = ref.watch(sharedPreferencesProvider).getString(_prefsKey);
    return AnimationLevel.values.asNameMap()[saved] ?? AnimationLevel.full;
  }

  Future<void> set(AnimationLevel level) async {
    state = level;
    await ref.read(sharedPreferencesProvider).setString(_prefsKey, level.name);
  }
}

/// The level chosen in Settings (before Reduce Motion is applied).
final animationLevelProvider =
    NotifierProvider<AnimationLevelController, AnimationLevel>(
      AnimationLevelController.new,
    );

/// Shared durations and curves, so animations across the app feel alike.
abstract final class MotionTokens {
  /// Taps and toggles: checkboxes, chips.
  static const quick = Duration(milliseconds: 180);

  /// Things moving on screen: list changes, month swipes.
  static const standard = Duration(milliseconds: 300);

  /// Big moments: opening a notebook, turning a page.
  static const emphasized = Duration(milliseconds: 520);

  /// Fades used instead of movement when animations are reduced.
  static const fade = Duration(milliseconds: 150);

  static const enter = Curves.easeOutCubic;
  static const exit = Curves.easeInCubic;
  static const move = Curves.easeInOutCubic;
  static const bounce = Curves.easeOutBack;
}

/// The animation level in effect for a part of the app. Read it with
/// `Motion.of(context)`.
@immutable
class Motion {
  const Motion(this.level);

  final AnimationLevel level;

  /// The effective level: the Settings choice, capped by Reduce Motion
  /// (`MediaQuery.disableAnimations`).
  static Motion of(BuildContext context) {
    final chosen = _MotionScope.maybeOf(context) ?? AnimationLevel.full;
    final systemReduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (systemReduced && chosen == AnimationLevel.full) {
      return const Motion(AnimationLevel.reduced);
    }
    return Motion(chosen);
  }

  bool get full => level == AnimationLevel.full;
  bool get off => level == AnimationLevel.off;

  /// [d] at full level, a short fade at reduced, nothing when off.
  Duration duration(Duration d) => switch (level) {
    AnimationLevel.full => d,
    AnimationLevel.reduced => d < MotionTokens.fade ? d : MotionTokens.fade,
    AnimationLevel.off => Duration.zero,
  };
}

/// Puts the Settings choice where [Motion.of] can find it. Placed once, above
/// the router, in `NotelyApp`.
class MotionScope extends ConsumerWidget {
  const MotionScope({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      _MotionScope(level: ref.watch(animationLevelProvider), child: child);
}

class _MotionScope extends InheritedWidget {
  const _MotionScope({required this.level, required super.child});

  final AnimationLevel level;

  static AnimationLevel? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_MotionScope>()?.level;

  @override
  bool updateShouldNotify(_MotionScope old) => old.level != level;
}
