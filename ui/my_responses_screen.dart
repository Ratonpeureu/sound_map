import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/api_survey.dart';
import '../core/models_survey.dart';
import '../core/util.dart';
import '../state/data_hub.dart';
import 'widgets.dart';

class MyResponsesScreen extends StatefulWidget {
  const MyResponsesScreen({super.key});
  @override
  State<MyResponsesScreen> createState() => _MyResponsesScreenState();
}

class _MyResponsesScreenState extends State<MyResponsesScreen> {
  static const _page = 30;
  List<MyResponse> _items = [];
  TrustView? _trust;
  bool _loading = true, _more = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DataHub>().ensure();
      _reload();
    });
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = context.read<ApiClient>();
    try {
      final r = await Future.wait([api.surveyMine(limit: _page), api.surveyTrust()]);
      _items = r[0] as List<MyResponse>;
      _trust = r[1] as TrustView;
      _more = _items.length == _page;
    } on ApiException catch (e) {
      _error = e.code;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadMore() async {
    try {
      final more = await context.read<ApiClient>().surveyMine(limit: _page, offset: _items.length);
      setState(() {
        _items = [..._items, ...more];
        _more = more.length == _page;
      });
    } catch (e) {
      if (mounted) showToast(context, errorMessage(e));
    }
  }

  void _open(MyResponse r) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
      builder: (_) => _DetailSheet(id: r.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cat = context.watch<DataHub>().catalog;
    final t = _trust;
    return Scaffold(
      appBar: AppBar(title: const Text('Mes réponses')),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
          if (t != null)
            SoftCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.shield_rounded, color: cs.primary),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('Votre fiabilité de répondant', style: TextStyle(fontWeight: FontWeight.w800))),
                ]),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 6, children: [
                  StatusChip(t.label, cs.primary),
                  StatusChip('Confiance ${t.band}', const Color(0xFF22C55E)),
                  if (t.trend != null) StatusChip(t.trend!, cs.onSurfaceVariant),
                  StatusChip('${t.responses} réponse(s)', cs.onSurfaceVariant),
                ]),
                if (t.trust != null) Padding(padding: const EdgeInsets.only(top: 10), child: ClipRRect(borderRadius: BorderRadius.circular(5), child: LinearProgressIndicator(minHeight: 8, value: t.trust!.clamp(0.0, 1.0)))),
                if (t.tip != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(t.tip!, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5, height: 1.3))),
              ]),
            ),
          const SectionTitle('Historique'),
          if (_loading && _items.isEmpty) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
          if (_error != null) SoftCard(child: Text(apiErrorLabel(_error!), style: TextStyle(color: cs.error))),
          if (!_loading && _items.isEmpty && _error == null)
            SoftCard(child: Text('Aucune réponse pour le moment.', style: TextStyle(color: cs.onSurfaceVariant))),
          for (final r in _items) _tile(r, cat?.domain(r.domain), cs),
          if (_more && _items.isNotEmpty) TextButton(onPressed: _loadMore, child: const Text('Charger plus')),
        ]),
      ),
    );
  }

  Widget _tile(MyResponse r, DataDomain? d, ColorScheme cs) {
    final col = qualityColor(r.status);
    final dc = d?.color ?? cs.primary;
    return SoftCard(
      margin: const EdgeInsets.only(bottom: 10),
      onTap: () => _open(r),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 40, height: 40, decoration: BoxDecoration(color: dc.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(13)), child: Icon(domainIcon(d?.icon), color: dc, size: 22)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(fmtDateTime(r.submittedAt), style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
            ]),
          ),
          if (r.score != null)
            ScoreRing(value: r.score!, color: col, size: 44, stroke: 5, child: Text('${(r.score! * 100).round()}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 4, children: [
          StatusChip(qualityLabel(r.status), col),
          if (r.needsEvidence) const StatusChip('Photo à ajouter', Color(0xFFF59E0B), icon: Icons.photo_camera_rounded),
          for (final x in r.reasons.take(2)) StatusChip(x.label, cs.onSurfaceVariant),
        ]),
      ]),
    );
  }
}

class _DetailSheet extends StatefulWidget {
  const _DetailSheet({required this.id});
  final String id;
  @override
  State<_DetailSheet> createState() => _DetailSheetState();
}

class _DetailSheetState extends State<_DetailSheet> {
  late final Future<ResponseDetail> _f = context.read<ApiClient>().surveyResponse(widget.id);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: FutureBuilder<ResponseDetail>(
        future: _f,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()));
          if (snap.hasError) return Padding(padding: const EdgeInsets.all(24), child: Text(errorMessage(snap.error!), style: TextStyle(color: cs.error)));
          final d = snap.data!;
          final col = qualityColor(d.status);
          return ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), shrinkWrap: true, children: [
            Row(children: [
              Expanded(child: Text(d.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 19))),
              StatusChip(qualityLabel(d.status), col),
            ]),
            if (d.submittedAt != null) Text(fmtDateTime(d.submittedAt!), style: TextStyle(color: cs.onSurfaceVariant)),
            if (d.subScores.isNotEmpty) ...[
              const SectionTitle('Détail du score'),
              for (final e in d.subScores.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    SizedBox(width: 110, child: Text(_subLabel(e.key), style: const TextStyle(fontSize: 12.5))),
                    Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(minHeight: 8, value: e.value.clamp(0.0, 1.0), color: col))),
                    SizedBox(width: 44, child: Text('${(e.value * 100).round()} %', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12))),
                  ]),
                ),
            ],
            if (d.reasons.isNotEmpty) ...[
              const SectionTitle('Raisons'),
              for (final r in d.reasons)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('• ${r.label}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    if (r.tip != null) Padding(padding: const EdgeInsets.only(left: 12), child: Text(r.tip!, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5))),
                  ]),
                ),
            ],
            const SectionTitle('Mes réponses'),
            for (final a in d.answers)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(flex: 5, child: Text(a.question, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5))),
                  const SizedBox(width: 8),
                  Expanded(flex: 4, child: Text(a.answer, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
                ]),
              ),
          ]);
        },
      ),
    );
  }

  String _subLabel(String k) => switch (k) {
        'consistency' => 'Cohérence',
        'timing' => 'Rythme',
        'effort' => 'Effort',
        'location' => 'Lieu',
        'peers' => 'Voisins',
        'reference' => 'Référence',
        'evidence' => 'Preuves',
        'reputation' => 'Réputation',
        'behavior' => 'Comportement',
        _ => k,
      };
}