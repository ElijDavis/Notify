import 'package:flutter/material.dart';
import 'screens/home_screen.dart'; // Import your screen

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Notify',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: const HomeScreen(), // Set HomeScreen as the starting page
    );
  }
}