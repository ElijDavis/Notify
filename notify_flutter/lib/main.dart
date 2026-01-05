import 'package:flutter/material.dart';
import 'dart:io'; // Add this for Platform check
import 'package:sqflite_common_ffi/sqflite_ffi.dart'; // Add this
import 'screens/home_screen.dart';
import 'screens/auth_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/notification_service.dart'; // Add this

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // --- WINDOWS DATABASE FIX START ---
  if (Platform.isWindows || Platform.isLinux) {
    // Initialize the database factory for desktop
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    print("Windows: SQLite FFI initialized");
  }
  // --- WINDOWS DATABASE FIX END ---

  // 1. Initialize Supabase
  await Supabase.initialize(
    url: 'https://zsqofefvkcsvalcigyti.supabase.co',
    anonKey: 'sb_publishable_5mYGQFeNIdxVdkPHBvEHFg_RLOoAQTj',
  );

  // 2. Session Recovery Logic
  final auth = Supabase.instance.client.auth;
  final session = auth.currentSession;

  if (session != null) {
    if (session.isExpired) {
      try {
        await auth.refreshSession();
        print("Supabase: Session refreshed successfully.");
      } catch (e) {
        await auth.signOut();
        print("Supabase: Session refresh failed, user signed out.");
      }
    }
  }

  // 3. Initialize Notifications
  // We keep this non-awaited so the UI loads instantly
  NotificationService().init();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Check if a session already exists
    final session = Supabase.instance.client.auth.currentSession;

    return MaterialApp(
      title: 'Notify',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: session != null ? const HomeScreen() : const AuthScreen(),
    );
  }
}