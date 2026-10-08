import 'package:flutter/material.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:talkory_core/talkory_core.dart';

String _two(int n) => n.toString().padLeft(2, '0');
String _dur(int s) => '${s ~/ 60}m ${_two(s % 60)}s';
String _when(String iso) {
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final d = DateTime.parse(iso).toLocal();
  return '${d.day} ${m[d.month - 1]}, ${_two(d.hour)}:${_two(d.minute)}';
}

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key, required this.api});
  final Api api;
  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  static const _presets = [100, 200, 500, 1000];
  late final Razorpay _rz;
  int? _balance; // paise
  int _amount = 200; // rupees
  bool _busy = false;
  final _items = <Map<String, dynamic>>[];
  int _page = 0;
  bool _more = false, _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _rz = Razorpay()
      ..on(Razorpay.EVENT_PAYMENT_SUCCESS, _onSuccess)
      ..on(Razorpay.EVENT_PAYMENT_ERROR, _onError);
    _load();
    _loadHistory();
  }

  @override
  void dispose() {
    _rz.clear();
    super.dispose();
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _load() async {
    try {
      final b = await widget.api.walletBalance();
      if (mounted) setState(() => _balance = b);
    } catch (_) {
      _snack('Could not load balance');
    }
  }

  Future<void> _loadHistory({int page = 0}) async {
    setState(() => _loadingMore = true);
    try {
      final rows = await widget.api.walletHistory(page);
      if (!mounted) return;
      setState(() {
        if (page == 0) _items.clear();
        _items.addAll(rows);
        _page = page;
        _more = rows.length == 30;
      });
    } catch (_) {
      _snack('Could not load activity');
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Widget _activityTile(Map<String, dynamic> it) {
    final amount = it['amount'] as int; // paise, negative = spent
    final kind = it['kind'] as String;
    final (icon, title) = switch (kind) {
      'topup' => (Icons.add_circle_outline, 'Added credits'),
      'call' => (Icons.call_made, 'Call with ${it['counterpart']}'),
      'refund' => (Icons.undo, 'Refund'),
      _ => (Icons.tune, 'Adjustment'),
    };
    final sub = [_when(it['at']), if (kind == 'call') _dur((it['seconds'] ?? 0) as int)].join('  ·  ');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(sub),
      trailing: Text('${amount >= 0 ? '+' : '−'}₹${(amount.abs() / 100).toStringAsFixed(2)}',
          style: TextStyle(fontWeight: FontWeight.w600, color: amount >= 0 ? Colors.green : null)),
    );
  }

  Future<void> _pay() async {
    setState(() => _busy = true);
    try {
      final o = await widget.api.createTopup(_amount);
      _rz.open({
        'key': o['keyId'],
        'order_id': o['orderId'],
        'amount': o['amount'],
        'currency': 'INR',
        'name': 'Talkory',
        'description': 'Wallet top-up',
        'theme': {'color': '#6C4DFF'},
      });
    } on ApiException catch (e) {
      _snack(e.message);
      setState(() => _busy = false);
    } catch (_) {
      _snack('Network error. Try again.');
      setState(() => _busy = false);
    }
  }

  Future<void> _onSuccess(PaymentSuccessResponse r) async {
    try {
      final b = await widget.api.verifyTopup(
        orderId: r.orderId ?? '',
        paymentId: r.paymentId ?? '',
        signature: r.signature ?? '',
      );
      if (mounted) setState(() => _balance = b);
      _snack('Payment successful');
      _loadHistory();
    } catch (_) {
      // Money was charged; the server webhook will still credit it.
      _snack('Payment received. Your balance will update shortly.');
      _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onError(PaymentFailureResponse r) {
    _snack(r.message?.isNotEmpty == true ? r.message! : 'Payment cancelled');
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Wallet')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Text('Balance', style: text.labelLarge),
                  const SizedBox(height: 8),
                  Text(_balance == null ? '—' : '₹${(_balance! / 100).toStringAsFixed(2)}',
                      style: text.displaySmall?.copyWith(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text('Add credits', style: text.titleMedium),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              for (final a in _presets)
                ChoiceChip(label: Text('₹$a'), selected: _amount == a, onSelected: (_) => setState(() => _amount = a)),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _pay,
            child: _busy
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text('Pay ₹$_amount'),
          ),
          const SizedBox(height: 32),
          Text('Activity', style: text.titleMedium),
          if (_items.isEmpty && !_loadingMore)
            const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('No activity yet')),
          for (final it in _items) _activityTile(it),
          if (_more)
            TextButton(
              onPressed: _loadingMore ? null : () => _loadHistory(page: _page + 1),
              child: Text(_loadingMore ? 'Loading…' : 'Load more'),
            ),
        ],
      ),
    );
  }
}
