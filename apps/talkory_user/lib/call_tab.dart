import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:talkory_core/talkory_core.dart';
import 'daily_reward.dart';

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
  bool _searching = false; // the slim header swaps to a search field
  bool _rewardWaiting = false; // today's daily reward not collected yet: red dot on the gift icon

  @override
  void initState() {
    super.initState();
    _loadReward();
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

  Future<void> _loadReward() async {
    try {
      final s = await widget.api.dailyReward();
      if (mounted) setState(() => _rewardWaiting = s['claimedToday'] != true);
    } catch (_) {}
  }

  /// The daily reward used to be a full card above the hosts; now it opens from this gift icon.
  /// A red dot shows while today's coins are waiting.
  Widget _rewardIcon() => IconButton(
        tooltip: 'Daily reward',
        visualDensity: VisualDensity.compact,
        onPressed: () async {
          await showModalBottomSheet<void>(
            context: context,
            showDragHandle: true,
            builder: (_) => SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _rewardWaiting
                    ? DailyRewardCard(api: widget.api, onCollected: widget.onBalanceChanged)
                    : const Padding(
                        padding: EdgeInsets.fromLTRB(24, 4, 24, 16),
                        child: Text("You've collected today's reward. Come back tomorrow for more coins.", textAlign: TextAlign.center),
                      ),
              ),
            ),
          );
          _loadReward();
        },
        icon: Stack(clipBehavior: Clip.none, children: [
          const Icon(Icons.card_giftcard, color: Colors.white),
          if (_rewardWaiting)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(color: const Color(0xFFFF4D4F), shape: BoxShape.circle, border: Border.all(color: kRoyal, width: 1.5)),
              ),
            ),
        ]),
      );

  @override
  void didUpdateWidget(CallTab old) {
    super.didUpdateWidget(old);
    if (old.preferredLanguage != widget.preferredLanguage) {
      _language = widget.preferredLanguage;
      _reload();
    }
  }

  void _chat(Partner p) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ChatScreen(api: widget.api, otherId: p.id, otherName: p.name, isUser: true, onAddCoins: widget.onWallet),
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
      AgoraWarm.warm(); // start the call engine while the call request is on its way
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
        // One slim bar instead of the old tall header: logo, search, daily reward, coins.
        Container(
          color: kRoyal,
          padding: EdgeInsets.fromLTRB(12, top + 6, 8, 6),
          child: _searching
              ? Row(children: [
                  Expanded(
                    child: SizedBox(
                      height: 40,
                      child: TextField(
                        controller: _search,
                        autofocus: true,
                        onChanged: _onSearchChanged,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: 'Search names',
                          isDense: true,
                          filled: true,
                          fillColor: Colors.white,
                          prefixIcon: const Icon(Icons.search, size: 20),
                          contentPadding: EdgeInsets.zero,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close search',
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () {
                      setState(() => _searching = false);
                      if (_search.text.isNotEmpty) {
                        _search.clear();
                        _reload();
                      }
                    },
                  ),
                ])
              : Row(children: [
                  const LogoBadge(size: 30),
                  const SizedBox(width: 8),
                  const Text('Talkory', style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Search names',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.search, color: Colors.white),
                    onPressed: () => setState(() => _searching = true),
                  ),
                  _rewardIcon(),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: widget.onWallet,
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(color: kGold, borderRadius: BorderRadius.circular(999)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.monetization_on, size: 16, color: kRoyalDeep),
                        const SizedBox(width: 4),
                        Text(widget.balance == null ? '—' : formatCoins(widget.balance!),
                            style: const TextStyle(color: kRoyalDeep, fontWeight: FontWeight.w800, fontSize: 13)),
                      ]),
                    ),
                  ),
                ]),
        ),
        SizedBox(
          height: 42,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 7, 12, 5),
            children: [
              for (final l in [null, ...kLanguages])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(l ?? 'All'),
                    selected: _language == l,
                    showCheckmark: false,
                    selectedColor: kInk,
                    backgroundColor: const Color(0xFFF2EFF9),
                    side: BorderSide.none,
                    shape: const StadiumBorder(),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    labelStyle: TextStyle(color: _language == l ? Colors.white : kInk, fontWeight: FontWeight.w500, fontSize: 12),
                    onSelected: (_) {
                      _language = l;
                      _reload();
                    },
                  ),
                ),
            ],
          ),
        ),
        RandomCallBanner(
          api: widget.api,
          compact: true,
          onAddCoins: widget.onWallet,
          onFinished: () {
            widget.onBalanceChanged();
            _reload();
          },
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
                // Online hosts first, then Busy, then Offline. No headings: the photo ring's colour shows each status.
                final items = <Partner>[
                  for (final st in const ['online', 'busy', 'offline']) ...list.where((p) => p.status == st),
                ];
                return ListView.builder(
                  padding: const EdgeInsets.only(top: 2, bottom: 12),
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final h = items[i];
                    return HostCard(p: h, baseUrl: widget.api.baseUrl, api: widget.api, onCall: () => _call(h), onChat: () => _chat(h));
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
  const HostCard({super.key, required this.p, required this.baseUrl, required this.onCall, required this.onChat, this.api});
  final Partner p;
  final String baseUrl;
  final Api? api; // for the heart (favourite) and Book next buttons
  final VoidCallback onCall, onChat;

  @override
  Widget build(BuildContext context) {
    final canCall = p.status == 'online';
    final stColor = p.status == 'busy' ? Colors.orange.shade700 : p.status == 'offline' ? Colors.grey.shade500 : const Color(0xFF3BA55C);
    // Star rating out of 5 on a small tag over the bottom of the photo ring. New hosts show "New".
    final rated = p.ratingCount > 0;
    final ratingTag = Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0.5),
      decoration: BoxDecoration(
        color: rated ? const Color(0xFF3BA55C) : kRoyal,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (rated) const Icon(Icons.star_rounded, size: 11, color: Colors.white),
        Text(rated ? p.rating.toStringAsFixed(1) : 'New',
            semanticsLabel: rated ? 'Rated ${p.rating.toStringAsFixed(1)} out of 5 by ${p.ratingCount} people' : 'New host',
            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
      ]),
    );
    // Photo with the status ring (green online, orange busy, grey offline) and the rating tag.
    final photo = Stack(clipBehavior: Clip.none, alignment: Alignment.bottomCenter, children: [
      Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white, border: Border.all(color: stColor, width: 2.5)),
        child: ProfileAvatar(baseUrl: baseUrl, name: p.name, url: p.avatarUrl, radius: 24),
      ),
      Positioned(bottom: -7, child: ratingTag),
    ]);
    // Small gold pill: coin, "30/min", phone. Busy hosts get "Book next" instead.
    final callButton = p.status == 'busy' && api != null
        ? BookSlotButton(api: api!, p: p)
        : FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: kGold,
              foregroundColor: kRoyalDeep,
              disabledBackgroundColor: const Color(0xFFE6E2EE),
              shape: const StadiumBorder(),
              minimumSize: const Size(0, 30),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            onPressed: canCall ? onCall : null,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.monetization_on, size: 15),
              const SizedBox(width: 3),
              Text('${formatCoins(p.ratePerMin)}/min', maxLines: 1, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
              const SizedBox(width: 4),
              const Icon(Icons.call, size: 14),
            ]),
          );
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 4, 10, 4),
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFECE9F3)),
      ),
      child: Row(children: [
        photo,
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Flexible(child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: kInk))),
              if (p.verified) const Padding(padding: EdgeInsets.only(left: 3), child: Icon(Icons.verified, size: 15, color: Colors.blue)),
            ]),
            Text(
              [if (p.tagline.isNotEmpty) p.tagline, p.languages.join(', ')].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            if (p.introUrl != null)
              Padding(padding: const EdgeInsets.only(top: 4), child: IntroButton(baseUrl: baseUrl, url: p.introUrl!, compact: true)),
          ]),
        ),
        const SizedBox(width: 6),
        Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            InkWell(
              onTap: onChat,
              customBorder: const CircleBorder(),
              child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.chat_bubble_outline, size: 19, color: kRoyal, semanticLabel: 'Chat')),
            ),
            if (api != null) FavouriteHeart(api: api!, p: p),
          ]),
          const SizedBox(height: 4),
          callButton,
        ]),
      ]),
    );
  }
}

/// Heart on a host card: tap to get an alert when this host comes online.
class FavouriteHeart extends StatefulWidget {
  const FavouriteHeart({super.key, required this.api, required this.p});
  final Api api;
  final Partner p;

  @override
  State<FavouriteHeart> createState() => _FavouriteHeartState();
}

class _FavouriteHeartState extends State<FavouriteHeart> {
  bool _busy = false;

  Future<void> _toggle() async {
    if (_busy) return;
    final on = !widget.p.favourite;
    setState(() { _busy = true; widget.p.favourite = on; });
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.api.setFavourite(widget.p.id, on);
      messenger.showSnackBar(SnackBar(
          duration: const Duration(seconds: 2),
          content: Text(on ? "Added to favourites. We'll tell you when ${widget.p.name} is online." : 'Removed from favourites')));
    } catch (e) {
      if (mounted) setState(() => widget.p.favourite = !on);
      messenger.showSnackBar(SnackBar(content: Text(e is ApiException ? e.message : 'Network error. Try again.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final on = widget.p.favourite;
    return InkWell(
      onTap: _toggle,
      customBorder: const CircleBorder(),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(on ? Icons.favorite : Icons.favorite_border, size: 19, color: on ? const Color(0xFFE53970) : Colors.grey.shade500,
            semanticLabel: on ? 'Remove from favourites' : 'Add to favourites'),
      ),
    );
  }
}

/// On a busy host's card: join the line ("Book next"). When the host is free, the first in line gets an alert
/// and the host is kept for them for 2 minutes. Tap again to leave the line.
class BookSlotButton extends StatefulWidget {
  const BookSlotButton({super.key, required this.api, required this.p});
  final Api api;
  final Partner p;

  @override
  State<BookSlotButton> createState() => _BookSlotButtonState();
}

class _BookSlotButtonState extends State<BookSlotButton> {
  bool _busy = false;

  Future<void> _tap() async {
    if (_busy) return;
    final join = widget.p.booked == null;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final pos = await widget.api.bookSlot(widget.p.id, join);
      if (!mounted) return;
      setState(() => widget.p.booked = pos);
      messenger.showSnackBar(SnackBar(
          content: Text(join
              ? "You're #$pos in line. We'll alert you when ${widget.p.name} is free, and keep the call for you for 2 minutes."
              : 'You left the line')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e is ApiException ? e.message : 'Network error. Try again.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pos = widget.p.booked;
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: pos == null ? Colors.orange.shade300 : const Color(0xFFEDE7FA),
        foregroundColor: pos == null ? kInk : kRoyal,
        shape: const StadiumBorder(),
        minimumSize: const Size(0, 30),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
      onPressed: _busy ? null : _tap,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(pos == null ? Icons.event_available : Icons.hourglass_top, size: 14),
        const SizedBox(width: 4),
        Text(pos == null ? 'Book next' : 'In line #$pos', maxLines: 1, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
      ]),
    );
  }
}
