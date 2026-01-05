import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    // Initialize timezone data
    tz.initializeTimeZones();

    const initializationSettingsMacOS = DarwinInitializationSettings();
    const initializationSettingsWindows = InitializationSettings(); // Add Windows settings if needed

    const initializationSettings = InitializationSettings(
      macOS: initializationSettingsMacOS,
    );

    await flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  Future<void> scheduleNotification(String id, String title, DateTime scheduledTime) async {
    // We convert the ID string to a unique integer for the notification engine
    int notificationId = id.hashCode;

    await flutterLocalNotificationsPlugin.zonedSchedule(
      notificationId,
      'Reminder: $title',
      'Time to check your note!',
      tz.TZDateTime.from(scheduledTime, tz.local),
      const NotificationDetails(
        macOS: DarwinNotificationDetails(),
      ),
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }
}