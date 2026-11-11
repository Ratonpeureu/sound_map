import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../core/api.dart';
import '../core/api_ext.dart';
import '../core/models_social.dart';
import '../core/util.dart';
import '../state/account_controller.dart';
import '../state/proposals_controller.dart';
import '../state/reviews_controller.dart';
import '../state/session_controller.dart';
import '../state/view_models.dart';
import 'auth_screen.dart' show passwordPolicyOk;
import 'guide_screen.dart';
import 'leaderboard_screen.dart';
import 'my_mapping.dart';
import 'proposals_screen.dart';
import 'reviews_screen.dart';
import 'schedule_screen.dart';
import 'settings_screen.dart';
import 'widgets.dart';
import '../state/studies_controller.dart';
import 'studies_screen.dart'; 
import 'rewards_screen.dart';

import 'my_responses_screen.dart';
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<HistoryViewModel>().reload();
      context.read<AccountController>().loadAll();
    });
  }

  Future<void> _refresh() async {
    await context.read<HistoryViewModel>().reload();
    if (mounted) await context.read<AccountController>().loadAll();
  }

  Widget _kpi(BuildContext context, IconData i, String v, String l) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        Icon(i, color: cs.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(v, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            Text(l, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11)),
          ]),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SessionController>();
    final h = context.watch<HistoryViewModel>();
    final proposals = context.watch<ProposalsController>();
    final acc = context.watch<AccountController>();
    final cs = Theme.of(context).colorScheme;
    final u = s.user!;
    final stats = h.stats;
    final p = acc.profile;
    final board = acc.board;
    final name = p?.displayName ?? u.pseudonym;
    final level = p?.level ?? board?.level;
    final season = board?.periods['season'];
    final week = board?.periods['week'];

    return Scaffold(
      appBar: AppBar(title: const Text('Moi'), actions: [
        IconButton(icon: const Icon(Icons.settings_rounded), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()))),
      ]),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            // ---------------------------------------------------------------- en-tête
            SoftCard(
              child: Column(children: [
                Row(children: [
                  if (level != null) LevelAvatar(name, level, radius: 30) else CircleAvatar(radius: 30, child: Text(name.characters.first.toUpperCase())),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 19)),
                      if (p != null && (p.city != null || p.district != null))
                        Text([p.district, p.city].whereType<String>().join(', '), style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                      const SizedBox(height: 6),
                      Wrap(spacing: 6, runSpacing: 4, children: [
                        if (level != null) LevelChip(level),
                        StatusChip(u.roleLabel, cs.primary),
                        if (p?.analystEnabled ?? false) const StatusChip('Analyseur', Color(0xFF7C3AED), icon: Icons.hearing_rounded),
                        if (u.participationPaused) const StatusChip('En pause', Color(0xFFF59E0B)),
                      ]),
                    ]),
                  ),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.edit_outlined), label: const Text('Modifier'), onPressed: p == null ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => EditProfileScreen(profile: p))))),
                  const SizedBox(width: 10),
                  Expanded(child: FilledButton.icon(icon: const Icon(Icons.leaderboard_rounded), label: const Text('Classement'), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LeaderboardScreen())))),
                ]),
                if (p?.memberSince != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Membre depuis le ${fmtDay(p!.memberSince!)}', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12))),
              ]),
            ),

            // ---------------------------------------------------------------- guide
            const SizedBox(height: 12),
            _GuideCard(onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GuideScreen()))),

            // ---------------------------------------------------------------- niveau + badges
            if (board != null) ...[
              const SectionTitle('Niveau et badges'),
              _LevelCard(board: board, week: week),
            ],

            // ---------------------------------------------------------------- contributions
            const SectionTitle('Mes contributions'),
            SoftCard(
              child: stats == null
                  ? const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
                  : Column(children: [
                      Row(children: [
                        SizedBox(
                          width: 130,
                          height: 130,
                          child: stats.total == 0
                              ? const ScoreRing(value: 0, color: Colors.grey, size: 130, stroke: 14)
                              : PieChart(PieChartData(sectionsSpace: 3, centerSpaceRadius: 38, sections: [
                                  for (final k in const ['validated', 'indicative', 'rejected', 'pending'])
                                    if (stats.count(k) > 0) PieChartSectionData(value: stats.count(k).toDouble(), color: qualityColor(k), radius: 22, showTitle: false),
                                ])),
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${stats.total}', style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w800, height: 1)),
                            Text('mesure(s)', style: TextStyle(color: cs.onSurfaceVariant)),
                            const SizedBox(height: 10),
                            for (final k in const ['validated', 'indicative', 'rejected', 'pending'])
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Row(children: [
                                  Container(width: 10, height: 10, decoration: BoxDecoration(color: qualityColor(k), shape: BoxShape.circle)),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(qualityLabel(k), style: const TextStyle(fontSize: 13))),
                                  Text('${stats.count(k)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                                ]),
                              ),
                          ]),
                        ),
                      ]),
                      const SizedBox(height: 16),
                      Row(children: [
                        Expanded(child: _kpi(context, Icons.hexagon_outlined, '${stats.cellsCovered}', 'Zones couvertes')),
                        const SizedBox(width: 10),
                        Expanded(child: _kpi(context, Icons.verified_rounded, '${(stats.validationRate * 100).round()} %', 'Taux de validation')),
                      ]),
                      if (stats.lastMeasurementAt != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text('Dernière mesure : ${fmtAgo(stats.lastMeasurementAt!)}', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13))),
                    ]),
            ),

            const SectionTitle('Ma cartographie'),
            const MyMappingCard(),

            const SectionTitle('Notation et historique'),
            _ScoreCard(board: board, season: season),

            const SectionTitle('Analyseur'),
            const _AnalystCard(),

            const SectionTitle('Enquêtes'),
            SoftCard(
              padding: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.assignment_rounded),
                title: const Text('Mes réponses aux enquêtes'),
                subtitle: const Text('Statuts, fiabilité et photos à ajouter'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyResponsesScreen())),
              ),
            ),
            const SectionTitle('Études et récompenses'),
            SoftCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                ListTile(
                  leading: const Icon(Icons.campaign_rounded),
                  title: const Text('Études, sondages, enquêtes commerciales'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const StudiesScreen())),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.card_giftcard_rounded),
                  title: const Text('Mes récompenses'),
                  trailing: context.watch<StudiesController>().claimCount > 0
                      ? Badge(label: Text('${context.watch<StudiesController>().claimCount}'))
                      : const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RewardsScreen())),
                ),
              ]),
            ),

            const SectionTitle('Invitations'),
            const _InviteCard(),

            const SectionTitle('Connexion et sécurité'),
            const _SecurityCard(),

            // ---------------------------------------------------------------- collecte hybride
            const SectionTitle('Collecte hybride'),
            SoftCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                SwitchListTile(
                  secondary: const Icon(Icons.auto_awesome_rounded),
                  title: const Text('Propositions de mesure', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('Recevoir des suggestions de zones à mesurer.'),
                  value: u.hybridCollectionEnabled,
                  onChanged: (v) async {
                    try {
                      await s.setHybrid(v);
                      if (v) proposals.startPolling();
                    } catch (e) {
                      if (context.mounted) showToast(context, errorMessage(e));
                    }
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.notifications_active_outlined),
                  title: const Text('Mes propositions'),
                  trailing: proposals.list.isEmpty ? const Icon(Icons.chevron_right_rounded) : Badge(label: Text('${proposals.list.length}')),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProposalsScreen())),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.event_available_rounded),
                  title: const Text('Mon planning'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ScheduleScreen())),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================ guide
class _GuideCard extends StatelessWidget {
  const _GuideCard({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(colors: [Color(0xFF0B1F2A), Color(0xFF0E7C7B)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          ),
          child: Row(children: [
            Container(width: 48, height: 48, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(15)), child: const Icon(Icons.menu_book_rounded, color: Colors.white)),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Guide complet', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17)),
                SizedBox(height: 2),
                Text('Comment ça marche : mesures, carte, routes, missions, points, vie privée.', style: TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.3)),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white),
          ]),
        ),
      ),
    );
  }
}

// ============================================================================ niveau + badges
class _LevelCard extends StatelessWidget {
  const _LevelCard({required this.board, this.week});
  final MyBoard board;
  final PeriodScore? week;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lv = board.level;
    final col = levelColor(lv.index);
    return SoftCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          ScoreRing(value: lv.progress, color: col, size: 78, stroke: 8, child: Text('${lv.index + 1}', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 24, color: col))),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(lv.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 19)),
              Text(lv.nextXp == null ? '${lv.xp} XP · niveau maximum' : '${lv.xp} / ${lv.nextXp} XP', style: TextStyle(color: cs.onSurfaceVariant)),
              const SizedBox(height: 6),
              ClipRRect(borderRadius: BorderRadius.circular(5), child: LinearProgressIndicator(minHeight: 8, value: lv.progress, color: col, backgroundColor: cs.outlineVariant.withValues(alpha: 0.35))),
            ]),
          ),
        ]),
        if (week != null && week!.rank > 0) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [
            StatusChip('Rang semaine : #${week!.rank}', cs.primary, icon: Icons.emoji_events_rounded),
            StatusChip('${week!.score.toStringAsFixed(0)} pts', const Color(0xFF22C55E)),
          ]),
        ],
        const SizedBox(height: 14),
        const Text('Badges', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Wrap(spacing: 10, runSpacing: 10, children: [for (final b in board.badges) _BadgeTile(b)]),
      ]),
    );
  }
}

class _BadgeTile extends StatelessWidget {
  const _BadgeTile(this.b);
  final BadgeInfo b;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final col = b.earned ? const [Color(0xFF94A3B8), Color(0xFF0E9F9A), Color(0xFF2563EB), Color(0xFF7C3AED), Color(0xFFF59E0B), Color(0xFFDB2777)][b.tier.clamp(0, 5)] : cs.outlineVariant;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          icon: Icon(badgeIcon(b.icon), color: col, size: 36),
          title: Text(b.label),
          content: Text('${b.description}\n\n${b.earned ? 'Obtenu${b.awardedAt != null ? ' le ${fmtDay(b.awardedAt!)}' : ''}.' : 'Pas encore obtenu.'}'),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
        ),
      ),
      child: SizedBox(
        width: 72,
        child: Column(children: [
          Stack(alignment: Alignment.center, children: [
            Container(width: 52, height: 52, decoration: BoxDecoration(color: col.withValues(alpha: b.earned ? 0.18 : 0.12), shape: BoxShape.circle, border: Border.all(color: col, width: 2)), child: Icon(badgeIcon(b.icon), color: col)),
            if (!b.earned) Positioned(right: 0, bottom: 0, child: Icon(Icons.lock_rounded, size: 16, color: cs.onSurfaceVariant)),
          ]),
          const SizedBox(height: 4),
          Text(b.label, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: b.earned ? null : cs.onSurfaceVariant)),
        ]),
      ),
    );
  }
}

// ============================================================================ notation
class _ScoreCard extends StatelessWidget {
  const _ScoreCard({required this.board, required this.season});
  final MyBoard? board;
  final PeriodScore? season;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final b = board;
    if (b == null) return const SoftCard(child: Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator())));
    const labels = {'week': 'Semaine', 'month': 'Mois', 'season': 'Saison (90 j)'};
    final comps = <(String, String, num)>[
      ('Mesures validées', 'v', 10), ('Mesures indicatives', 'i', 4), ('Mesures rejetées', 'r', -2),
      ('Zones couvertes', 'cells', 3), ("Jours d'activité", 'days', 5), ('Missions réussies', 'missions', 40),
      ('Mesures de mission', 'units', 4), ('Avis concordants', 'reviews', 2), ('Filleuls actifs', 'invites', 25),
    ];
    final sc = season;
    final hist = b.history;
    return SoftCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final k in const ['week', 'month', 'season'])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              SizedBox(width: 100, child: Text(labels[k]!, style: const TextStyle(fontWeight: FontWeight.w700))),
              Expanded(
                child: b.periods[k] == null
                    ? Text('Pas encore classé', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13))
                    : Text(b.periods[k]!.rank == 0 ? 'Rang masqué' : 'Rang #${b.periods[k]!.rank}', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
              ),
              if (b.periods[k] != null) Text('${b.periods[k]!.score.toStringAsFixed(0)} pts', style: const TextStyle(fontWeight: FontWeight.w800)),
            ]),
          ),
        if (sc != null) ...[
          const Divider(height: 24),
          const Text('Comment votre score de saison est calculé', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          for (final c in comps)
            if (sc.comp(c.$2) != 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  Expanded(child: Text(c.$1, style: const TextStyle(fontSize: 13))),
                  Text('${sc.comp(c.$2).round()} × ${c.$3}', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                  SizedBox(width: 64, child: Text('${(sc.comp(c.$2) * c.$3).round()} pts', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
                ]),
              ),
          const SizedBox(height: 8),
          Row(children: [
            const Expanded(child: Text('Total brut', style: TextStyle(fontWeight: FontWeight.w700))),
            Text('${sc.comp('raw').round()} pts', style: const TextStyle(fontWeight: FontWeight.w800)),
          ]),
          Row(children: [
            Expanded(child: Text('Fiabilité ${(sc.reliability * 100).round()} % → multiplicateur', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13))),
            Text('× ${(0.6 + 0.8 * sc.reliability).toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            const Expanded(child: Text('Score final', style: TextStyle(fontWeight: FontWeight.w800))),
            Text('${sc.score.toStringAsFixed(0)} pts', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: cs.primary)),
          ]),
        ],
        if (hist.length >= 2) ...[
          const Divider(height: 24),
          const Text('Évolution du score (saison)', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          SizedBox(
            height: 150,
            child: LineChart(LineChartData(
              gridData: FlGridData(drawVerticalLine: false, getDrawingHorizontalLine: (_) => FlLine(color: cs.outlineVariant.withValues(alpha: 0.4), strokeWidth: 1)),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 34, getTitlesWidget: (v, m) => Text(v.toStringAsFixed(0), style: const TextStyle(fontSize: 10)))),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 22,
                    interval: (hist.length / 3).ceilToDouble().clamp(1, 100),
                    getTitlesWidget: (v, m) {
                      final i = v.toInt();
                      return i < 0 || i >= hist.length ? const SizedBox.shrink() : Text(fmtDay(hist[i].date), style: const TextStyle(fontSize: 10));
                    },
                  ),
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: [for (var i = 0; i < hist.length; i++) FlSpot(i.toDouble(), hist[i].score)],
                  isCurved: true,
                  barWidth: 3,
                  color: cs.primary,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(show: true, color: cs.primary.withValues(alpha: 0.12)),
                ),
              ],
            )),
          ),
        ],
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            icon: const Icon(Icons.leaderboard_rounded),
            label: const Text('Voir le classement'),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LeaderboardScreen())),
          ),
        ),
      ]),
    );
  }
}

// ============================================================================ analyseur
class _AnalystCard extends StatelessWidget {
  const _AnalystCard();
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final acc = context.watch<AccountController>();
    final rev = context.watch<ReviewsController>();
    final a = acc.analyst;
    if (a == null) return const SoftCard(child: Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator())));
    final canToggle = a.enabled || a.eligible;
    return SoftCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.hearing_rounded, color: Color(0xFF7C3AED)),
          const SizedBox(width: 10),
          const Expanded(child: Text("Donner mon avis sur les mesures proches", style: TextStyle(fontWeight: FontWeight.w800))),
          Switch(
            value: a.enabled,
            onChanged: !canToggle
                ? null
                : (v) async {
                    try {
                      await acc.setAnalyst(v);
                    } catch (e) {
                      if (context.mounted) showToast(context, errorMessage(e));
                    }
                  },
          ),
        ]),
        Text("Quand quelqu'un mesure près de vous, vous confirmez ou corrigez le niveau (10 min pour répondre).", style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5, height: 1.3)),
        if (a.suspended) ...[
          const SizedBox(height: 8),
          StatusChip('Suspendu jusqu\'au ${fmtDay(a.suspendedUntil!)}', const Color(0xFFEF4444), icon: Icons.pause_circle_rounded),
        ],
        const SizedBox(height: 10),
        const Text('Conditions', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        for (final c in a.criteria)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Icon(c.ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, size: 20, color: c.ok ? const Color(0xFF22C55E) : cs.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(child: Text(c.label, style: const TextStyle(fontSize: 13))),
              Text('${c.value} / ${c.reverse ? '≤' : '≥'} ${c.required}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.ok ? const Color(0xFF22C55E) : cs.onSurfaceVariant)),
            ]),
          ),
        if (a.votes > 0) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            StatusChip('${a.votes} avis (60 j)', cs.primary),
            StatusChip('Concordance ${(a.agreement * 100).round()} %', const Color(0xFF22C55E)),
          ]),
        ],
        if (a.enabled) ...[
          const SizedBox(height: 10),
          FilledButton.icon(
            icon: Badge(isLabelVisible: rev.pending.isNotEmpty, label: Text('${rev.pending.length}'), child: const Icon(Icons.rate_review_rounded)),
            label: const Text('Mes avis'),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReviewsScreen())),
          ),
        ],
      ]),
    );
  }
}

// ============================================================================ invitations
class _InviteCard extends StatelessWidget {
  const _InviteCard();
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final acc = context.watch<AccountController>();
    return SoftCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text("Invitez des amis : vous gagnez 25 points quand ils deviennent actifs (3 mesures validées).", style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5, height: 1.3)),
        const SizedBox(height: 8),
        if (acc.invitations.isEmpty) Text('Aucun code pour le moment.', style: TextStyle(color: cs.onSurfaceVariant)),
        for (final i in acc.invitations)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.card_giftcard_rounded, color: i.active ? cs.primary : cs.onSurfaceVariant),
            title: SelectableText(i.code, style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.4, color: i.active ? null : cs.onSurfaceVariant)),
            subtitle: Text('${i.uses}/${i.maxUses} utilisation(s)${i.expiresAt != null ? ' · jusqu\'au ${fmtDay(i.expiresAt!)}' : ''}${i.active ? '' : ' · inactif'}', style: const TextStyle(fontSize: 12)),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(icon: const Icon(Icons.copy_rounded), onPressed: () { Clipboard.setData(ClipboardData(text: i.code)); showToast(context, 'Code copié'); }),
              if (i.active)
                IconButton(
                  icon: const Icon(Icons.block_rounded),
                  onPressed: () async {
                    try {
                      await acc.revoke(i.id);
                    } catch (e) {
                      if (context.mounted) showToast(context, errorMessage(e));
                    }
                  },
                ),
            ]),
          ),
        const SizedBox(height: 6),
        OutlinedButton.icon(
          icon: const Icon(Icons.add_rounded),
          label: const Text('Créer un code'),
          onPressed: () async {
            try {
              await acc.newInvitation();
            } catch (e) {
              if (context.mounted) showToast(context, errorMessage(e));
            }
          },
        ),
      ]),
    );
  }
}

// ============================================================================ sécurité
class _SecurityCard extends StatelessWidget {
  const _SecurityCard();

  Future<void> _changePassword(BuildContext context) async {
    final cur = TextEditingController(), nw = TextEditingController();
    final key = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Changer le mot de passe'),
        content: Form(
          key: key,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(controller: cur, obscureText: true, decoration: const InputDecoration(labelText: 'Mot de passe actuel'), validator: (v) => (v == null || v.isEmpty) ? 'Requis' : null),
            const SizedBox(height: 10),
            TextFormField(controller: nw, obscureText: true, decoration: const InputDecoration(labelText: 'Nouveau mot de passe'), validator: (v) => passwordPolicyOk(v ?? '') ? null : '10 caractères min., lettres + chiffres, 3 types (ou 14 car.)'),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(100, 44)), onPressed: () { if (key.currentState!.validate()) Navigator.pop(ctx, true); }, child: const Text('Changer')),
        ],
      ),
    );
    final c = cur.text, n = nw.text;
    cur.dispose();
    nw.dispose();
    if (ok != true || !context.mounted) return;
    try {
      await context.read<ApiClient>().changePassword(c, n);
      if (!context.mounted) return;
      showToast(context, 'Mot de passe modifié. Reconnectez-vous.');
      await context.read<SessionController>().signOut();
    } catch (e) {
      if (context.mounted) showToast(context, errorMessage(e));
    }
  }

  Future<void> _newCodes(BuildContext context) async {
    final pw = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nouveaux codes de récupération'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Les anciens codes seront annulés. Confirmez avec votre mot de passe.', style: TextStyle(fontSize: 13)),
          const SizedBox(height: 10),
          TextField(controller: pw, obscureText: true, decoration: const InputDecoration(labelText: 'Mot de passe')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(100, 44)), onPressed: () => Navigator.pop(ctx, true), child: const Text('Générer')),
        ],
      ),
    );
    final password = pw.text;
    pw.dispose();
    if (ok != true || !context.mounted) return;
    try {
      final codes = await context.read<ApiClient>().regenerateRecoveryCodes(password);
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Vos nouveaux codes'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Conservez-les en lieu sûr : ils ne seront plus affichés.', style: TextStyle(fontSize: 13)),
            const SizedBox(height: 10),
            SelectableText(codes.join('\n'), style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700, fontSize: 16, height: 1.6)),
          ]),
          actions: [
            TextButton(onPressed: () { Clipboard.setData(ClipboardData(text: codes.join('\n'))); showToast(ctx, 'Codes copiés'); }, child: const Text('Copier')),
            FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(100, 44)), onPressed: () => Navigator.pop(ctx), child: const Text("J'ai noté")),
          ],
        ),
      );
    } catch (e) {
      if (context.mounted) showToast(context, errorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = context.watch<AccountController>().connections;
    return SoftCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (c == null)
          const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
        else ...[
          if (c.lastLoginAt != null) Text('Dernière connexion : ${fmtDateTime(c.lastLoginAt!)}', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6, children: [
            StatusChip('${c.sessions.length} session(s) ouverte(s)', cs.primary, icon: Icons.devices_rounded),
            StatusChip('${c.devices.length} appareil(s)', cs.onSurfaceVariant, icon: Icons.smartphone_rounded),
          ]),
          if (c.devices.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final d in c.devices) Text('• ${d.name} · Android ${d.android}${d.lastSeen != null ? ' · vu ${fmtAgo(d.lastSeen!)}' : ''}', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
          ],
          if (c.events.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text('Connexions récentes', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            for (final e in c.events.take(5))
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Row(children: [
                  Icon(e.success ? Icons.check_circle_rounded : Icons.error_rounded, size: 15, color: e.success ? const Color(0xFF22C55E) : const Color(0xFFEF4444)),
                  const SizedBox(width: 6),
                  Expanded(child: Text('${e.at != null ? fmtDateTime(e.at!) : '—'} · ${e.platform}${e.success ? '' : ' · échec'}', style: const TextStyle(fontSize: 12.5))),
                ]),
              ),
          ],
        ],
        const Divider(height: 24),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(icon: const Icon(Icons.password_rounded), label: const Text('Mot de passe'), style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)), onPressed: () => _changePassword(context)),
          OutlinedButton.icon(icon: const Icon(Icons.key_rounded), label: const Text('Codes de récupération'), style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)), onPressed: () => _newCodes(context)),
          OutlinedButton.icon(
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Déconnecter partout'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () async {
              try {
                await context.read<ApiClient>().logoutAll();
                if (context.mounted) await context.read<SessionController>().signOut();
              } catch (e) {
                if (context.mounted) showToast(context, errorMessage(e));
              }
            },
          ),
        ]),
      ]),
    );
  }
}

// ============================================================================ modifier le profil
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key, required this.profile});
  final AccountProfile profile;
  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.profile.displayName);
  late final _first = TextEditingController(text: widget.profile.firstName ?? '');
  late final _last = TextEditingController(text: widget.profile.lastName ?? '');
  late final _phone = TextEditingController(text: widget.profile.phone ?? '');
  late final _city = TextEditingController(text: widget.profile.city ?? '');
  late final _district = TextEditingController(text: widget.profile.district ?? '');
  late int? _year = widget.profile.birthYear;
  late bool _show = widget.profile.showInLeaderboard;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _first, _last, _phone, _city, _district]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _n(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await context.read<AccountController>().saveProfile({
        'display_name': _name.text.trim(),
        'first_name': _n(_first),
        'last_name': _n(_last),
        'phone': _n(_phone),
        'city': _n(_city),
        'district': _n(_district),
        if (_year != null) 'birth_year': _year,
        'show_in_leaderboard': _show,
      });
      if (mounted) {
        showToast(context, 'Profil enregistré.');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) showToast(context, errorMessage(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Modifier le profil')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text('Seul votre pseudo est visible des autres. Le reste reste privé.', style: TextStyle(color: cs.onSurfaceVariant)),
        const SizedBox(height: 16),
        Form(
          key: _form,
          child: Column(children: [
            TextFormField(controller: _name, maxLength: 24, decoration: fieldDecoration(context, 'Pseudo public', Icons.badge_outlined), validator: (v) => RegExp(r"^[\w .'-]{3,24}$").hasMatch((v ?? '').trim()) ? null : '3 à 24 caractères'),
            Row(children: [
              Expanded(child: TextFormField(controller: _first, decoration: fieldDecoration(context, 'Prénom', Icons.person_outline_rounded))),
              const SizedBox(width: 10),
              Expanded(child: TextFormField(controller: _last, decoration: fieldDecoration(context, 'Nom', Icons.person_outline_rounded))),
            ]),
            const SizedBox(height: 14),
            TextFormField(controller: _phone, keyboardType: TextInputType.phone, decoration: fieldDecoration(context, 'Téléphone', Icons.phone_outlined), validator: (v) => (v == null || v.trim().isEmpty || RegExp(r'^\+?[0-9 ()-]{6,20}$').hasMatch(v.trim())) ? null : 'Numéro invalide'),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: TextFormField(controller: _city, decoration: fieldDecoration(context, 'Ville', Icons.location_city_rounded))),
              const SizedBox(width: 10),
              Expanded(child: TextFormField(controller: _district, decoration: fieldDecoration(context, 'Quartier', Icons.holiday_village_outlined))),
            ]),
            const SizedBox(height: 14),
            DropdownButtonFormField<int>(
              initialValue: _year,
              decoration: fieldDecoration(context, 'Année de naissance', Icons.cake_outlined),
              items: [for (var y = DateTime.now().year - 13; y >= 1930; y--) DropdownMenuItem(value: y, child: Text('$y'))],
              onChanged: (v) => setState(() => _year = v),
            ),
            const SizedBox(height: 8),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Apparaître dans le classement'), subtitle: const Text('Désactivé : vous gagnez quand même points et niveaux.'), value: _show, onChanged: (v) => setState(() => _show = v)),
            const SizedBox(height: 16),
            FilledButton(onPressed: _busy ? null : _save, child: _busy ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : const Text('Enregistrer')),
          ]),
        ),
      ]),
    );
  }
}