import 'package:flutter/material.dart';
import 'dart:io'; // Add this for Platform check
import 'package:sqflite_common_ffi/sqflite_ffi.dart'; // Add this
import 'screens/home_screen.dart';
import 'screens/auth_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/notification_service.dart'; // Add this

Future<void> main() async {

  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase
  await Supabase.initialize(
    url: 'https://zsqofefvkcsvalcigyti.supabase.co',
    anonKey: 'sb_publishable_5mYGQFeNIdxVdkPHBvEHFg_RLOoAQTj',
  );

  // 2. Initialize Notifications (Add this line)
  await NotificationService().init();

  // 1. Check if we are on Desktop (Windows, Linux, or Mac)
  if (Platform.isWindows || Platform.isLinux) {
    // 2. Initialize the database factory for desktop
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

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