import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/config.dart';
import '../core/models.dart';
import '../core/util.dart';
import '../state/proposals_controller.dart';
import '../state/recorder_controller.dart';
import 'widgets.dart';

class RecordScreen extends StatefulWidget {
  const RecordScreen({super.key, this.proposal});
  final ProposalOut? proposal;
  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  late final RecorderController _rec;

  @override
  void initState() {
    super.initState();
    _rec = context.read<RecorderController>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _rec.resetForNew();
      _rec.attachProposal(widget.proposal);
      _rec.startGpsWatch();
    });
  }

  @override
  void dispose() {
    _rec.stopGpsWatch();
    super.dispose();
  }

  Future<bool> _confirmCancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Annuler la mesure ?'),
        content: const Text('La mesure en cours sera perdue.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Continuer')),
          FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(100, 44)),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Annuler la mesure')),
        ],
      ),
    );
    if (ok == true) await _rec.cancel();
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final r = context.watch<RecorderController>();
    final cs = Theme.of(context).colorScheme;
    final recording = r.phase == RecPhase.recording;

    return PopScope(
      canPop: !r.busy,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (r.phase == RecPhase.recording || r.phase == RecPhase.preparing) {
          if (await _confirmCancel() && mounted) Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(title: Text(widget.proposal != null ? 'Mesure proposée' : 'Nouvelle mesure')),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(children: [
              _GpsBadge(r.gps),
              if (widget.proposal != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: SoftCard(
                    padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      Icon(Icons.flag_rounded, color: cs.primary),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text(
                              'Zone prioritaire (${widget.proposal!.priority.toStringAsFixed(0)}/100) · durée ${widget.proposal!.sessionSeconds} s',
                              style: const TextStyle(fontWeight: FontWeight.w600))),
                    ]),
                  ),
                ),
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(end: r.phase == RecPhase.done ? r.result!.laeq : r.liveDb),
                      duration: const Duration(milliseconds: 160),
                      builder: (_, db, __) => CustomPaint(
                        painter: _GaugePainter(db: db, active: recording, track: cs.outlineVariant),
                        child: Center(child: _gaugeCenter(context, r, db)),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 56, child: CustomPaint(size: const Size(double.infinity, 56), painter: _WavePainter(r.wave))),
              const SizedBox(height: 14),
              if (recording)
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                      minHeight: 8, value: r.total == 0 ? 0 : r.elapsed / r.total),
                ),
              if (recording)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('${r.elapsed} / ${r.total} s · LAeq ${r.leqDb.toStringAsFixed(1)} · Lmax ${r.maxDb.toStringAsFixed(1)}',
                      style: TextStyle(color: cs.onSurfaceVariant)),
                ),
              if (r.phase == RecPhase.idle || r.phase == RecPhase.failed || r.phase == RecPhase.preparing) ...[
                const SizedBox(height: 4),
                Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Contexte sonore (facultatif)',
                        style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600))),
                const SizedBox(height: 8),
                SizedBox(
                  height: 42,
                  child: ListView(scrollDirection: Axis.horizontal, children: [
                    for (final t in NoiseTag.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          avatar: Icon(t.icon, size: 18),
                          label: Text(t.label),
                          selected: r.tag == t,
                          showCheckmark: false,
                          onSelected: (s) => r.setTag(s ? t : null),
                        ),
                      ),
                  ]),
                ),
              ],
              if (r.phase == RecPhase.failed)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(apiErrorLabel(r.errorCode ?? 'capture_error'),
                      textAlign: TextAlign.center, style: TextStyle(color: cs.error)),
                ),
              if (r.phase == RecPhase.done) _ResultCard(r),
              const SizedBox(height: 14),
              _mainButton(context, r),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _gaugeCenter(BuildContext context, RecorderController r, double db) {
    final cs = Theme.of(context).colorScheme;
    switch (r.phase) {
      case RecPhase.preparing:
        return const CircularProgressIndicator();
      case RecPhase.sending:
        return const Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(),
          SizedBox(height: 10),
          Text('Envoi…'),
        ]);
      case RecPhase.idle:
      case RecPhase.failed:
        return Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.mic_rounded, size: 52, color: cs.primary),
          const SizedBox(height: 8),
          Text('${r.total} secondes', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
          Text('Restez immobile', style: TextStyle(color: cs.onSurfaceVariant)),
        ]);
      default:
        final col = noiseColor(db);
        return Column(mainAxisSize: MainAxisSize.min, children: [
          Text(db.toStringAsFixed(0),
              style: TextStyle(fontSize: 76, fontWeight: FontWeight.w800, color: col, height: 1)),
          const Text('dB(A)', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          StatusChip(noiseLabel(db), col),
        ]);
    }
  }

  Widget _mainButton(BuildContext context, RecorderController r) {
    switch (r.phase) {
      case RecPhase.recording:
        return OutlinedButton.icon(
            onPressed: _confirmCancel, icon: const Icon(Icons.stop_rounded), label: const Text('Annuler'));
      case RecPhase.preparing:
      case RecPhase.sending:
        return const FilledButton(onPressed: null, child: Text('Veuillez patienter…'));
      case RecPhase.done:
        return Row(children: [
          Expanded(
              child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(), child: const Text('Fermer'))),
          const SizedBox(width: 12),
          Expanded(
              child: FilledButton(
                  onPressed: () {
                    r.resetForNew();
                    r.attachProposal(null);
                  },
                  child: const Text('Nouvelle mesure'))),
        ]);
      default:
        return FilledButton.icon(
          onPressed: () async {
            await r.start();
            if (mounted) context.read<ProposalsController>().refresh();
          },
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text(r.phase == RecPhase.failed ? 'Réessayer' : 'Démarrer la mesure'),
        );
    }
  }
}

class _GpsBadge extends StatelessWidget {
  const _GpsBadge(this.pos);
  final dynamic pos;
  @override
  Widget build(BuildContext context) {
    final acc = pos?.accuracy as double?;
    final color = acc == null
        ? const Color(0xFF94A3B8)
        : acc <= 20
            ? const Color(0xFF22C55E)
            : acc <= 100
                ? const Color(0xFFF59E0B)
                : const Color(0xFFEF4444);
    return Align(
      alignment: Alignment.centerLeft,
      child: StatusChip(acc == null ? 'GPS : recherche…' : 'GPS ± ${acc.toStringAsFixed(0)} m', color,
          icon: Icons.gps_fixed_rounded),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard(this.r);
  final RecorderController r;
  @override
  Widget build(BuildContext context) {
    final res = r.result!;
    final cs = Theme.of(context).colorScheme;
    final q = r.qualityStatus;
    return SoftCard(
      margin: const EdgeInsets.only(top: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(res.sent ? Icons.cloud_done_rounded : Icons.cloud_queue_rounded,
              color: res.sent ? const Color(0xFF22C55E) : const Color(0xFFF59E0B)),
          const SizedBox(width: 8),
          Expanded(
              child: Text(res.sent ? 'Mesure enregistrée et envoyée' : 'Enregistrée · envoi dès le retour du réseau',
                  style: const TextStyle(fontWeight: FontWeight.w800))),
        ]),
        const SizedBox(height: 10),
        Text('LAeq ${res.laeq.toStringAsFixed(1)} · Lmax ${res.lmax.toStringAsFixed(1)} · Lmin ${res.lmin.toStringAsFixed(1)} dB(A)'),
        const SizedBox(height: 10),
        Row(children: [
          if (res.tag != null) ...[NoiseTagChip(res.tag!), const SizedBox(width: 8)],
          if (!res.sent)
            const StatusChip('En attente', Color(0xFFF59E0B))
          else if (q == null)
            Row(children: [
              const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 8),
              Text('Évaluation en cours…', style: TextStyle(color: cs.onSurfaceVariant)),
            ])
          else ...[
            StatusChip(qualityLabel(q), qualityColor(q)),
            if (r.qualityScore != null) ...[
              const SizedBox(width: 8),
              Text('Score ${(r.qualityScore! * 100).round()} %', style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ],
        ]),
        if (q != null && r.reasons.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final code in r.reasons.where((c) => c != 'insufficient_neighbors'))
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('• ${reasonLabel(code)}', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
            ),
        ],
      ]),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({required this.db, required this.active, required this.track});
  final double db;
  final bool active;
  final Color track;
  static const int ticks = 54;
  static const double minDb = 20, maxDb = 110;

  @override
  void paint(Canvas c, Size s) {
    final ctr = s.center(Offset.zero);
    final r = s.width / 2 - 6;
    final level = ((db - minDb) / (maxDb - minDb)).clamp(0.0, 1.0);
    final startAngle = 3 * pi / 4; // 135°
    const sweep = 3 * pi / 2; // 270°
    final p = Paint()
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < ticks; i++) {
      final f = i / (ticks - 1);
      final a = startAngle + sweep * f;
      final inner = Offset(ctr.dx + cos(a) * (r - 18), ctr.dy + sin(a) * (r - 18));
      final outer = Offset(ctr.dx + cos(a) * r, ctr.dy + sin(a) * r);
      final on = f <= level && (active || db > 0);
      p.color = on ? noiseColor(minDb + f * (maxDb - minDb)) : track.withValues(alpha: 0.35);
      c.drawLine(inner, outer, p);
    }
  }

  @override
  bool shouldRepaint(_GaugePainter o) => o.db != db || o.active != active;
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.values);
  final List<double> values;
  @override
  void paint(Canvas c, Size s) {
    if (values.isEmpty) return;
    const n = 48;
    final w = s.width / n;
    final p = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = max(2, w * 0.5);
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      final h = (((v - 20) / 90).clamp(0.05, 1.0)) * s.height;
      final x = (n - values.length + i) * w + w / 2;
      p.color = noiseColor(v);
      c.drawLine(Offset(x, s.height / 2 - h / 2), Offset(x, s.height / 2 + h / 2), p);
    }
  }

  @override
  bool shouldRepaint(_WavePainter o) => true;
}