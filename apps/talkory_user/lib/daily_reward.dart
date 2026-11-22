import 'package:flutter/material.dart';
import 'package:talkory_core/talkory_core.dart';

/// Daily check-in card on the Call tab: collect free coins once a day; coming back every day builds a 7-day streak.
/// Shows only while today's reward is waiting, then hides itself.
class DailyRewardCard extends StatefulWidget {
  const DailyRewardCard({super.key, required this.api, required this.onCollected});
  final Api api;
  final Future<void> Function() onCollected; // refresh the coin balance

  @override
  State<DailyRewardCard> createState() => _DailyRewardCardState();
}

class _DailyRewardCardState extends State<DailyRewardCard> {
  Map<String, dynamic>? _s;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await widget.api.dailyReward();
      if (mounted) setState(() => _s = s);
    } catch (_) {} // no card if the server can't be reached
  }

  Future<void> _collect() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final r = await widget.api.collectDailyReward();
      final streak = r['streak'] as int;
      messenger.showSnackBar(SnackBar(
          content: Text('+${r['coins']} coins collected! ${streak > 1 ? '$streak days in a row. ' : ''}Come back tomorrow for more.')));
      await widget.onCollected();
      if (mounted) setState(() => _s = {...?_s, 'claimedToday': true});
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e is ApiException ? e.message : 'Network error. Try again.')));
      _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    if (s == null || s['claimedToday'] == true) return const SizedBox.shrink();
    final rewards = List<int>.from(s['rewards'] as List);
    final day = s['day'] as int; // 1..7: today's reward day
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFFFFF4D6), Color(0xFFFFE8F0)]),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF5D88A)),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(day == rewards.length ? 'Day $day: big reward today!' : 'Daily reward · Day $day',
                style: const TextStyle(fontWeight: FontWeight.w800, color: kInk, fontSize: 15)),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(children: [
              for (var i = 0; i < rewards.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 5),
                  child: Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < day - 1 ? kGold : i == day - 1 ? Colors.white : Colors.white.withValues(alpha: 0.6),
                      border: Border.all(color: i == day - 1 ? kRoyal : const Color(0xFFF0CF73), width: i == day - 1 ? 2 : 1),
                    ),
                    child: i < day - 1
                        ? const Icon(Icons.check, size: 14, color: kRoyalDeep)
                        : Text('${rewards[i]}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: i == day - 1 ? kRoyal : kInk)),
                  ),
                ),
            ]),
            ),
          ]),
        ),
        const SizedBox(width: 8),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: kRoyal, foregroundColor: Colors.white, shape: const StadiumBorder(), padding: const EdgeInsets.symmetric(horizontal: 14)),
          onPressed: _busy ? null : _collect,
          child: Text('Get ${s['coins']}'),
        ),
      ]),
    );
  }
}
