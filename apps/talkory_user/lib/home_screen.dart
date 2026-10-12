import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:talkory_core/talkory_core.dart';
import 'call_tab.dart';
import 'profile_tab.dart';
import 'wallet_screen.dart';

/// Bottom-tab shell: Call (find hosts), Chat and Profile.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.api, required this.onLogout});
  final Api api;
  final VoidCallback onLogout;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  int? _balance; // paise
  int _unread = 0;
  String? _language; // preferred language chosen in Profile
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    loadBalance();
    _loadUnread();
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _language = p.getString('pref_language'));
    }).catchError((_) {});
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _loadUnread());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadUnread() async {
    try {
      final n = await widget.api.chatUnread();
      if (mounted && n != _unread) setState(() => _unread = n);
    } catch (_) {}
  }

  Future<void> loadBalance() async {
    try {
      final b = await widget.api.walletBalance();
      if (mounted) setState(() => _balance = b);
    } catch (_) {}
  }

  Future<void> _setLanguage(String? l) async {
    setState(() => _language = l);
    try {
      final p = await SharedPreferences.getInstance();
      if (l == null) {
        await p.remove('pref_language');
      } else {
        await p.setString('pref_language', l);
      }
    } catch (_) {}
  }

  void openWallet() => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => WalletScreen(api: widget.api)))
      .then((_) => loadBalance());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(index: _tab, children: [
          CallTab(api: widget.api, balance: _balance, onWallet: openWallet, onBalanceChanged: loadBalance, onLogout: widget.onLogout, preferredLanguage: _language),
          // Only build the chat inbox while it is selected so it reloads each time it is opened
          _tab == 1
              ? ChatTab(api: widget.api, isUser: true, onBalanceChanged: () async { await loadBalance(); await _loadUnread(); }, onLogout: widget.onLogout)
              : const SizedBox.shrink(),
          ProfileTab(
            api: widget.api,
            balance: _balance,
            onWallet: openWallet,
            onLogout: widget.onLogout,
            language: _language,
            onLanguage: _setLanguage,
            active: _tab == 2,
          ),
        ]),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) {
          setState(() => _tab = i);
          if (i != 0) loadBalance();
          _loadUnread();
        },
        destinations: [
          const NavigationDestination(icon: Icon(Icons.call_outlined), selectedIcon: Icon(Icons.call), label: 'Call'),
          NavigationDestination(
            icon: Badge(isLabelVisible: _unread > 0, label: Text('$_unread'), child: const Icon(Icons.chat_bubble_outline)),
            selectedIcon: Badge(isLabelVisible: _unread > 0, label: Text('$_unread'), child: const Icon(Icons.chat_bubble)),
            label: 'Chat',
          ),
          const NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}
