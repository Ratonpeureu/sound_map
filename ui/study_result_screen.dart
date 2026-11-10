import 'package:flutter/material.dart';

import '../core/models_study.dart';
import '../core/util.dart';
import 'rewards_screen.dart';
import 'study_widgets.dart';
import 'widgets.dart';

class StudyResultScreen extends StatelessWidget {
  const StudyResultScreen({super.key, required this.ack, required this.detail});
  final StudyAck ack;
  final StudyDetail detail;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final col = qualityColor(ack.status);
    final outro = detail.definition.outro;
    final rw = ack.reward;
    return Scaffold(
      appBar: AppBar(title: Text(ack.screenedOut ? 'Étude terminée' : 'Réponses envoyées'), automaticallyImplyLeading: false),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
        if (ack.screenedOut)
          SoftCard(
            child: Column(children: [
              Icon(Icons.how_to_reg_rounded, size: 46, color: cs.primary),
              const SizedBox(height: 10),
              const Text('Merci de votre intérêt', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19)),
              const SizedBox(height: 6),
              Text(ack.message ?? "Cette étude ne correspond pas à votre situation. Merci d'avoir répondu !", textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant, height: 1.4)),
            ]),
          )
        else ...[
          SoftCard(
            child: Row(children: [
              ScoreRing(value: ack.score ?? 0, color: col, size: 84, stroke: 9, child: ack.score == null ? Icon(Icons.hourglass_top_rounded, color: col) : Text('${(ack.score! * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17))),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(ack.duplicate ? 'Déjà enregistrée' : 'Merci !', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 19)),
                  const SizedBox(height: 4),
                  StatusChip(qualityLabel(ack.status), col),
                  const SizedBox(height: 6),
                  Text('Votre qualité de réponse : score affiché ci-contre.', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                ]),
              ),
            ]),
          ),
          if (rw != null) ...[
            const SectionTitle('Votre récompense'),
            SoftCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(rewardKindIcon(rw.kind), color: rewardStatusColor(rw.status), size: 30),
                  const SizedBox(width: 12),
                  Expanded(child: Text(rw.headline, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                  StatusChip(rw.statusLabel, rewardStatusColor(rw.status)),
                ]),
                if (rw.reasonLabel != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Motif : ${rw.reasonLabel}', style: TextStyle(color: cs.error, fontSize: 13))),
                if (rw.status == 'pending') Padding(padding: const EdgeInsets.only(top: 8), child: Text("L'organisateur vérifie vos réponses avant d'attribuer la récompense.", style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5))),
                if (rw.status == 'entered') Padding(padding: const EdgeInsets.only(top: 8), child: Text('Vous participez au tirage au sort.', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5))),
                if (rw.code != null) Padding(padding: const EdgeInsets.only(top: 8), child: SelectableText('Code : ${rw.code}', style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1))),
                if (rw.needsClaim) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Pensez à renseigner vos coordonnées dans « Mes récompenses ».', style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700, fontSize: 13))),
              ]),
            ),
          ],
          if (ack.reasons.where((r) => r != 'new_participant').isNotEmpty) ...[
            const SectionTitle('Pourquoi ce score ?'),
            for (final r in ack.reasons.where((r) => r != 'new_participant')) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('• ${studyReasonLabel(r)}', style: TextStyle(color: cs.onSurfaceVariant))),
          ],
          if (outro != null && ((outro.title ?? '').isNotEmpty || (outro.text ?? '').isNotEmpty || outro.media.isNotEmpty)) ...[
            const SizedBox(height: 14),
            SoftCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if ((outro.title ?? '').isNotEmpty) Text(outro.title!, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                if ((outro.text ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(outro.text!, style: const TextStyle(height: 1.45))),
                if (outro.media.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: MediaStrip(outro.media)),
              ]),
            ),
          ],
        ],
        const SizedBox(height: 18),
        if (!ack.screenedOut) OutlinedButton.icon(icon: const Icon(Icons.card_giftcard_rounded), label: const Text('Mes récompenses'), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RewardsScreen()))),
        const SizedBox(height: 10),
        FilledButton(onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst), child: const Text("Retour à l'accueil")),
      ]),
    );
  }
}