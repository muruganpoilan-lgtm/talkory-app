import 'package:flutter/material.dart';
import 'package:talkory_core/talkory_core.dart';

String _rs(num paise) => '₹${(paise / 100).toStringAsFixed(2)}';
String _two(int n) => n.toString().padLeft(2, '0');
String _dur(int s) => '${s ~/ 60}m ${_two(s % 60)}s';

String _when(String? iso) {
  if (iso == null) return '';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final d = DateTime.parse(iso).toLocal();
  return '${d.day} ${months[d.month - 1]}, ${_two(d.hour)}:${_two(d.minute)}';
}

class EarningsScreen extends StatefulWidget {
  const EarningsScreen({super.key, required this.api});
  final Api api;
  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen> {
  Map<String, dynamic>? _d;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _load() async {
    try {
      final d = await widget.api.partnerEarnings();
      if (mounted) setState(() { _d = d; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiException ? e.message : 'Network error. Pull down to retry.');
    }
  }

  Future<void> _guard(Future<void> Function() task, String okMessage) async {
    setState(() => _busy = true);
    try {
      await task();
      _snack(okMessage);
      await _load();
    } on ApiException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('Network error. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _ask({required String title, required String hint, TextInputType? type, String? initial}) {
    final c = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(controller: c, autofocus: true, keyboardType: type, decoration: InputDecoration(hintText: hint)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Continue')),
        ],
      ),
    );
  }

  Future<void> _editUpi() async {
    final v = await _ask(title: 'Your UPI ID', hint: 'name@bank', initial: _d?['upiId'] as String?);
    if (v == null || v.isEmpty) return;
    await _guard(() => widget.api.setPayoutMethod(v), 'UPI ID saved');
  }

  Future<void> _withdraw() async {
    final d = _d!;
    final min = d['minPayoutRupees'] as int;
    if (d['upiId'] == null) {
      _snack('Add your UPI ID first');
      return _editUpi();
    }
    final v = await _ask(
      title: 'Withdraw to ${d['upiId']}',
      hint: 'Amount in ₹ (min $min)',
      type: TextInputType.number,
    );
    final rupees = int.tryParse(v ?? '');
    if (rupees == null) return;
    if (rupees < min) return _snack('Minimum withdrawal is ₹$min');
    if (rupees * 100 > (d['balance'] as int)) return _snack('That is more than your balance');
    await _guard(() => widget.api.requestPayout(rupees), 'Withdrawal requested');
  }

  Color _statusColor(String s) => switch (s) {
        'paid' => Colors.green,
        'rejected' => Colors.red,
        _ => Colors.orange,
      };

  Widget _stat(BuildContext context, String label, num paise) => Expanded(
        child: Column(children: [
          Text(_rs(paise), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final d = _d;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Earnings & payouts')),
      body: d == null
          ? Center(child: _error == null ? const CircularProgressIndicator() : Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(children: [
                        Text('Available balance', style: text.labelLarge),
                        const SizedBox(height: 4),
                        Text(_rs(d['balance']), style: text.displaySmall?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 16),
                        Row(children: [
                          _stat(context, 'Today', d['today']),
                          _stat(context, 'Total earned', d['totalEarned']),
                        ]),
                        const SizedBox(height: 12),
                        Row(children: [
                          _stat(context, 'Pending payout', d['pending']),
                          _stat(context, 'Withdrawn', d['withdrawn']),
                        ]),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _busy ? null : _withdraw,
                            icon: const Icon(Icons.north_east),
                            label: const Text('Withdraw'),
                          ),
                        ),
                      ]),
                    ),
                  ),
                  if (d['kyc'] != 'approved')
                    const Card(
                      color: Color(0xFFFFF3CD),
                      child: ListTile(
                        leading: Icon(Icons.info_outline),
                        title: Text('KYC pending'),
                        subtitle: Text('You can go online and withdraw once verification is approved.'),
                      ),
                    ),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.account_balance_outlined),
                      title: Text(d['upiId'] ?? 'No UPI ID added'),
                      subtitle: const Text('Payout destination'),
                      trailing: TextButton(onPressed: _busy ? null : _editUpi, child: Text(d['upiId'] == null ? 'Add' : 'Change')),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Payouts', style: text.titleMedium),
                  if ((d['payouts'] as List).isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('No withdrawals yet')),
                  for (final p in d['payouts'] as List)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(_rs(p['amount'])),
                      subtitle: Text('${_when(p['requestedAt'])}  ·  ${p['upiId'] ?? ''}'),
                      trailing: Chip(
                        label: Text(p['status'], style: TextStyle(color: _statusColor(p['status']))),
                        side: BorderSide(color: _statusColor(p['status'])),
                        backgroundColor: Colors.transparent,
                      ),
                    ),
                  const SizedBox(height: 16),
                  Text('Recent calls', style: text.titleMedium),
                  if ((d['recentCalls'] as List).isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('No calls yet')),
                  for (final c in d['recentCalls'] as List)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.call_received),
                      title: Text('+ ${_rs(c['earned'])}'),
                      subtitle: Text('${_when(c['startedAt'])}  ·  ${_dur(c['seconds'])}'),
                    ),
                ],
              ),
            ),
    );
  }
}
