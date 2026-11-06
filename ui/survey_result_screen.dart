import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/api_survey.dart';
import '../core/models_survey.dart';
import '../core/util.dart';
import '../state/session_controller.dart';
import 'widgets.dart';

class SurveyResultScreen extends StatefulWidget {
  const SurveyResultScreen({super.key, required this.ack, required this.def, required this.evidenceQuestions});
  final SubmitAck ack;
  final SurveyDefinition def;
  final List<SurveyQuestion> evidenceQuestions;
  @override
  State<SurveyResultScreen> createState() => _SurveyResultScreenState();
}

class _SurveyResultScreenState extends State<SurveyResultScreen> {
  ResponseDetail? _d;
  Timer? _poll, _tick;
  int _tries = 0;
  bool _busy = false, _finalized = false;
  final Map<String, int> _uploaded = {};

  @override
  void initState() {
    super.initState();
    _startPoll();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.ack.deadline != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  void _startPoll() {
    _poll?.cancel();
    _tries = 0;
    _fetch();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _fetch());
  }

  Future<void> _fetch() async {
    if (++_tries > 25) {
      _poll?.cancel();
      return;
    }
    try {
      final d = await context.read<ApiClient>().surveyResponse(widget.ack.id);
      if (!mounted) return;
      setState(() => _d = d);
      if (d.status != 'pending') _poll?.cancel();
    } catch (_) {}
  }

  Future<void> _photo(SurveyQuestion q) async {
    final s = context.read<SessionController>();
    final api = context.read<ApiClient>();
    if (!s.consentOf('photo')) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Autoriser les photos ?'),
          content: const Text('Les photos servent uniquement à vérifier la réponse. Elles sont vues par les administrateurs puis supprimées après 90 jours.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Non')),
            FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(100, 44)), onPressed: () => Navigator.pop(context, true), child: const Text('Autoriser')),
          ],
        ),
      );
      if (ok != true) return;
      try {
        await s.setConsent('photo', true);
      } catch (e) {
        if (mounted) showToast(context, errorMessage(e));
        return;
      }
    }
    final x = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 1600, imageQuality: 70);
    if (x == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await api.surveyEvidence(widget.ack.id, q.key, x.path);
      if (mounted) setState(() => _uploaded[q.key] = (_uploaded[q.key] ?? 0) + 1);
    } catch (e) {
      if (mounted) showToast(context, errorMessage(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _finish() async {
    setState(() => _busy = true);
    try {
      await context.read<ApiClient>().surveyEvidenceDone(widget.ack.id);
      _finalized = true;
      _startPoll();
    } catch (e) {
      if (mounted) showToast(context, errorMessage(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  String _left() {
    final dl = widget.ack.deadline;
    if (dl == null) return '';
    final d = dl.toLocal().difference(DateTime.now());
    if (d.isNegative) return 'délai écoulé';
    return '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final d = _d;
    final status = d?.status ?? widget.ack.status;
    final col = qualityColor(status);
    final needsPhoto = widget.ack.evidenceRequired.isNotEmpty && !_finalized;
    return Scaffold(
      appBar: AppBar(title: const Text('Réponse envoyée'), automaticallyImplyLeading: false),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
        SoftCard(
          child: Row(children: [
            ScoreRing(
              value: d?.score ?? 0,
              color: col,
              size: 84,
              stroke: 9,
              child: d?.score == null ? Icon(Icons.hourglass_top_rounded, color: col) : Text('${(d!.score! * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.ack.duplicate ? 'Déjà enregistrée' : 'Merci !', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                const SizedBox(height: 4),
                StatusChip(qualityLabel(status), col),
                if (status == 'pending')
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(needsPhoto ? 'L\'évaluation démarre après vos photos.' : 'Évaluation automatique en cours…', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
                  ),
              ]),
            ),
          ]),
        ),
        if (widget.evidenceQuestions.isNotEmpty) ...[
          SectionTitle(needsPhoto ? 'Photos demandées' : 'Photos (facultatif)', trailing: widget.ack.deadline == null ? null : Text(_left(), style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700))),
          for (final q in widget.evidenceQuestions)
            SoftCard(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Icon((_uploaded[q.key] ?? 0) > 0 ? Icons.check_circle_rounded : Icons.photo_camera_outlined, color: (_uploaded[q.key] ?? 0) > 0 ? const Color(0xFF22C55E) : cs.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${q.title}${widget.ack.evidenceRequired.contains(q.key) ? ' *' : ''}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                    Text(q.evidenceHint ?? 'Photo prise maintenant, sur place.', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                  ]),
                ),
                if ((_uploaded[q.key] ?? 0) > 0) Padding(padding: const EdgeInsets.only(right: 4), child: Text('×${_uploaded[q.key]}', style: const TextStyle(fontWeight: FontWeight.w800))),
                IconButton.filledTonal(onPressed: _busy || _finalized ? null : () => _photo(q), icon: const Icon(Icons.photo_camera_rounded)),
              ]),
            ),
          const SizedBox(height: 4),
          FilledButton.icon(
            onPressed: (_busy || _finalized || _uploaded.isEmpty && needsPhoto) ? null : _finish,
            icon: const Icon(Icons.done_all_rounded),
            label: Text(_finalized ? 'Photos envoyées' : 'Terminer'),
          ),
        ],
        if (d != null && d.reasons.where((r) => r.code != 'new_respondent').isNotEmpty) ...[
          const SectionTitle('Pourquoi ce statut ?'),
          for (final r in d.reasons.where((r) => r.code != 'new_respondent' && r.code != 'insufficient_peers'))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('• ${r.label}', style: const TextStyle(fontWeight: FontWeight.w700)),
                if (r.tip != null) Padding(padding: const EdgeInsets.only(left: 12, top: 2), child: Text(r.tip!, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13))),
              ]),
            ),
        ],
        const SizedBox(height: 20),
        FilledButton(onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst), child: const Text('Retour à l\'accueil')),
      ]),
    );
  }
}