import 'package:flutter/material.dart';

/// The three reasons a host can pick when blocking a user. The choice is sent to the admin team as a report too.
const hostBlockReasons = [
  'Asking personal details',
  'Harassment talks',
  'Using vulgar words',
];

const _hints = {
  'Asking personal details': 'Phone number, address, social media, money or other private questions',
  'Harassment talks': 'Pressure, threats, insults or repeated unwanted messages',
  'Using vulgar words': 'Dirty, abusive or sexual language',
};

/// Asks the host why they are blocking. Returns the chosen reason, or null if they cancelled.
Future<String?> askBlockReason(BuildContext context, String name) {
  String? chosen;
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: Text('Block $name?'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Choose why. Our team will review it and this person will not reach you again.'),
          const SizedBox(height: 8),
          for (final r in hostBlockReasons)
            RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(r, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(_hints[r] ?? '', style: const TextStyle(fontSize: 12)),
              value: r,
              groupValue: chosen,
              onChanged: (v) => setS(() => chosen = v),
            ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: chosen == null ? null : () => Navigator.pop(ctx, chosen),
            child: const Text('Block'),
          ),
        ],
      ),
    ),
  );
}
