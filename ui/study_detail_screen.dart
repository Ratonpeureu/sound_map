import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/api_study.dart';
import '../core/models_study.dart';
import '../core/util.dart';
import '../state/studies_controller.dart';
import 'sponsor_screen.dart';
import 'study_fill_screen.dart';
import 'study_widgets.dart';
import 'widgets.dart';

String endsLabel(DateTime? d) {
  if (d == null) return 'Sans date de clôture';
  final diff = d.difference(DateTime.now());
  if (diff.isNegative) return 'Clôturée';
  if (diff.inDays >= 1) return 'Clôture dans ${diff.inDays} j';
  return 'Clôture dans ${diff.inHours} h';
}

class StudyDetailScreen extends StatefulWidget {
  const StudyDetailScreen({super.key, required this.card});
  final StudyCard card;
  @override
  State<StudyDetailScreen> createState() => _StudyDetailScreenState();
}

class _StudyDetailScreenState extends State<StudyDetailScreen> {
  StudyDetail? _d;
  String? _error;
  bool _loading = true, _busy = false;
  Position? _pos;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (context.read<StudiesController>().session.consentOf('geolocation')) _pos = await Geolocator.getLastKnownPosition();
    } catch (_) {}
    try {
      final d = await context.read<ApiClient>().studyGet(widget.card.id, lat: _pos?.latitude, lon: _pos?.longitude);
      if (mounted) setState(() => _d = d);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.code);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _participate() async {
    final d = _d!;
    setState(() => _busy = true);
    try {
      await context.read<ApiClient>().studyStart(d.id, lat: _pos?.latitude, lon: _pos?.longitude);
      if (!mounted) return;
      final ctrl = context.read<StudiesController>();
      Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => StudyFillScreen(detail: d))).then((_) {
        ctrl.refresh();
        if (mounted) Navigator.pop(context);
      });
    } on ApiException catch (e) {
      if (mounted) showToast(context, apiErrorLabel(e.code));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _decline() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Ne pas participer ?'),
        content: const Text("Cette étude ne vous sera plus proposée."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(100, 44)), onPressed: () => Navigator.pop(context, true), child: const Text('Refuser')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<ApiClient>().studyDecline(widget.card.id);
      if (!mounted) return;
      context.read<StudiesController>().refresh();
      Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) showToast(context, apiErrorLabel(e.code));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = widget.card;
    final d = _d;
    return Scaffold(
      appBar: AppBar(title: const Text('Étude')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : d == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(apiErrorLabel(_error ?? 'network'), textAlign: TextAlign.center, style: TextStyle(color: cs.error)),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: _load, child: const Text('Réessayer')),
                    ]),
                  ),
                )
              : ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 120), children: [
                  if (c.coverAssetId != null) Padding(padding: const EdgeInsets.only(bottom: 14), child: StudyImage(assetId: c.coverAssetId, width: double.infinity, height: 180, radius: 22)),
                  Wrap(spacing: 8, runSpacing: 6, children: [
                    StatusChip(c.kindLabel, cs.primary, icon: Icons.campaign_rounded),
                    StatusChip('~${c.estimatedMinutes} min', cs.onSurfaceVariant, icon: Icons.timer_outlined),
                    StatusChip(endsLabel(c.endsAt), cs.onSurfaceVariant, icon: Icons.event_rounded),
                    if (c.quotaLeft != null) StatusChip('${c.quotaLeft} place(s)', cs.onSurfaceVariant, icon: Icons.people_alt_rounded),
                  ]),
                  const SizedBox(height: 10),
                  Text(c.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 24, height: 1.2, letterSpacing: -0.4)),
                  if (c.summary != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(c.summary!, style: TextStyle(color: cs.onSurfaceVariant, height: 1.4))),
                  const SizedBox(height: 14),

                  // ---- initiateur
                  SoftCard(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SponsorScreen(sponsorId: d.sponsor.brief.id))),
                    child: Row(children: [
                      SponsorAvatar(d.sponsor.brief, size: 52),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Demandé par', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11.5)),
                          Text(d.sponsor.brief.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                          Text([d.sponsor.brief.kindLabel, if (d.sponsor.city != null) d.sponsor.city!].join(' · '), style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
                        ]),
                      ),
                      const Icon(Icons.chevron_right_rounded),
                    ]),
                  ),

                  // ---- récompense
                  if (c.reward.enabled) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), gradient: const LinearGradient(colors: [Color(0xFFDB2777), Color(0xFF7C3AED)], begin: Alignment.topLeft, end: Alignment.bottomRight)),
                      child: Row(children: [
                        Icon(rewardKindIcon(c.reward.kind), color: Colors.white, size: 34),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(c.reward.headline, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                            Text(c.reward.lottery ? 'Tirage au sort parmi les participants valides' : 'Garantie pour chaque participation valide',
                                style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12.5)),
                          ]),
                        ),
                      ]),
                    ),
                  ],

                  if (c.why.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(spacing: 6, runSpacing: 4, children: [
                      Text('Pourquoi vous :', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
                      for (final w in c.why) StatusChip(w, const Color(0xFF16A34A)),
                    ]),
                  ],
                  if (d.description != null) ...[const SectionTitle('À propos'), Text(d.description!, style: const TextStyle(height: 1.5))],

                  // ---- règles et conditions
                  const SectionTitle('Règles et conditions'),
                  Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: Column(children: [
                      for (final r in d.rules)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(16), border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5))),
                          child: ExpansionTile(
                            leading: Icon(ruleIcon(r.icon), color: cs.primary),
                            title: Text(r.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            expandedCrossAxisAlignment: CrossAxisAlignment.start,
                            children: [for (final i in r.items) Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Padding(padding: const EdgeInsets.only(top: 7, right: 8), child: Icon(Icons.circle, size: 6, color: cs.primary)), Expanded(child: Text(i, style: const TextStyle(height: 1.4, fontSize: 13.5)))]))],
                          ),
                        ),
                    ]),
                  ),
                  if (d.terms != null)
                    Theme(
                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(tilePadding: EdgeInsets.zero, title: const Text("Conditions générales de l'étude", style: TextStyle(fontWeight: FontWeight.w700)), children: [Text(d.terms!, style: TextStyle(color: cs.onSurfaceVariant, height: 1.45, fontSize: 13))]),
                    ),
                ]),
      bottomNavigationBar: d == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(children: [
                  Expanded(child: OutlinedButton(onPressed: _busy ? null : _decline, child: const Text('Refuser'))),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _participate,
                      icon: _busy ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2.5)) : const Icon(Icons.play_arrow_rounded),
                      label: Text(d.startedAt != null ? 'Reprendre' : 'Participer'),
                    ),
                  ),
                ]),
              ),
            ),
    );
  }
}