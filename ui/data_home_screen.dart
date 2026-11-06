import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models_survey.dart';
import '../core/util.dart';
import '../state/data_hub.dart';
import 'data_map_screen.dart';
import 'my_responses_screen.dart';
import 'surveys_screen.dart';
import 'widgets.dart';

class DataHomeScreen extends StatefulWidget {
  const DataHomeScreen({super.key});
  @override
  State<DataHomeScreen> createState() => _DataHomeScreenState();
}

class _DataHomeScreenState extends State<DataHomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<DataHub>().ensure());
  }

  void _openDomain(DataDomain d) {
    final hub = context.read<DataHub>();
    final todo = hub.todoOf(d.key);
    final nav = Navigator.of(context);
    if (todo.isEmpty) {
      nav.push(MaterialPageRoute(builder: (_) => DataMapScreen(domain: d)));
      return;
    }
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _ChoiceSheet(
        domain: d,
        surveys: todo,
        stats: hub.summary?.items[d.key],
        onSurvey: (c) {
          Navigator.pop(context);
          nav.push(MaterialPageRoute(builder: (_) => SurveyFillScreen(card: c))).then((_) => hub.loadAvailable());
        },
        onMap: () {
          Navigator.pop(context);
          nav.push(MaterialPageRoute(builder: (_) => DataMapScreen(domain: d)));
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hub = context.watch<DataHub>();
    final cs = Theme.of(context).colorScheme;
    final cat = hub.catalog;
    final domains = cat == null
        ? <DataDomain>[]
        : ([...cat.domains]..sort((a, b) => hub.todo(b.key).compareTo(hub.todo(a.key))));
    final totalTodo = hub.available.length;
    return Scaffold(
      appBar: AppBar(title: const Text('Sunu Données')),
      body: RefreshIndicator(
        onRefresh: hub.refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: const LinearGradient(
                    colors: [Color(0xFF0B1F2A), Color(0xFF1D4ED8)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  totalTodo > 0 ? '$totalTodo enquête(s) à faire' : 'Cartographier la société',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
                ),
                const SizedBox(height: 4),
                Text(
                  totalTodo > 0
                      ? 'Quelques secondes chacune : choisissez le profil qui vous ressemble.'
                      : 'Choisissez un thème pour explorer la carte ou répondre quand une enquête s\'ouvre.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.8), height: 1.35, fontSize: 13),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFF0B1F2A), minimumSize: const Size.fromHeight(46)),
                      icon: const Icon(Icons.assignment_rounded),
                      label: const Text('Enquêtes'),
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SurveysScreen())).then((_) => hub.loadAvailable()),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54), minimumSize: const Size.fromHeight(46)),
                      icon: const Icon(Icons.history_rounded),
                      label: const Text('Mes réponses'),
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyResponsesScreen())),
                    ),
                  ),
                ]),
              ]),
            ),
            const SectionTitle('Thèmes'),
            if (hub.loading && cat == null)
              const Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator()))
            else if (cat == null)
              SoftCard(
                child: Row(children: [
                  Icon(Icons.cloud_off_rounded, color: cs.error),
                  const SizedBox(width: 12),
                  Expanded(child: Text(hub.error == null ? 'Indisponible' : apiErrorLabel(hub.error!), style: TextStyle(color: cs.error))),
                  TextButton(onPressed: hub.refresh, child: const Text('Réessayer')),
                ]),
              )
            else
              LayoutBuilder(builder: (ctx, c) {
                final w = (c.maxWidth - 12) / 2;
                return Wrap(spacing: 12, runSpacing: 12, children: [
                  for (final d in domains)
                    SizedBox(
                      width: w,
                      child: _DomainCard(domain: d, stats: hub.summary?.items[d.key], todo: hub.todo(d.key), onTap: () => _openDomain(d)),
                    ),
                ]);
              }),
            const SizedBox(height: 12),
            Text('Échantillon participatif : indicatif, ce n\'est pas un recensement.', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _DomainCard extends StatelessWidget {
  const _DomainCard({required this.domain, required this.todo, required this.onTap, this.stats});
  final DataDomain domain;
  final DataSummaryItem? stats;
  final int todo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = stats;
    final has = (s?.responses ?? 0) > 0;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: todo > 0 ? Border.all(color: domain.color, width: 1.6) : null,
      ),
      child: SoftCard(
        padding: const EdgeInsets.all(14),
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: domain.color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(14)),
              child: Icon(domainIcon(domain.icon), color: domain.color),
            ),
            const Spacer(),
            if (todo > 0) StatusChip('$todo à faire', domain.color, icon: Icons.edit_note_rounded),
          ]),
          const SizedBox(height: 10),
          Text(domain.label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 2),
          Text(domain.summary, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11.5, height: 1.3)),
          const SizedBox(height: 8),
          Text(
            has ? '${s!.responses} réponse(s) · ${s.zones} zone(s)' : 'Pas encore de données',
            style: TextStyle(color: has ? domain.color : cs.onSurfaceVariant, fontWeight: FontWeight.w700, fontSize: 11.5),
          ),
          if (s?.lastAt != null) Text('Dernière : ${fmtAgo(s!.lastAt!)}', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 10.5)),
        ]),
      ),
    );
  }
}

class _ChoiceSheet extends StatelessWidget {
  const _ChoiceSheet({required this.domain, required this.surveys, required this.onSurvey, required this.onMap, this.stats});
  final DataDomain domain;
  final List<SurveyCard> surveys;
  final DataSummaryItem? stats;
  final void Function(SurveyCard) onSurvey;
  final VoidCallback onMap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
        Row(children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: domain.color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(15)),
            child: Icon(domainIcon(domain.icon), color: domain.color),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(domain.label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20))),
        ]),
        const SizedBox(height: 14),
        Text('À faire', style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700, fontSize: 12)),
        const SizedBox(height: 6),
        for (final c in surveys)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(colors: [domain.color.withValues(alpha: 0.16), domain.color.withValues(alpha: 0.04)]),
              border: Border.all(color: domain.color.withValues(alpha: 0.5)),
            ),
            child: ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              leading: Icon(Icons.edit_note_rounded, color: domain.color, size: 30),
              title: Text(c.title, style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text('~${c.estimatedMinutes} min · ${c.nQuestions} question(s)'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => onSurvey(c),
            ),
          ),
        const SizedBox(height: 4),
        Text('Ou', style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700, fontSize: 12)),
        const SizedBox(height: 6),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          icon: const Icon(Icons.map_rounded),
          label: Text((stats?.responses ?? 0) > 0 ? 'Explorer la carte (${stats!.responses} réponses)' : 'Explorer la carte'),
          onPressed: onMap,
        ),
      ]),
    );
  }
}