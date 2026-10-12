import 'package:flutter/material.dart';
import 'package:talkory_core/talkory_core.dart';
import 'earnings_screen.dart';
import 'kyc_screen.dart';

String _rs(num paise) => '₹${(paise / 100).toStringAsFixed(2)}';

class HomeTab extends StatefulWidget {
  const HomeTab({super.key, required this.api, required this.onLogout});
  final Api api;
  final VoidCallback onLogout;
  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  Map<String, dynamic>? _profile, _earn;
  bool _online = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _load() async {
    try {
      final p = await widget.api.myProfile();
      final e = await widget.api.partnerEarnings();
      if (mounted) {
        setState(() {
          _profile = p;
          _earn = e;
          _online = p['isOnline'] == true;
        });
      }
    } on ApiException catch (e) {
      if (e.status == 401) widget.onLogout();
    } catch (_) {}
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

  Widget _stat(String label, String value) => Expanded(
        child: Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final name = (_profile?['displayName'] as String?) ?? '';
    final kyc = _profile?['kyc'] as String?;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Talkory Partner', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
          if (name.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('Hello, $name')),
          const SizedBox(height: 12),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: SwitchListTile(
              value: _online,
              onChanged: _toggle,
              title: Text(_online ? 'You are online' : 'You are offline'),
              subtitle: Text(_online ? 'Incoming calls will ring even if the app is closed' : 'Go online to start receiving calls'),
            ),
          ),
          if (kyc != null && kyc != 'approved')
            Card(
              color: const Color(0xFFFFF3CD),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: ListTile(
                leading: const Icon(Icons.verified_user_outlined, color: Colors.black87),
                title: const Text('Complete verification', style: TextStyle(color: Colors.black87)),
                subtitle: const Text('Required before you can go online', style: TextStyle(color: Colors.black87)),
                trailing: const Icon(Icons.chevron_right, color: Colors.black87),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => KycScreen(api: widget.api))).then((_) => _load()),
              ),
            ),
          const SizedBox(height: 4),
          Row(children: [
            _stat('Earned today', _earn == null ? '—' : _rs(_earn!['today'])),
            _stat('Balance', _earn == null ? '—' : _rs(_earn!['balance'])),
          ]),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: ListTile(
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: const Text('Earnings & payouts'),
              subtitle: const Text('Balance, call history, withdrawals'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => EarningsScreen(api: widget.api))).then((_) => _load()),
            ),
          ),
        ],
      ),
    );
  }
}
