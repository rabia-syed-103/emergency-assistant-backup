import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'firebase_options.dart';
import 'models/user_model.dart';
import 'screens/auth_screen.dart';
import 'screens/contacts_list_screen.dart';
import 'screens/home_screen.dart';
import 'services/deep_link_service.dart'; // <-- ADDED
import 'config.dart'; // <-- ADDED

void main() async {
   WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await FirebaseMessaging.instance.requestPermission();
  final token = await FirebaseMessaging.instance.getToken();
  print('=== FCM DEVICE TOKEN ===');
  print(token);
  print('========================');

  // <-- ADDED: wire up FCM-based deep link handling before runApp()
  await DeepLinkService.instance.init(
     baseUrl: AppConfig.baseUrl
  );

  runApp(const EmergencyAssistantApp());
}

class EmergencyAssistantApp extends StatefulWidget {
  const EmergencyAssistantApp({super.key});

  @override
  State<EmergencyAssistantApp> createState() => _EmergencyAssistantAppState();
}

class _EmergencyAssistantAppState extends State<EmergencyAssistantApp> {
  bool _hasRegisteredDeviceForCurrentUser = false;

  UserModel _userModelFromFirebase(User user) {
    return UserModel(
      fullName: user.displayName ?? user.email ?? 'Emergency User',
      phoneNumber: user.uid,
      dateOfBirth: '',
      bloodGroup: '',
      homeAddress: '',
      passwordHash: '',
    );
  }

  Future<void> _registerCurrentDevice() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return;
    }

    try {
      final deviceToken = await FirebaseMessaging.instance.getToken();
      if (deviceToken == null || deviceToken.isEmpty) {
        print('Could not get FCM token, skipping registration.');
        return;
      }

      final idToken = await currentUser.getIdToken();
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/devices/register'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          'contact_id': currentUser.uid,
          'device_token': deviceToken,
        }),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        print('Device token registered successfully.');
      } else {
        print('Token registration failed: ${response.statusCode}');
      }
    } catch (e) {
      print('Token registration error (ignored): $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: DeepLinkService.instance.navigatorKey, // <-- ADDED
      title: 'Emergency Assistant',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.red,
        scaffoldBackgroundColor: Colors.white,
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          final user = snapshot.data;

          if (user != null) {
            if (!_hasRegisteredDeviceForCurrentUser) {
              _hasRegisteredDeviceForCurrentUser = true;
              Future.microtask(_registerCurrentDevice);
            }

            return RootScreen(currentUser: _userModelFromFirebase(user));
          }

          _hasRegisteredDeviceForCurrentUser = false;
          return const AuthScreen();
        },
      ),
    );
  }
}

class RootScreen extends StatefulWidget {
  final UserModel currentUser;
  const RootScreen({super.key, required this.currentUser});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final screens = [
      HomeScreen(currentUser: widget.currentUser),
      const ContactsListScreen(),
    ];

    return Scaffold(
      body: screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        selectedItemColor: Colors.red,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.people), label: 'Contacts'),
        ],
      ),
    );
  }
}