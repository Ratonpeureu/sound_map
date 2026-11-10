import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/api_study.dart';
import '../core/models_study.dart';
import '../core/util.dart';
import '../state/studies_controller.dart';
import 'rewards_screen.dart';
import 'study_detail_screen.dart';
import 'study_profile_screen.dart';
import 'study_widgets.dart';
import 'widgets.dart';

class StudiesScreen extends StatefulWidget {
  const StudiesScreen({super.key});
  @override
  State<StudiesScreen> createState() => _StudiesScreenState();
}

class _StudiesScreenState extends State<StudiesScreen> {
  bool _mine = false;
  List<StudyParticipation>? _parts;
  String? _partsError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<StudiesController>().refresh());
  }

  Future<void> _loadParts() async {
    try {
      final r = await context.read<ApiClient>().studyParticipations();
      if (mounted) setState(() => _parts = r);
    } on ApiException catch (e) {
      if (mounted) setState(() => _partsError = e.code);
    }
  }

  Future<void> _refresh() async {
    await context.read<StudiesController>().refresh();
    if (_mine) await _loadParts();
  }

  void _open(StudyCard c) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => StudyDetailScreen(card: c))).then((_) => _refresh());

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sc = context.watch<StudiesController>();
    final invited = sc.list.where((s) => s.invited).toList();
    final others = sc.list.where((s) => !s.invited).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Études et sondages'), actions: [
        IconButton(
          tooltip: 'Mes récompenses',
          icon: Badge(isLabelVisible: sc.claimCount > 0, label: Text('${sc.claimCount}'), child: const Icon(Icons.card_giftcard_rounded)),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RewardsScreen())),
        ),
        IconButton(tooltip: 'Mon profil études', icon: const Icon(Icons.manage_accounts_rounded), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const StudyProfileScreen()))),
      ]),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
          if (sc.needsConsent)
            SoftCard(
              margin: const EdgeInsets.only(bottom: 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Autorisation nécessaire', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text("Pour recevoir des études, autorisez l'utilisation de votre profil à des fins de ciblage. Vos réponses ne vont jamais sur une carte et restent pseudonymes.", style: TextStyle(color: cs.onSurfaceVariant, height: 1.35, fontSize: 13)),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () async {
                    try {
                      await sc.allowStudies();
                    } catch (e) {
                      if (context.mounted) showToast(context, errorMessage(e));
                    }
                  },
                  child: const Text('Autoriser'),
                ),
              ]),
            ),
          SegmentedButton<bool>(
            segments: const [ButtonSegment(value: false, label: Text('Pour moi'), icon: Icon(Icons.campaign_rounded)), ButtonSegment(value: true, label: Text('Mes participations'), icon: Icon(Icons.history_rounded))],
            selected: {_mine},
            showSelectedIcon: false,
            onSelectionChanged: (v) {
              setState(() => _mine = v.first);
              if (_mine) _loadParts();
            },
          ),
          const SizedBox(height: 12),
          if (!_mine) ...[
            if (sc.loading && sc.list.isEmpty) const Center(child: Padding(padding: EdgeInsets.all(28), child: CircularProgressIndicator())),
            if (sc.error != null) SoftCard(child: Text(apiErrorLabel(sc.error!), style: TextStyle(color: cs.error))),
            if (!sc.loading && sc.error == null && !sc.needsConsent && sc.list.isEmpty)
              SoftCard(
                padding: const EdgeInsets.all(24),
                child: Column(children: [
                  Icon(Icons.inbox_rounded, size: 40, color: cs.primary),
                  const SizedBox(height: 8),
                  const Text('Aucune étude pour le moment', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text('Complétez votre profil études pour recevoir des invitations ciblées.', textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
                  const SizedBox(height: 10),
                  OutlinedButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const StudyProfileScreen())), child: const Text('Mon profil études')),
                ]),
              ),
            if (invited.isNotEmpty) ...[SectionTitle('Invitations pour vous (${invited.length})'), for (final c in invited) _tile(c, cs)],
            if (others.isNotEmpty) ...[const SectionTitle('Études ouvertes'), for (final c in others) _tile(c, cs)],
          ] else ...[
            if (_parts == null && _partsError == null) const Center(child: Padding(padding: EdgeInsets.all(28), child: CircularProgressIndicator())),
            if (_partsError != null) SoftCard(child: Text(apiErrorLabel(_partsError!), style: TextStyle(color: cs.error))),
            if (_parts != null && _parts!.isEmpty) SoftCard(child: Text('Aucune participation pour le moment.', style: TextStyle(color: cs.onSurfaceVariant))),
            for (final p in _parts ?? const <StudyParticipation>[]) _part(p, cs),
          ],
        ]),
      ),
    );
  }

  Widget _tile(StudyCard c, ColorScheme cs) {
    return SoftCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.zero,
      onTap: () => _open(c),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (c.coverAssetId != null)
          Stack(children: [
            ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(20)), child: StudyImage(assetId: c.coverAssetId, width: double.infinity, height: 120)),
            if (c.invited) const Positioned(left: 12, top: 12, child: StatusChip('Invitation', Color(0xFF4F46E5), icon: Icons.mark_email_unread_rounded)),
          ]),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              SponsorAvatar(c.sponsor, size: 34),
              const SizedBox(width: 10),
              Expanded(child: Text(c.sponsor.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600, fontSize: 13))),
              if (c.invited && c.coverAssetId == null) const StatusChip('Invitation', Color(0xFF4F46E5)),
              const SizedBox(width: 6),
              StatusChip(c.kindLabel, cs.primary),
            ]),
            const SizedBox(height: 10),
            Text(c.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, height: 1.25)),
            if (c.summary != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(c.summary!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13, height: 1.35))),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 6, children: [
              StatusChip('~${c.estimatedMinutes} min', cs.onSurfaceVariant, icon: Icons.timer_outlined),
              StatusChip(endsLabel(c.endsAt), cs.onSurfaceVariant, icon: Icons.event_rounded),
              if (c.reward.enabled) StatusChip(c.reward.headline, const Color(0xFFDB2777), icon: rewardKindIcon(c.reward.kind)),
              if (c.participationStatus == 'started') const StatusChip('En cours', Color(0xFFF59E0B), icon: Icons.play_circle_outline_rounded),
              if (c.quotaLeft != null) StatusChip('${c.quotaLeft} place(s)', cs.onSurfaceVariant),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _part(StudyParticipation p, ColorScheme cs) {
    final label = switch (p.status) { 'completed' => 'Terminée', 'screened_out' => 'Hors cible', 'started' => 'En cours', _ => p.status };
    final col = switch (p.status) { 'completed' => const Color(0xFF22C55E), 'started' => const Color(0xFFF59E0B), _ => cs.onSurfaceVariant };
    return SoftCard(
      margin: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        SponsorAvatar(p.sponsor, size: 42),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
            Text('${p.sponsor.name} · ${p.kindLabel}', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 4, children: [
              StatusChip(label, col),
              if (p.reward != null) StatusChip(p.reward!.statusLabel, rewardStatusColor(p.reward!.status), icon: rewardKindIcon(p.reward!.kind)),
            ]),
          ]),
        ),
        if (p.finishedAt != null) Text(fmtDay(p.finishedAt!), style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
      ]),
    );
  }
}