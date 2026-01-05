import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:async';
import 'dart:io';

class NotificationService {
  // Singleton pattern to use the same instance everywhere
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();

  // This map keeps track of active timers so we don't schedule duplicates
  final Map<String, Timer> _activeTimers = {};

  /*Future<void> init() async {
    // 1. Define settings for each platform
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    
    // Note: For Windows, we add Darwin settings or default initialization
    // but the specific fix is ensuring the InitializationSettings object is complete.
    const initializationSettings = InitializationSettings(
      macOS: DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      ),
      android: androidSettings,
      linux: LinuxInitializationSettings(defaultActionName: 'Open'),
      // If your package version supports it, you can add Windows: here, 
      // otherwise, the Darwin/Linux settings act as the fallback for desktop.
    );

    // 2. Initialize
    await _notifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (details) {
        print("Notification clicked: ${details.payload}");
      },
    );

    // 3. Request Permission for Samsung (Android 13+)
    if (Platform.isAndroid) {
      final androidPlugin = _notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      
      if (androidPlugin != null) {
        await androidPlugin.requestNotificationsPermission();
      }
    }
  }*/

  Future<void> init() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings();
    
    // WINDOWS FIX: You MUST include linux settings for Windows to initialize correctly
    const linuxSettings = LinuxInitializationSettings(defaultActionName: 'Open');

    const initializationSettings = InitializationSettings(
      android: androidSettings,
      macOS: darwinSettings,
      linux: linuxSettings, // This is the line that stops the Windows crash
    );

    await _notifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (details) {
        print("Notification clicked: ${details.payload}");
      },
    );
    
    // Only request Android permissions if we are actually on Android
    if (Platform.isAndroid) {
      final androidPlugin = _notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestNotificationsPermission();
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
    // 1. Define Android-specific details
    // IMPORTANT: If you change these settings later, you MUST change the channel ID 
    // (e.g., to 'alarm_channel_v2') for Android to recognize the new settings.
    const androidDetails = AndroidNotificationDetails(
      'alarm_channel_high_importance', // Unique ID for the channel
      'Reminders',                     // User-visible name in system settings
      channelDescription: 'Notifications for your scheduled notes',
      importance: Importance.max,      // Makes it pop up on screen
      priority: Priority.high,         // Ensures high visibility
      playSound: true,                 // Tells Android to play the default sound
      ticker: 'ticker',
    );

    // 2. Combine with macOS details
    const notificationDetails = NotificationDetails(
      macOS: DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
        presentBadge: true,
      ),
      android: androidDetails,
    );

    // 3. Show the notification
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
    _notifications.cancelAll(); // Also clears any active system notifications
  }
}