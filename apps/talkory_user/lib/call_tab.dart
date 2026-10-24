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
                    elevation: 3,
                    shadowColor: const Color(0x554B22B0),
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
                  return ListView(children: const [Padding(padding: EdgeInsets.all(32), child: Text('No hosts to show right now. Pull down to refresh.'))]);
                }
                // Online hosts first, then Busy, then Offline, each under a small heading
                final items = <Object>[];
                for (final st in const ['online', 'busy', 'offline']) {
                  final group = list.where((p) => p.status == st).toList();
                  if (group.isEmpty) continue;
                  items.add(st);
                  for (var k = 0; k < group.length; k += 2) {
                    items.add(group.sublist(k, k + 2 > group.length ? group.length : k + 2));
                  }
                }
                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final it = items[i];
                    if (it is String) {
                      final label = it == 'online' ? 'ONLINE' : it == 'busy' ? 'BUSY' : 'OFFLINE';
                      final color = it == 'online' ? Colors.green.shade700 : it == 'busy' ? Colors.orange.shade800 : Colors.grey.shade600;
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(24, 12, 20, 2),
                        child: Row(children: [
                          Container(width: 9, height: 9, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                          const SizedBox(width: 8),
                          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800, letterSpacing: 1, fontSize: 12)),
                        ]),
                      );
                    }
                    final pair = it as List<Partner>;
                    Widget cell(Partner h) => Expanded(child: HostCard(p: h, baseUrl: widget.api.baseUrl, onCall: () => _call(h), onChat: () => _chat(h)));
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                      child: IntrinsicHeight(
                        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          cell(pair[0]),
                          if (pair.length > 1) cell(pair[1]) else const Expanded(child: SizedBox()),
                        ]),
                      ),
                    );
                  },
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
    final canCall = p.status == 'online';
    final stColor = p.status == 'busy' ? Colors.orange : p.status == 'offline' ? Colors.grey : Colors.greenAccent.shade400;
    final stLabel = p.status == 'busy' ? 'Busy' : p.status == 'offline' ? 'Offline' : 'Online';
    const tints = [Color(0xFFF0C4E0), Color(0xFFC4D6F2), Color(0xFFDCEBC0), Color(0xFFF0DCC0), Color(0xFFD8CCF2), Color(0xFFC0EBE3)];
    final tint = tints[p.name.codeUnits.fold<int>(0, (a, c) => a + c) % tints.length];
    final ring = p.status == 'busy' ? Colors.orange : p.status == 'offline' ? Colors.grey.shade400 : Colors.green;
    final photo = Container(
      color: tint,
      alignment: Alignment.center,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          border: Border.all(color: ring, width: 3),
          boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 10, offset: Offset(0, 4))],
        ),
        child: ProfileAvatar(baseUrl: baseUrl, name: p.name, url: p.avatarUrl, radius: 42),
      ),
    );
    Widget chip(Widget child, Color bg) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
          child: child,
        );
    return Container(
      margin: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [BoxShadow(color: Color(0x141B1740), blurRadius: 16, offset: Offset(0, 6))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: AspectRatio(
              aspectRatio: 1,
              child: Stack(fit: StackFit.expand, children: [
                photo,
                Positioned(
                  left: 8,
                  top: 8,
                  child: chip(
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(width: 8, height: 8, decoration: BoxDecoration(color: stColor, shape: BoxShape.circle)),
                      const SizedBox(width: 5),
                      Text(stLabel, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                    ]),
                    const Color(0x99000000),
                  ),
                ),
                Positioned(
                  right: 8,
                  top: 8,
                  child: chip(
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.star_rounded, size: 13, color: kGold),
                      const SizedBox(width: 2),
                      Text(p.rating.toStringAsFixed(1), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                    ]),
                    const Color(0x99000000),
                  ),
                ),
              ]),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
          child: Row(children: [
            Flexible(child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: kInk))),
            if (p.verified) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.verified, size: 16, color: Colors.blue)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 2, 12, 0),
          child: Text(p.languages.join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
        ),
        if (p.tagline.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 0),
            child: Text(p.tagline, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: kInk, fontSize: 12)),
          ),
        if (p.introUrl != null) Padding(padding: const EdgeInsets.fromLTRB(8, 4, 8, 0), child: IntroButton(baseUrl: baseUrl, url: p.introUrl!)),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
          child: Row(children: [
            InkWell(
              onTap: onChat,
              customBorder: const CircleBorder(),
              child: Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(color: Color(0xFFEDE7FA), shape: BoxShape.circle),
                child: const Icon(Icons.chat_bubble_outline, size: 19, color: kRoyal),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: kGold,
                  foregroundColor: kInk,
                  disabledBackgroundColor: const Color(0xFFE6E2EE),
                  shape: const StadiumBorder(),
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                ),
                onPressed: canCall ? onCall : null,
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.call, size: 16),
                  const SizedBox(width: 4),
                  Flexible(child: Text('${formatCoins(p.ratePerMin)}/min', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800))),
                ]),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}
