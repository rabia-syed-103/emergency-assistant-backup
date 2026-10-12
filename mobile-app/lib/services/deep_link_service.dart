import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import '../config.dart';

import '../responder/dashboard_screen.dart'; // adjust path if dashboard_screen.dart lives elsewhere

/// FCM-based "deep link" handler for the responder app.
///
/// Expected data payload from notify_trusted_contacts():
///   { "type": "emergency_alert", "user_id": "ER-2048" }
///
/// user_id is the same id DashboardScreen uses to call
/// /emergency/<id>/status on the backend.
class DeepLinkService {
  DeepLinkService._();
  static final DeepLinkService instance = DeepLinkService._();

  /// Give this to MaterialApp(navigatorKey: ...), otherwise
  /// navigatorKey.currentState stays null and navigation silently fails.
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  String baseUrl = AppConfig.baseUrl;

  StreamSubscription<RemoteMessage>? _onMessageSub;
  StreamSubscription<RemoteMessage>? _onMessageOpenedAppSub;
  bool _initialized = false;

  /// Call once after Firebase.initializeApp(), before runApp().
  Future<void> init({String? baseUrl}) async {
    if (_initialized) return;
    _initialized = true;
    if (baseUrl != null) this.baseUrl = baseUrl;

    // 1) App was terminated, opened by tapping the notification.
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      // Navigator isn't mounted yet — wait one frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleMessage(initialMessage, openedFromTap: true);
      });
    }

    // 2) App was in background, user tapped the notification, app resumed.
    _onMessageOpenedAppSub = FirebaseMessaging.onMessageOpenedApp.listen((msg) {
      _handleMessage(msg, openedFromTap: true);
    });

    // 3) App is in foreground, message arrived silently (no tap yet).
    //    Don't force-navigate here — show a banner the responder can tap.
    _onMessageSub = FirebaseMessaging.onMessage.listen((msg) {
      _handleMessage(msg, openedFromTap: false);
    });
  }

  void dispose() {
    _onMessageSub?.cancel();
    _onMessageOpenedAppSub?.cancel();
    _initialized = false;
  }

  void _handleMessage(RemoteMessage message, {required bool openedFromTap}) {
  final data = message.data;
  if (data['type'] != 'emergency_alert') return;

  final userId = data['user_id']?.toString();
  if (userId == null || userId.isEmpty) {
    debugPrint('DeepLinkService: no user_id, data=$data');
    return;
  }

  if (openedFromTap) {
    _openDashboard(data);
  } else {
    _showForegroundBanner(data, message);
  }
}

  void _openDashboard(Map<String, dynamic> data) {
  final navState = navigatorKey.currentState;
  if (navState == null) return;

  navState.push(
    MaterialPageRoute(
      builder: (_) => DashboardScreen(
        userId: data['user_id'].toString(),
        baseUrl: baseUrl,
        userName: data['user_name']?.toString(),
        phoneNumber: data['phone_number']?.toString(),
        bloodGroup: data['blood_group']?.toString(),
      ),
    ),
  );
}

  void _showForegroundBanner(Map<String, dynamic> data, RemoteMessage message) {
  final overlayContext = navigatorKey.currentState?.overlay?.context;
  if (overlayContext == null) return;

  final name = data['user_name']?.toString() ?? 'Someone';

  ScaffoldMessenger.maybeOf(overlayContext)?.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF1A1D24),
      content: Text(
        '$name ne emergency alert bheja hai',
        style: const TextStyle(color: Colors.white),
      ),
      action: SnackBarAction(
        label: 'VIEW',
        textColor: const Color(0xFF5B8CFF),
        onPressed: () => _openDashboard(data),
      ),
      duration: const Duration(seconds: 8),
    ),
  );
}
}