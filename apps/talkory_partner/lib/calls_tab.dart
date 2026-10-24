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
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
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
        onRefresh: _load,
        edgeOffset: 80,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            const GradientHeader(title: 'Calls', subtitle: 'Your recent calls and earnings'),
            const SizedBox(height: 8),
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
