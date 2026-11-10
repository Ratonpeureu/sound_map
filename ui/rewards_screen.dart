import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/api_study.dart';
import '../core/models_study.dart';
import '../core/util.dart';
import '../state/studies_controller.dart';
import 'widgets.dart';

class RewardsScreen extends StatefulWidget {
  const RewardsScreen({super.key});
  @override
  State<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends State<RewardsScreen> {
  RewardsData? _d;
  bool _loading = true;
  String? _error;
  String _filter = 'all';

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
      final d = await context.read<ApiClient>().studyRewards();
      if (mounted) setState(() => _d = d);
      context.read<StudiesController>().refreshRewards();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.code);
    }
    if (mounted) setState(() => _loading = false);
  }

  bool _match(RewardItem r) => switch (_filter) {
        'ok' => r.status == 'granted' || r.status == 'delivered',
        'wait' => r.status == 'pending' || r.status == 'entered',
        'no' => r.status == 'refused' || r.status == 'revoked' || r.status == 'expired',
        _ => true,
      };

  void _open(RewardItem r) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
      builder: (_) => _RewardSheet(id: r.id),
    ).whenComplete(_load);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final d = _d;
    final items = d?.items.where(_match).toList() ?? [];
    return Scaffold(
      appBar: AppBar(title: const Text('Mes récompenses')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
          if (_loading && d == null) const Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator())),
          if (_error != null) SoftCard(child: Text(apiErrorLabel(_error!), style: TextStyle(color: cs.error))),
          if (d != null) ...[
            SoftCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  ScoreRing(value: (d.s('avg_score')).toDouble(), color: cs.primary, size: 80, stroke: 9, child: Text('${(d.s('avg_score') * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Score moyen aux études', style: TextStyle(fontWeight: FontWeight.w800)),
                      Text('${d.s('participations')} participation(s) valide(s)', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                    ]),
                  ),
                ]),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  StatusChip('${d.s('granted') + d.s('delivered')} obtenue(s)', const Color(0xFF22C55E), icon: Icons.check_circle_rounded),
                  StatusChip('${d.s('pending') + d.s('entered')} en attente', const Color(0xFFF59E0B), icon: Icons.hourglass_top_rounded),
                  StatusChip('${d.s('refused')} refusée(s)', const Color(0xFFEF4444), icon: Icons.block_rounded),
                  StatusChip('${d.s('revoked') + d.s('expired')} perdue(s)', const Color(0xFF94A3B8), icon: Icons.report_gmailerrorred_rounded),
                ]),
                const SizedBox(height: 12),
                Wrap(spacing: 14, runSpacing: 6, children: [
                  if (d.s('points_total') > 0) Text('+${d.s('points_total').round()} points', style: const TextStyle(fontWeight: FontWeight.w800)),
                  if (d.s('credits_total') > 0) Text('+${d.s('credits_total')} crédits', style: const TextStyle(fontWeight: FontWeight.w800)),
                  if (d.s('cash_total') > 0) Text('${d.s('cash_total').round()} FCFA reçus ou à recevoir', style: const TextStyle(fontWeight: FontWeight.w800)),
                ]),
              ]),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, children: [
              for (final f in const [('all', 'Toutes'), ('ok', 'Obtenues'), ('wait', 'En attente'), ('no', 'Refusées / perdues')])
                ChoiceChip(label: Text(f.$2), selected: _filter == f.$1, onSelected: (_) => setState(() => _filter = f.$1)),
            ]),
            const SizedBox(height: 8),
            if (items.isEmpty) SoftCard(child: Text('Aucune récompense ici pour le moment.', style: TextStyle(color: cs.onSurfaceVariant))),
            for (final r in items) _tile(r, cs),
          ],
        ]),
      ),
    );
  }

  Widget _tile(RewardItem r, ColorScheme cs) {
    final col = rewardStatusColor(r.status);
    return SoftCard(
      margin: const EdgeInsets.only(bottom: 10),
      onTap: () => _open(r),
      child: Row(children: [
        Container(width: 46, height: 46, decoration: BoxDecoration(color: col.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(15)), child: Icon(rewardKindIcon(r.kind), color: col)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r.headline, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
            Text([if (r.studyTitle != null) r.studyTitle!, if (r.sponsorName != null) r.sponsorName!].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 4, children: [
              StatusChip(r.statusLabel, col),
              if (r.needsClaim) const StatusChip('Coordonnées à renseigner', Color(0xFFF59E0B), icon: Icons.edit_note_rounded),
              if (r.reasonLabel != null && (r.status == 'refused' || r.status == 'revoked' || r.status == 'expired')) StatusChip(r.reasonLabel!, cs.error),
            ]),
          ]),
        ),
        if (r.score != null) ScoreRing(value: r.score!, color: col, size: 42, stroke: 5, child: Text('${(r.score! * 100).round()}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11))),
      ]),
    );
  }
}

class _RewardSheet extends StatefulWidget {
  const _RewardSheet({required this.id});
  final String id;
  @override
  State<_RewardSheet> createState() => _RewardSheetState();
}

class _RewardSheetState extends State<_RewardSheet> {
  RewardDetail? _d;
  String? _error;
  bool _busy = false;
  final _phone = TextEditingController(), _name = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _phone.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await context.read<ApiClient>().studyReward(widget.id);
      if (mounted) {
        setState(() => _d = d);
        if (d.phone != null && _phone.text.isEmpty) _phone.text = d.phone!;
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.code);
    }
  }

  Future<void> _claim() async {
    if (_phone.text.trim().length < 6) {
      showToast(context, apiErrorLabel('invalid_phone'));
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<ApiClient>().studyClaim(widget.id, _phone.text.trim(), _name.text.trim());
      if (mounted) showToast(context, 'Coordonnées enregistrées. Vous serez contacté pour la remise.');
      await _load();
    } on ApiException catch (e) {
      if (mounted) showToast(context, apiErrorLabel(e.code));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final d = _d;
    if (d == null) return Padding(padding: const EdgeInsets.all(40), child: Center(child: _error == null ? const CircularProgressIndicator() : Text(apiErrorLabel(_error!), style: TextStyle(color: cs.error))));
    final r = d.item;
    final col = rewardStatusColor(r.status);
    return SafeArea(
      child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [
        Row(children: [
          Icon(rewardKindIcon(r.kind), color: col, size: 34),
          const SizedBox(width: 12),
          Expanded(child: Text(r.headline, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 19))),
          StatusChip(r.statusLabel, col),
        ]),
        const SizedBox(height: 6),
        Text([if (r.studyTitle != null) r.studyTitle!, if (r.sponsorName != null) 'par ${r.sponsorName}'].join(' · '), style: TextStyle(color: cs.onSurfaceVariant)),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 6, children: [
          if (r.kindLabel != null) StatusChip(r.kindLabel!, cs.primary),
          if (r.mode == 'lottery') const StatusChip('Tirage au sort', Color(0xFF7C3AED)),
          if (r.score != null) StatusChip('Score ${(r.score! * 100).round()} %', const Color(0xFF22C55E), icon: Icons.verified_rounded),
          if (r.deliveredAt != null) StatusChip('Remise le ${fmtDay(r.deliveredAt!)}', cs.onSurfaceVariant),
          if (r.validUntil != null) StatusChip("Valable jusqu'au ${fmtDay(r.validUntil!)}", cs.onSurfaceVariant),
        ]),
        if (r.reasonLabel != null) ...[
          const SectionTitle('Motif'),
          Text(r.reasonLabel!, style: TextStyle(color: cs.error, fontWeight: FontWeight.w700)),
          if (r.reasonText != null) Text(r.reasonText!, style: TextStyle(color: cs.onSurfaceVariant)),
        ],
        if (r.code != null) ...[
          const SectionTitle('Votre code'),
          SoftCard(
            child: Row(children: [
              Expanded(child: SelectableText(r.code!, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, letterSpacing: 1.2))),
              IconButton(icon: const Icon(Icons.copy_rounded), onPressed: () {
                Clipboard.setData(ClipboardData(text: r.code!));
                showToast(context, 'Code copié');
              }),
            ]),
          ),
        ],
        if (r.note != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(r.note!, style: TextStyle(color: cs.onSurfaceVariant))),
        if (d.instructions != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(d.instructions!, style: const TextStyle(height: 1.4))),
        if (r.needsClaim) ...[
          const SectionTitle('Recevoir ma récompense'),
          if (r.claimDeadlineAt != null) Text("À renseigner avant le ${fmtDay(r.claimDeadlineAt!)}, sinon la récompense expire.", style: TextStyle(color: cs.error, fontSize: 12.5)),
          const SizedBox(height: 8),
          TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: d.contactLabel ?? 'Numéro de téléphone', border: const OutlineInputBorder(), prefixIcon: const Icon(Icons.phone_rounded))),
          const SizedBox(height: 10),
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nom du bénéficiaire (facultatif)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.person_outline_rounded))),
          const SizedBox(height: 10),
          FilledButton(onPressed: _busy ? null : _claim, child: _busy ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : const Text('Envoyer mes coordonnées')),
        ],
        const SectionTitle('Règles de cette récompense'),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: Column(children: [
            for (final s in d.rules)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                leading: Icon(ruleIcon(s.icon), color: cs.primary),
                title: Text(s.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                childrenPadding: const EdgeInsets.only(bottom: 8),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [for (final i in s.items) Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text('• $i', style: const TextStyle(height: 1.4, fontSize: 13.5)))],
              ),
          ]),
        ),
      ]),
    );
  }
}