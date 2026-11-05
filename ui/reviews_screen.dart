import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models_social.dart';
import '../core/util.dart';
import '../state/reviews_controller.dart';
import 'widgets.dart';

class ReviewsScreen extends StatefulWidget {
  const ReviewsScreen({super.key});
  @override
  State<ReviewsScreen> createState() => _ReviewsScreenState();
}

class _ReviewsScreenState extends State<ReviewsScreen> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ReviewsController>().loadHistory();
    });
  }

  Future<void> _vote(ReviewRequest r, String vote, {bool strong = false}) async {
    setState(() => _busy = true);
    try {
      await context.read<ReviewsController>().vote(r.id, vote, strong);
    } catch (e) {
      if (mounted) showToast(context, errorMessage(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rev = context.watch<ReviewsController>();
    return Scaffold(
      appBar: AppBar(title: const Text('Mes avis')),
      body: RefreshIndicator(
        onRefresh: () async {
          await rev.refresh();
          await rev.loadHistory();
        },
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
          if (rev.pending.isNotEmpty) ...[
            SectionTitle('En attente (${rev.pending.length})'),
            for (final r in rev.pending) _pendingCard(r, cs),
          ] else
            SoftCard(child: Text('Aucune demande d\'avis en ce moment.', style: TextStyle(color: cs.onSurfaceVariant))),
          const SectionTitle('Historique'),
          if (rev.history.isEmpty)
            SoftCard(child: Text('Aucun avis donné pour l\'instant.', style: TextStyle(color: cs.onSurfaceVariant))),
          for (final h in rev.history) _historyTile(h, cs),
        ]),
      ),
    );
  }

  Widget _pendingCard(ReviewRequest r, ColorScheme cs) {
    return SoftCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.hearing_rounded, color: Color(0xFF7C3AED)),
          const SizedBox(width: 10),
          Expanded(child: Text('Ce niveau vous semble-t-il juste ?', style: const TextStyle(fontWeight: FontWeight.w800))),
        ]),
        const SizedBox(height: 8),
        Text('${r.levelDb.toStringAsFixed(0)} dB(A) · à ${r.distanceM.round()} m · ${fmtAgo(r.measuredAt)}',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
        Text('Expire dans ${fmtTime(r.expiresAt)}', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: _busy ? null : () => _vote(r, 'lower', strong: true), child: const Text('Plus faible'))),
          const SizedBox(width: 8),
          Expanded(child: FilledButton(onPressed: _busy ? null : () => _vote(r, 'confirm'), child: const Text('Oui'))),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton(onPressed: _busy ? null : () => _vote(r, 'higher', strong: true), child: const Text('Plus fort'))),
        ]),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: _busy ? null : () => _vote(r, 'confirm', strong: true),
            child: const Text('Écart important'),
          ),
        ),
      ]),
    );
  }

  Widget _historyTile(ReviewHistoryItem h, ColorScheme cs) {
    final ok = h.matched == true;
    return SoftCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        Icon(
          h.matched == null ? Icons.hourglass_empty_rounded : (ok ? Icons.check_circle_rounded : Icons.cancel_rounded),
          color: h.matched == null ? cs.onSurfaceVariant : (ok ? const Color(0xFF22C55E) : const Color(0xFFEF4444)),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${h.levelDb.toStringAsFixed(0)} dB(A) · ${h.vote ?? '—'}', style: const TextStyle(fontWeight: FontWeight.w700)),
          Text('${h.votedAt != null ? fmtAgo(h.votedAt!) : ''} · statut : ${h.status}', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
        ])),
        StatusChip(
          h.outcome ?? 'en attente',
          h.matched == null ? cs.primary : (ok ? const Color(0xFF22C55E) : const Color(0xFFEF4444)),
        ),
      ]),
    );
  }
}