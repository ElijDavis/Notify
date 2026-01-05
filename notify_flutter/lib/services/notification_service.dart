import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:async';

class NotificationService {
  // Singleton pattern to use the same instance everywhere
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();

  // This map keeps track of active timers so we don't schedule duplicates
  final Map<String, Timer> _activeTimers = {};

  Future<void> init() async {
    // 1. Define Android settings (using the default app icon)
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');

    const initializationSettings = InitializationSettings(
      macOS: DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      ),
      android: androidSettings, // <--- ADD THIS LINE
      linux: LinuxInitializationSettings(defaultActionName: 'Open'),
    );

    // 2. Initialize
    await _notifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (details) {
        print("Notification clicked: ${details.payload}");
      },
    );

    // 3. Request Permission for Samsung (Android 13+)
    final androidPlugin = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    
    if (androidPlugin != null) {
      await androidPlugin.requestNotificationsPermission();
    }
  }

  Future<void> scheduleNotification(String id, String title, DateTime scheduledTime) async {
    final now = DateTime.now();
    final delay = scheduledTime.difference(now);

    // 1. If the time is already in the past, don't schedule
    if (delay.isNegative) {
      print("Reminder time for '$title' is in the past. Skipping.");
      return;
    }

    // 2. Cancel existing timer for this specific ID if it exists 
    // (Prevents double-notifications if you update a note)
    _activeTimers[id]?.cancel();

    // 3. Create a new timer
    print("Scheduling alarm for '$title' in ${delay.inSeconds} seconds.");
    
    _activeTimers[id] = Timer(delay, () async {
      await _showImmediateNotification(id, title);
      _activeTimers.remove(id); // Clean up after it fires
    });
  }

  // This helper uses the simple .show() method which is very stable
  Future<void> _showImmediateNotification(String id, String title) async {
    const notificationDetails = NotificationDetails(
      macOS: DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
        presentBadge: true,
      ),
    );

    await _notifications.show(
      id.hashCode.abs(),
      'Reminder',
      title,
      notificationDetails,
      payload: id,
    );
  }
  
  void cancelAll() {
    for (var timer in _activeTimers.values) {
      timer.cancel();
    }
    _activeTimers.clear();
  }
}