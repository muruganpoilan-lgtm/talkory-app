import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  Timer? _timer, _ringPoll;
  bool _ringing = false;
  final Set<String> _seenCalls = {};

  @override
  void initState() {
    super.initState();
    loadBalance();
    _loadUnread();
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _language = p.getString('pref_language'));
    }).catchError((_) {});
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _loadUnread());
    _ringPoll = Timer.periodic(const Duration(seconds: 3), (_) => _checkIncoming());
  }

  /// A host is calling this user: show Accept / Decline, ring and vibrate until answered (max 20s).
  Future<void> _checkIncoming() async {
    if (_ringing || !mounted) return;
    try {
      final c = await widget.api.hostCallIncoming();
      final id = c?['id'] as String?;
      if (id == null || !_seenCalls.add(id)) return;
      await _showIncoming(id, (c?['partner_name'] as String?) ?? 'Host');
    } catch (_) {}
  }

  Future<void> _showIncoming(String callId, String hostName) async {
    _ringing = true;
    void ring() {
      SystemSound.play(SystemSoundType.alert);
      HapticFeedback.vibrate();
    }

    ring();
    final ringer = Timer.periodic(const Duration(milliseconds: 1500), (_) => ring());
    final nav = Navigator.of(context, rootNavigator: true);
    final timeout = Timer(const Duration(seconds: 20), () {
      if (_ringing) nav.pop();
    });
    final accept = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dctx) => AlertDialog(
        title: const Text('Incoming call'),
        content: Text('$hostName is calling you'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dctx).pop(false), child: const Text('Decline')),
          FilledButton(onPressed: () => Navigator.of(dctx).pop(true), child: const Text('Accept')),
        ],
      ),
    );
    timeout.cancel();
    ringer.cancel();
    _ringing = false;
    if (accept == false) {
      try {
        await widget.api.rejectHostCall(callId);
      } catch (_) {}
      return;
    }
    if (accept != true || !mounted) return;
    try {
      final session = await widget.api.acceptHostCall(callId);
      if (!mounted) return;
      final connected = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => CallScreen(api: widget.api, session: session, peerName: hostName, onAddCredits: openWallet)),
      );
      if (connected == true && mounted) {
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => PostCallScreen(api: widget.api, callId: session.callId, peerName: hostName, canRate: true),
        ));
      }
      loadBalance();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.status == 402 ? 'Not enough coins for this call.' : e.message)));
    } catch (_) {}
  }

  @override
  void dispose() {
    _ringPoll?.cancel();
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
