import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:provider/provider.dart';

import '../core/models_ext.dart';
import '../core/util.dart';
import '../state/missions_controller.dart';
import '../state/quota_controller.dart';
import 'proposals_screen.dart';
import 'widgets.dart';
import '../core/models_roads.dart';

class MissionsScreen extends StatefulWidget {
  const MissionsScreen({super.key});
  @override
  State<MissionsScreen> createState() => _MissionsScreenState();
}

class _MissionsScreenState extends State<MissionsScreen> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<QuotaController>().refresh();
      context.read<MissionsController>().refresh();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    await context.read<QuotaController>().refresh();
    if (mounted) await context.read<MissionsController>().refresh();
  }

  Future<void> _respond(Mission m, bool accept) async {
    try {
      await context.read<MissionsController>().respond(m.id, accept);
    } catch (e) {
      if (mounted) showToast(context, errorMessage(e));
    }
  }

  String _left(DateTime t) {
    final d = t.difference(DateTime.now());
    if (d.isNegative) return 'expirée';
    if (d.inHours >= 24) return '${d.inDays} j ${d.inHours % 24} h';
    return '${d.inHours} h ${(d.inMinutes % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final q = context.watch<QuotaController>().state;
    final mc = context.watch<MissionsController>();
    final offered = mc.list.where((m) => m.status == 'offered').toList();
    final running = mc.list.where((m) => m.status == 'accepted').toList();
    final finished = mc.list.where((m) => !m.isActive).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Missions et solde')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
          _quotaCard(cs, q),
          if (offered.isNotEmpty) ...[
            SectionTitle('À accepter (${offered.length})'),
            for (final m in offered) _card(cs, m),
          ],
          if (running.isNotEmpty) ...[
            SectionTitle('En cours (${running.length})'),
            for (final m in running) _card(cs, m),
          ],
          if (offered.isEmpty && running.isEmpty) ...[
            const SectionTitle('Missions'),
            SoftCard(
              child: Text(
                mc.loading
                    ? 'Recherche de zones à couvrir…'
                    : 'Aucune mission pour le moment. Elles sont générées selon les zones en manque de mesures près de vous, votre fiabilité et votre historique.',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ),
          ],
          if (finished.isNotEmpty) ...[
            const SectionTitle('Récentes'),
            for (final m in finished) _card(cs, m),
          ],
          const SectionTitle('Autres'),
          SoftCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.notifications_active_outlined),
              title: const Text('Propositions de mesure'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProposalsScreen())),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _quotaCard(ColorScheme cs, QuotaState? q) {
    if (q == null) {
      return const SoftCard(child: Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())));
    }
    final ratio = q.cap <= 0 ? 0.0 : (q.balance / q.cap).clamp(0.0, 1.0).toDouble();
    final low = q.balance < 1;
    final col = low ? const Color(0xFFEF4444) : cs.primary;
    return SoftCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          ScoreRing(
            value: ratio,
            color: col,
            size: 92,
            stroke: 10,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(q.balance.toStringAsFixed(1), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22, color: col)),
              Text('crédits', style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
            ]),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${q.measurementsLeft} prélèvement(s) disponible(s)',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 4),
              Text(
                'Recharge actuelle : +${q.ratePerHour.toStringAsFixed(2)} crédit/h · objectif du jour ${q.dailyTarget.toStringAsFixed(1)}',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [
          StatusChip('Fiabilité ${(q.reliability * 100).round()} %', const Color(0xFF22C55E), icon: Icons.verified_rounded),
          StatusChip('Utilisation ${(q.utilization * 100).round()} %', cs.primary, icon: Icons.speed_rounded),
          StatusChip('Missions ${(q.missionRate * 100).round()} %', const Color(0xFFF59E0B), icon: Icons.flag_rounded),
        ]),
        const SizedBox(height: 12),
        Text(
          'Aujourd\'hui : +${q.todayCredited.toStringAsFixed(1)} reçus · −${q.todayUsed.toStringAsFixed(1)} utilisés'
          '${q.todayDecayed > 0.05 ? ' · −${q.todayDecayed.toStringAsFixed(1)} perdus' : ''}',
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
        ),
        const SizedBox(height: 6),
        Text(
          'Le solde se cumule mais diminue si vous ne l\'utilisez pas (conservation ${(q.retentionPerDay * 100).round()} % par jour). '
          'Sans mesure, il serait de ${q.projected24h.toStringAsFixed(1)} dans 24 h. '
          'Mesurer dans une zone en manque coûte moins cher ; refaire une mesure au même endroit coûte plus et impose un délai.',
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12, height: 1.35),
        ),
      ]),
    );
  }

  Widget _card(ColorScheme cs, Mission m) {
    final offered = m.status == 'offered';
    final running = m.status == 'accepted';
    final col = running
        ? cs.primary
        : offered
            ? const Color(0xFFF59E0B)
            : m.status == 'completed'
                ? const Color(0xFF22C55E)
                : cs.onSurfaceVariant;
    final label = switch (m.status) {
      'offered' => 'À accepter',
      'accepted' => 'En cours',
      'completed' => 'Terminée',
      'failed' => 'Échouée',
      'declined' => 'Refusée',
      _ => 'Expirée',
    };
    final progress = m.requiredCount == 0 ? 0.0 : (m.confirmedCount / m.requiredCount).clamp(0.0, 1.0).toDouble();
    final pending = (m.doneCount - m.confirmedCount).clamp(0, 999);

    return SoftCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.flag_rounded, color: col),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              m.isRoad
                  ? (m.roadName ?? roadClassLabel(m.roadClass))
                  : '${m.requiredCount} mesure(s) · à ${m.distanceKm.toStringAsFixed(1)} km',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
          StatusChip(label, col),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 6, children: [
          StatusChip('+${m.rewardCredits.toStringAsFixed(1)} crédit(s)', const Color(0xFF22C55E), icon: Icons.bolt_rounded),
          StatusChip('Priorité ${m.priority.round()}/100', cs.primary),
          StatusChip('Zone ${(m.radiusM / 1000).toStringAsFixed(1)} km', cs.onSurfaceVariant),
        ]),

        if (m.isRoad) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6, children: [
            StatusChip(roadClassLabel(m.roadClass), cs.primary, icon: Icons.add_road_rounded),
            if (m.targetDayPart != null) StatusChip('Plage : ${dayPartLabel(m.targetDayPart!)}', const Color(0xFF7C3AED), icon: Icons.schedule_rounded),
            StatusChip('à ${m.distanceKm.toStringAsFixed(1)} km', cs.onSurfaceVariant),
          ]),
          if (m.windowEndAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                  'Mesurez à moins de ${m.radiusM.round()} m du point cible, avant ${fmtTime(m.windowEndAt!)}. Pas besoin d\'être pile dessus.',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
            ),
        ],
        if (running || m.status == 'completed') ...[
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(minHeight: 8, value: progress),
          ),
          const SizedBox(height: 4),
          Text(
            '${m.confirmedCount}/${m.requiredCount} validée(s)${pending > 0 ? ' · $pending en évaluation' : ''}',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
          ),
        ],
        const SizedBox(height: 8),
        if (offered)
          Text('Expire dans ${_left(m.offerExpiresAt)}', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12))
        else if (running && m.deadlineAt != null)
          Text('À terminer dans ${_left(m.deadlineAt!)}', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),

        if (m.isActive) ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.map_outlined),
                label: const Text('Voir'),
                onPressed: () => Navigator.pop(context, MissionFocus(m)),
              ),
            ),
            if (m.isRoad) ...[
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.directions_rounded),
                  label: const Text('Itinéraire'),
                  onPressed: () => Navigator.pop(context, MissionFocus(m, route: true)),
                ),
              ),
            ],
          ]),
        ],

        if (offered) ...[
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => _respond(m, false), child: const Text('Refuser'))),
            const SizedBox(width: 10),
            Expanded(child: FilledButton(onPressed: () => _respond(m, true), child: const Text('Accepter'))),
          ]),
        ],
      ]),
    );
  }
}