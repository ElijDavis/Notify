import 'package:flutter_local_notifications/flutter_local_notifications.dart';
// Add this line specifically:
import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    // 1. Initialize timezone data (essential for zonedSchedule)
    tz.initializeTimeZones();

    // 2. Platform-specific settings
    const initializationSettingsMacOS = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    // We keep Windows initialization minimal for now
    const initializationSettings = InitializationSettings(
      macOS: initializationSettingsMacOS,
      // Linux/Windows often use default settings or specific plugins
    );

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (details) {
        // This is where you'd handle what happens when a user clicks the notification
        print("Notification clicked: ${details.payload}");
      },
    );
  }

  /*Future<void> scheduleNotification(String id, String title, DateTime scheduledTime) async {
    // Ensure we aren't scheduling a time in the past, which causes a crash
    if (scheduledTime.isBefore(DateTime.now())) return;

    // Use the hash of the string ID to get a unique integer
    int notificationId = id.hashCode.abs(); 

    await flutterLocalNotificationsPlugin.zonedSchedule(
      notificationId,
      'Reminder: $title',
      'Time to check your note!',
      tz.TZDateTime.from(scheduledTime, tz.local),
      const NotificationDetails(
        macOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          presentBadge: true,
        ),
      ),
      // This is the parameter that was causing your error:
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }*/

  Future<void> scheduleNotification(String id, String title, DateTime scheduledTime) async {
    if (scheduledTime.isBefore(DateTime.now())) return;

    int notificationId = id.hashCode.abs(); 

    // We use the 'payload' to store the ID so we can find this note if the user clicks the notification
    await flutterLocalNotificationsPlugin.zonedSchedule(
      notificationId,
      'Reminder: $title',
      'Time to check your note!',
      tz.TZDateTime.from(scheduledTime, tz.local),
      const NotificationDetails(
        macOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
        ),
      ),
      // If the error persists, check if your IDE suggests 'dateInterpretation' 
      // but 'uiLocalNotificationDateInterpretation' is the standard for 17.0.0+
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: id, 
    );
  }
}