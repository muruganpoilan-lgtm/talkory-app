import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:talkory_core/talkory_core.dart';
import 'home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final api = Api();
  await api.load();
  await SentryFlutter.init(
    (o) {
      o.dsn = const String.fromEnvironment('SENTRY_DSN'); // empty = disabled. Pass with --dart-define=SENTRY_DSN=...
      o.sendDefaultPii = false;
      o.tracesSampleRate = 0;
    },
    appRunner: () => runApp(TalkoryApp(api: api)),
  );
}

class TalkoryApp extends StatefulWidget {
  const TalkoryApp({super.key, required this.api});
  final Api api;
  @override
  State<TalkoryApp> createState() => _TalkoryAppState();
}

class _TalkoryAppState extends State<TalkoryApp> {
  late bool _loggedIn = widget.api.token != null;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Talkory',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF6C4DFF), useMaterial3: true),
      home: _loggedIn
          ? HomeScreen(api: widget.api, onLogout: () async {
              await widget.api.logout();
              setState(() => _loggedIn = false);
            })
          : LoginScreen(
              api: widget.api,
              role: 'user',
              title: 'Talkory',
              onLoggedIn: () => setState(() => _loggedIn = true),
            ),
    );
  }
}
