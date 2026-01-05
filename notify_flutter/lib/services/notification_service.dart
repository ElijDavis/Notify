import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    tz.initializeTimeZones();
    
    // Minimal settings to avoid compiler confusion
    const initializationSettings = InitializationSettings(
      macOS: DarwinInitializationSettings(),
      iOS: DarwinInitializationSettings(),
    );

    await _notifications.initialize(initializationSettings);
  }

  Future<void> scheduleNotification(String id, String title, DateTime scheduledTime) async {
    // Check if the time is in the past
    if (scheduledTime.isBefore(DateTime.now())) return;

    // Convert to timezone-aware format
    final tzTime = tz.TZDateTime.from(scheduledTime, tz.local);

    try {
      await _notifications.zonedSchedule(
        id.hashCode.abs(),
        'Reminder',
        title,
        tzTime,
        const NotificationDetails(
          macOS: DarwinNotificationDetails(presentSound: true),
        ),
        // HARDCORE FIX: Use the specific Enum without the extra parameter if possible
        // Or use the old-school positional argument style if named fails
        uiLocalNotificationDateInterpretation: 
            UILocalNotificationDateInterpretation.absoluteTime,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    } catch (e) {
      print("Schedule error: $e");
    }
  }
}