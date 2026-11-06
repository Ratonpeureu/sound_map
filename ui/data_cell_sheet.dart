import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/api_survey.dart';
import '../core/models_survey.dart';
import '../core/util.dart';
import 'data_map_screen.dart' show shortValue;
import 'widgets.dart';

class DataCellSheet extends StatefulWidget {
  const DataCellSheet({super.key, required this.feature, required this.map, required this.domain, required this.days, required this.includeIndicative});
  final DataFeature feature;
  final DataMap map;
  final DataDomain domain;
  final int days;
  final bool includeIndicative;
  @override
  State<DataCellSheet> createState() => _DataCellSheetState();
}

class _DataCellSheetState extends State<DataCellSheet> {
  late final Future<DataCellDetail> _f =
      context.read<ApiClient>().dataCell(widget.feature.h3, widget.domain.key, days: widget.days, includeIndicative: widget.includeIndicative);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final f = widget.feature, m = widget.map;
    final col = widget.domain.color;
    return SafeArea(
      child: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), shrinkWrap: true, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m.label, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
              const SizedBox(height: 4),
              Text(f.label, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: col, height: 1.1)),
            ]),
          ),
          Column(children: [
            ScoreRing(value: f.confidence, color: cs.primary, size: 66, stroke: 7, child: Text('${(f.confidence * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13))),
            const SizedBox(height: 3),
            Text('Confiance', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11)),
          ]),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          StatusChip('${f.n} réponse(s)', col, icon: Icons.forum_rounded),
          StatusChip('${f.contributors} contributeur(s)', col, icon: Icons.people_alt_rounded),
          if (f.provedShare > 0) StatusChip('${(f.provedShare * 100).round()} % avec photo', const Color(0xFF16A34A), icon: Icons.photo_camera_rounded),
          if (f.lastAt != null) StatusChip(fmtAgo(f.lastAt!), cs.onSurfaceVariant, icon: Icons.schedule_rounded),
          if (f.reference != null)
            StatusChip(
              'Référence ${shortValue(f.reference!, m.unit)}${f.deviation == null ? '' : ' · écart ${f.deviation! >= 0 ? '+' : ''}${f.deviation!.toStringAsFixed(1)}'}',
              const Color(0xFF7C3AED),
              icon: Icons.fact_check_rounded,
            ),
        ]),
        if (f.categories.isNotEmpty) ...[
          const SectionTitle('Répartition'),
          CategoryBar(shares: f.categories, order: widget.domain.indicator(m.key)?.catOrder ?? const []),
        ],
        if (m.kind != 'derived') ...[
          const SectionTitle('Évolution mensuelle'),
          SoftCard(child: TrendCard(indicator: m.key, h3: f.h3, metric: m.metric, color: col)),
        ],
        const SectionTitle('Tous les indicateurs de la zone'),
        FutureBuilder<DataCellDetail>(
          future: _f,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
            }
            if (snap.hasError) return Text(errorMessage(snap.error!), style: TextStyle(color: cs.error));
            final d = snap.data!;
            if (d.items.isEmpty) return Text('Pas encore de données pour cette zone.', style: TextStyle(color: cs.onSurfaceVariant));
            return Column(children: [
              for (final it in d.items) _ItemTile(item: it, h3: f.h3, color: col, order: widget.domain.indicator(it.indicator)?.catOrder ?? const []),
              Padding(padding: const EdgeInsets.only(top: 8), child: Text(d.caveat, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11))),
            ]);
          },
        ),
      ]),
    );
  }
}

// ------------------------------------------------------------------ barre de répartition
class CategoryBar extends StatelessWidget {
  const CategoryBar({super.key, required this.shares, required this.order});
  final List<DataCategoryShare> shares;
  final List<String> order;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final total = shares.fold<double>(0, (a, b) => a + b.share);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          height: 16,
          child: Row(children: [
            for (final s in shares)
              Expanded(flex: (s.share * 10).round().clamp(1, 10000), child: ColoredBox(color: catColor(s.code, order), child: const SizedBox.expand())),
            if (total < 100) Expanded(flex: ((100 - total) * 10).round().clamp(1, 10000), child: ColoredBox(color: cs.outlineVariant, child: const SizedBox.expand())),
          ]),
        ),
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 12, runSpacing: 4, children: [
        for (final s in shares)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: catColor(s.code, order), shape: BoxShape.circle)),
            const SizedBox(width: 5),
            Text('${s.label} · ${s.share.toStringAsFixed(0)} %', style: const TextStyle(fontSize: 12)),
          ]),
      ]),
    ]);
  }
}

// ------------------------------------------------------------------ ligne d'indicateur
class _ItemTile extends StatefulWidget {
  const _ItemTile({required this.item, required this.h3, required this.color, required this.order});
  final DataCellItem item;
  final String h3;
  final Color color;
  final List<String> order;
  @override
  State<_ItemTile> createState() => _ItemTileState();
}

class _ItemTileState extends State<_ItemTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final it = widget.item;
    if (it.hidden) {
      return SoftCard(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Icon(Icons.lock_outline_rounded, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(child: Text('${it.label} : masqué (pas assez de contributeurs, confidentialité)', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5))),
        ]),
      );
    }
    final v = it.value ?? 0;
    Widget? visual;
    if (it.categories.isNotEmpty) {
      visual = CategoryBar(shares: it.categories, order: widget.order);
    } else if (it.kind == 'share') {
      visual = ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(minHeight: 9, value: (v / 100).clamp(0.0, 1.0), color: widget.color, backgroundColor: cs.outlineVariant.withValues(alpha: 0.35)),
      );
    } else if (it.kind == 'scale') {
      visual = Row(children: [
        for (var i = 1; i <= 5; i++)
          Icon(i <= v.round() ? Icons.star_rounded : Icons.star_border_rounded, color: const Color(0xFFF59E0B), size: 20),
      ]);
    }
    final canTrend = it.kind != 'derived';
    return SoftCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(it.label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5))),
          Text(it.labelValue ?? '', style: TextStyle(fontWeight: FontWeight.w800, color: widget.color)),
        ]),
        if (visual != null) Padding(padding: const EdgeInsets.only(top: 8), child: visual),
        const SizedBox(height: 6),
        Row(children: [
          Text('${it.n ?? 0} rép. · ${it.contributors ?? 0} contrib. · confiance ${((it.confidence ?? 0) * 100).round()} %', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11)),
          const Spacer(),
          if (canTrend)
            TextButton.icon(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: () => setState(() => _open = !_open),
              icon: Icon(_open ? Icons.expand_less_rounded : Icons.show_chart_rounded, size: 18),
              label: Text(_open ? 'Masquer' : 'Évolution'),
            ),
        ]),
        if (_open) TrendCard(indicator: it.indicator, h3: widget.h3, metric: it.metric, color: widget.color),
      ]),
    );
  }
}

// ------------------------------------------------------------------ courbe d'évolution
class TrendCard extends StatefulWidget {
  const TrendCard({super.key, required this.indicator, required this.h3, required this.color, this.metric});
  final String indicator, h3;
  final String? metric;
  final Color color;
  @override
  State<TrendCard> createState() => _TrendCardState();
}

class _TrendCardState extends State<TrendCard> {
  late final Future<DataTrend> _f = context.read<ApiClient>().dataTrend(widget.indicator, h3: widget.h3, metric: widget.metric);

  String _m(String iso) => iso.length >= 7 ? '${iso.substring(5, 7)}/${iso.substring(2, 4)}' : iso;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FutureBuilder<DataTrend>(
      future: _f,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)));
        }
        if (snap.hasError) return Text(errorMessage(snap.error!), style: TextStyle(color: cs.error, fontSize: 12));
        final t = snap.data!;
        final pts = t.points;
        if (pts.isEmpty) {
          return Text('Pas assez de contributeurs par mois (min ${t.minContributors}) pour tracer une courbe.', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12));
        }
        if (pts.length == 1) {
          return Text('Un seul mois disponible (${_m(pts.first.month)}) : ${shortValue(pts.first.value, t.unit)}.', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12));
        }
        final vals = pts.map((p) => p.value);
        var lo = vals.reduce((a, b) => a < b ? a : b), hi = vals.reduce((a, b) => a > b ? a : b);
        final pad = (hi - lo) * 0.2 == 0 ? 1.0 : (hi - lo) * 0.2;
        lo -= pad;
        hi += pad;
        final step = (pts.length / 5).ceil().clamp(1, 100);
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            height: 170,
            child: LineChart(LineChartData(
              minY: lo,
              maxY: hi,
              gridData: FlGridData(drawVerticalLine: false, getDrawingHorizontalLine: (_) => FlLine(color: cs.outlineVariant.withValues(alpha: 0.4), strokeWidth: 1)),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: true, reservedSize: 40, getTitlesWidget: (v, m) => Text(shortValue(v, t.unit), style: const TextStyle(fontSize: 10))),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 22,
                    interval: 1,
                    getTitlesWidget: (v, m) {
                      final i = v.toInt();
                      if (i < 0 || i >= pts.length || v != i.toDouble() || i % step != 0) return const SizedBox.shrink();
                      return Padding(padding: const EdgeInsets.only(top: 5), child: Text(_m(pts[i].month), style: const TextStyle(fontSize: 10)));
                    },
                  ),
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: [for (var i = 0; i < pts.length; i++) FlSpot(i.toDouble(), pts[i].value)],
                  isCurved: true,
                  barWidth: 3,
                  color: widget.color,
                  dotData: const FlDotData(show: true),
                  belowBarData: BarAreaData(show: true, color: widget.color.withValues(alpha: 0.15)),
                ),
              ],
            )),
          ),
          const SizedBox(height: 4),
          Text('${pts.length} mois · ${pts.fold<int>(0, (a, p) => a + p.n)} réponses', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11)),
        ]);
      },
    );
  }
}