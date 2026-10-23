import 'package:flutter/material.dart';

/// Weekly "Paradise" level of a host, from the hours spent on calls (Monday to Sunday).
/// Green 15h+, Golden 10-15h, Ruby 7-10h, Blue 5-7h, Purple 0-5h.
class TierStyle {
  const TierStyle(this.emoji, this.color);
  final String emoji;
  final Color color;
}

const _tiers = <String, TierStyle>{
  'green': TierStyle('🟢', Color(0xFF1FA85A)),
  'golden': TierStyle('🟡', Color(0xFFE0A100)),
  'ruby': TierStyle('🔴', Color(0xFFD62839)),
  'blue': TierStyle('🔵', Color(0xFF2F6FEB)),
  'purple': TierStyle('🟣', Color(0xFF7B3FCB)),
};

TierStyle tierStyle(String? key) => _tiers[key] ?? _tiers['purple']!;

/// "7h 20m" from seconds
String tierHours(int sec) {
  final h = sec ~/ 3600, m = (sec % 3600) ~/ 60;
  return h > 0 ? '${h}h ${m}m' : '${m}m';
}

/// Small coloured label such as "🟢 Green Paradise"
class TierChip extends StatelessWidget {
  const TierChip({super.key, required this.tier, required this.name, this.small = true});
  final String? tier, name;
  final bool small;
  @override
  Widget build(BuildContext context) {
    final s = tierStyle(tier);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 6 : 10, vertical: small ? 1 : 4),
      decoration: BoxDecoration(color: s.color.withAlpha(31), borderRadius: BorderRadius.circular(10), border: Border.all(color: s.color.withAlpha(128))),
      child: Text('${s.emoji} ${name ?? ''}', style: TextStyle(fontSize: small ? 10 : 13, fontWeight: FontWeight.w700, color: s.color)),
    );
  }
}
