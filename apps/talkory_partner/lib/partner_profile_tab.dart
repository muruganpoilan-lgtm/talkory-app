import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:talkory_core/talkory_core.dart';
import 'earnings_screen.dart';
import 'intro_screen.dart';
import 'kyc_screen.dart';
import 'profile_screen.dart';

class PartnerProfileTab extends StatefulWidget {
  const PartnerProfileTab({super.key, required this.api, required this.onLogout});
  final Api api;
  final VoidCallback onLogout;
  @override
  State<PartnerProfileTab> createState() => _PartnerProfileTabState();
}

class _PartnerProfileTabState extends State<PartnerProfileTab> {
  Map<String, dynamic>? _p, _me;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await widget.api.myProfile();
      final me = await widget.api.accountMe();
      if (mounted) setState(() { _p = p; _me = me; });
    } catch (_) {}
  }

  void _open(Widget screen) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen)).then((_) => _load());

  Widget _row(IconData icon, String title, {String? subtitle, VoidCallback? onTap}) {
    final scheme = Theme.of(context).colorScheme;
    return SoftCard(
      child: ListTile(
        leading: CircleAvatar(backgroundColor: scheme.primaryContainer, child: Icon(icon, color: scheme.primary)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, color: kInk)),
        subtitle: subtitle == null ? null : Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = (_p?['displayName'] as String?) ?? '';
    final tagline = (_p?['tagline'] as String?) ?? '';
    final kyc = _p?['kyc'] as String?;
    final top = MediaQuery.of(context).padding.top;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          RoyalBox(
            padding: EdgeInsets.fromLTRB(20, top + 20, 20, 28),
            child: Column(children: [
              ProfileAvatar(baseUrl: widget.api.baseUrl, name: name, url: _p?['avatarUrl'] as String?, radius: 48, ring: kGold),
              const SizedBox(height: 12),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Text(name.isEmpty ? '—' : name, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
                if (kyc == 'approved') const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.verified, color: Colors.white, size: 20)),
              ]),
              if (tagline.isNotEmpty) Text(tagline, style: const TextStyle(color: Colors.white, fontSize: 15)),
              Text((_me?['phone'] as String?) ?? '', style: const TextStyle(color: Colors.white70)),
            ]),
          ),
          const SizedBox(height: 10),
          _row(Icons.person_outline, 'My profile', subtitle: 'Name, tagline, bio, languages, rate, photo', onTap: () => _open(ProfileScreen(api: widget.api))),
          _row(
            Icons.mic_none,
            'Voice intro',
            subtitle: switch (_p?['introStatus']) {
              'pending' => 'Being reviewed',
              'rejected' => 'Not approved: tap to record again',
              'approved' => 'Live: users can play it on your card',
              _ => 'Record a short hello for your card',
            },
            onTap: () => _open(IntroScreen(api: widget.api)),
          ),
          _row(Icons.verified_user_outlined, 'Verification (KYC)',
              subtitle: kyc == 'approved' ? 'Verified' : kyc == 'rejected' ? 'Not approved: tap to fix' : 'Required before you can go online',
              onTap: () => _open(KycScreen(api: widget.api))),
          _row(Icons.account_balance_wallet_outlined, 'Earnings & payouts', onTap: () => _open(EarningsScreen(api: widget.api))),
          _row(Icons.shield_outlined, 'Privacy & Security',
              subtitle: 'Terms, Privacy Policy, delete account',
              onTap: () => showLegalSheet(context, widget.api, onAccountDeleted: widget.onLogout)),
          _row(Icons.support_agent, 'Customer Support',
              subtitle: 'Chat with the Talkory team',
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SupportScreen(api: widget.api)))),
          _row(Icons.logout, 'Logout', onTap: widget.onLogout),
        ],
      ),
    );
  }
}
