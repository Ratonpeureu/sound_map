import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../core/util.dart';
import '../state/recorder_controller.dart';
import '../state/view_models.dart';
import 'widgets.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _scroll = ScrollController();
  int _seen = -1;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) {
        context.read<HistoryViewModel>().loadMore();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<HistoryViewModel>().reload());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<HistoryViewModel>();
    final rec = context.watch<RecorderController>();
    final cs = Theme.of(context).colorScheme;

    if (rec.completedVersion != _seen) {
      _seen = rec.completedVersion;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.read<HistoryViewModel>().reload();
      });
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Mes mesures')),
      body: RefreshIndicator(
        onRefresh: () async {
          await context.read<RecorderController>().flushPending();
          await vm.reload();
        },
        child: ListView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
          children: [
            if (rec.pendingCount > 0)
              SoftCard(
                margin: const EdgeInsets.only(bottom: 12),
                child: Row(children: [
                  const Icon(Icons.cloud_upload_outlined, color: Color(0xFFF59E0B)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Text('${rec.pendingCount} mesure(s) en attente d\'envoi',
                          style: const TextStyle(fontWeight: FontWeight.w700))),
                  TextButton(
                      onPressed: () => context.read<RecorderController>().flushPending(),
                      child: const Text('Envoyer')),
                ]),
              ),
            if (vm.stats != null) _SummaryCard(vm.stats!),
            const SectionTitle('Historique'),
            if (vm.error != null)
              SoftCard(child: Text(apiErrorLabel(vm.error!), style: TextStyle(color: cs.error))),
            if (vm.items.isEmpty && !vm.loading && vm.error == null)
              SoftCard(
                padding: const EdgeInsets.all(28),
                child: Column(children: [
                  Icon(Icons.graphic_eq_rounded, size: 40, color: cs.primary),
                  const SizedBox(height: 10),
                  const Text('Aucune mesure pour le moment', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text('Appuyez sur « Mesurer » pour contribuer à la carte.',
                      textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
                ]),
              ),
            for (final it in vm.items) _MeasurementTile(it),
            if (vm.loading)
              const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard(this.s);
  final Contributions s;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SoftCard(
      child: Row(children: [
        ScoreRing(
          value: s.validationRate,
          color: qualityColor('validated'),
          size: 84,
          stroke: 9,
          child: Text('${(s.validationRate * 100).round()}%',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Taux de validation', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text('${s.total} mesure(s) · ${s.cellsCovered} zone(s)',
                style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final k in const ['validated', 'indicative', 'rejected', 'pending'])
                if (s.count(k) > 0) StatusChip('${qualityLabel(k)} ${s.count(k)}', qualityColor(k)),
            ]),
          ]),
        ),
      ]),
    );
  }
}

class _MeasurementTile extends StatelessWidget {
  const _MeasurementTile(this.it);
  final HistoryItem it;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final col = noiseColor(it.laeq);
    final tag = NoiseTagX.parse(it.noiseContext);
    return SoftCard(
      margin: const EdgeInsets.only(bottom: 10),
      onTap: () => showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) => _DetailSheet(it)),
      child: Row(children: [
        Container(
          width: 62,
          height: 62,
          decoration: BoxDecoration(color: col.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(18)),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(it.laeq.toStringAsFixed(0),
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22, color: col, height: 1)),
            Text('dB(A)', style: TextStyle(fontSize: 10, color: col, fontWeight: FontWeight.w700)),
          ]),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(fmtDateTime(it.measuredAt), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text('${dayPartLabel(it.dayPart)} · Lmax ${it.lmax.toStringAsFixed(0)}',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 4, children: [
              StatusChip(qualityLabel(it.qualityStatus), qualityColor(it.qualityStatus)),
              if (tag != null) Icon(tag.icon, size: 18, color: cs.primary),
            ]),
          ]),
        ),
        if (it.qualityScore != null)
          ScoreRing(
            value: it.qualityScore!,
            color: qualityColor(it.qualityStatus),
            size: 46,
            stroke: 5,
            child: Text('${(it.qualityScore! * 100).round()}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
          ),
      ]),
    );
  }
}

class _DetailSheet extends StatelessWidget {
  const _DetailSheet(this.it);
  final HistoryItem it;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final col = noiseColor(it.laeq);
    return SafeArea(
      child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [
        Row(children: [
          Text(it.laeq.toStringAsFixed(1), style: TextStyle(fontSize: 46, fontWeight: FontWeight.w800, color: col)),
          const SizedBox(width: 6),
          const Text('dB(A)', style: TextStyle(fontWeight: FontWeight.w700)),
          const Spacer(),
          StatusChip(qualityLabel(it.qualityStatus), qualityColor(it.qualityStatus)),
        ]),
        const SizedBox(height: 4),
        Text(fmtDateTime(it.measuredAt), style: TextStyle(color: cs.onSurfaceVariant)),
        const SizedBox(height: 16),
        if (it.qualityScore != null)
          SoftCard(
            child: Row(children: [
              ScoreRing(
                value: it.qualityScore!,
                color: qualityColor(it.qualityStatus),
                size: 70,
                stroke: 8,
                child: Text('${(it.qualityScore! * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 16),
              const Expanded(
                  child: Text('Score de qualité : fiabilité de cette mesure (GPS, durée, saturation, mouvement, calibration, cohérence avec les zones voisines).',
                      style: TextStyle(fontSize: 13))),
            ]),
          ),
        const SectionTitle('Détails'),
        _row('Lmax', '${it.lmax.toStringAsFixed(1)} dB(A)'),
        _row('Plage horaire', dayPartLabel(it.dayPart)),
        _row('Téléphone', it.calibrationStatus == 'calibrated' ? 'Calibré' : 'Non calibré'),
        _row('Position', it.locationAnonymized ? 'Arrondie au centre de la zone' : 'Précise (arrondie après la période de rétention)'),
        if (NoiseTagX.parse(it.noiseContext) != null)
          Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Align(alignment: Alignment.centerLeft, child: NoiseTagChip(NoiseTagX.parse(it.noiseContext)!))),
        if (it.reasons.isNotEmpty) ...[
          const SectionTitle('Pourquoi ce statut ?'),
          for (final code in it.reasons)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('• ${reasonLabel(code)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                if (reasonTip(code) != null)
                  Padding(
                      padding: const EdgeInsets.only(left: 12, top: 2),
                      child: Text(reasonTip(code)!, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13))),
              ]),
            ),
        ],
      ]),
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 110, child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(child: Text(v)),
        ]),
      );
}