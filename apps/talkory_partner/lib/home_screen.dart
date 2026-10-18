import 'dart:async';
import 'package:flutter/material.dart';
import 'package:talkory_core/talkory_core.dart';
import 'calls_tab.dart';
import 'home_tab.dart';
import 'partner_profile_tab.dart';
import 'push_service.dart';

/// Bottom-tab shell: Home (online switch + today), Calls (history), Chat and Profile.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.api, required this.onLogout});
  final Api api;
  final VoidCallback onLogout;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  int _unread = 0;
  Timer? _timer;

  Future<void> _loadUnread() async {
    try {
      final n = await widget.api.chatUnread();
      if (mounted && n != _unread) setState(() => _unread = n);
    } catch (_) {}
  }

  @override
  void dispose() {
    AdminCallWatcher.instance.stop();
    _timer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadUnread();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _loadUnread());
    // Registers this phone for call alerts and listens for accept/decline from the call screen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PushService.instance.start(widget.api).catchError((_) {});
      AdminCallWatcher.instance.start(context, widget.api);
    });
    // A few seconds later, so the location box does not collide with the notification box.
    Future.delayed(const Duration(seconds: 4), () { if (mounted) LocationShare.share(widget.api); });
  }

  @override
  Widget build(BuildContext context) {
    // Only the selected tab is built, so each tab reloads fresh data whenever it is opened.
    final tabs = <Widget>[
      HomeTab(api: widget.api, onLogout: widget.onLogout),
      CallsTab(api: widget.api),
      ChatTab(api: widget.api, isUser: false, onBalanceChanged: _loadUnread, onLogout: widget.onLogout),
      PartnerProfileTab(api: widget.api, onLogout: widget.onLogout),
    ];
    return Scaffold(
      body: SafeArea(top: false, child: tabs[_tab]),
      bottomNavigationBar: FloatingNav(
          child: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) {
          setState(() => _tab = i);
          _loadUnread();
        },
        destinations: [
          const NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          const NavigationDestination(icon: Icon(Icons.call_outlined), selectedIcon: Icon(Icons.call), label: 'Calls'),
          NavigationDestination(
            icon: Badge(isLabelVisible: _unread > 0, label: Text('$_unread'), child: const Icon(Icons.chat_bubble_outline)),
            selectedIcon: Badge(isLabelVisible: _unread > 0, label: Text('$_unread'), child: const Icon(Icons.chat_bubble)),
            label: 'Chat',
          ),
          const NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
        ],
      )),
    );
  }
}
