import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/api_study.dart';
import '../core/models_study.dart';
import '../core/util.dart';
import '../state/studies_controller.dart';
import 'study_detail_screen.dart';
import 'study_widgets.dart';
import 'widgets.dart';

class SponsorScreen extends StatefulWidget {
  const SponsorScreen({super.key, required this.sponsorId});
  final String sponsorId;
  @override
  State<SponsorScreen> createState() => _SponsorScreenState();
}

class _SponsorScreenState extends State<SponsorScreen> {
  late final Future<SponsorFull> _f = context.read<ApiClient>().studySponsor(widget.sponsorId);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final studies = context.watch<StudiesController>().list.where((s) => s.sponsor.id == widget.sponsorId).toList();
    return Scaffold(
      appBar: AppBar(title: const Text("Profil de l'initiateur")),
      body: FutureBuilder<SponsorFull>(
        future: _f,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) return Center(child: Text(errorMessage(snap.error!), style: TextStyle(color: cs.error)));
          final s = snap.data!;
          final b = s.brief;
          return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 40), children: [
            if (s.coverAssetId != null) StudyImage(assetId: s.coverAssetId, width: double.infinity, height: 150, radius: 22),
            const SizedBox(height: 14),
            Row(children: [
              SponsorAvatar(b, size: 72),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(b.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 21)),
                  const SizedBox(height: 4),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    StatusChip(b.kindLabel, cs.primary),
                    if (b.verified) const StatusChip('Vérifié', Color(0xFF2563EB), icon: Icons.verified_rounded),
                    if (b.sector != null) StatusChip(b.sector!, cs.onSurfaceVariant),
                  ]),
                ]),
              ),
            ]),
            if (s.tagline != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(s.tagline!, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
            if (s.description != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(s.description!, style: const TextStyle(height: 1.5))),
            if (s.activities.isNotEmpty) ...[
              const SectionTitle('Activités'),
              Wrap(spacing: 8, runSpacing: 8, children: [for (final a in s.activities) Chip(label: Text(a))]),
            ],
            const SectionTitle('Informations'),
            SoftCard(
              child: Column(children: [
                if (s.city != null || s.country != null) _row(cs, Icons.place_rounded, 'Localisation', [s.city, s.country].whereType<String>().join(', ')),
                if (s.website != null) _row(cs, Icons.language_rounded, 'Site web', s.website!, selectable: true),
                if (s.contactPublic != null) _row(cs, Icons.alternate_email_rounded, 'Contact', s.contactPublic!, selectable: true),
                for (final e in s.facts.entries) _row(cs, Icons.info_outline_rounded, e.key, e.value),
                if (s.memberSince != null) _row(cs, Icons.event_available_rounded, 'Sur SunuSound depuis', fmtDay(s.memberSince!)),
                _row(cs, Icons.campaign_rounded, 'Études ouvertes', '${s.studiesCount}'),
              ]),
            ),
            if (studies.isNotEmpty) ...[
              const SectionTitle('Ses études pour vous'),
              for (final c in studies)
                SoftCard(
                  margin: const EdgeInsets.only(bottom: 8),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => StudyDetailScreen(card: c))),
                  child: Row(children: [
                    Expanded(child: Text(c.title, style: const TextStyle(fontWeight: FontWeight.w700))),
                    if (c.reward.enabled) StatusChip(c.reward.headline, const Color(0xFFDB2777)),
                    const Icon(Icons.chevron_right_rounded),
                  ]),
                ),
            ],
          ]);
        },
      ),
    );
  }

  Widget _row(ColorScheme cs, IconData i, String k, String v, {bool selectable = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(i, size: 18, color: cs.primary),
          const SizedBox(width: 10),
          SizedBox(width: 120, child: Text(k, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13))),
          Expanded(child: selectable ? SelectableText(v, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)) : Text(v, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
        ]),
      );
}