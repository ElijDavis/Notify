import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'home_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  Future<void> _handleAuth(bool isSignUp) async {
    setState(() => _isLoading = true);
    try {
      if (isSignUp) {
        await Supabase.instance.client.auth.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Check your email or try logging in!')));
      // Inside _handleAuth, update the success block for Sign In:
      } else {
        await Supabase.instance.client.auth.signInWithPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
        
        if (mounted) {
          // This clears the navigation stack so the new user starts fresh
          Navigator.pushAndRemoveUntil(
            context, 
            MaterialPageRoute(builder: (context) => const HomeScreen()),
            (route) => false,
          );
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notify Login')),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            TextField(controller: _emailController, decoration: const InputDecoration(labelText: 'Email')),
            TextField(controller: _passwordController, decoration: const InputDecoration(labelText: 'Password'), obscureText: true),
            const SizedBox(height: 20),
            _isLoading 
              ? const CircularProgressIndicator() 
              : Row(
                  children: [
                    Expanded(child: ElevatedButton(onPressed: () => _handleAuth(false), child: const Text('Login'))),
                    const SizedBox(width: 10),
                    Expanded(child: OutlinedButton(onPressed: () => _handleAuth(true), child: const Text('Sign Up'))),
                  ],
                ),
          ],
        ),
      ),
    );
  }
}