import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../core/util.dart';
import '../state/proposals_controller.dart';
import '../state/session_controller.dart';
import 'record_screen.dart';
import 'widgets.dart';

class ProposalsScreen extends StatefulWidget {
  const ProposalsScreen({super.key});
  @override
  State<ProposalsScreen> createState() => _ProposalsScreenState();
}

class _ProposalsScreenState extends State<ProposalsScreen> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<ProposalsController>().refresh());
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _respond(ProposalOut p, bool accept) async {
    try {
      await context.read<ProposalsController>().respond(p.id, accept);
    } catch (e) {
      if (mounted) showToast(context, errorMessage(e));
    }
  }

  String _remaining(DateTime t) {
    final d = t.difference(DateTime.now());
    if (d.isNegative) return 'expirée';
    return '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final pc = context.watch<ProposalsController>();
    final s = context.watch<SessionController>();
    final cs = Theme.of(context).colorScheme;
    final u = s.user!;

    return Scaffold(
      appBar: AppBar(title: const Text('Propositions')),
      body: RefreshIndicator(
        onRefresh: pc.refresh,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
          if (!u.hybridCollectionEnabled)
            SoftCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Collecte hybride désactivée', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text('Activez-la pour recevoir des propositions de zones à mesurer.',
                    style: TextStyle(color: cs.onSurfaceVariant)),
                const SizedBox(height: 12),
                FilledButton(
                    onPressed: () async {
                      try {
                        await s.setHybrid(true);
                      } catch (e) {
                        if (context.mounted) showToast(context, errorMessage(e));
                      }
                    },
                    child: const Text('Activer')),
              ]),
            )
          else
            SoftCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Demander une proposition', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('Selon votre position, votre planning et votre batterie.',
                    style: TextStyle(color: cs.onSurfaceVariant)),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                      child: OutlinedButton(
                          onPressed: pc.loading ? null : () => pc.requestNow('contextual'),
                          child: const Text('Ici et maintenant'))),
                  const SizedBox(width: 10),
                  Expanded(
                      child: OutlinedButton(
                          onPressed: pc.loading ? null : () => pc.requestNow('scheduled'),
                          child: const Text('Créneau planifié'))),
                ]),
                if (pc.lastReason != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(proposalReasonLabel(pc.lastReason!),
                        style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600)),
                  ),
                if (pc.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(apiErrorLabel(pc.error!), style: TextStyle(color: cs.error)),
                  ),
              ]),
            ),
          const SectionTitle('En cours'),
          if (pc.loading) const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator())),
          if (!pc.loading && pc.list.isEmpty)
            SoftCard(
                child: Text('Aucune proposition ouverte.', style: TextStyle(color: cs.onSurfaceVariant))),
          for (final p in pc.list)
            SoftCard(
              margin: const EdgeInsets.only(bottom: 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(p.trigger == 'scheduled' ? Icons.schedule_rounded : Icons.near_me_rounded, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(p.trigger == 'scheduled' ? 'Créneau planifié' : 'Zone proche de vous',
                          style: const TextStyle(fontWeight: FontWeight.w800))),
                  StatusChip(p.status == 'accepted' ? 'Acceptée' : 'À répondre',
                      p.status == 'accepted' ? const Color(0xFF22C55E) : cs.primary),
                ]),
                const SizedBox(height: 10),
                Text('Priorité ${p.priority.toStringAsFixed(0)}/100 · durée ${p.sessionSeconds} s · expire dans ${_remaining(p.expiresAt)}',
                    style: TextStyle(color: cs.onSurfaceVariant)),
                const SizedBox(height: 12),
                if (p.status == 'pending')
                  Row(children: [
                    Expanded(child: OutlinedButton(onPressed: () => _respond(p, false), child: const Text('Refuser'))),
                    const SizedBox(width: 10),
                    Expanded(child: FilledButton(onPressed: () => _respond(p, true), child: const Text('Accepter'))),
                  ])
                else
                  FilledButton.icon(
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Démarrer la mesure'),
                    onPressed: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => RecordScreen(proposal: p)))
                        .then((_) => pc.refresh()),
                  ),
              ]),
            ),
        ]),
      ),
    );
  }
}