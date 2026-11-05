import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/models.dart';
import '../core/util.dart';
import 'widgets.dart';

class CellSheet extends StatefulWidget {
  const CellSheet({super.key, required this.cell, required this.filters, this.store});
  final NoiseCell cell;
  final MapFilters filters;
  final dynamic store; // Optionnel

  @override
  State<CellSheet> createState() => _CellSheetState();
}

class _CellSheetState extends State<CellSheet> {
  late final Future<CellDetail> _f = context.read<ApiClient>().cellDetail(widget.cell.h3, widget.filters);
  late final Future<TrafficFlow?> _traffic = context.read<ApiClient>().cellTraffic(widget.cell.h3);

  @override
  Widget build(BuildContext context) {
    final c = widget.cell;
    final cs = Theme.of(context).colorScheme;
    final col = noiseColor(c.laeq);
    return SafeArea(
      child: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), shrinkWrap: true, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(c.laeq.toStringAsFixed(1),
                    style: TextStyle(fontSize: 52, fontWeight: FontWeight.w800, color: col, height: 1)),
                const Padding(
                    padding: EdgeInsets.only(left: 6, bottom: 6),
                    child: Text('dB(A)', style: TextStyle(fontWeight: FontWeight.w700))),
              ]),
              const SizedBox(height: 6),
              StatusChip(noiseLabel(c.laeq), col, icon: Icons.graphic_eq_rounded),
            ]),
          ),
          Column(children: [
            ScoreRing(
              value: c.confidence,
              color: cs.primary,
              size: 72,
              stroke: 7,
              child: Text('${(c.confidence * 100).round()}%',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 4),
            Text('Confiance', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
          ]),
        ]),
        const SizedBox(height: 18),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _stat(context, Icons.vertical_align_top_rounded, 'Lmax', '${c.lmax.toStringAsFixed(1)} dB'),
          _stat(context, Icons.straighten_rounded, 'Mesures', '${c.count}'),
          _stat(context, Icons.people_alt_rounded, 'Contributeurs', '${c.devices}'),
          _stat(context, Icons.tune_rounded, 'Calibrées', '${(c.calibratedShare * 100).round()} %'),
          if (c.last != null) _stat(context, Icons.schedule_rounded, 'Dernière', fmtAgo(c.last!)),
        ]),
        FutureBuilder<TrafficFlow?>(
          future: _traffic,
          builder: (context, snap) {
            final t = snap.data;
            if (t == null) return const SizedBox.shrink();
            final col = switch (t.level) {
              'free' => const Color(0xFF22C55E),
              'moderate' => const Color(0xFFF59E0B),
              _ => const Color(0xFFEF4444),
            };
            return Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(children: [
                Icon(Icons.traffic_rounded, color: col),
                const SizedBox(width: 8),
                Text('Trafic en ce moment : ', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                StatusChip('${t.levelLabel} · ${t.current.round()}/${t.freeFlow.round()} km/h', col),
              ]),
            );
          },
        ),
        FutureBuilder<CellDetail>(
          future: _f,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()));
            }
            if (snap.hasError) {
              return Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Text(errorMessage(snap.error!), style: TextStyle(color: cs.error)),
              );
            }
            final d = snap.data!;
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (d.context.isNotEmpty) ...[
                const SectionTitle('Contexte sonore déclaré'),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final e in d.context.entries)
                    if (NoiseTagX.parse(e.key) != null) NoiseTagChip(NoiseTagX.parse(e.key)!, count: e.value),
                ]),
              ],
              if (d.byDayPart.isNotEmpty) ...[
                const SectionTitle('Par plage horaire'),
                SizedBox(height: 170, child: _DayPartChart(d)),
              ],
              if (d.daily.length > 1) ...[
                const SectionTitle('Évolution journalière'),
                SizedBox(height: 190, child: _DailyChart(d)),
              ],
            ]);
          },
        ),
      ]),
    );
  }

  Widget _stat(BuildContext context, IconData i, String l, String v) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(i, size: 16, color: cs.primary),
        const SizedBox(width: 6),
        Text('$l ', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
        Text(v, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
      ]),
    );
  }
}

class _DayPartChart extends StatelessWidget {
  const _DayPartChart(this.d);
  final CellDetail d;
  @override
  Widget build(BuildContext context) {
    const order = ['morning', 'afternoon', 'evening', 'night'];
    final byPart = {for (final p in d.byDayPart) p.part: p};
    final maxY = (d.byDayPart.map((e) => e.laeq).reduce((a, b) => a > b ? a : b) + 10).ceilToDouble();
    return BarChart(BarChartData(
      maxY: maxY,
      minY: 0,
      gridData: const FlGridData(show: false),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 26,
            getTitlesWidget: (v, meta) => Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(dayPartLabel(order[v.toInt()]), style: const TextStyle(fontSize: 11)),
            ),
          ),
        ),
      ),
      barGroups: [
        for (var i = 0; i < order.length; i++)
          BarChartGroupData(x: i, barRods: [
            BarChartRodData(
              toY: byPart[order[i]]?.laeq ?? 0,
              width: 28,
              borderRadius: BorderRadius.circular(8),
              color: byPart[order[i]] == null ? Colors.transparent : noiseColor(byPart[order[i]]!.laeq),
            ),
          ], showingTooltipIndicators: byPart[order[i]] == null ? [] : [0]),
      ],
      barTouchData: BarTouchData(
        enabled: false,
        touchTooltipData: BarTouchTooltipData(
          getTooltipColor: (_) => Colors.transparent,
          tooltipPadding: EdgeInsets.zero,
          getTooltipItem: (g, gi, rod, ri) => BarTooltipItem(
            rod.toY.toStringAsFixed(0),
            TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w700, fontSize: 12),
          ),
        ),
      ),
    ));
  }
}

class _DailyChart extends StatelessWidget {
  const _DailyChart(this.d);
  final CellDetail d;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final spots = [for (var i = 0; i < d.daily.length; i++) FlSpot(i.toDouble(), d.daily[i].laeq)];
    final vals = d.daily.map((e) => e.laeq);
    final minY = (vals.reduce((a, b) => a < b ? a : b) - 8).floorToDouble();
    final maxY = (vals.reduce((a, b) => a > b ? a : b) + 8).ceilToDouble();
    final step = (d.daily.length / 4).ceil().clamp(1, 100);
    return LineChart(LineChartData(
      minY: minY < 0 ? 0 : minY,
      maxY: maxY,
      gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(color: cs.outlineVariant.withValues(alpha: 0.4), strokeWidth: 1)),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 34,
            getTitlesWidget: (v, meta) => Text(v.toStringAsFixed(0), style: const TextStyle(fontSize: 10)),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: 1,
            reservedSize: 24,
            getTitlesWidget: (v, meta) {
              final i = v.toInt();
              if (i < 0 || i >= d.daily.length || i % step != 0) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(fmtDay(d.daily[i].date), style: const TextStyle(fontSize: 10)),
              );
            },
          ),
        ),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          barWidth: 3,
          color: cs.primary,
          dotData: const FlDotData(show: true),
          belowBarData: BarAreaData(show: true, color: cs.primary.withValues(alpha: 0.12)),
        ),
      ],
    ));
  }
}