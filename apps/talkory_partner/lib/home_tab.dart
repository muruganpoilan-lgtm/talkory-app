import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  Widget _stat(String label, String value, IconData icon) => Expanded(
        child: SoftCard(
          margin: const EdgeInsets.fromLTRB(6, 6, 6, 6),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 10),
              Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: kInk)),
              const SizedBox(height: 2),
              Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final name = (_profile?['displayName'] as String?) ?? '';
    final kyc = _profile?['kyc'] as String?;
    final scheme = Theme.of(context).colorScheme;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: RefreshIndicator(
        onRefresh: _load,
        edgeOffset: 80,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            GradientHeader(
              title: name.isEmpty ? 'Talkory Partner' : 'Hi, $name',
              subtitle: 'Talkory Partner',
              bottomPadding: 56,
              trailing: ProfileAvatar(baseUrl: widget.api.baseUrl, name: name, url: _profile?['avatarUrl'] as String?, radius: 26, ring: kGold),
            ),
            Transform.translate(
              offset: const Offset(0, -34),
              child: SoftCard(
                child: SwitchListTile(
                  value: _online,
                  onChanged: _toggle,
                  activeColor: Colors.green,
                  secondary: CircleAvatar(
                    backgroundColor: _online ? Colors.green.shade50 : Colors.grey.shade200,
                    child: Icon(_online ? Icons.wifi_tethering : Icons.wifi_tethering_off, color: _online ? Colors.green : Colors.grey),
                  ),
                  title: Text(_online ? 'You are online' : 'You are offline', style: const TextStyle(fontWeight: FontWeight.w700, color: kInk)),
                  subtitle: Text(_online ? 'Incoming calls will ring even if the app is closed' : 'Go online to start receiving calls'),
                ),
              ),
            ),
            if (kyc != null && kyc != 'approved')
              SoftCard(
                color: const Color(0xFFFFF3CD),
                child: ListTile(
                  leading: const Icon(Icons.verified_user_outlined, color: Colors.black87),
                  title: const Text('Complete verification', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w700)),
                  subtitle: const Text('Required before you can go online', style: TextStyle(color: Colors.black87)),
                  trailing: const Icon(Icons.chevron_right, color: Colors.black87),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => KycScreen(api: widget.api))).then((_) => _load()),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(children: [
                _stat('Earned today', _earn == null ? '—' : _rs(_earn!['today']), Icons.trending_up),
                _stat('Balance', _earn == null ? '—' : _rs(_earn!['balance']), Icons.account_balance_wallet_outlined),
              ]),
            ),
            SoftCard(
              child: ListTile(
                leading: CircleAvatar(backgroundColor: scheme.primaryContainer, child: Icon(Icons.payments_outlined, color: scheme.primary)),
                title: const Text('Earnings & payouts', style: TextStyle(fontWeight: FontWeight.w700, color: kInk)),
                subtitle: const Text('Balance, call history, withdrawals'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => EarningsScreen(api: widget.api))).then((_) => _load()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
