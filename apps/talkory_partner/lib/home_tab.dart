import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:talkory_core/talkory_core.dart';
import 'earnings_screen.dart';
import 'contract_screen.dart';
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
  String _status = 'offline'; // 'online' | 'busy' | 'offline'
  Map<String, dynamic>? _ot; // today's online time vs the daily minimum
  Map<String, dynamic>? _wt; // this week's call hours and Paradise level
  Timer? _otTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _otTimer = Timer.periodic(const Duration(minutes: 1), (_) => _loadOnline());
  }

  @override
  void dispose() {
    _otTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadOnline() async {
    try {
      final o = await widget.api.onlineToday();
      if (mounted) setState(() => _ot = o);
    } catch (_) {}
    try {
      final w = await widget.api.weeklyTier();
      if (mounted) setState(() => _wt = w);
    } catch (_) {}
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  bool _contractAsked = false; // open the agreement automatically once per app start

  Future<void> _load() async {
    try {
      final p = await widget.api.myProfile();
      final e = await widget.api.partnerEarnings();
      _loadOnline();
      if (p['kyc'] == 'approved') {
        try {
          final c = await widget.api.partnerContract();
          if (mounted) setState(() => _contractSigned = c['signed'] == true);
          if (mounted && c['signed'] != true && !_contractAsked) {
            _contractAsked = true;
            _openContract();
          }
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _profile = p;
          _earn = e;
          _status = (p['status'] as String?) ?? (p['isOnline'] == true ? 'online' : 'offline');
        });
      }
    } on ApiException catch (e) {
      if (e.status == 401) widget.onLogout();
    } catch (_) {}
  }

  bool _contractSigned = true;

  Future<void> _openContract() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ContractScreen(api: widget.api)));
    _load();
  }

  Future<void> _setStatus(String value) async {
    try {
      await widget.api.setStatus(value);
      setState(() => _status = value);
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

  /// Weekly Paradise level from call hours (Monday to Sunday).
  Widget _tierCard() {
    final w = _wt!;
    final cur = Map<String, dynamic>.from(w['tier'] as Map);
    final next = w['next'] == null ? null : Map<String, dynamic>.from(w['next'] as Map);
    final last = Map<String, dynamic>.from(w['lastWeek'] as Map);
    final lastTier = Map<String, dynamic>.from(last['tier'] as Map);
    final secs = (w['seconds'] as num).toInt();
    final style = tierStyle(cur['key'] as String?);
    final goalHours = next == null ? (cur['minHours'] as num).toInt() : (next['minHours'] as num).toInt();
    final double progress = goalHours == 0 ? 1.0 : (secs / (goalHours * 3600)).clamp(0.0, 1.0).toDouble();
    return SoftCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('This week on calls', style: const TextStyle(fontWeight: FontWeight.w700, color: kInk))),
            TierChip(tier: cur['key'] as String?, name: cur['name'] as String?, small: false),
          ]),
          const SizedBox(height: 8),
          Text(tierHours(secs), style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: style.color)),
          const SizedBox(height: 6),
          ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: progress, minHeight: 8, color: style.color, backgroundColor: style.color.withAlpha(38))),
          const SizedBox(height: 8),
          Text(
            next == null
                ? 'You are at the top level this week. Keep it up!'
                : '${tierHours((next['secondsToGo'] as num).toInt())} more on calls to reach ${next['name']}.',
            style: const TextStyle(color: Colors.black54, fontSize: 12),
          ),
          const SizedBox(height: 2),
          Text('Last week: ${tierHours((last['seconds'] as num).toInt())} · ${lastTier['name']}. Levels restart every Monday.',
              style: const TextStyle(color: Colors.black45, fontSize: 11)),
        ]),
      ),
    );
  }

  /// Daily goal: be Online for 4 hours. Shows progress and what a shortfall costs.
  Widget _onlineGoalCard() {
    final done = (_ot!['seconds'] as num).toInt();
    final need = (_ot!['requiredSeconds'] as num).toInt();
    final block = (_ot!['blockMinutes'] as num).toInt();
    final pen = (_ot!['penaltyPaise'] as num).toInt();
    String hm(int sec) {
      final h = sec ~/ 3600, m = (sec % 3600) ~/ 60;
      return h > 0 ? '${h}h ${m}m' : '${m}m';
    }

    final met = done >= need;
    return SoftCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(met ? Icons.check_circle : Icons.schedule, color: met ? Colors.green : kRoyal, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text("Today's online time", style: const TextStyle(fontWeight: FontWeight.w700, color: kInk))),
            Text('${hm(done)} / ${hm(need)}', style: const TextStyle(fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 8),
          ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: (done / need).clamp(0.0, 1.0), minHeight: 8, color: met ? Colors.green : kRoyal)),
          const SizedBox(height: 8),
          Text(
            met
                ? 'Daily goal done. Thank you!'
                : 'Stay Online for ${hm(need)} every day. For each $block minutes short, ${_rs(pen)} is deducted from your earnings at midnight. Busy and Offline time does not count.',
            style: const TextStyle(color: Colors.black54, fontSize: 12),
          ),
        ]),
      ),
    );
  }

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
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(_status == 'online' ? Icons.wifi_tethering : _status == 'busy' ? Icons.do_not_disturb_on_outlined : Icons.wifi_tethering_off,
                          color: _status == 'online' ? Colors.green : _status == 'busy' ? Colors.orange : Colors.grey),
                      const SizedBox(width: 10),
                      Text(_status == 'online' ? 'You are online' : _status == 'busy' ? 'You are busy' : 'You are offline',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: kInk)),
                    ]),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<String>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(value: 'online', label: Text('Online')),
                          ButtonSegment(value: 'busy', label: Text('Busy')),
                          ButtonSegment(value: 'offline', label: Text('Offline')),
                        ],
                        selected: {_status},
                        onSelectionChanged: (v) => _setStatus(v.first),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _status == 'online'
                          ? 'Incoming calls will ring even if the app is closed'
                          : _status == 'busy'
                              ? 'Shown as Busy: users can see you but cannot call'
                              : 'Go online to start receiving calls',
                      style: const TextStyle(color: Colors.black54, fontSize: 13),
                    ),
                  ]),
                ),
              ),
            ),
            if (kyc == 'approved' && !_contractSigned)
              SoftCard(
                color: const Color(0xFFFFF3CD),
                child: ListTile(
                  leading: const Icon(Icons.draw_outlined, color: Colors.black87),
                  title: const Text('Sign your agreement', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w700)),
                  subtitle: const Text('Required before you can go online', style: TextStyle(color: Colors.black87)),
                  trailing: const Icon(Icons.chevron_right, color: Colors.black87),
                  onTap: _openContract,
                ),
              ),
            if (_ot != null && _ot!['enabled'] == true && kyc == 'approved') _onlineGoalCard(),
            if (_wt != null && kyc == 'approved') _tierCard(),
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
