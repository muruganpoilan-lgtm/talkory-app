import 'package:flutter/material.dart';
import 'package:talkory_core/talkory_core.dart';
import 'home_screen.dart';
import 'push_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await UserPush.instance.init();
  final api = Api();
  await api.load();
  runApp(TalkoryApp(api: api));
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
      scaffoldMessengerKey: messengerKey,
      debugShowCheckedModeBanner: false,
      theme: talkoryTheme(const Color(0xFF5B3DF5)),
      home: _loggedIn
          ? HomeScreen(api: widget.api, onLogout: () async {
              await UserPush.instance.stop();
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
