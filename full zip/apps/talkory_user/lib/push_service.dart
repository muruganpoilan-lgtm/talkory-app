import 'dart:async';
import 'dart:io' show Platform;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:talkory_core/talkory_core.dart';

final messengerKey = GlobalKey<ScaffoldMessengerState>();

/// Firebase from --dart-define values (no google-services.json needed). Returns false when it is not set up:
/// the app then works normally, just without "host is online" notifications.
Future<bool> initFirebase() async {
  try {
    const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
    if (apiKey.isEmpty) {
      await Firebase.initializeApp();
    } else {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: apiKey,
          appId: String.fromEnvironment('FIREBASE_APP_ID'),
          messagingSenderId: String.fromEnvironment('FIREBASE_SENDER_ID'),
          projectId: String.fromEnvironment('FIREBASE_PROJECT_ID'),
        ),
      );
    }
    return true;
  } catch (_) {
    return false;
  }
}

/// Registers this phone for "a host is online" notifications. Everything here is best effort and never throws.
class UserPush {
  UserPush._();
  static final instance = UserPush._();

  bool _firebaseReady = false;
  String? _token;
  Api? _api;
  StreamSubscription? _refresh, _fg;

  Future<void> init() async => _firebaseReady = await initFirebase();

  Future<void> start(Api api) async {
    _api = api;
    if (!_firebaseReady) return;
    try {
      final fm = FirebaseMessaging.instance;
      await fm.requestPermission(alert: true, sound: true, badge: false);
      await _register(await fm.getToken());
      await _refresh?.cancel();
      _refresh = fm.onTokenRefresh.listen(_register);
      await _fg?.cancel();
      // App open: the system shows nothing, so show a small banner instead.
      _fg = FirebaseMessaging.onMessage.listen((m) {
        final n = m.notification;
        if (n == null) return;
        messengerKey.currentState?.showSnackBar(SnackBar(content: Text(n.title ?? 'A host is online')));
      });
    } catch (_) {}
  }

  Future<void> _register(String? token) async {
    if (token == null) return;
    _token = token;
    try {
      await _api?.registerDevice(platform: Platform.isIOS ? 'ios' : 'android', pushToken: token);
    } catch (_) {} // retried next app start / token refresh
  }

  Future<void> stop() async {
    await _refresh?.cancel();
    await _fg?.cancel();
    final t = _token;
    if (t != null) {
      try {
        await _api?.unregisterDevice(t);
      } catch (_) {}
    }
    _token = null;
  }
}
