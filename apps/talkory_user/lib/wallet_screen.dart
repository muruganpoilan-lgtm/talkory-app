import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  late final Razorpay _rz;
  int? _balance; // paise
  // Coin packs come from the server (pay = rupees charged, coins = coins credited). These are used if the server cannot be reached.
  List<Map<String, dynamic>> _packs = [
    {'id': 'p100', 'pay': 100, 'coins': 100, 'tag': ''},
    {'id': 'p200', 'pay': 200, 'coins': 210, 'tag': ''},
    {'id': 'p500', 'pay': 500, 'coins': 560, 'tag': 'Popular'},
    {'id': 'p1000', 'pay': 1000, 'coins': 1200, 'tag': 'Best value'},
  ];
  bool _packsFromServer = false;
  String _packId = 'p500';
  // UPI app chosen on the screen: opens straight into that app. 'other' lets the person pick on Razorpay's sheet.
  String _upiApp = 'gpay';
  static const _upiPackages = {'gpay': 'com.google.android.apps.nbu.paisa.user', 'phonepe': 'com.phonepe.app'};
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
    _loadPacks();
  }

  Future<void> _loadPacks() async {
    try {
      final p = await widget.api.topupPacks();
      if (mounted && p.isNotEmpty) {
        setState(() {
          _packs = p;
          _packsFromServer = true;
          if (!p.any((x) => x['id'] == _packId)) _packId = p.first['id'] as String;
        });
      }
    } catch (_) {}
  }

  Map<String, dynamic> get _pack => _packs.firstWhere((p) => p['id'] == _packId, orElse: () => _packs.first);

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
      'topup' => (Icons.add_circle_outline, 'Added coins'),
      'chat' => (Icons.chat_bubble_outline, 'Chat with ${it['counterpart']}'),
      'call' => (Icons.call_made, 'Call with ${it['counterpart']}'),
      'refund' => (Icons.undo, 'Refund'),
      _ => (Icons.tune, 'Adjustment'),
    };
    final sub = [_when(it['at']), if (kind == 'call') _dur((it['seconds'] ?? 0) as int), if (kind == 'chat') '${it['seconds']} message${it['seconds'] == 1 ? '' : 's'}'].join('  ·  ');
    return SoftCard(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: const Color(0xFFEDE6FB), foregroundColor: kRoyal, child: Icon(icon, size: 20)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(sub),
        trailing: Text('${amount >= 0 ? '+' : '−'}${formatCoins(amount.abs())}',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: amount >= 0 ? Colors.green.shade700 : kInk)),
      ),
    );
  }

  Widget _upiTile(String id, String label, Color color) {
    final on = _upiApp == id;
    return GestureDetector(
      onTap: () => setState(() => _upiApp = id),
      child: Container(
        width: 96,
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: on ? kRoyal : Colors.black26, width: on ? 2 : 1),
        ),
        child: Column(children: [
          CircleAvatar(radius: 20, backgroundColor: color, child: Text(label[0], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18))),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(fontSize: 13, fontWeight: on ? FontWeight.w700 : FontWeight.w500)),
        ]),
      ),
    );
  }

  Widget _packCard(Map<String, dynamic> p) {
    final pay = p['pay'] as int, coins = p['coins'] as int, tag = (p['tag'] as String?) ?? '';
    final bonus = coins - pay;
    final selected = p['id'] == _packId;
    return GestureDetector(
      onTap: () => setState(() => _packId = p['id'] as String),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFF6F1FF) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? kRoyal : Colors.black26, width: selected ? 2 : 1),
        ),
        child: Column(children: [
          if (tag.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: selected ? kRoyal : const Color(0xFFE6DAFB),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Text(tag, style: TextStyle(color: selected ? Colors.white : kRoyal, fontWeight: FontWeight.w700, fontSize: 12)),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(children: [
              const Icon(Icons.monetization_on, color: kGold, size: 30),
              const SizedBox(width: 8),
              Text('$coins', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: kInk)),
              const Spacer(),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('₹$pay', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: kInk)),
                if (bonus > 0) Text('+$bonus bonus coins', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.green.shade700)),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  // upiOnly: Razorpay shows only UPI (GPay, PhonePe, Paytm, BHIM ...). Otherwise UPI is listed first, then cards and netbanking.
  Future<void> _pay({bool upiOnly = true}) async {
    setState(() => _busy = true);
    try {
      final o = _packsFromServer ? await widget.api.createPackTopup(_packId) : await widget.api.createTopup(_pack['pay'] as int);
      _rz.open({
        'key': o['keyId'],
        'order_id': o['orderId'],
        'amount': o['amount'],
        'currency': 'INR',
        'name': 'Talkory',
        'description': 'Wallet top-up',
        'theme': {'color': '#6C4DFF'},
        if (upiOnly) 'method': {'upi': true, 'card': false, 'netbanking': false, 'wallet': false, 'emi': false, 'paylater': false},
        if (upiOnly && _upiPackages[_upiApp] != null) ...{'_[flow]': 'intent', 'upi_app_package_name': _upiPackages[_upiApp]},
        if (!upiOnly)
          'config': {
            'display': {
              'sequence': ['block.upi', 'block.other'],
              'preferences': {'show_default_blocks': true},
              'blocks': {
                'upi': {'name': 'Pay with UPI', 'instruments': [{'method': 'upi'}]},
              },
            },
          },
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
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            RoyalBox(
              padding: EdgeInsets.fromLTRB(8, top + 8, 20, 34),
              child: Column(
                children: [
                  Row(children: [
                    IconButton(icon: const Icon(Icons.arrow_back), color: Colors.white, onPressed: () => Navigator.maybePop(context)),
                    const Text('Wallet', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                  ]),
                  const SizedBox(height: 12),
                  const Text('Balance', style: TextStyle(color: Colors.white70, fontSize: 14)),
                  const SizedBox(height: 6),
                  Text(_balance == null ? '—' : '${formatCoins(_balance!)} coins',
                      style: const TextStyle(color: kGold, fontSize: 40, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Add coins', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: kInk)),
                  const SizedBox(height: 12),
                  for (final p in _packs) _packCard(p),
                  const SizedBox(height: 8),
                  const Text('Pay with', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Row(children: [
                    _upiTile('gpay', 'GPay', const Color(0xFF4285F4)),
                    _upiTile('phonepe', 'PhonePe', const Color(0xFF5F259F)),
                  ]),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: kRoyal, minimumSize: const Size(0, 56)),
                      onPressed: _busy ? null : () => _pay(),
                      child: _busy
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Column(mainAxisSize: MainAxisSize.min, children: [
                              Text('Add ₹${_pack['pay']} with ${_upiApp == 'phonepe' ? 'PhonePe' : 'GPay'}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                              const Text('(incl. of all taxes)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w400)),
                            ]),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Center(
                    child: TextButton(
                      onPressed: _busy ? null : () => _pay(upiOnly: false),
                      child: const Text('More options (other UPI apps, card, netbanking)'),
                    ),
                  ),
                  const Center(child: Text('Not installed? Use More options for any other UPI app', style: TextStyle(fontSize: 12, color: Colors.black54))),
                  const SizedBox(height: 28),
                  Text('Activity', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: kInk)),
                  const SizedBox(height: 4),
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
            ),
          ],
        ),
      ),
    );
  }
}
