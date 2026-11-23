import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'api.dart';
import 'block_reasons.dart';
import 'call_screen.dart';
import 'gift_sheet.dart';
import 'post_call_screen.dart';
import 'ringer.dart';
import 'theme.dart';
import 'widgets.dart';

final _hostCalling = <String>{};

/// Host only: ring a user from anywhere (chat list or chat screen). A user's own free call is short and daily,
/// then normal rates apply. Opens the call screen and, after a connected call, the post-call screen.
Future<void> startHostCall(BuildContext context, Api api, String userId, String userName) async {
  if (!_hostCalling.add(userId)) return;
  final nav = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    // If this call would spend her own free minutes, say so first: she earns nothing for them.
    try {
      final s = await api.hostFreeStatus(userId);
      final gift = s['gift'] as Map?;
      if (gift != null && gift['used'] == true && context.mounted) {
        final mins = ((gift['seconds'] as num?) ?? 180) ~/ 60;
        final yes = await showDialog<bool>(
          context: context,
          builder: (d) => AlertDialog(
            title: Text('Give $userName $mins free minutes?'),
            content: Text('This would use your own free call. You will not earn for these $mins minutes. '
                'You get one every 3 hours.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(d, true), child: Text('Give $mins minutes')),
            ],
          ),
        );
        if (yes != true) return;
      }
    } catch (_) {} // could not check: ring anyway, the server decides what the call costs
    final session = await api.hostCall(userId);
    final connected = await nav.push<bool>(
      MaterialPageRoute(builder: (_) => CallScreen(api: api, session: session, peerName: userName, peerFemale: false)),
    );
    if (connected == true) {
      await nav.push(MaterialPageRoute(
        builder: (_) => PostCallScreen(api: api, callId: session.callId, peerName: userName, canRate: false),
      ));
    }
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  } catch (_) {
    messenger.showSnackBar(const SnackBar(content: Text('Network error. Try again.')));
  } finally {
    _hostCalling.remove(userId);
  }
}

/// Chat inbox, shared by both apps. [isUser] controls the hint text (users pay per message, hosts reply free).
class ChatTab extends StatefulWidget {
  const ChatTab({super.key, required this.api, required this.isUser, this.onBalanceChanged, this.onLogout, this.onAddCoins});
  final VoidCallback? onAddCoins; // user app: opens the wallet (used by the gift shop)
  final Api api;
  final bool isUser;
  final Future<void> Function()? onBalanceChanged;
  final VoidCallback? onLogout;
  @override
  State<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<ChatTab> {
  List<Map<String, dynamic>>? _threads;
  String? _error;
  Timer? _timer;
  final _search = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final t = await widget.api.chatThreads();
      if (mounted) setState(() { _threads = t; _error = null; });
    } on ApiException catch (e) {
      if (e.status == 401) return widget.onLogout?.call();
      if (mounted && _threads == null) setState(() => _error = e.message);
    } catch (_) {
      if (mounted && _threads == null) setState(() => _error = 'Network error. Pull down to retry.');
    }
  }

  String _ago(String? iso) {
    final t = DateTime.tryParse(iso ?? '')?.toLocal();
    if (t == null) return '';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'now';
    if (d.inHours < 1) return '${d.inMinutes}m';
    if (d.inDays < 1) return '${d.inHours}h';
    return '${d.inDays}d';
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final top = MediaQuery.of(context).padding.top;
    final shown = _threads?.where((t) => _query.isEmpty || (t['name'] as String).toLowerCase().contains(_query)).toList();
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Column(children: [
        RoyalBox(
          padding: EdgeInsets.fromLTRB(16, top + 12, 16, 18),
          child: NameSearchField(controller: _search, onChanged: (v) => setState(() => _query = v.trim().toLowerCase())),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: shown == null
                ? ListView(children: [
                    Padding(padding: const EdgeInsets.all(32), child: Center(child: _error == null ? const CircularProgressIndicator() : Text(_error!))),
                  ])
                : shown.isEmpty
                    ? ListView(children: [
                        Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            _threads!.isNotEmpty
                                ? 'No chats match "${_search.text.trim()}".'
                                : widget.isUser
                                    ? 'No chats yet. Open a host on the Call tab and tap the chat button to say hello.\nEach message costs ${formatCoins(kMessageCostPaise)} coins.'
                                    : 'No chats yet. When a user messages you, it shows up here and you can reply free.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: muted),
                          ),
                        ),
                      ])
                    : ListView.separated(
                        itemCount: shown.length,
                        separatorBuilder: (_, __) => const Divider(height: 1, indent: 80),
                        itemBuilder: (_, i) {
                          final t = shown[i];
                          final unread = (t['unread'] ?? 0) as int;
                          return ListTile(
                            leading: ProfileAvatar(baseUrl: widget.api.baseUrl, name: t['name'] as String, url: t['avatar_url'] as String?, radius: 26, female: widget.isUser),
                            title: Row(children: [
                              Flexible(child: Text(t['name'] as String, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: unread > 0 ? FontWeight.bold : FontWeight.w500))),
                              if (t['best_friend'] == true) ...[const SizedBox(width: 6), const BestFriendBadge()],
                            ]),
                            subtitle: Text(t['last_body'] as String, maxLines: 1, overflow: TextOverflow.ellipsis),
                            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                              Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                                Text(_ago(t['last_at'] as String?), style: TextStyle(color: muted, fontSize: 12)),
                                const SizedBox(height: 4),
                                if (unread > 0)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(color: Colors.green.shade600, borderRadius: BorderRadius.circular(10)),
                                    child: Text('$unread', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                  ),
                              ]),
                              if (!widget.isUser) ...[
                                const SizedBox(width: 6),
                                // hosts: call this user straight from the list
                                IconButton.filled(
                                  style: IconButton.styleFrom(backgroundColor: Colors.green.shade600, foregroundColor: Colors.white),
                                  tooltip: 'Call',
                                  icon: const Icon(Icons.call),
                                  onPressed: () async {
                                    await startHostCall(context, widget.api, t['id'] as String, t['name'] as String);
                                    _load();
                                  },
                                ),
                              ],
                            ]),
                            onTap: () async {
                              await Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => ChatScreen(api: widget.api, otherId: t['id'] as String, otherName: t['name'] as String, isUser: widget.isUser, onAddCoins: widget.onAddCoins),
                              ));
                              widget.onBalanceChanged?.call();
                              _load();
                            },
                          );
                        },
                      ),
          ),
        ),
      ]),
    );
  }
}

/// One conversation. Polls every 4 seconds while open.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.api, required this.otherId, required this.otherName, required this.isUser, this.onAddCoins});
  final VoidCallback? onAddCoins;
  final Api api;
  final String otherId, otherName;
  final bool isUser;
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _msgs = <Map<String, dynamic>>[];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  Timer? _timer;
  bool _sending = false, _loaded = false;
  int? _balance; // paise, users only
  bool _bestFriend = false;
  Map<String, dynamic>? _free; // hosts only: is a free 2-minute call to this user available?

  int get _lastId => _msgs.isEmpty ? 0 : _msgs.last['id'] as int;

  @override
  void initState() {
    super.initState();
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _poll());
    if (widget.isUser) widget.api.walletBalance().then((b) { if (mounted) setState(() => _balance = b); }).catchError((_) {});
    if (!widget.isUser) _loadFree();
    widget.api.isBestFriend(widget.otherId).then((b) { if (mounted) setState(() => _bestFriend = b); }).catchError((_) {});
  }

  Future<void> _loadFree() async {
    try {
      final f = await widget.api.hostFreeStatus(widget.otherId);
      if (mounted) setState(() => _free = f);
    } catch (_) {}
  }

  String _freeText() {
    final f = _free;
    if (f == null) return '';
    // The user's own free call may be switched off entirely, so her giveaway is what usually counts.
    if (f['available'] == true) {
      return 'Free call: your next call to this user is free for ${formatSeconds(f['seconds'])}. You are not paid for it.';
    }
    final gift = f['gift'] as Map?;
    if (gift == null) return '';
    if (gift['available'] == true) {
      return 'You can give this user ${formatSeconds(gift['seconds'])} free, once every 3 hours. '
          'You are not paid for those minutes.';
    }
    final next = DateTime.tryParse((gift['nextAt'] as String?) ?? '')?.toLocal();
    if (next == null) return '';
    final left = next.difference(DateTime.now());
    if (left.isNegative) return '';
    return 'You have used your free minutes. You can give more in ${left.inHours}h ${left.inMinutes % 60}m; '
        'normal rates until then.';
  }

  @override
  void dispose() {
    _timer?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toast(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      });

  Future<void> _poll() async {
    try {
      final fresh = await widget.api.chatMessages(widget.otherId, after: _lastId);
      if (!mounted) return;
      final known = _msgs.map((m) => m['id']).toSet();
      final add = fresh.where((m) => !known.contains(m['id'])).toList();
      if (add.isNotEmpty || !_loaded) {
        final wasLoaded = _loaded;
        setState(() { _msgs.addAll(add); _loaded = true; });
        if (add.isNotEmpty) _toBottom();
        if (wasLoaded && add.any((m) => m['mine'] != true)) Ringer.instance.message();
      }
    } catch (_) {}
  }

  Future<void> _gift() async {
    final r = await showGiftSheet(context, widget.api, hostId: widget.otherId, hostName: widget.otherName, onAddCoins: widget.onAddCoins);
    if (r == null || !mounted) return;
    final m = Map<String, dynamic>.from(r['message'] as Map);
    setState(() {
      if (!_msgs.any((x) => x['id'] == m['id'])) _msgs.add(m);
      if (r['balance'] is int) _balance = r['balance'] as int;
    });
    _toBottom();
    _toast('${(r['gift'] as Map)['emoji']} Gift sent to ${widget.otherName}');
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final m = await widget.api.sendMessage(widget.otherId, text);
      if (!mounted) return;
      setState(() {
        if (!_msgs.any((x) => x['id'] == m['id'])) _msgs.add(m);
        if (m['balance'] != null) _balance = m['balance'] as int;
        _input.clear();
      });
      _toBottom();
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('Network error. Try again.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _report() async {
    final c = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Report this chat'),
        content: TextField(controller: c, maxLines: 3, maxLength: 500, decoration: const InputDecoration(hintText: 'What happened?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Report')),
        ],
      ),
    );
    if (reason == null || reason.isEmpty) return;
    try {
      await widget.api.reportChat(widget.otherId, reason);
      _toast('Thanks, our team will review this');
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _block() async {
    // Both sides pick a reason: it is sent to the admin team as a report and kept on the block itself,
    // so the admin panel always shows why this person was blocked.
    final reason = await askBlockReason(context, widget.otherName, isUser: widget.isUser);
    if (reason == null) return;
    try {
      try { await widget.api.reportChat(widget.otherId, reason); } catch (_) {} // the block still goes ahead if the report fails
      await widget.api.blockChat(widget.otherId, reason: reason);
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }

  /// Host only: ring this user (see startHostCall).
  Future<void> _callUser() async {
    await startHostCall(context, widget.api, widget.otherId, widget.otherName);
    if (mounted) _loadFree();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          Flexible(child: Text(widget.otherName, overflow: TextOverflow.ellipsis)),
          if (_bestFriend) ...[const SizedBox(width: 8), const BestFriendBadge()],
        ]),
        actions: [
          if (!widget.isUser)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.green.shade600, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 14)),
                onPressed: _callUser,
                icon: const Icon(Icons.call, size: 18),
                label: const Text('Call'),
              ),
            ),
          PopupMenuButton<String>(
            onSelected: (v) => v == 'report' ? _report() : _block(),
            itemBuilder: (_) => widget.isUser
                ? const [
                    PopupMenuItem(value: 'report', child: Text('Report')),
                    PopupMenuItem(value: 'block', child: Text('Block')),
                  ]
                : const [PopupMenuItem(value: 'block', child: Text('Block user'))],
          ),
        ],
      ),
      body: Column(children: [
        if (!widget.isUser && _freeText().isNotEmpty)
          Container(
            width: double.infinity,
            color: _free?['available'] == true ? Colors.green.shade100 : scheme.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [
              Icon(Icons.card_giftcard, size: 18, color: _free?['available'] == true ? Colors.green.shade800 : scheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_freeText(),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: _free?['available'] == true ? Colors.green.shade900 : scheme.onSurfaceVariant)),
              ),
            ]),
          ),
        if (widget.isUser)
          Container(
            width: double.infinity,
            color: scheme.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Text(
              '${formatCoins(kMessageCostPaise)} coins per message${_balance == null ? '' : '  ·  Balance ${formatCoins(_balance!)} coins'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        Expanded(
          child: !_loaded
              ? const Center(child: CircularProgressIndicator())
              : _msgs.isEmpty
                  ? const Center(child: Text('Say hello 👋'))
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(12),
                      itemCount: _msgs.length,
                      itemBuilder: (_, i) {
                        final m = _msgs[i];
                        final mine = m['mine'] == true;
                        if (m['gift_key'] != null) {
                          final body = (m['body'] as String).split(' ');
                          return Align(
                            alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                            child: GiftBubble(emoji: body.first, name: body.skip(1).join(' '), mine: mine),
                          );
                        }
                        return Align(
                          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 3),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                            decoration: BoxDecoration(
                              color: mine ? scheme.primary : scheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(m['body'] as String, style: TextStyle(color: mine ? scheme.onPrimary : scheme.onSurface)),
                          ),
                        );
                      },
                    ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 8, 8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 500,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'Message',
                    counterText: '',
                    suffixIcon: widget.isUser ? IconButton(onPressed: _gift, tooltip: 'Send a gift', icon: const Icon(Icons.card_giftcard, color: kRoyal)) : null,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton.filled(onPressed: _sending ? null : _send, icon: const Icon(Icons.send)),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Small gold "Best Friend" badge, shown once a user and a host have had more than 5 calls together.
class BestFriendBadge extends StatelessWidget {
  const BestFriendBadge({super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: const Color(0xFFFFF1CC), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFE0A800))),
        child: const Text('❤ Best Friend', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF8A5A00))),
      );
}
