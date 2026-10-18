import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:talkory_core/talkory_core.dart';

class CallTab extends StatefulWidget {
  const CallTab({
    super.key,
    required this.api,
    required this.balance,
    required this.onWallet,
    required this.onBalanceChanged,
    required this.onLogout,
    this.preferredLanguage,
  });
  final String? preferredLanguage; // from Profile > Language; null = all
  final Api api;
  final int? balance; // paise
  final VoidCallback onWallet, onLogout;
  final Future<void> Function() onBalanceChanged;

  @override
  State<CallTab> createState() => _CallTabState();
}

class _CallTabState extends State<CallTab> {
  final _search = TextEditingController();
  Timer? _debounce;
  late String? _language = widget.preferredLanguage;
  late Future<List<Partner>> _future = _load();
  Timer? _friendTimer;
  List<Partner> _friends = [];
  final Set<String> _dismissed = {}; // best friends whose banner was closed during this visit

  @override
  void initState() {
    super.initState();
    _loadFriends();
    _friendTimer = Timer.periodic(const Duration(seconds: 20), (_) => _loadFriends());
  }

  Future<void> _loadFriends() async {
    try {
      final f = await widget.api.bestFriendsOnline();
      if (mounted) {
        setState(() {
          _friends = f;
          _dismissed.removeWhere((id) => !f.any((p) => p.id == id)); // went offline: show the banner again when they return
        });
      }
    } catch (_) {}
  }

  @override
  void didUpdateWidget(CallTab old) {
    super.didUpdateWidget(old);
    if (old.preferredLanguage != widget.preferredLanguage) {
      _language = widget.preferredLanguage;
      _reload();
    }
  }

  void _chat(Partner p) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ChatScreen(api: widget.api, otherId: p.id, otherName: p.name, isUser: true),
      )).then((_) => widget.onBalanceChanged());

  Future<List<Partner>> _load() => widget.api.listPartners(language: _language, query: _search.text.trim());

  void _reload() => setState(() => _future = _load());

  @override
  void dispose() {
    _debounce?.cancel();
    _friendTimer?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _reload);
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _call(Partner p) async {
    try {
      final session = await widget.api.startCall(p.id);
      if (!mounted) return;
      final connected = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => CallScreen(api: widget.api, session: session, peerName: p.name, onAddCredits: widget.onWallet)),
      );
      if (connected == true && mounted) {
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => PostCallScreen(api: widget.api, callId: session.callId, peerName: p.name, canRate: true),
        ));
      }
      widget.onBalanceChanged();
      _reload();
    } on ApiException catch (e) {
      if (e.status == 401) return widget.onLogout();
      if (!mounted) return;
      if (e.status == 402) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Not enough coins for this call.'),
          action: SnackBarAction(label: 'Add coins', onPressed: widget.onWallet),
        ));
      } else {
        _snack(e.message);
      }
    } catch (_) {
      _snack('Network error. Try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final friend = _friends.where((f) => !_dismissed.contains(f.id)).firstOrNull;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Column(
      children: [
        RoyalBox(
          padding: EdgeInsets.fromLTRB(16, top + 12, 16, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: NameSearchField(controller: _search, onChanged: _onSearchChanged)),
              const SizedBox(width: 10),
              InkWell(
                onTap: widget.onWallet,
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(color: kGold, borderRadius: BorderRadius.circular(999)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.monetization_on, size: 18, color: kRoyalDeep),
                    const SizedBox(width: 6),
                    Text(widget.balance == null ? '—' : formatCoins(widget.balance!),
                        style: const TextStyle(color: kRoyalDeep, fontWeight: FontWeight.w800)),
                  ]),
                ),
              ),
            ]),
            const SizedBox(height: 16),
            const Text('Talkory', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
            const SizedBox(height: 2),
            const Text('Talk to someone who listens', style: TextStyle(color: Colors.white70, fontSize: 14)),
          ]),
        ),
        SizedBox(
          height: 54,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              for (final l in [null, ...kLanguages])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(l ?? 'All'),
                    selected: _language == l,
                    showCheckmark: false,
                    selectedColor: kInk,
                    backgroundColor: Colors.white,
                    side: BorderSide.none,
                    shape: const StadiumBorder(),
                    labelStyle: TextStyle(color: _language == l ? Colors.white : kInk, fontWeight: FontWeight.w500),
                    onSelected: (_) {
                      _language = l;
                      _reload();
                    },
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              widget.onBalanceChanged();
                      _reload();
              await _future;
            },
            child: FutureBuilder<List<Partner>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
                if (snap.hasError) {
                  final e = snap.error;
                  if (e is ApiException && e.status == 401) WidgetsBinding.instance.addPostFrameCallback((_) => widget.onLogout());
                  return ListView(children: [Padding(padding: const EdgeInsets.all(32), child: Text('Could not load hosts.\n$e'))]);
                }
                final list = snap.data!;
                if (list.isEmpty) {
                  return ListView(children: const [Padding(padding: EdgeInsets.all(32), child: Text('No hosts online right now. Pull down to refresh.'))]);
                }
                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: list.length,
                  itemBuilder: (_, i) => HostCard(p: list[i], baseUrl: widget.api.baseUrl, onCall: () => _call(list[i]), onChat: () => _chat(list[i])),
                );
              },
            ),
          ),
        ),
        if (friend != null) _bestFriendBanner(friend),
      ],
    ));
  }

  /// Slim "best friend is online" bar: shown while a host this user called before is online.
  Widget _bestFriendBanner(Partner f) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 6),
      padding: const EdgeInsets.fromLTRB(10, 6, 2, 6),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [kRoyalDeep, kRoyal, Color(0xFF7A3FD0)]),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x441E0A56), blurRadius: 10, offset: Offset(0, 3))],
      ),
      child: Row(children: [
        ProfileAvatar(baseUrl: widget.api.baseUrl, name: f.name, url: f.avatarUrl, radius: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('Best friend ${f.name} is online ❤', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Colors.white)),
            if (_friends.length > 1) Text('+${_friends.length - 1} more online', style: const TextStyle(fontSize: 11, color: Colors.white70)),
          ]),
        ),
        const SizedBox(width: 6),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: kGold, foregroundColor: kInk, padding: const EdgeInsets.symmetric(horizontal: 14), minimumSize: const Size(0, 34), visualDensity: VisualDensity.compact),
          onPressed: f.busy ? null : () => _call(f),
          child: Text(f.busy ? 'Busy' : 'Call', style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
        IconButton(
          icon: const Icon(Icons.close, size: 18),
          color: Colors.white70,
          visualDensity: VisualDensity.compact,
          tooltip: 'Hide',
          onPressed: () => setState(() => _dismissed.add(f.id)),
        ),
      ]),
    );
  }
}

class HostCard extends StatelessWidget {
  const HostCard({super.key, required this.p, required this.baseUrl, required this.onCall, required this.onChat});
  final Partner p;
  final String baseUrl;
  final VoidCallback onCall, onChat;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dot = p.busy ? Colors.orange : Colors.green;
    final muted = TextStyle(color: scheme.onSurfaceVariant, fontSize: 12);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [BoxShadow(color: Color(0x121B1740), blurRadius: 18, offset: Offset(0, 6))],
      ),
      child: Row(children: [
        Stack(children: [
          ProfileAvatar(baseUrl: baseUrl, name: p.name, url: p.avatarUrl, radius: 32),
          Positioned(
            right: 0,
            bottom: 2,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3)),
            ),
          ),
        ]),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(p.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: kInk))),
              if (p.verified) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.verified, size: 17, color: Colors.blue)),
            ]),
            if (p.tagline.isNotEmpty) Text(p.tagline, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurface, fontSize: 13)),
            const SizedBox(height: 2),
            Text(p.languages.join(', '), maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.star_rounded, size: 16, color: Color(0xFFFFB020)),
              const SizedBox(width: 2),
              Flexible(
                child: Text('${p.rating.toStringAsFixed(1)} · ${formatCoins(p.ratePerMin)} coins/min${p.busy ? ' · Busy' : ''}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: kInk)),
              ),
            ]),
            if (p.introUrl != null) Padding(padding: const EdgeInsets.only(top: 6), child: IntroButton(baseUrl: baseUrl, url: p.introUrl!)),
          ]),
        ),
        const SizedBox(width: 8),
        Column(mainAxisSize: MainAxisSize.min, children: [
          Opacity(
            opacity: p.busy ? 0.4 : 1,
            child: Material(
              color: Colors.transparent,
              child: Ink(
                width: 48,
                height: 48,
                decoration: BoxDecoration(gradient: brandGradient(scheme.primary), shape: BoxShape.circle),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: p.busy ? null : onCall,
                  child: const Icon(Icons.call, color: Colors.white, size: 22),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          IconButton(
            onPressed: onChat,
            tooltip: 'Chat',
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.chat_bubble_outline, size: 20, color: scheme.primary),
          ),
        ]),
      ]),
    );
  }
}
