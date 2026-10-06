import 'package:flutter/material.dart';
import 'api.dart';

const _reasons = ['Abusive or offensive language', 'Harassment or threats', 'Sexual or inappropriate content', 'Spam or promotion', 'Other'];

/// Shown after a connected call. Users can rate; both sides can report or block.
class PostCallScreen extends StatefulWidget {
  const PostCallScreen({super.key, required this.api, required this.callId, required this.peerName, required this.canRate});
  final Api api;
  final String callId, peerName;
  final bool canRate;
  @override
  State<PostCallScreen> createState() => _PostCallScreenState();
}

class _PostCallScreenState extends State<PostCallScreen> {
  final _comment = TextEditingController();
  int _stars = 0;
  bool _busy = false, _reported = false, _blocked = false;

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _run(Future<void> Function() task, {VoidCallback? onOk, String? ok}) async {
    setState(() => _busy = true);
    try {
      await task();
      onOk?.call();
      if (ok != null) _snack(ok);
    } on ApiException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('Network error. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitRating() async {
    await _run(() => widget.api.rateCall(widget.callId, _stars, _comment.text.trim()), ok: 'Thanks for your feedback');
    if (mounted && _stars > 0) Navigator.of(context).pop();
  }

  Future<void> _report() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Report this person'),
        children: [for (final r in _reasons) SimpleDialogOption(onPressed: () => Navigator.pop(ctx, r), child: Text(r))],
      ),
    );
    if (reason == null) return;
    await _run(() => widget.api.reportCall(widget.callId, reason),
        onOk: () => setState(() => _reported = true), ok: 'Report sent. Our team will review it.');
  }

  Future<void> _block() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Block ${widget.peerName}?'),
        content: const Text('You will not be connected with each other again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Block')),
        ],
      ),
    );
    if (yes != true) return;
    await _run(() => widget.api.blockCall(widget.callId),
        onOk: () => setState(() => _blocked = true), ok: '${widget.peerName} is blocked');
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Call ended'), automaticallyImplyLeading: false),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (widget.canRate) ...[
            Text('How was your call with ${widget.peerName}?', style: text.titleLarge),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 1; i <= 5; i++)
                  IconButton(
                    iconSize: 40,
                    onPressed: () => setState(() => _stars = i),
                    icon: Icon(i <= _stars ? Icons.star : Icons.star_border, color: Colors.amber),
                  ),
              ],
            ),
            TextField(
              controller: _comment,
              maxLength: 500,
              maxLines: 3,
              decoration: const InputDecoration(hintText: 'Add a comment (optional)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            FilledButton(onPressed: _busy || _stars == 0 ? null : _submitRating, child: const Text('Submit rating')),
          ] else
            Text('Call with ${widget.peerName} ended', style: text.titleLarge),
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 8),
          Text('Something went wrong?', style: text.titleSmall),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy || _reported ? null : _report,
                icon: const Icon(Icons.flag_outlined),
                label: Text(_reported ? 'Reported' : 'Report'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy || _blocked ? null : _block,
                icon: const Icon(Icons.block),
                label: Text(_blocked ? 'Blocked' : 'Block'),
              ),
            ),
          ]),
          const SizedBox(height: 24),
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(widget.canRate ? 'Skip' : 'Done')),
        ],
      ),
    );
  }
}
