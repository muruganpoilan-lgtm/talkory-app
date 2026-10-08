import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:talkory_core/talkory_core.dart';
import 'home_screen.dart';
import 'push_service.dart';

/// Firebase from --dart-define values (no google-services.json needed), else the platform config files.
/// Returns false if Firebase is not configured: the app then works, just without incoming-call alerts.
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

/// Runs when a push arrives while the app is in the background or killed (Android).
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  await initFirebase();
  await handlePushData(message.data);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (await initFirebase()) FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);

  final api = Api();
  await api.load();
  await SentryFlutter.init(
    (o) {
      o.dsn = const String.fromEnvironment('SENTRY_DSN'); // empty = disabled. Pass with --dart-define=SENTRY_DSN=...
      o.sendDefaultPii = false;
      o.tracesSampleRate = 0;
    },
    appRunner: () => runApp(PartnerApp(api: api)),
  );
}

class PartnerApp extends StatefulWidget {
  const PartnerApp({super.key, required this.api});
  final Api api;
  @override
  State<PartnerApp> createState() => _PartnerAppState();
}

class _PartnerAppState extends State<PartnerApp> {
  late bool _loggedIn = widget.api.token != null;

  Future<void> _logout() async {
    try {
      await widget.api.setOnline(false); // don't stay listed as online after signing out
    } catch (_) {}
    await PushService.instance.stop();
    await widget.api.logout();
    if (mounted) setState(() => _loggedIn = false);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Talkory Partner',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF00A884), useMaterial3: true),
      home: _loggedIn
          ? HomeScreen(api: widget.api, onLogout: _logout)
          : LoginScreen(
              api: widget.api,
              role: 'partner',
              title: 'Talkory Partner',
              onLoggedIn: () => setState(() => _loggedIn = true),
            ),
    );
  }
}
