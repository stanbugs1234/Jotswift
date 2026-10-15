import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    hide Day;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../core/day.dart';
import 'reminders.dart';

/// Reminders as local notifications on iOS and Android. Nothing goes
/// through a server.
class LocalReminders implements ReminderService {
  LocalReminders._(this._plugin);

  /// Sets up the plugin and the device's time zone.
  static Future<LocalReminders> create() async {
    tzdata.initializeTimeZones();
    try {
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
    } catch (e) {
      // Unknown zone name: UTC times still fire, maybe at the wrong hour.
      debugPrint('Time zone not found: $e');
    }
    final reminders = LocalReminders._(FlutterLocalNotificationsPlugin());
    await reminders._plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        // Ask only when the user first sets a reminder.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (r) => reminders._tapped(r.payload),
    );
    final launch = await reminders._plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      reminders._tapped(launch!.notificationResponse?.payload);
    }
    return reminders;
  }

  final FlutterLocalNotificationsPlugin _plugin;

  // Holds a tap that launched the app until the app listens.
  final _taps = StreamController<Day>();

  void _tapped(String? payload) {
    final day = Day.tryParse(payload);
    if (day != null) _taps.add(day);
  }

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'reminders',
      'Reminders',
      channelDescription: 'Reminders for tasks and events',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
  );

  @override
  Future<bool> requestPermission() async {
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await ios?.requestPermissions(alert: true, sound: true) ??
        await android?.requestNotificationsPermission() ??
        false;
  }

  @override
  Future<void> schedule(List<Reminder> reminders) async {
    await _plugin.cancelAllPendingNotifications();
    for (final r in reminders) {
      await _plugin.zonedSchedule(
        id: r.id,
        scheduledDate: tz.TZDateTime.from(r.at, tz.local),
        notificationDetails: _details,
        // Within a few minutes is fine; exact alarms need extra permission
        // on Android.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: r.title,
        body: r.body,
        payload: r.day.toString(),
      );
    }
  }

  @override
  Stream<Day> get taps => _taps.stream;
}
