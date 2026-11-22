import 'package:flutter/material.dart';
import 'package:talkory_core/talkory_core.dart';

const _medals = ['🥇', '🥈', '🥉'];

/// Home tab card: this host's place this week and the top 3. Tap for the full top 10.
class LeaderboardCard extends StatelessWidget {
  const LeaderboardCard({super.key, required this.api, required this.data});
  final Api api;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final me = Map<String, dynamic>.from(data['me'] as Map);
    final top = (data['top'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final bonuses = List<int>.from((data['bonuses'] as List?) ?? const []);
    final rank = me['rank'] as int?;
    final line = rank == null
        ? 'Take calls this week to join the leaderboard.'
        : rank == 1
            ? 'You are #1 this week. Amazing!'
            : 'You are #$rank this week. ${rank <= 10 ? 'Keep going!' : 'Top 10 is close!'}';
    return SoftCard(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => LeaderboardScreen(api: api))),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Text('🏆', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 6),
              const Expanded(child: Text('Weekly leaderboard', style: TextStyle(fontWeight: FontWeight.w700, color: kInk))),
              const Icon(Icons.chevron_right, color: Colors.black38),
            ]),
            const SizedBox(height: 6),
            Text(line, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: kInk)),
            if (bonuses.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text('Top ${bonuses.length} win ${bonuses.map((b) => '₹$b').join(' / ')} every Monday', style: const TextStyle(color: Colors.black54, fontSize: 12)),
            ],
            const SizedBox(height: 8),
            for (final r in top.take(3))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  SizedBox(width: 26, child: Text(_medals[(r['rank'] as int).clamp(1, 3) - 1], style: const TextStyle(fontSize: 16))),
                  Expanded(
                      child: Text(r['me'] == true ? '${r['name']} (you)' : '${r['name']}',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: r['me'] == true ? FontWeight.w800 : FontWeight.w500))),
                  Text(tierHours((r['seconds'] as num).toInt()), style: const TextStyle(color: Colors.black54, fontSize: 12)),
                ]),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Full top 10 for this week, with this host's own place at the bottom if they are not in it.
class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key, required this.api});
  final Api api;

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  late Future<Map<String, dynamic>> _f = widget.api.leaderboard();

  Widget _row(Map<String, dynamic> r) {
    final rank = r['rank'] as int?;
    final me = r['me'] == true;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: me ? const Color(0xFFF1EBFF) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: me ? kRoyal : const Color(0x14000000)),
      ),
      child: Row(children: [
        SizedBox(
          width: 34,
          child: rank != null && rank <= 3
              ? Text(_medals[rank - 1], style: const TextStyle(fontSize: 20))
              : Text(rank == null ? '–' : '#$rank', style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.black54)),
        ),
        ProfileAvatar(baseUrl: widget.api.baseUrl, name: '${r['name'] ?? 'You'}', url: r['avatarUrl'] as String?, radius: 18),
        const SizedBox(width: 10),
        Expanded(
            child: Text(me ? '${r['name'] ?? 'You'} (you)' : '${r['name']}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: me ? FontWeight.w800 : FontWeight.w600, color: kInk))),
        if (r['tier'] != null) Padding(padding: const EdgeInsets.only(right: 8), child: TierChip(tier: r['tier'] as String?, name: null, small: true)),
        Text(tierHours((r['seconds'] as num).toInt()), style: const TextStyle(fontWeight: FontWeight.w700, color: kInk)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Weekly leaderboard')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _f,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) return Center(child: TextButton(onPressed: () => setState(() => _f = widget.api.leaderboard()), child: const Text('Could not load. Tap to retry')));
          final d = snap.data!;
          final top = (d['top'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          final me = Map<String, dynamic>.from(d['me'] as Map);
          final bonuses = List<int>.from((d['bonuses'] as List?) ?? const []);
          return RefreshIndicator(
            onRefresh: () async {
              setState(() => _f = widget.api.leaderboard());
              await _f;
            },
            child: ListView(padding: const EdgeInsets.symmetric(vertical: 12), children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                    'Ranked by talk time on calls this week (Monday to Sunday). ${bonuses.isEmpty ? '' : 'Top ${bonuses.length} win ${bonuses.map((b) => '₹$b').join(' / ')} on Monday.'}',
                    style: const TextStyle(color: Colors.black54)),
              ),
              if (top.isEmpty) const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No calls yet this week. Be the first!'))),
              for (final r in top) _row(r),
              if (top.every((r) => r['me'] != true)) ...[
                const Padding(padding: EdgeInsets.fromLTRB(16, 12, 16, 4), child: Text('Your place', style: TextStyle(fontWeight: FontWeight.w700))),
                _row(me),
              ],
            ]),
          );
        },
      ),
    );
  }
}
