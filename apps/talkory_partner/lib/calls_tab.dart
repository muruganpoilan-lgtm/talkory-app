import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:talkory_core/talkory_core.dart';

String _rs(num paise) => '₹${(paise / 100).toStringAsFixed(2)}';
String _two(int n) => n.toString().padLeft(2, '0');
String _dur(int s) => '${s ~/ 60}m ${_two(s % 60)}s';
String _when(String? iso) {
  if (iso == null) return '';
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final d = DateTime.parse(iso).toLocal();
  return '${d.day} ${m[d.month - 1]}, ${_two(d.hour)}:${_two(d.minute)}';
}

class CallsTab extends StatefulWidget {
  const CallsTab({super.key, required this.api});
  final Api api;
  @override
  State<CallsTab> createState() => _CallsTabState();
}

class _CallsTabState extends State<CallsTab> {
  List<dynamic>? _calls;
  List<Map<String, dynamic>>? _users; // users who have the app open right now
  bool _showAll = false;
  String? _error;
  Timer? _timer;
  final Set<String> _calling = {};

  @override
  void initState() {
    super.initState();
    _load();
    _loadUsers();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _loadUsers());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    try {
      final u = await widget.api.onlineUsers();
      if (mounted) setState(() => _users = u);
    } catch (_) {}
  }

  Future<void> _callUser(Map<String, dynamic> u) async {
    final id = u['id'] as String;
    if (!_calling.add(id)) return;
    try {
      await startHostCall(context, widget.api, id, (u['name'] ?? 'User') as String);
    } finally {
      _calling.remove(id);
      _loadUsers();
      _load();
    }
  }

  Widget _onlineUsers() {
    final users = _users;
    if (users == null) return const SizedBox.shrink();
    final shown = _showAll ? users : users.take(5).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 2),
        child: Row(children: [
          Container(width: 9, height: 9, decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text('USERS ONLINE (${users.length})', style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.w800, letterSpacing: 1, fontSize: 12)),
        ]),
      ),
      if (users.isEmpty) const Padding(padding: EdgeInsets.fromLTRB(20, 6, 20, 8), child: Text('Nobody is online right now. This list refreshes by itself.', style: TextStyle(color: Colors.black54))),
      for (final u in shown)
        SoftCard(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            leading: Stack(children: [
              ProfileAvatar(baseUrl: widget.api.baseUrl, name: (u['name'] ?? 'User') as String, url: null, radius: 22, female: false),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(color: u['busy'] == true ? Colors.orange : Colors.green, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                ),
              ),
            ]),
            title: Text((u['name'] ?? 'User') as String, style: const TextStyle(fontWeight: FontWeight.w800, color: kInk)),
            subtitle: Text(u['busy'] == true ? 'On a call' : 'Online'),
            trailing: IconButton.filled(
              style: IconButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
              tooltip: 'Call',
              icon: const Icon(Icons.call),
              onPressed: u['busy'] == true ? null : () => _callUser(u),
            ),
          ),
        ),
      if (users.length > 5)
        Center(child: TextButton(onPressed: () => setState(() => _showAll = !_showAll), child: Text(_showAll ? 'Show fewer' : 'Show all ${users.length}'))),
      const Padding(
        padding: EdgeInsets.fromLTRB(20, 10, 20, 2),
        child: Text('RECENT CALLS', style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w800, letterSpacing: 1, fontSize: 12)),
      ),
    ]);
  }

  Future<void> _load() async {
    try {
      final d = await widget.api.partnerEarnings();
      if (mounted) setState(() { _calls = d['recentCalls'] as List<dynamic>; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiException ? e.message : 'Network error. Pull down to retry.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final calls = _calls;
    final scheme = Theme.of(context).colorScheme;
    // Calls are newest first, so the first row seen for each user is the one that gets the call button
    final seenUsers = <String>{};
    final showCall = <Object?>{};
    for (final c in calls ?? const []) {
      final uid = c['userId'];
      if (uid is String && seenUsers.add(uid)) showCall.add(c['id']);
    }
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: RefreshIndicator(
        onRefresh: () async {
          _loadUsers();
          await _load();
        },
        edgeOffset: 80,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            const GradientHeader(title: 'Calls', subtitle: 'Users online and your recent calls'),
            const SizedBox(height: 8),
            _onlineUsers(),
            if (calls == null && _error == null) const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
            if (_error != null) Padding(padding: const EdgeInsets.all(16), child: Text(_error!)),
            if (calls != null && calls.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('No calls yet. Go online on the Home tab to receive calls.')),
            for (final c in calls ?? const [])
              SoftCard(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: CircleAvatar(backgroundColor: scheme.primaryContainer, child: Icon(Icons.call_received, color: scheme.primary)),
                  title: Text('+ ${_rs(c['earned'])}', style: const TextStyle(fontWeight: FontWeight.w800, color: kInk)),
                  subtitle: Text('${_when(c['startedAt'])}  ·  ${_dur(c['seconds'])}'),
                  trailing: !showCall.contains(c['id'])
                      ? null
                      : Row(mainAxisSize: MainAxisSize.min, children: [
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 90),
                            child: Text((c['userName'] ?? 'User') as String,
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, color: kInk, fontSize: 13)),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filled(
                            style: IconButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                            tooltip: 'Call back',
                            icon: const Icon(Icons.call),
                            onPressed: () async {
                              await startHostCall(context, widget.api, c['userId'] as String, (c['userName'] ?? 'User') as String);
                              _load();
                            },
                          ),
                        ]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
