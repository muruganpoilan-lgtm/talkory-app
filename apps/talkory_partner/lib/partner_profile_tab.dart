import 'package:flutter/material.dart';
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

  @override
  Widget build(BuildContext context) {
    final name = (_p?['displayName'] as String?) ?? '';
    final tagline = (_p?['tagline'] as String?) ?? '';
    final kyc = _p?['kyc'] as String?;
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 8),
        Center(
          child: Column(children: [
            ProfileAvatar(baseUrl: widget.api.baseUrl, name: name, url: _p?['avatarUrl'] as String?, radius: 48),
            const SizedBox(height: 12),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Text(name.isEmpty ? '—' : name, style: text.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              if (kyc == 'approved') const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.verified, color: Colors.blue, size: 20)),
            ]),
            if (tagline.isNotEmpty) Text(tagline, style: text.bodyLarge),
            Text((_me?['phone'] as String?) ?? '', style: text.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ]),
        ),
        const SizedBox(height: 16),
        ListTile(leading: const Icon(Icons.person_outline), title: const Text('My profile'), subtitle: const Text('Name, tagline, bio, languages, rate, photo'), onTap: () => _open(ProfileScreen(api: widget.api))),
        ListTile(
          leading: const Icon(Icons.mic_none),
          title: const Text('Voice intro'),
          subtitle: Text(switch (_p?['introStatus']) {
            'pending' => 'Being reviewed',
            'rejected' => 'Not approved: tap to record again',
            'approved' => 'Live: users can play it on your card',
            _ => 'Record a short hello for your card',
          }),
          onTap: () => _open(IntroScreen(api: widget.api)),
        ),
        ListTile(
          leading: const Icon(Icons.verified_user_outlined),
          title: const Text('Verification (KYC)'),
          subtitle: Text(kyc == 'approved' ? 'Verified' : kyc == 'rejected' ? 'Not approved: tap to fix' : 'Required before you can go online'),
          onTap: () => _open(KycScreen(api: widget.api)),
        ),
        ListTile(leading: const Icon(Icons.account_balance_wallet_outlined), title: const Text('Earnings & payouts'), onTap: () => _open(EarningsScreen(api: widget.api))),
        ListTile(
          leading: const Icon(Icons.shield_outlined),
          title: const Text('Privacy & Security'),
          subtitle: const Text('Terms, Privacy Policy, delete account'),
          onTap: () => showLegalSheet(context, widget.api, onAccountDeleted: widget.onLogout),
        ),
        ListTile(
          leading: const Icon(Icons.support_agent),
          title: const Text('Customer Support'),
          onTap: () {
            final email = (_me?['supportEmail'] as String?) ?? '';
            if (email.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Support contact is not set up yet')));
            } else {
              openSupport(email);
            }
          },
        ),
        ListTile(leading: const Icon(Icons.logout), title: const Text('Logout'), onTap: widget.onLogout),
      ],
    );
  }
}
