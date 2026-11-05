import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/api_ext.dart';
import '../core/models.dart';
import '../core/models_roads.dart';
import '../core/util.dart';
import 'widgets.dart';

class RoadSheet extends StatefulWidget {
  const RoadSheet({super.key, required this.seg, required this.filters, this.state});
  final RoadSeg seg;
  final RoadState? state;
  final MapFilters filters;
  @override
  State<RoadSheet> createState() => _RoadSheetState();
}

class _RoadSheetState extends State<RoadSheet> {
  late final Future<RoadDetail> _f = context.read<ApiClient>().roadSegment(widget.seg.id, widget.filters);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = widget.seg;
    return SafeArea(
      child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [
        Row(children: [
          Icon(Icons.add_road_rounded, color: cs.primary, size: 30),
          const SizedBox(width: 10),
          Expanded(child: Text(s.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 19))),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 6, children: [
          StatusChip(roadClassLabel(s.highway), cs.primary),
          if (s.ref != null) StatusChip(s.ref!, cs.onSurfaceVariant),
          if (s.maxspeed != null) StatusChip('${s.maxspeed} km/h', cs.onSurfaceVariant),
          if (s.oneway) StatusChip('Sens unique', cs.onSurfaceVariant),
          StatusChip('${s.lengthM.round()} m', cs.onSurfaceVariant),
        ]),
        FutureBuilder<RoadDetail>(
          future: _f,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Padding(padding: EdgeInsets.all(28), child: Center(child: CircularProgressIndicator()));
            }
            if (snap.hasError) {
              return Padding(padding: const EdgeInsets.only(top: 20), child: Text(errorMessage(snap.error!), style: TextStyle(color: cs.error)));
            }
            final d = snap.data!;
            final st = d.state;
            final col = st.hasData ? noiseColor(st.laeq) : const Color(0xFF22C55E);
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(height: 16),
              if (st.hasData) ...[
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(st.laeq.toStringAsFixed(1), style: TextStyle(fontSize: 48, fontWeight: FontWeight.w800, color: col, height: 1)),
                  const Padding(padding: EdgeInsets.only(left: 6, bottom: 6), child: Text('dB(A)', style: TextStyle(fontWeight: FontWeight.w700))),
                  const Spacer(),
                  StatusChip(noiseLabel(st.laeq), col),
                ]),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 6, children: [
                  StatusChip('${st.count} mesure(s)', cs.primary, icon: Icons.straighten_rounded),
                  StatusChip('${st.devices} contributeur(s)', cs.primary, icon: Icons.people_alt_rounded),
                  StatusChip('Confiance ${(st.confidence * 100).round()} %', const Color(0xFF22C55E), icon: Icons.verified_rounded),
                  if (st.lmax != null) StatusChip('Lmax ${st.lmax!.toStringAsFixed(0)} dB', cs.onSurfaceVariant),
                ]),
                if (st.last != null)
                  Padding(padding: const EdgeInsets.only(top: 8), child: Text('Dernière mesure : ${fmtAgo(st.last!)}', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13))),
              ] else
                SoftCard(
                  child: Row(children: [
                    const Icon(Icons.eco_rounded, color: Color(0xFF22C55E), size: 30),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                          'Pas encore mesurée (ou pas assez de contributeurs). Elle est affichée en vert, le niveau de base : cela ne veut pas dire qu\'elle est silencieuse. Une mission « route » peut vous la proposer.',
                          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13, height: 1.35)),
                    ),
                  ]),
                ),
              if (d.byPart.isNotEmpty) ...[
                const SectionTitle('Par plage horaire'),
                for (final p in d.byPart)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      SizedBox(width: 90, child: Text(dayPartLabel(p.part))),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: LinearProgressIndicator(minHeight: 10, value: (p.laeq / 100).clamp(0.05, 1.0), color: noiseColor(p.laeq), backgroundColor: cs.outlineVariant.withValues(alpha: 0.3)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text('${p.laeq.round()} dB · ${p.count}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                    ]),
                  ),
              ],
              if (d.connected.isNotEmpty) ...[
                const SectionTitle('Routes connectées'),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final c in d.connected.map((e) => e.name).toSet().take(8)) StatusChip(c, cs.onSurfaceVariant),
                ]),
              ],
            ]);
          },
        ),
      ]),
    );
  }
}