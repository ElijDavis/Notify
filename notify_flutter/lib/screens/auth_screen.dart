/*import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'home_screen.dart';
// Note: You will need to add local_auth to your pubspec.yaml for biometrics
import 'package:local_auth/local_auth.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameController = TextEditingController(); // Added for Step 1
  final LocalAuthentication auth = LocalAuthentication();
  bool _isLoading = false;
  bool _isSignUpMode = false; // Toggle to show/hide username field

  Future<void> _handleAuth() async {
    setState(() => _isLoading = true);
    try {
      if (_isSignUpMode) {
        await Supabase.instance.client.auth.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
          data: {'username': _usernameController.text.trim()}, // Stores in metadata
        );
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Check your email to confirm!')));
      } else {
        await Supabase.instance.client.auth.signInWithPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
        _navigateToHome();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _authenticateWithBiometrics() async {
    try {
      // 1. Check if hardware supports it
      final bool canAuthenticateWithBiometrics = await auth.canCheckBiometrics;
      final bool canAuthenticate = canAuthenticateWithBiometrics || await auth.isDeviceSupported();

      if (canAuthenticate) {
        // 2. Trigger the OS popup
        final bool didAuthenticate = await auth.authenticate(
          localizedReason: 'Please authenticate to access your notes',
          options: const AuthenticationOptions(biometricOnly: true),
        );

        if (didAuthenticate) {
          // 3. IMPORTANT: Biometrics only "unlocks" the UI. 
          // You must have a saved Supabase session to actually "log in".
          if (Supabase.instance.client.auth.currentSession != null) {
            _navigateToHome();
          } else {
            throw "No saved session. Please login with password first.";
          }
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  // Placeholder for SSO - requires dashboard config
  Future<void> _handleSSOLogin(OAuthProvider provider) async {
    try {
      await Supabase.instance.client.auth.signInWithOAuth(provider);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  void _navigateToHome() {
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const HomeScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(elevation: 0, backgroundColor: Colors.transparent, iconTheme: const IconThemeData(color: Colors.black)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_isSignUpMode ? "Create Account" : "Welcome Back", 
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(_isSignUpMode ? "Register to start organizing" : "Sign in to access your notes"),
            const SizedBox(height: 30),
            
            if (_isSignUpMode) ...[
              TextField(controller: _usernameController, decoration: const InputDecoration(labelText: 'Username', border: OutlineInputBorder())),
              const SizedBox(height: 16),
            ],
            TextField(controller: _emailController, decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder())),
            const SizedBox(height: 16),
            TextField(controller: _passwordController, decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()), obscureText: true),
            const SizedBox(height: 24),
            
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _handleAuth,
                child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : Text(_isSignUpMode ? "Sign Up" : "Login"),
              ),
            ),
            
            Center(
              child: TextButton(
                onPressed: () => setState(() => _isSignUpMode = !_isSignUpMode),
                child: Text(_isSignUpMode ? "Already have an account? Login" : "New here? Create an account"),
              ),
            ),
            
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Row(
                children: [
                  Expanded(child: Divider()),
                  Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text("OR")),
                  Expanded(child: Divider()),
                ],
              ),
            ),

            // SSO Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _socialIcon(Icons.g_mobiledata, () => _handleSSOLogin(OAuthProvider.google), Colors.red),
                _socialIcon(Icons.apple, () => _handleSSOLogin(OAuthProvider.apple), Colors.black),
                _socialIcon(Icons.window, () => _handleSSOLogin(OAuthProvider.azure), Colors.blue),
              ],
            ),
            
            const SizedBox(height: 30),
            // Biometric Login Button
            Center(
              child: IconButton(
                icon: const Icon(Icons.fingerprint, size: 50, color: Colors.blueGrey),
                onPressed: () {
                  // Logic for local_auth goes here
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Biometric logic triggered")));
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _socialIcon(IconData icon, VoidCallback onTap, Color color) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, size: 30, color: color),
      ),
    );
  }
}*/

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:local_auth/local_auth.dart';
import 'home_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with SingleTickerProviderStateMixin {
  // Controllers
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  
  final LocalAuthentication auth = LocalAuthentication();
  late TabController _tabController;
  
  bool _isLoading = false;
  bool _isSignUpMode = false;
  bool _otpSent = false; // Tracks if we are waiting for a code

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  // --- EMAIL AUTH LOGIC ---
  Future<void> _handleEmailAuth() async {
    setState(() => _isLoading = true);
    try {
      if (_isSignUpMode) {
        await Supabase.instance.client.auth.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
          data: {'username': _usernameController.text.trim()},
        );
        if (mounted) _showMsg('Check your email to confirm!');
      } else {
        await Supabase.instance.client.auth.signInWithPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
        _navigateToHome();
      }
    } catch (e) {
      _showMsg(e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // --- PHONE AUTH LOGIC ---
  Future<void> _sendOtp() async {
    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.auth.signInWithOtp(
        phone: _phoneController.text.trim(), // e.g., +1234567890
      );
      setState(() => _otpSent = true);
      _showMsg('OTP Sent to your phone!');
    } catch (e) {
      _showMsg(e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _verifyOtp() async {
    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.auth.verifyOTP(
        phone: _phoneController.text.trim(),
        token: _otpController.text.trim(),
        type: OtpType.sms,
      );
      _navigateToHome();
    } catch (e) {
      _showMsg(e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // --- BIOMETRICS ---
  Future<void> _authenticateWithBiometrics() async {
    final bool didAuthenticate = await auth.authenticate(
      localizedReason: 'Authenticate to access your notes',
      options: const AuthenticationOptions(biometricOnly: true),
    );
    if (didAuthenticate && Supabase.instance.client.auth.currentSession != null) {
      _navigateToHome();
    }
  }

  void _navigateToHome() {
    if (mounted) {
      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const HomeScreen()), (r) => false);
    }
  }

  void _showMsg(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notify Login'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [Tab(text: "Email"), Tab(text: "Phone")],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildEmailTab(),
          _buildPhoneTab(),
        ],
      ),
    );
  }

  Widget _buildEmailTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          if (_isSignUpMode) 
            TextField(controller: _usernameController, decoration: const InputDecoration(labelText: 'Username')),
          TextField(controller: _emailController, decoration: const InputDecoration(labelText: 'Email')),
          TextField(controller: _passwordController, decoration: const InputDecoration(labelText: 'Password'), obscureText: true),
          const SizedBox(height: 20),
          _isLoading 
            ? const CircularProgressIndicator()
            : ElevatedButton(onPressed: _handleEmailAuth, child: Text(_isSignUpMode ? "Sign Up" : "Login")),
          TextButton(
            onPressed: () => setState(() => _isSignUpMode = !_isSignUpMode),
            child: Text(_isSignUpMode ? "Have an account? Login" : "New? Create Account"),
          ),
          _buildSocialRow(),
        ],
      ),
    );
  }

  Widget _buildPhoneTab() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          TextField(
            controller: _phoneController, 
            decoration: const InputDecoration(labelText: 'Phone Number (e.g. +1...)'),
            keyboardType: TextInputType.phone,
            enabled: !_otpSent,
          ),
          if (_otpSent) ...[
            const SizedBox(height: 16),
            TextField(controller: _otpController, decoration: const InputDecoration(labelText: 'Enter 6-Digit Code')),
          ],
          const SizedBox(height: 20),
          _isLoading 
            ? const CircularProgressIndicator()
            : ElevatedButton(
                onPressed: _otpSent ? _verifyOtp : _sendOtp, 
                child: Text(_otpSent ? "Verify Code" : "Send OTP"),
              ),
          if (_otpSent) 
            TextButton(onPressed: () => setState(() => _otpSent = false), child: const Text("Change Number")),
          const Spacer(),
          IconButton(icon: const Icon(Icons.fingerprint, size: 50), onPressed: _authenticateWithBiometrics),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildSocialRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(icon: const Icon(Icons.g_mobiledata, size: 40, color: Colors.red), onPressed: () {}),
        IconButton(icon: const Icon(Icons.apple, size: 30), onPressed: () {}),
        IconButton(icon: const Icon(Icons.window, size: 30, color: Colors.blue), onPressed: () {}),
      ],
    );
  }
}