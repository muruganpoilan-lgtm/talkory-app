import 'package:flutter/material.dart';
import 'package:talkory_core/talkory_core.dart';
import 'earnings_screen.dart';
import 'kyc_screen.dart';
import 'profile_screen.dart';
import 'push_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.api, required this.onLogout});
  final Api api;
  final VoidCallback onLogout;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _online = false;

  @override
  void initState() {
    super.initState();
    // Registers this phone for call alerts and listens for accept/decline from the call screen.
    WidgetsBinding.instance.addPostFrameCallback((_) => PushService.instance.start(widget.api).catchError((_) {}));
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _toggle(bool value) async {
    try {
      await widget.api.setOnline(value);
      setState(() => _online = value);
    } on ApiException catch (e) {
      if (e.status == 401) return widget.onLogout();
      _snack(e.message);
    } catch (_) {
      _snack('Network error. Try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Talkory Partner'),
        actions: [
          IconButton(onPressed: () => showLegalSheet(context, widget.api, onAccountDeleted: widget.onLogout), icon: const Icon(Icons.info_outline)),
          IconButton(onPressed: widget.onLogout, icon: const Icon(Icons.logout)),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Card(
              child: SwitchListTile(
                value: _online,
                onChanged: _toggle,
                title: Text(_online ? 'You are online' : 'You are offline'),
                subtitle: Text(_online
                    ? 'Incoming calls will ring even if the app is closed'
                    : 'Go online to start receiving calls'),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: const Icon(Icons.verified_user_outlined),
                title: const Text('Verification (KYC)'),
                subtitle: const Text('Required before you can go online'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => KycScreen(api: widget.api)),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: const Icon(Icons.person_outline),
                title: const Text('My profile'),
                subtitle: const Text('Name, bio, languages and your rate per minute'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => ProfileScreen(api: widget.api)),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: const Icon(Icons.account_balance_wallet_outlined),
                title: const Text('Earnings & payouts'),
                subtitle: const Text('Balance, call history, withdrawals'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => EarningsScreen(api: widget.api)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
