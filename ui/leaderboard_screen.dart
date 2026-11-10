import 'dart:math';

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

Color _medal(int rank) => switch (rank) {
      1 => const Color(0xFFFBBF24),
      2 => const Color(0xFFCBD5E1),
      _ => const Color(0xFFD08A52),
    };

// ---------- écran ----------
class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});
  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  static const _periods = [
    ('week', 'Semaine', Icons.bolt_rounded),
    ('month', 'Mois', Icons.calendar_month_rounded),
    ('season', 'Saison', Icons.emoji_events_rounded),
  ];

  String _period = 'week';
  final Map<String, LeaderBoard> _cache = {}; // changement de période instantané, puis rafraîchi
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = _period;
    setState(() {
      _loading = !_cache.containsKey(p);
      _error = null;
    });
    try {
      final b = await context.read<ApiClient>().leaderboard(p);
      if (mounted) setState(() => _cache[p] = b);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final b = _cache[_period];
    return Scaffold(
      appBar: AppBar(title: const Text('Classement')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
          children: [
            _picker(cs),
            const SizedBox(height: 14),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 320),
              switchInCurve: Curves.easeOutCubic,
              transitionBuilder: (c, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(position: Tween(begin: const Offset(0, 0.03), end: Offset.zero).animate(a), child: c),
              ),
              child: Column(
                key: ValueKey('$_period-${b == null ? 'x' : 'ok'}'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: b != null
                    ? _content(b, cs)
                    : _loading
                        ? [_skeleton(cs)]
                        : [_errorCard(cs)],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ sélecteur de période
  Widget _picker(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(children: [
        for (final p in _periods)
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (_period == p.$1) return;
                setState(() => _period = p.$1);
                _load();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: _period == p.$1
                      ? LinearGradient(colors: [cs.primary, Color.lerp(cs.primary, const Color(0xFF2563EB), 0.55)!])
                      : null,
                  boxShadow: _period == p.$1 ? [BoxShadow(color: cs.primary.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 4))] : null,
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(p.$3, size: 17, color: _period == p.$1 ? cs.onPrimary : cs.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(p.$2, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: _period == p.$1 ? cs.onPrimary : cs.onSurfaceVariant)),
                ]),
              ),
            ),
          ),
      ]),
    );
  }

  // ------------------------------------------------------------------ contenu
  List<Widget> _content(LeaderBoard b, ColorScheme cs) {
    final top = b.entries.isEmpty ? 0.0 : b.entries.map((e) => e.score).reduce(max);
    final inTop = b.entries.any((e) => e.isMe);
    final topRanks = {for (final e in b.entries) e.rank};
    final around = b.around.where((e) => !topRanks.contains(e.rank)).toList();
    final rest = b.entries.skip(3).toList();
    var i = 0;
    return [
      _meCard(b, cs),
      if (b.entries.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: SoftCard(
            padding: const EdgeInsets.all(28),
            child: Center(child: Column(children: [
              Icon(Icons.emoji_events_outlined, size: 42, color: cs.primary),
              const SizedBox(height: 8),
              const Text('Personne n\'est encore classé', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('Soyez le premier à valider une mesure.', style: TextStyle(color: cs.onSurfaceVariant)),
            ])),
          ),
        )
      else ...[
        const SizedBox(height: 16),
        _podium(b.entries.take(3).toList()),
        if (rest.isNotEmpty) SectionTitle('Du #4 au #${b.entries.length}'),
        for (final e in rest) _row(e, top, cs, i++),
        if (!inTop && around.isNotEmpty) ...[
          const SectionTitle('Autour de moi'),
          for (final e in around) _row(e, top, cs, i++),
        ],
      ],
    ];
  }

  // ------------------------------------------------------------------ ma position
  Widget _meCard(LeaderBoard b, ColorScheme cs) {
    final me = b.me;
    if (me == null) {
      return SoftCard(
        child: Row(children: [
          Icon(Icons.flag_rounded, color: cs.primary),
          const SizedBox(width: 12),
          Expanded(child: Text('Validez une mesure pour entrer dans le classement.', style: TextStyle(color: cs.onSurfaceVariant))),
        ]),
      );
    }
    final ranked = me.rank > 0;
    final pct = ranked && b.total > 0 ? max(1, (me.rank / b.total * 100).ceil()) : null;
    final rel = me.reliability.clamp(0.0, 1.0).toDouble();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          colors: [cs.primary, Color.lerp(cs.primary, const Color(0xFF2563EB), 0.65)!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [BoxShadow(color: cs.primary.withValues(alpha: 0.35), blurRadius: 22, offset: const Offset(0, 10))],
      ),
      child: Row(children: [
        CircleAvatar(radius: 31, backgroundColor: Colors.white, child: LevelAvatar(me.name, me.level, radius: 28)),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Ma position', style: TextStyle(color: Colors.white.withValues(alpha: 0.78), fontSize: 12, fontWeight: FontWeight.w600)),
            Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
              Text(ranked ? '#${me.rank}' : '—', style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w900, height: 1.1)),
              Text(ranked ? '  / ${b.total}' : '', style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 4, children: [
              _pill('${me.score.toStringAsFixed(0)} pts', Colors.white.withValues(alpha: 0.2), Colors.white),
              if (pct != null) _pill('Top $pct %', Colors.white.withValues(alpha: 0.2), Colors.white),
              if (me.delta != null && me.delta != 0) _deltaChip(me.delta!, onDark: true),
            ]),
          ]),
        ),
        Column(children: [
          ScoreRing(
            value: rel,
            color: Colors.white,
            size: 60,
            stroke: 6,
            child: Text('${(rel * 100).round()}%', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
          ),
          const SizedBox(height: 3),
          Text('Fiabilité', style: TextStyle(color: Colors.white.withValues(alpha: 0.78), fontSize: 10.5)),
        ]),
      ]),
    );
  }

  Widget _pill(String t, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Text(t, style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 11.5)),
      );

  Widget _deltaChip(int d, {bool onDark = false}) {
    final up = d > 0;
    final c = up ? const Color(0xFF22C55E) : const Color(0xFFEF4444);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: onDark ? Colors.white : c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(up ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded, size: 18, color: c),
        Text('${d.abs()}', style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 11.5)),
        const SizedBox(width: 3),
      ]),
    );
  }

  // ------------------------------------------------------------------ podium
  Widget _podium(List<LeaderEntry> top) {
    final order = <LeaderEntry>[
      if (top.length > 1) top[1],
      top[0],
      if (top.length > 2) top[2],
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 22, 10, 0),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(colors: [Color(0xFF0B1F2A), Color(0xFF0E5E63)], begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      child: Stack(children: [
        Positioned(right: -30, top: -30, child: _glow(110, const Color(0xFFFBBF24))),
        Positioned(left: -40, bottom: 20, child: _glow(120, const Color(0xFF2DD4BF))),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (final e in order) Expanded(child: _slot(e)),
        ]),
      ]),
    );
  }

  Widget _glow(double s, Color c) => IgnorePointer(
        child: Container(
          width: s,
          height: s,
          decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [c.withValues(alpha: 0.28), c.withValues(alpha: 0)])),
        ),
      );

  Widget _slot(LeaderEntry e) {
    final first = e.rank == 1;
    final medal = _medal(e.rank);
    final h = first ? 118.0 : (e.rank == 2 ? 88.0 : 68.0);
    final r = first ? 36.0 : 28.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (first) Icon(Icons.workspace_premium_rounded, color: medal, size: 30),
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: [medal, medal.withValues(alpha: 0.35)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            boxShadow: [BoxShadow(color: medal.withValues(alpha: 0.5), blurRadius: first ? 22 : 14)],
          ),
          child: DecoratedBox(
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF10303C)),
            child: LevelAvatar(e.name, e.level, radius: r),
          ),
        ),
        const SizedBox(height: 8),
        Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: TextStyle(color: e.isMe ? const Color(0xFF2DD4BF) : Colors.white, fontWeight: FontWeight.w800, fontSize: first ? 14.5 : 13)),
        const SizedBox(height: 2),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: e.score),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (_, v, __) => Text('${v.round()} pts', style: TextStyle(color: Colors.white.withValues(alpha: 0.82), fontWeight: FontWeight.w700, fontSize: 12)),
        ),
        const SizedBox(height: 8),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: h),
          duration: Duration(milliseconds: 650 + e.rank * 150),
          curve: Curves.easeOutBack,
          builder: (_, v, __) => Container(
            height: max(0.0, v),
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
              gradient: LinearGradient(colors: [medal.withValues(alpha: 0.95), medal.withValues(alpha: 0.35)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
            ),
            alignment: Alignment.topCenter,
            padding: const EdgeInsets.only(top: 10),
            child: Text('${e.rank}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 26, shadows: [Shadow(color: Colors.black38, blurRadius: 6)])),
          ),
        ),
      ]),
    );
  }

  // ------------------------------------------------------------------ ligne du classement
  Widget _row(LeaderEntry e, double top, ColorScheme cs, int i) {
    final me = e.isMe;
    final lc = levelColor(e.level.index);
    final frac = top <= 0 ? 0.0 : (e.score / top).clamp(0.0, 1.0).toDouble();
    return _Reveal(
      key: ValueKey('$_period-r${e.rank}-${e.name}'),
      index: i,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 11, 14, 11),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: me ? LinearGradient(colors: [cs.primary.withValues(alpha: 0.18), cs.primary.withValues(alpha: 0.05)]) : null,
          color: me ? null : cs.surfaceContainerHigh,
          border: Border.all(color: me ? cs.primary : cs.outlineVariant.withValues(alpha: 0.4), width: me ? 1.6 : 1),
          boxShadow: me ? [BoxShadow(color: cs.primary.withValues(alpha: 0.22), blurRadius: 14, offset: const Offset(0, 5))] : null,
        ),
        child: Row(children: [
          SizedBox(width: 34, child: Text('#${e.rank}', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: cs.onSurfaceVariant))),
          LevelAvatar(e.name, e.level, radius: 21),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800))),
                if (me) ...[const SizedBox(width: 6), StatusChip('Vous', cs.primary)],
              ]),
              const SizedBox(height: 2),
              Text('${e.validated} validées · ${e.missions} missions · ${e.days} j', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11.5)),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: frac),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeOutCubic,
                  builder: (_, v, __) => LinearProgressIndicator(minHeight: 5, value: v, color: lc, backgroundColor: cs.outlineVariant.withValues(alpha: 0.25)),
                ),
              ),
            ]),
          ),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: e.score),
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeOutCubic,
              builder: (_, v, __) => Text('${v.round()}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, height: 1.1)),
            ),
            Text('pts', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 10.5)),
            if (e.delta != null && e.delta != 0) Padding(padding: const EdgeInsets.only(top: 3), child: _deltaChip(e.delta!)),
          ]),
        ]),
      ),
    );
  }

  // ------------------------------------------------------------------ états
  Widget _skeleton(ColorScheme cs) {
    Widget box(double h, double r) => Container(
          height: h,
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(r)),
        );
    return _Pulse(child: Column(children: [box(96, 26), box(190, 28), for (var i = 0; i < 5; i++) box(66, 20)]));
  }

  Widget _errorCard(ColorScheme cs) => SoftCard(
        child: Row(children: [
          Icon(Icons.cloud_off_rounded, color: cs.error),
          const SizedBox(width: 12),
          Expanded(child: Text(_error ?? 'Indisponible', style: TextStyle(color: cs.error))),
          TextButton(onPressed: _load, child: const Text('Réessayer')),
        ]),
      );
}

// ---------- animations utilitaires ----------
/// Apparition en cascade (glissement + fondu), décalée selon l'index.
class _Reveal extends StatefulWidget {
  const _Reveal({super.key, required this.index, required this.child});
  final int index;
  final Widget child;
  @override
  State<_Reveal> createState() => _RevealState();
}

class _RevealState extends State<_Reveal> {
  bool _on = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: min(widget.index * 45, 500)), () {
      if (mounted) setState(() => _on = true);
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedSlide(
        offset: _on ? Offset.zero : const Offset(0, 0.18),
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(opacity: _on ? 1 : 0, duration: const Duration(milliseconds: 420), child: widget.child),
      );
}

/// Pulsation douce pour les écrans de chargement.
class _Pulse extends StatefulWidget {
  const _Pulse({required this.child});
  final Widget child;
  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: Tween(begin: 0.4, end: 1.0).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)), child: widget.child);
}