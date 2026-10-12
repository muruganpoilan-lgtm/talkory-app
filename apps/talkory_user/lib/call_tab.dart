import 'dart:async';
import 'package:flutter/material.dart';
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
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(children: [
            Text('Talkory', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: scheme.primary)),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: widget.onWallet,
              icon: const Icon(Icons.monetization_on_outlined, size: 18),
              label: Text(widget.balance == null ? '—' : '${formatCoins(widget.balance!)} coins'),
              style: OutlinedButton.styleFrom(shape: const StadiumBorder()),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _search,
            onChanged: _onSearchChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search name',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(28)),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
        SizedBox(
          height: 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            children: [
              for (final l in [null, ...kLanguages])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(l ?? 'All'),
                    selected: _language == l,
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
      ],
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
    final status = p.busy ? Colors.orange : Colors.green;
    final muted = Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(children: [
              ProfileAvatar(baseUrl: baseUrl, name: p.name, url: p.avatarUrl, radius: 38, ring: status),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: Colors.green.shade600, borderRadius: BorderRadius.circular(4)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.star, size: 14, color: Colors.white),
                  const SizedBox(width: 2),
                  Text(p.rating.toStringAsFixed(1), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                ]),
              ),
              const SizedBox(height: 4),
              Text(p.busy ? 'BUSY' : 'ONLINE', style: TextStyle(color: status, fontSize: 12, fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(child: Text(p.name, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
                    if (p.verified) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.verified, size: 18, color: Colors.blue)),
                  ]),
                  if (p.tagline.isNotEmpty) Text(p.tagline, style: Theme.of(context).textTheme.bodyLarge),
                  const SizedBox(height: 4),
                  Row(children: [
                    const Icon(Icons.translate, size: 16),
                    const SizedBox(width: 6),
                    Expanded(child: Text(p.languages.join(', '), maxLines: 1, overflow: TextOverflow.ellipsis, style: muted)),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    if (p.introUrl != null) ...[
                      IntroButton(baseUrl: baseUrl, url: p.introUrl!),
                      const SizedBox(width: 8),
                    ],
                    IconButton.outlined(onPressed: onChat, tooltip: 'Chat', icon: const Icon(Icons.chat_bubble_outline, size: 18)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: p.busy ? null : onCall,
                        icon: const Icon(Icons.call, size: 18),
                        label: Text('${formatCoins(p.ratePerMin)}/min'),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
