import 'package:flutter/material.dart';
import 'package:talkory_core/talkory_core.dart';
import 'wallet_screen.dart';

const _languages = ['Hindi', 'English', 'Tamil', 'Telugu', 'Bengali', 'Marathi'];

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.api, required this.onLogout});
  final Api api;
  final VoidCallback onLogout;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _language;
  late Future<List<Partner>> _future = _load();

  Future<List<Partner>> _load() => widget.api.listPartners(language: _language);

  int? _balance; // paise

  @override
  void initState() {
    super.initState();
    _loadBalance();
  }

  Future<void> _loadBalance() async {
    try {
      final b = await widget.api.walletBalance();
      if (mounted) setState(() => _balance = b);
    } catch (_) {}
  }

  void _refresh() {
    _loadBalance();
    setState(() => _future = _load());
  }

  void _openWallet() => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => WalletScreen(api: widget.api)))
      .then((_) => _loadBalance());

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _call(Partner p) async {
    try {
      final session = await widget.api.startCall(p.id);
      if (!mounted) return;
      final connected = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => CallScreen(api: widget.api, session: session, peerName: p.name, onAddCredits: _openWallet)),
      );
      if (connected == true && mounted) {
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => PostCallScreen(api: widget.api, callId: session.callId, peerName: p.name, canRate: true),
        ));
      }
      _refresh();
    } on ApiException catch (e) {
      if (e.status == 401) return widget.onLogout();
      if (e.status == 402) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Not enough balance for this call.'),
          action: SnackBarAction(label: 'Add credits', onPressed: _openWallet),
        ));
      } else {
        _snack(e.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Talkory'),
        actions: [
          TextButton.icon(
            onPressed: _openWallet,
            icon: const Icon(Icons.account_balance_wallet_outlined),
            label: Text(_balance == null ? '—' : '₹${(_balance! / 100).toStringAsFixed(0)}'),
          ),
          IconButton(onPressed: () => showLegalSheet(context, widget.api, onAccountDeleted: widget.onLogout), icon: const Icon(Icons.info_outline)),
          IconButton(onPressed: widget.onLogout, icon: const Icon(Icons.logout)),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                for (final l in [null, ..._languages])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(l ?? 'All'),
                      selected: _language == l,
                      onSelected: (_) {
                        _language = l;
                        _refresh();
                      },
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                _refresh();
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
                  if (list.isEmpty) return ListView(children: const [Padding(padding: EdgeInsets.all(32), child: Text('No hosts online right now. Pull down to refresh.'))]);
                  return ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final p = list[i];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundImage: p.avatarUrl == null ? null : NetworkImage('${widget.api.baseUrl}${p.avatarUrl}'),
                          child: p.avatarUrl == null ? Text(p.name[0].toUpperCase()) : null,
                        ),
                        title: Text(p.name),
                        subtitle: Text('${p.languages.join(', ')}\n★ ${p.rating.toStringAsFixed(1)} (${p.ratingCount})  ·  ₹${(p.ratePerMin / 100).toStringAsFixed(0)}/min'),
                        isThreeLine: true,
                        trailing: FilledButton.icon(
                          onPressed: p.busy ? null : () => _call(p),
                          icon: const Icon(Icons.call),
                          label: Text(p.busy ? 'Busy' : 'Call'),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
