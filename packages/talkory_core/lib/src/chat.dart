import 'dart:async';
import 'package:flutter/material.dart';
import 'api.dart';
import 'call_screen.dart';
import 'post_call_screen.dart';
import 'ringer.dart';
import 'widgets.dart';

/// Chat inbox, shared by both apps. [isUser] controls the hint text (users pay per message, hosts reply free).
class ChatTab extends StatefulWidget {
  const ChatTab({super.key, required this.api, required this.isUser, this.onBalanceChanged, this.onLogout});
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

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
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
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Align(alignment: Alignment.centerLeft, child: Text('Chats', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold))),
      ),
      Expanded(
        child: RefreshIndicator(
          onRefresh: _load,
          child: _threads == null
              ? ListView(children: [
                  Padding(padding: const EdgeInsets.all(32), child: Center(child: _error == null ? const CircularProgressIndicator() : Text(_error!))),
                ])
              : _threads!.isEmpty
                  ? ListView(children: [
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          widget.isUser
                              ? 'No chats yet. Open a host on the Call tab and tap the chat button to say hello.\nEach message costs ${formatCoins(kMessageCostPaise)} coins.'
                              : 'No chats yet. When a user messages you, it shows up here and you can reply free.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: muted),
                        ),
                      ),
                    ])
                  : ListView.separated(
                      itemCount: _threads!.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, indent: 80),
                      itemBuilder: (_, i) {
                        final t = _threads![i];
                        final unread = (t['unread'] ?? 0) as int;
                        return ListTile(
                          leading: ProfileAvatar(baseUrl: widget.api.baseUrl, name: t['name'] as String, url: t['avatar_url'] as String?, radius: 26, female: widget.isUser),
                          title: Text(t['name'] as String, style: TextStyle(fontWeight: unread > 0 ? FontWeight.bold : FontWeight.w500)),
                          subtitle: Text(t['last_body'] as String, maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Text(_ago(t['last_at'] as String?), style: TextStyle(color: muted, fontSize: 12)),
                            const SizedBox(height: 4),
                            if (unread > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(color: Colors.green.shade600, borderRadius: BorderRadius.circular(10)),
                                child: Text('$unread', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                              ),
                          ]),
                          onTap: () async {
                            await Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => ChatScreen(api: widget.api, otherId: t['id'] as String, otherName: t['name'] as String, isUser: widget.isUser),
                            ));
                            widget.onBalanceChanged?.call();
                            _load();
                          },
                        );
                      },
                    ),
        ),
      ),
    ]);
  }
}

/// One conversation. Polls every 4 seconds while open.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.api, required this.otherId, required this.otherName, required this.isUser});
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

  int get _lastId => _msgs.isEmpty ? 0 : _msgs.last['id'] as int;

  @override
  void initState() {
    super.initState();
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _poll());
    if (widget.isUser) widget.api.walletBalance().then((b) { if (mounted) setState(() => _balance = b); }).catchError((_) {});
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
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Block ${widget.otherName}?'),
        content: const Text('You will not see each other in chats or calls.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Block')),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await widget.api.blockChat(widget.otherId);
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }

  bool _calling = false;

  /// Host only: ring this user. They pay the normal per-minute rate once they accept.
  Future<void> _callUser() async {
    if (_calling) return;
    _calling = true;
    try {
      final session = await widget.api.hostCall(widget.otherId);
      if (!mounted) return;
      final connected = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => CallScreen(api: widget.api, session: session, peerName: widget.otherName, peerFemale: false)),
      );
      if (connected == true && mounted) {
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => PostCallScreen(api: widget.api, callId: session.callId, peerName: widget.otherName, canRate: false),
        ));
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Network error. Try again.')));
    } finally {
      _calling = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.otherName),
        actions: [
          if (!widget.isUser) IconButton(icon: const Icon(Icons.call), tooltip: 'Call', onPressed: _callUser),
          PopupMenuButton<String>(
            onSelected: (v) => v == 'report' ? _report() : _block(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'report', child: Text('Report')),
              PopupMenuItem(value: 'block', child: Text('Block')),
            ],
          ),
        ],
      ),
      body: Column(children: [
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
