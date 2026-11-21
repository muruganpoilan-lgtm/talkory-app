import 'package:flutter/material.dart';
import 'api.dart';

/// A row of friendly nickname suggestions. Tapping one calls [onPick]; the person can still type their own name.
class NicknameChips extends StatefulWidget {
  const NicknameChips({super.key, required this.api, required this.onPick});
  final Api api;
  final void Function(String name) onPick;
  @override
  State<NicknameChips> createState() => _NicknameChipsState();
}

class _NicknameChipsState extends State<NicknameChips> {
  List<String> _names = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final n = await widget.api.nicknameSuggestions();
      if (mounted) setState(() => _names = n);
    } catch (_) {} // no suggestions when offline: typing still works
  }

  @override
  Widget build(BuildContext context) {
    if (_names.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Tap a nickname, or type your own', style: Theme.of(context).textTheme.bodySmall),
          const Spacer(),
          TextButton.icon(
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            onPressed: _load,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('More'),
          ),
        ]),
        Wrap(spacing: 8, runSpacing: 0, children: [
          for (final n in _names) ActionChip(label: Text(n), onPressed: () => widget.onPick(n)),
        ]),
      ]),
    );
  }
}
