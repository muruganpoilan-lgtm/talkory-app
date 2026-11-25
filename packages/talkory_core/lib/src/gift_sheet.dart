import 'package:flutter/material.dart';
import 'api.dart';
import 'theme.dart';

/// The gift shop: a sheet with the gifts, grouped by price. Pass [hostId] from a chat, or [callId] during a call.
/// Returns the server's answer when a gift was sent ({ok, balance, gift, message}), or null if nothing was sent.
Future<Map<String, dynamic>?> showGiftSheet(BuildContext context, Api api, {String? hostId, String? callId, String? hostName, VoidCallback? onAddCoins}) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (_) => _GiftSheet(api: api, hostId: hostId, callId: callId, hostName: hostName, onAddCoins: onAddCoins),
  );
}

class _GiftSheet extends StatefulWidget {
  const _GiftSheet({required this.api, this.hostId, this.callId, this.hostName, this.onAddCoins});
  final Api api;
  final String? hostId, callId, hostName;
  final VoidCallback? onAddCoins;
  @override
  State<_GiftSheet> createState() => _GiftSheetState();
}

class _GiftSheetState extends State<_GiftSheet> {
  List<Map<String, dynamic>>? _gifts;
  int? _balance; // paise
  String? _error, _sending;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final g = await widget.api.gifts();
      final b = await widget.api.walletBalance().catchError((_) => -1);
      if (mounted) setState(() { _gifts = g; _balance = b < 0 ? null : b; });
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiException ? e.message : 'Could not load gifts. Check your internet.');
    }
  }

  Future<void> _send(Map<String, dynamic> g) async {
    final coins = (g['coins'] as num).toInt();
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Send ${g['emoji']} ${g['name']}?'),
        content: Text('This costs $coins coins${widget.hostName == null ? '' : ' and goes to ${widget.hostName}'}.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Send for $coins coins')),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() { _sending = g['key'] as String; _error = null; });
    try {
      final r = await widget.api.sendGift(g['key'] as String, hostId: widget.hostId, callId: widget.callId);
      if (mounted) Navigator.of(context).pop(r);
    } on ApiException catch (e) {
      if (mounted) setState(() { _sending = null; _error = e.message; });
    } catch (_) {
      if (mounted) setState(() { _sending = null; _error = 'Network error. Try again.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final gifts = _gifts;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.78),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // Balance card with + ADD
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F2FF),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE6DAFB)),
              ),
              child: Row(children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(color: const Color(0xFFEDE6FB), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.account_balance_wallet, color: kRoyal),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Available Balance', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                    Row(children: [
                      const Icon(Icons.monetization_on, size: 24, color: kGold),
                      const SizedBox(width: 4),
                      Text(_balance == null ? '...' : formatCoins(_balance!), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: kRoyal)),
                    ]),
                  ]),
                ),
                if (widget.onAddCoins != null)
                  TextButton(
                    style: TextButton.styleFrom(backgroundColor: const Color(0xFFEDE6FB), foregroundColor: kRoyal, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    onPressed: () { Navigator.of(context).pop(); widget.onAddCoins!(); },
                    child: const Text('+ ADD', style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
              ]),
            ),
            const SizedBox(height: 10),
            if (_error != null)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(12)),
                child: Text(_error!, style: TextStyle(color: Colors.red.shade800)),
              ),
            if (gifts == null && _error == null)
              const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()))
            else if (gifts != null)
              Flexible(
                child: GridView.count(
                  shrinkWrap: true,
                  crossAxisCount: 3,
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                  childAspectRatio: 0.95,
                  children: [for (final g in gifts) _card(g)],
                ),
              ),
          ]),
        ),
      ),
    );
  }

  // One gift: a big picture, its name, and the price with a coin. No box around it.
  Widget _card(Map<String, dynamic> g) {
    final busy = _sending == g['key'];
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: _sending != null ? null : () => _send(g),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        SizedBox(
          height: 54,
          child: Center(child: busy ? const SizedBox(width: 30, height: 30, child: CircularProgressIndicator(strokeWidth: 2.5)) : Text('${g['emoji']}', style: const TextStyle(fontSize: 44))),
        ),
        const SizedBox(height: 2),
        Text('${g['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
        const SizedBox(height: 2),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.monetization_on, size: 20, color: kGold),
          const SizedBox(width: 3),
          Text('${g['coins']}', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: kInk)),
        ]),
      ]),
    );
  }
}

/// How a gift looks in a chat: a big emoji on a soft card. The host sees "Gift from ..." and what they earned.
class GiftBubble extends StatelessWidget {
  const GiftBubble({super.key, required this.emoji, required this.name, required this.mine, this.earnedLine});
  final String emoji, name;
  final bool mine;
  final String? earnedLine;
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFFFFF3D6), Color(0xFFFFE3F0)]),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kGold, width: 1.2),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(emoji, style: const TextStyle(fontSize: 46)),
        const SizedBox(height: 2),
        Text(mine ? 'You sent $name' : 'Gift: $name', style: const TextStyle(fontWeight: FontWeight.w800, color: kInk)),
        if (earnedLine != null) Text(earnedLine!, style: TextStyle(fontSize: 12, color: Colors.green.shade800, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}
