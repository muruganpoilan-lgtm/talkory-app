import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:talkory_core/talkory_core.dart';
import 'package:url_launcher/url_launcher.dart';

/// Refer and earn: share your code, your friend gets welcome coins, you get paid
/// once they add coins for the first time.
class ReferScreen extends StatefulWidget {
  const ReferScreen({super.key, required this.api, this.onCoinsChanged});
  final Api api;
  final VoidCallback? onCoinsChanged; // so the balance in the app updates after welcome coins land

  @override
  State<ReferScreen> createState() => _ReferScreenState();
}

class _ReferScreenState extends State<ReferScreen> {
  Map<String, dynamic>? _d;
  String? _error;
  bool _busy = false;
  final _code = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await widget.api.referral();
      if (mounted) setState(() { _d = d; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load. Check your connection.');
    }
  }

  String get _shareText {
    final d = _d!;
    return 'Talk to real people on Talkory. Use my code ${d['code']} when you join '
        'and you get ${d['friendCoins']} free coins. Download: https://talkory.com';
  }

  Future<void> _share() async {
    final url = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(_shareText)}');
    final ok = await launchUrl(url, mode: LaunchMode.externalApplication).catchError((_) => false);
    if (!ok && mounted) _copy(); // no WhatsApp on this phone: the text is on the clipboard instead
  }

  void _copy() {
    Clipboard.setData(ClipboardData(text: _shareText));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Copied. Paste it to your friends.')),
      );
    }
  }

  Future<void> _useCode() async {
    final code = _code.text.trim().toUpperCase();
    if (code.length != 6) {
      setState(() => _error = 'The code is 6 letters and numbers.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final r = await widget.api.useReferralCode(code);
      widget.onCoinsChanged?.call();
      if (!mounted) return;
      _code.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${r['coins']} coins added. Thank ${r['from']}!')),
      );
      await _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not use that code. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final d = _d;
    return Scaffold(
      appBar: AppBar(title: const Text('Refer and earn')),
      body: d == null
          ? Center(child: _error == null ? const CircularProgressIndicator() : Text(_error!))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // The offer, in one line
                  Card(
                    color: scheme.primaryContainer,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Get ${d['referrerCoins']} coins for every friend',
                            style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: scheme.onPrimaryContainer)),
                        const SizedBox(height: 6),
                        Text('They get ${d['friendCoins']} coins free when they join with your code. '
                            'You get ${d['referrerCoins']} coins the first time they add coins.',
                            style: TextStyle(color: scheme.onPrimaryContainer)),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 16),

                  Text('Your code', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: _copy,
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      decoration: BoxDecoration(
                        border: Border.all(color: scheme.outlineVariant, width: 2),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text('${d['code']}',
                            style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 6)),
                        const SizedBox(width: 10),
                        Icon(Icons.copy, size: 20, color: scheme.onSurfaceVariant),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _share,
                    icon: const Icon(Icons.share),
                    label: const Text('Share with friends'),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  ),
                  const SizedBox(height: 24),

                  // New users can type someone else's code
                  if (d['canUseCode'] == true) ...[
                    Text('Got a code from a friend?', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                        child: TextField(
                          controller: _code,
                          textCapitalization: TextCapitalization.characters,
                          maxLength: 6,
                          decoration: const InputDecoration(
                            hintText: 'ABC123',
                            counterText: '',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton(
                        onPressed: _busy ? null : _useCode,
                        child: _busy
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : Text('Get ${d['friendCoins']}'),
                      ),
                    ]),
                    const SizedBox(height: 24),
                  ],

                  if (_error != null) ...[
                    Text(_error!, style: TextStyle(color: scheme.error)),
                    const SizedBox(height: 16),
                  ],

                  Row(children: [
                    Expanded(child: _stat(context, '${d['joined']}', 'Friends joined')),
                    const SizedBox(width: 12),
                    Expanded(child: _stat(context, '${d['earned']}', 'Coins earned')),
                  ]),
                  const SizedBox(height: 16),

                  if ((d['friends'] as List).isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text('No friends have joined yet. Share your code to get started.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: scheme.onSurfaceVariant)),
                    )
                  else
                    for (final f in (d['friends'] as List).cast<Map<String, dynamic>>())
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: f['paid'] == true ? Colors.green.shade100 : scheme.surfaceContainerHighest,
                          child: Icon(f['paid'] == true ? Icons.check : Icons.hourglass_empty,
                              size: 18, color: f['paid'] == true ? Colors.green.shade800 : scheme.onSurfaceVariant),
                        ),
                        title: Text('${f['name']}'),
                        subtitle: Text(f['paid'] == true
                            ? 'Added coins: you earned ${f['coins']}'
                            : 'Joined. You earn ${d['referrerCoins']} when they add coins.'),
                      ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _stat(BuildContext context, String value, String label) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
      child: Column(children: [
        Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
      ]),
    );
  }
}
