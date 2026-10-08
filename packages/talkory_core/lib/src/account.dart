import 'package:flutter/material.dart';
import 'api.dart';

/// Warns, asks the user to type DELETE, deletes the account on the server, then calls [onDeleted] (log out locally).
Future<void> confirmAndDeleteAccount(BuildContext context, Api api, VoidCallback onDeleted) async {
  var balance = 0;
  try {
    balance = await api.walletBalance();
  } catch (_) {}
  if (!context.mounted) return;

  final typed = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('Delete your account?'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('This permanently removes your profile and personal details and cannot be undone. '
                'Payment and call records we must keep by law stay on file without your name or number.'),
            if (balance > 0)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text('Your remaining balance of ₹${(balance / 100).toStringAsFixed(2)} will be lost. Contact support first if you need a refund or payout.',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: typed,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Type DELETE to confirm'),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: typed.text.trim() == 'DELETE' ? () => Navigator.pop(ctx, true) : null,
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    ),
  );
  if (ok != true) return;

  try {
    await api.deleteAccount();
    onDeleted();
  } catch (e) {
    if (!context.mounted) return;
    final msg = e is ApiException ? e.message : 'Network error. Please try again.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
