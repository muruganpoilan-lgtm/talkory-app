import 'package:flutter/material.dart';
import 'package:talkory_core/talkory_core.dart';
import 'home.dart';
import 'login.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final api = Api();
  await api.load();
  runApp(AdminApp(api: api));
}

class AdminApp extends StatefulWidget {
  const AdminApp({super.key, required this.api});
  final Api api;
  @override
  State<AdminApp> createState() => _AdminAppState();
}

class _AdminAppState extends State<AdminApp> {
  late bool _loggedIn = widget.api.token != null;

  Future<void> _logout() async {
    await widget.api.logout();
    if (mounted) setState(() => _loggedIn = false);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Talkory Admin',
      debugShowCheckedModeBanner: false,
      theme: talkoryTheme(const Color(0xFF5B3DF5)),
      home: _loggedIn
          ? AdminHome(api: widget.api, onLogout: _logout)
          : AdminLogin(api: widget.api, onLoggedIn: () => setState(() => _loggedIn = true)),
    );
  }
}
