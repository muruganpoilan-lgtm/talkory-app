import 'package:flutter/material.dart';
import 'package:talkory_core/talkory_core.dart';

/// Withdraw money to GPay or PhonePe (UPI). Shown from the Earnings screen.
class WithdrawScreen extends StatefulWidget {
  const WithdrawScreen({super.key, required this.api, required this.balancePaise, required this.minRupees, this.upiId, this.upiApp, this.gstPercent = 18, this.payOn});
  final Api api;
  final int balancePaise, minRupees;
  final String? upiId, upiApp, payOn;
  final num gstPercent;
  @override
  State<WithdrawScreen> createState() => _WithdrawScreenState();
}

class _WithdrawScreenState extends State<WithdrawScreen> {
  late final TextEditingController _amount, _upi;
  String _app = 'gpay';
  bool _busy = false;
  String? _error;

  static const _handles = {
    'gpay': ['@okicici', '@oksbi', '@okhdfcbank', '@okaxis'],
    'phonepe': ['@ybl', '@ibl', '@axl'],
  };

  @override
  void initState() {
    super.initState();
    _app = widget.upiApp == 'phonepe' ? 'phonepe' : 'gpay';
    _upi = TextEditingController(text: widget.upiId ?? '');
    _amount = TextEditingController(text: '${widget.balancePaise ~/ 100}');
  }

  @override
  void dispose() {
    _amount.dispose();
    _upi.dispose();
    super.dispose();
  }

  Widget _appTile(String id, String label, Color color) {
    final on = _app == id;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _app = id),
        child: Container(
          margin: const EdgeInsets.only(right: 10),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: on ? Theme.of(context).colorScheme.primary : Colors.black26, width: on ? 2 : 1),
            color: on ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.4) : null,
          ),
          child: Column(children: [
            CircleAvatar(radius: 20, backgroundColor: color, child: Text(label[0], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18))),
            const SizedBox(height: 6),
            Text(label, style: TextStyle(fontWeight: on ? FontWeight.w700 : FontWeight.w500)),
          ]),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final rupees = int.tryParse(_amount.text.trim());
    final upi = _upi.text.trim().toLowerCase();
    if (rupees == null || rupees < widget.minRupees) return setState(() => _error = 'Minimum withdrawal is ₹${widget.minRupees}');
    if (rupees * 100 > widget.balancePaise) return setState(() => _error = 'That is more than your balance');
    if (!RegExp(r'^[\w.\-]{2,}@[a-zA-Z]{2,}$').hasMatch(upi)) return setState(() => _error = 'Enter a valid UPI ID, like name@bank');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.setPayoutMethod(upi, upiApp: _app);
      await widget.api.requestPayout(rupees);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Network error. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final name = _app == 'phonepe' ? 'PhonePe' : 'GPay';
    return Scaffold(
      appBar: AppBar(title: const Text('Withdraw')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(children: [
              Text('Available balance', style: text.labelLarge),
              const SizedBox(height: 4),
              Text('₹${(widget.balancePaise / 100).toStringAsFixed(2)}', style: text.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _amount,
          keyboardType: TextInputType.number,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: 'Amount (₹)', helperText: 'Minimum ₹${widget.minRupees}', border: const OutlineInputBorder(), prefixText: '₹ '),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(onPressed: () => setState(() => _amount.text = '${widget.balancePaise ~/ 100}'), child: const Text('Withdraw everything')),
        ),
        Builder(builder: (_) {
          final r = int.tryParse(_amount.text.trim()) ?? 0;
          final gst = (r * widget.gstPercent / 100);
          final pay = DateTime.tryParse(widget.payOn ?? '');
          const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
          return Card(
            color: const Color(0xFFF4F0FF),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Withdrawal ₹$r'),
                Text('GST ${widget.gstPercent}%: − ₹${gst.toStringAsFixed(2)}'),
                Text('You receive ₹${(r - gst).toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w800)),
                if (pay != null) Text('Paid on ${pay.day} ${m[pay.month - 1]}. You get an invoice after payment.', style: const TextStyle(color: Colors.black54, fontSize: 12)),
              ]),
            ),
          );
        }),
        const SizedBox(height: 4),
        Text('Receive money in', style: text.titleSmall),
        const SizedBox(height: 8),
        Row(children: [_appTile('gpay', 'GPay', const Color(0xFF4285F4)), _appTile('phonepe', 'PhonePe', const Color(0xFF5F259F))]),
        const SizedBox(height: 16),
        TextField(
          controller: _upi,
          autocorrect: false,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(labelText: 'Your $name UPI ID', hintText: 'name@bank', border: const OutlineInputBorder()),
        ),
        const SizedBox(height: 6),
        Wrap(spacing: 6, children: [
          for (final h in _handles[_app]!)
            ActionChip(
              label: Text(h),
              onPressed: () {
                final base = _upi.text.split('@').first;
                setState(() => _upi.text = '$base$h');
              },
            ),
        ]),
        const SizedBox(height: 6),
        Text('Find your UPI ID in $name: Profile → UPI IDs.', style: text.bodySmall?.copyWith(color: Colors.black54)),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy ? null : _submit,
          style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
          child: _busy ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text('Withdraw to $name'),
        ),
        const SizedBox(height: 8),
        Text('Money is sent to this UPI ID on the next pay day (10th, 20th or 30th of the month).', textAlign: TextAlign.center, style: text.bodySmall?.copyWith(color: Colors.black54)),
      ]),
    );
  }
}
