import 'dart:async';
import 'package:flutter/material.dart';
import 'api.dart';
import 'ringer.dart';

/// Customer Support, shared by both apps: your requests, a button to open a new one, and the team's replies.
class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key, required this.api});
  final Api api;
  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  List<Map<String, dynamic>>? _tickets;
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
      final t = await widget.api.supportTickets();
      if (mounted) setState(() { _tickets = t; _error = null; });
    } on ApiException catch (e) {
      if (mounted && _tickets == null) setState(() => _error = e.message);
    } catch (_) {
      if (mounted && _tickets == null) setState(() => _error = 'Network error. Pull down to retry.');
    }
  }

  void _toast(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _newRequest() async {
    final subject = TextEditingController();
    final body = TextEditingController();
    final send = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('How can we help?'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: subject, maxLength: 80, decoration: const InputDecoration(labelText: 'Subject, e.g. top-up missing')),
            TextField(controller: body, maxLines: 5, maxLength: 2000, decoration: const InputDecoration(labelText: 'Describe the problem')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send')),
        ],
      ),
    );
    if (send != true) return;
    final s = subject.text.trim();
    final b = body.text.trim();
    if (s.isEmpty || b.isEmpty) return _toast('Please fill in both the subject and the description');
    try {
      await widget.api.createSupportTicket(s, b);
      _toast('Sent. We will reply here.');
      _load();
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('Network error. Try again.');
    }
  }

  Future<void> _open(Map<String, dynamic> t) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SupportThreadScreen(api: widget.api, ticketId: t['id'] as String, subject: t['subject'] as String),
    ));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Customer Support')),
      floatingActionButton: FloatingActionButton.extended(onPressed: _newRequest, icon: const Icon(Icons.edit), label: const Text('New request')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _tickets == null
            ? ListView(children: [
                const SizedBox(height: 120),
                Center(child: _error == null ? const CircularProgressIndicator() : Padding(padding: const EdgeInsets.all(24), child: Text(_error!))),
              ])
            : _tickets!.isEmpty
                ? ListView(children: const [
                    SizedBox(height: 120),
                    Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('No requests yet.\nTap "New request" and tell us what went wrong. We reply right here.', textAlign: TextAlign.center),
                    ),
                  ])
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 90),
                    itemCount: _tickets!.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final t = _tickets![i];
                      final unread = t['customer_unread'] == true;
                      final closed = t['status'] == 'closed';
                      return ListTile(
                        title: Text(t['subject'] as String, style: TextStyle(fontWeight: unread ? FontWeight.bold : FontWeight.w500)),
                        subtitle: Text((t['last_body'] as String?) ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: unread
                            ? Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(10)),
                                child: Text('New reply', style: TextStyle(color: scheme.onPrimary, fontSize: 12)),
                              )
                            : Text(closed ? 'Closed' : 'Open', style: TextStyle(color: scheme.onSurfaceVariant)),
                        onTap: () => _open(t),
                      );
                    },
                  ),
      ),
    );
  }
}

/// One support request: the conversation with the Talkory team.
class SupportThreadScreen extends StatefulWidget {
  const SupportThreadScreen({super.key, required this.api, required this.ticketId, required this.subject});
  final Api api;
  final String ticketId, subject;
  @override
  State<SupportThreadScreen> createState() => _SupportThreadScreenState();
}

class _SupportThreadScreenState extends State<SupportThreadScreen> {
  List<Map<String, dynamic>> _msgs = [];
  bool _open = true, _sending = false, _loaded = false;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 6), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      });

  Future<void> _load() async {
    try {
      final d = await widget.api.supportTicket(widget.ticketId);
      final t = Map<String, dynamic>.from(d['ticket'] as Map);
      final m = (d['messages'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (!mounted) return;
      final grew = m.length != _msgs.length;
      final newReply = _loaded && grew && m.isNotEmpty && m.last['from_admin'] == true;
      setState(() {
        _msgs = m;
        _open = t['status'] == 'open';
        _loaded = true;
      });
      if (grew) _toBottom();
      if (newReply) Ringer.instance.message();
    } catch (_) {}
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.api.replySupportTicket(widget.ticketId, text);
      _input.clear();
      await _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Network error. Try again.')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.subject, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: Column(children: [
        Expanded(
          child: !_loaded
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(12),
                  itemCount: _msgs.length,
                  itemBuilder: (_, i) {
                    final m = _msgs[i];
                    final admin = m['from_admin'] == true;
                    return Align(
                      alignment: admin ? Alignment.centerLeft : Alignment.centerRight,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                        decoration: BoxDecoration(
                          color: admin ? scheme.surfaceContainerHighest : scheme.primaryContainer,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          if (admin) Text('Talkory Support', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: scheme.primary)),
                          Text(m['body'] as String),
                        ]),
                      ),
                    );
                  },
                ),
        ),
        if (_open)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 8, 8),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 2000,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(hintText: 'Write a message', counterText: '', border: OutlineInputBorder()),
                  ),
                ),
                IconButton(onPressed: _sending ? null : _send, icon: const Icon(Icons.send)),
              ]),
            ),
          )
        else
          Container(
            width: double.infinity,
            color: scheme.surfaceContainerHighest,
            padding: const EdgeInsets.all(14),
            child: const Text('This request is closed. If you still need help, go back and tap "New request".', textAlign: TextAlign.center),
          ),
      ]),
    );
  }
}
