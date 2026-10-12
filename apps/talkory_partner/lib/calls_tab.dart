import 'package:flutter/material.dart';
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
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Calls', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (calls == null && _error == null) const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
          if (_error != null) Padding(padding: const EdgeInsets.all(16), child: Text(_error!)),
          if (calls != null && calls.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No calls yet. Go online on the Home tab to receive calls.')),
          for (final c in calls ?? const [])
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.call_received)),
                title: Text('+ ${_rs(c['earned'])}', style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('${_when(c['startedAt'])}  ·  ${_dur(c['seconds'])}'),
              ),
            ),
        ],
      ),
    );
  }
}
