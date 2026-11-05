import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/api_ext.dart';
import '../core/models_social.dart';
import '../core/util.dart';
import 'widgets.dart';

// ---------- helpers partagés (utilisés par profile_screen.dart) ----------
Color levelColor(int index) => const [
      Color(0xFF94A3B8), Color(0xFF0E9F9A), Color(0xFF2563EB),
      Color(0xFF7C3AED), Color(0xFFF59E0B), Color(0xFFDB2777),
    ][index.clamp(0, 5)];

IconData badgeIcon(String icon) => switch (icon) {
      'mic' => Icons.mic_rounded,
      'streak' || 'fire' => Icons.local_fire_department_rounded,
      'star' => Icons.star_rounded,
      'trophy' => Icons.emoji_events_rounded,
      'compass' => Icons.explore_rounded,
      'map' => Icons.map_rounded,
      'shield' => Icons.shield_rounded,
      'verified' => Icons.verified_rounded,
      'hearing' => Icons.hearing_rounded,
      'road' => Icons.add_road_rounded,
      'target' => Icons.my_location_rounded,
      'award' => Icons.military_tech_rounded,
      'diamond' => Icons.diamond_rounded,
      _ => Icons.workspace_premium_rounded,
    };

class LevelAvatar extends StatelessWidget {
  const LevelAvatar(this.name, this.level, {super.key, this.radius = 24});
  final String name;
  final Level level;
  final double radius;
  @override
  Widget build(BuildContext context) {
    final col = levelColor(level.index);
    return CircleAvatar(
      radius: radius,
      backgroundColor: col.withValues(alpha: 0.18),
      child: Text(
        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        style: TextStyle(color: col, fontWeight: FontWeight.w800, fontSize: radius * 0.8),
      ),
    );
  }
}

class LevelChip extends StatelessWidget {
  const LevelChip(this.level, {super.key});
  final Level level;
  @override
  Widget build(BuildContext context) {
    final col = levelColor(level.index);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: col.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.military_tech_rounded, size: 14, color: col),
        const SizedBox(width: 4),
        Text('Niv. ${level.index + 1} · ${level.name}',
            style: TextStyle(color: col, fontWeight: FontWeight.w700, fontSize: 12)),
      ]),
    );
  }
}

// ---------- écran ----------
class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});
  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  String _period = 'week';
  LeaderBoard? _board;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final b = await context.read<ApiClient>().leaderboard(_period);
      if (mounted) setState(() => _board = b);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Classement')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'week', label: Text('Semaine')),
              ButtonSegment(value: 'month', label: Text('Mois')),
              ButtonSegment(value: 'season', label: Text('Saison')),
            ],
            selected: {_period},
            onSelectionChanged: (v) {
              setState(() => _period = v.first);
              _load();
            },
            showSelectedIcon: false,
          ),
        ),
        if (_loading) const Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()),
        if (_error != null) Padding(padding: const EdgeInsets.all(16), child: Text(_error!, style: TextStyle(color: cs.error))),
        if (!_loading && _board != null)
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
              if (_board!.me != null) ...[
                SoftCard(
                  child: Row(children: [
                    LevelAvatar(_board!.me!.name, _board!.me!.level, radius: 26),
                    const SizedBox(width: 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Moi · #${_board!.me!.rank} / ${_board!.total}', style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text('${_board!.me!.score.toStringAsFixed(0)} pts', style: TextStyle(color: cs.onSurfaceVariant)),
                    ])),
                  ]),
                ),
                const SectionTitle('Autour de moi'),
                for (final e in _board!.around) _entry(e, cs, highlight: e.isMe),
                SectionTitle('Top ${_board!.entries.length}'),
              ],
              for (final e in _board!.entries) _entry(e, cs, highlight: e.isMe),
            ]),
          ),
      ]),
    );
  }

  Widget _entry(LeaderEntry e, ColorScheme cs, {bool highlight = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: highlight ? cs.primary.withValues(alpha: 0.10) : cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: highlight ? cs.primary : cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(children: [
        SizedBox(width: 32, child: Text('#${e.rank}', style: TextStyle(fontWeight: FontWeight.w800, color: e.rank <= 3 ? levelColor(e.rank - 1) : cs.onSurfaceVariant))),
        LevelAvatar(e.name, e.level, radius: 20),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(e.name, style: const TextStyle(fontWeight: FontWeight.w700)),
          Text('${e.validated} validées · ${e.missions} missions', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
        ])),
        Text('${e.score.toStringAsFixed(0)} pts', style: const TextStyle(fontWeight: FontWeight.w800)),
      ]),
    );
  }
}