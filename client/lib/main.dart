import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/sign_up_screen.dart';
import 'screens/users_list_screen.dart';
import 'services/api_service.dart';
import 'services/fcm_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase
  try {
    await Firebase.initializeApp();
  } catch (e) {
    print('Firebase initialization error: $e');
    // Continue without Firebase if not configured
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WebRTC Client',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  bool _isLoading = true;
  bool _isRegistered = false;

  @override
  void initState() {
    super.initState();
    _checkRegistration();
  }

  Future<void> _checkRegistration() async {
    final prefs = await SharedPreferences.getInstance();
    final deviceId = prefs.getString('deviceId');
    
    if (deviceId != null && deviceId.isNotEmpty) {
      setState(() {
        _isRegistered = true;
        _isLoading = false;
      });
      // Send user info on app start
      _sendUserInfoOnStart();
    } else {
      setState(() {
        _isRegistered = false;
        _isLoading = false;
      });
    }
  }

  Future<void> _sendUserInfoOnStart() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final deviceId = prefs.getString('deviceId');
      final deviceName = prefs.getString('deviceName');
      final fcmToken = await FCMService.getToken();

      if (deviceId != null && deviceName != null) {
        await ApiService.registerDevice(
          deviceId: deviceId,
          deviceName: deviceName,
          fcmToken: fcmToken,
        );
      }
    } catch (e) {
      print('Error sending user info on start: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_isRegistered) {
      return const UsersListScreen();
    }

    return const SignUpScreen();
  }
}

