import 'package:flutter/material.dart';

/// The three reasons a host can pick when blocking a user. The choice is sent to the admin team as a report too.
const hostBlockReasons = [
  'Asking personal details',
  'Harassment talks',
  'Using vulgar words',
];

/// The reasons a user can pick when blocking a host.
const userBlockReasons = [
  'Asked for personal details',
  'Rude or harassing talk',
  'Using vulgar words',
  'Not the person in the photo',
];

const _hints = {
  'Asking personal details': 'Phone number, address, social media, money or other private questions',
  'Harassment talks': 'Pressure, threats, insults or repeated unwanted messages',
  'Using vulgar words': 'Dirty, abusive or sexual language',
  'Asked for personal details': 'Wanted your number, address, social media or money',
  'Rude or harassing talk': 'Pressure, threats, insults or repeated unwanted messages',
  'Not the person in the photo': 'The voice did not match the profile',
};

/// Asks why they are blocking. Returns the chosen reason, or null if they cancelled.
/// [isUser] picks the wording and the reasons a user sees for blocking a host.
Future<String?> askBlockReason(BuildContext context, String name, {bool isUser = false}) {
  String? chosen;
  final reasons = isUser ? userBlockReasons : hostBlockReasons;
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: Text('Block $name?'),
        // Scrollable: four reasons plus their hints do not fit a small screen in landscape.
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(isUser
              ? 'Choose why. Our team will review it and you will not be connected again.'
              : 'Choose why. Our team will review it and this person will not reach you again.'),
          const SizedBox(height: 8),
          for (final r in reasons)
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
        ),
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
