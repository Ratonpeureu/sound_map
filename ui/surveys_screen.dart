import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../core/api.dart';
import '../core/api_survey.dart';
import '../core/models_survey.dart';
import '../core/util.dart';
import '../state/data_hub.dart';
import '../state/session_controller.dart';
import 'my_responses_screen.dart';
import 'profile_avatar.dart';
import 'survey_result_screen.dart';
import 'widgets.dart';

// ============================================================================ liste
class SurveysScreen extends StatefulWidget {
  const SurveysScreen({super.key});
  @override
  State<SurveysScreen> createState() => _SurveysScreenState();
}

class _SurveysScreenState extends State<SurveysScreen> {
  List<SurveyCard>? _list;
  String? _error;
  bool _loading = true;
  Position? _pos;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DataHub>().ensure();
      _load();
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final session = context.read<SessionController>();
    if (session.consentOf('geolocation')) {
      try {
        if (await ensureLocationPermission()) {
          _pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 8)));
        }
      } catch (_) {}
    }
    try {
      final r = await context.read<ApiClient>().surveysAvailable(_pos?.latitude, _pos?.longitude);
      if (mounted) setState(() => _list = r);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.code);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _allow() async {
    final s = context.read<SessionController>();
    try {
      if (!s.consentOf('survey_data')) await s.setConsent('survey_data', true);
      if (!s.consentOf('geolocation')) await s.setConsent('geolocation', true);
      await _load();
    } catch (e) {
      if (mounted) showToast(context, errorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = context.watch<SessionController>();
    final cat = context.watch<DataHub>().catalog;
    final okConsent = s.consentOf('survey_data') && s.consentOf('geolocation');
    return Scaffold(
      appBar: AppBar(title: const Text('Enquêtes'), actions: [
        IconButton(
          tooltip: 'Mes réponses',
          icon: const Icon(Icons.history_rounded),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyResponsesScreen())),
        ),
      ]),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), physics: const AlwaysScrollableScrollPhysics(), children: [
          if (!okConsent)
            SoftCard(
              margin: const EdgeInsets.only(bottom: 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Autorisation nécessaire', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(
                  'Vos réponses sont anonymisées et agrégées par zone ; seule la zone de votre position est conservée.',
                  style: TextStyle(color: cs.onSurfaceVariant, height: 1.35, fontSize: 13),
                ),
                const SizedBox(height: 12),
                FilledButton(onPressed: _allow, child: const Text('Autoriser')),
              ]),
            ),
          if (_loading) const Center(child: Padding(padding: EdgeInsets.all(28), child: CircularProgressIndicator())),
          if (_error != null) SoftCard(child: Text(apiErrorLabel(_error!), style: TextStyle(color: cs.error))),
          if (!_loading && _error == null && (_list?.isEmpty ?? true))
            SoftCard(
              padding: const EdgeInsets.all(24),
              child: Column(children: [
                Icon(Icons.assignment_turned_in_rounded, size: 40, color: cs.primary),
                const SizedBox(height: 8),
                const Text('Tout est à jour', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('Une même enquête ne se refait qu\'après un délai de repos.', textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
              ]),
            ),
          for (final c in _list ?? const <SurveyCard>[]) _card(c, cat?.domain(c.domain), cs),
        ]),
      ),
    );
  }

  Widget _card(SurveyCard c, DataDomain? d, ColorScheme cs) {
    final col = d?.color ?? cs.primary;
    return SoftCard(
      margin: const EdgeInsets.only(bottom: 12),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SurveyFillScreen(card: c))).then((_) {
        _load();
        context.read<DataHub>().loadAvailable();
      }),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              gradient: LinearGradient(colors: [col.withValues(alpha: 0.28), col.withValues(alpha: 0.10)]),
            ),
            child: Icon(domainIcon(d?.icon), color: col),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              Text(d?.label ?? c.domain, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
            ]),
          ),
          const Icon(Icons.chevron_right_rounded),
        ]),
        if (c.description != null && c.description!.isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 8), child: Text(c.description!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13, height: 1.35))),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 6, children: [
          StatusChip('~${c.estimatedMinutes} min', col, icon: Icons.timer_outlined),
          StatusChip('${c.nQuestions} question(s)', cs.onSurfaceVariant),
          if (c.needsEvidence) const StatusChip('Photo', Color(0xFFF59E0B), icon: Icons.photo_camera_rounded),
          if (c.need >= 0.6) const StatusChip('Besoin ici', Color(0xFF16A34A), icon: Icons.near_me_rounded),
        ]),
      ]),
    );
  }
}

// ============================================================================ questionnaire
class SurveyFillScreen extends StatefulWidget {
  const SurveyFillScreen({super.key, required this.card});
  final SurveyCard card;
  @override
  State<SurveyFillScreen> createState() => _SurveyFillScreenState();
}

class _SurveyFillScreenState extends State<SurveyFillScreen> {
  SurveyDefinition? _def;
  String? _error;
  bool _loading = true, _sending = false;
  DateTime _started = DateTime.now().toUtc();
  String _clientId = const Uuid().v4();
  final Map<String, Set<String>> _picked = {};
  final Set<String> _none = {};
  final Map<String, dynamic> _values = {};
  final TextEditingController _unit = TextEditingController();
  int _step = 0;
  Position? _pos;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _unit.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final session = context.read<SessionController>();
    if (_pos == null && session.consentOf('geolocation')) {
      try {
        if (await ensureLocationPermission()) {
          _pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 8)));
        }
      } catch (_) {}
    }
    try {
      final d = await context.read<ApiClient>().surveyGet(widget.card.id, _pos?.latitude, _pos?.longitude);
      if (!mounted) return;
      setState(() {
        _def = d;
        _picked.clear();
        _none.clear();
        _values.clear();
        _step = 0;
        _started = DateTime.now().toUtc();
        _clientId = const Uuid().v4();
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.code);
    }
    if (mounted) setState(() => _loading = false);
  }

  // ------------------------------------------------------------------ validation
  String? _valid(SurveyQuestion q, dynamic v) {
    if (q.kind == 'number' && v is num) {
      if (q.min != null && v < q.min!) return 'Minimum ${q.min}';
      if (q.max != null && v > q.max!) return 'Maximum ${q.max}';
    }
    return null;
  }

  bool _slotOk(SurveySlot s) {
    final qs = _def!.questionsOf(s.key);
    final profileMode = s.mode == 'profile' && s.profiles.isNotEmpty;
    final valuesOk = qs.every((q) => !_values.containsKey(q.key) || _valid(q, _values[q.key]) == null);
    if (profileMode && (_picked[s.key]?.isNotEmpty ?? false) && !_none.contains(s.key)) return valuesOk;
    if (profileMode && !_none.contains(s.key)) return false;
    return valuesOk && qs.every((q) => !q.required || _values.containsKey(q.key));
  }

  void _setValue(String key, dynamic v) => setState(() => v == null ? _values.remove(key) : _values[key] = v);

  void _togglePick(SurveySlot s, SurveyProfile p) {
    setState(() {
      _none.remove(s.key);
      final set = _picked.putIfAbsent(s.key, () => <String>{});
      if (set.contains(p.id)) {
        set.remove(p.id);
      } else {
        if (!s.multi) set.clear();
        set.add(p.id);
      }
    });
  }

  void _toggleNone(SurveySlot s) {
    setState(() {
      if (_none.contains(s.key)) {
        _none.remove(s.key);
      } else {
        _none.add(s.key);
        _picked[s.key]?.clear();
      }
    });
  }

  List<SurveyQuestion> _evidenceQs() => _def!.questions
      .where((q) => q.evidence != 'none' && (_values.containsKey(q.key) || ((_picked[q.slot]?.isNotEmpty ?? false) && !_none.contains(q.slot))))
      .toList();

  // ------------------------------------------------------------------ envoi
  Future<void> _send() async {
    final def = _def!;
    final s = context.read<SessionController>();
    if (!s.consentOf('survey_data') || !s.consentOf('geolocation')) {
      showToast(context, apiErrorLabel('survey_consent_required'));
      return;
    }
    setState(() => _sending = true);
    try {
      if (!await ensureLocationPermission()) throw ApiException(null, 'location_denied');
      final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)));
      final picks = <String, dynamic>{}, overrides = <String, dynamic>{}, direct = <String, dynamic>{};
      for (final sl in def.slots) {
        final qs = def.questionsOf(sl.key);
        final isNone = _none.contains(sl.key);
        final ids = _picked[sl.key] ?? <String>{};
        if (isNone) {
          picks[sl.key] = {'profile_ids': <String>[], 'none': true};
          for (final q in qs) {
            if (_values.containsKey(q.key)) direct[q.key] = _values[q.key];
          }
        } else if (sl.mode == 'profile' && ids.isNotEmpty) {
          picks[sl.key] = {'profile_ids': ids.toList(), 'none': false};
          for (final q in qs) {
            if (_values.containsKey(q.key)) overrides[q.key] = _values[q.key];
          }
        } else {
          for (final q in qs) {
            if (_values.containsKey(q.key)) direct[q.key] = _values[q.key];
          }
        }
      }
      final ack = await context.read<ApiClient>().surveySubmit({
        'client_response_id': _clientId,
        'survey_id': def.id,
        'survey_version': def.version,
        'started_at': _started.toIso8601String(),
        'submitted_at': DateTime.now().toUtc().toIso8601String(),
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'gps_accuracy_m': pos.accuracy,
        if (_unit.text.trim().isNotEmpty) 'unit_ref': _unit.text.trim(),
        'picks': picks,
        'overrides': overrides,
        'direct': direct,
      });
      if (!mounted) return;
      context.read<DataHub>().loadAvailable();
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => SurveyResultScreen(ack: ack, def: def, evidenceQuestions: _evidenceQs()),
      ));
    } on ApiException catch (e) {
      await _handle(e);
    } catch (_) {
      if (mounted) showToast(context, apiErrorLabel('gps_unavailable'));
    }
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _handle(ApiException e) async {
    if (!mounted) return;
    final def = _def!;
    if (e.code == 'inconsistent_answers') {
      final rules = ((e.detail is Map ? e.detail['rules'] : null) as List?) ?? const [];
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          icon: const Icon(Icons.rule_rounded),
          title: const Text('Réponses incohérentes'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final r in rules) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('• ${r['message']}')),
          ]),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Corriger'))],
        ),
      );
      setState(() => _step = 0);
    } else if (e.code == 'missing_answers') {
      final keys = ((e.detail is Map ? e.detail['questions'] : null) as List?)?.cast<String>() ?? const <String>[];
      final qs = def.questions.where((q) => keys.contains(q.key)).toList();
      if (qs.isNotEmpty) {
        final idx = def.slots.indexWhere((s) => s.key == qs.first.slot);
        if (idx >= 0) setState(() => _step = idx);
      }
      showToast(context, 'Questions obligatoires : ${qs.map((q) => q.title).take(3).join(', ')}');
    } else if (e.code == 'survey_version_changed') {
      showToast(context, apiErrorLabel(e.code));
      await _load();
    } else {
      showToast(context, apiErrorLabel(e.code));
    }
  }

  // ------------------------------------------------------------------ UI
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cat = context.watch<DataHub>().catalog;
    final dom = cat?.domain(widget.card.domain);
    final color = dom?.color ?? cs.primary;
    final def = _def;
    if (_loading || def == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.card.title)),
        body: Center(
          child: _loading
              ? const CircularProgressIndicator()
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_error == null ? 'Indisponible' : apiErrorLabel(_error!), textAlign: TextAlign.center, style: TextStyle(color: cs.error)),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _load, child: const Text('Réessayer')),
                  ]),
                ),
        ),
      );
    }
    final total = def.slots.length + 1;
    final last = _step == def.slots.length;
    final ok = last ? true : _slotOk(def.slots[_step]);
    return Scaffold(
      appBar: AppBar(
        title: Text(def.card.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: (_step + 1) / total),
            duration: const Duration(milliseconds: 300),
            builder: (_, v, __) => LinearProgressIndicator(minHeight: 4, value: v, color: color),
          ),
        ),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(position: Tween(begin: const Offset(0.04, 0), end: Offset.zero).animate(anim), child: child),
          ),
          child: Column(
            key: ValueKey(_step),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Étape ${_step + 1} sur $total', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
              const SizedBox(height: 4),
              if (last) ..._review(def, dom, color, cs) else ..._slotPage(def, def.slots[_step], dom, color, cs),
            ],
          ),
        ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(children: [
            if (_step > 0) ...[
              Expanded(child: OutlinedButton(onPressed: _sending ? null : () => setState(() => _step--), child: const Text('Retour'))),
              const SizedBox(width: 12),
            ],
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: (!ok || _sending) ? null : () => last ? _send() : setState(() => _step++),
                child: _sending
                    ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                    : Text(last ? 'Envoyer ma réponse' : 'Suivant'),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  List<Widget> _slotPage(SurveyDefinition def, SurveySlot s, DataDomain? dom, Color color, ColorScheme cs) {
    final qs = def.questionsOf(s.key);
    final profileMode = s.mode == 'profile' && s.profiles.isNotEmpty;
    final picked = _picked[s.key] ?? <String>{};
    final isNone = _none.contains(s.key);
    final chosen = s.profiles.where((p) => picked.contains(p.id)).toList();
    String? hintFor(SurveyQuestion q) {
      for (final p in chosen) {
        for (final x in p.summary) {
          if (x.question == q.title) return 'Profil : ${x.answer}';
        }
      }
      return null;
    }

    final out = <Widget>[
      Text(s.label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 22, letterSpacing: -0.3)),
      if (s.help != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(s.help!, style: TextStyle(color: cs.onSurfaceVariant, height: 1.35))),
      const SizedBox(height: 14),
    ];
    if (profileMode) {
      out.add(Text(s.multi ? 'Choisissez un ou plusieurs profils qui vous ressemblent' : 'Lequel vous ressemble le plus ?', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)));
      out.add(const SizedBox(height: 8));
      for (final p in s.profiles) {
        out.add(_ProfileTile(
          profile: p,
          domain: widget.card.domain,
          fallback: domainIcon(dom?.icon),
          selected: picked.contains(p.id),
          multi: s.multi,
          color: color,
          onTap: () => _togglePick(s, p),
        ));
      }
      if (chosen.isNotEmpty && qs.any((q) => q.allowOverride)) {
        out.add(Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Un détail est différent ?', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('Facultatif : ne corrigez que ce qui change.', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
            children: [
              for (final q in qs.where((q) => q.allowOverride))
                _QField(key: ValueKey('ov_${q.key}'), q: q, value: _values[q.key], hint: hintFor(q), color: color, showRequired: false, onChanged: (v) => _setValue(q.key, v)),
            ],
          ),
        ));
      }
      if (s.allowNone) {
        out.add(const SizedBox(height: 4));
        out.add(_NoneTile(selected: isNone, onTap: () => _toggleNone(s)));
      }
    }
    if (!profileMode || isNone) {
      if (isNone) {
        out.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text('Répondez directement : cela nous aide à créer de meilleurs profils.', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
        ));
      }
      for (final q in qs) {
        out.add(_QField(key: ValueKey('d_${q.key}'), q: q, value: _values[q.key], color: color, showRequired: true, onChanged: (v) => _setValue(q.key, v)));
      }
    }
    return out;
  }

  List<Widget> _review(SurveyDefinition def, DataDomain? dom, Color color, ColorScheme cs) {
    final session = context.watch<SessionController>();
    final unitHint = switch (def.unit) {
      'person' => 'Repère de la personne (facultatif)',
      'household' => 'Nom ou repère du ménage (facultatif)',
      'dwelling' => 'Repère du logement (facultatif)',
      'enterprise' => 'Nom de l\'entreprise (facultatif)',
      'farm' => 'Nom de l\'exploitation (facultatif)',
      'facility' => 'Nom de la structure (facultatif)',
      _ => 'Nom du quartier ou de la communauté (facultatif)',
    };
    return [
      const Text('Vérifiez et envoyez', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
      const SizedBox(height: 12),
      for (final s in def.slots)
        Builder(builder: (_) {
          final chosen = _none.contains(s.key) ? <SurveyProfile>[] : s.profiles.where((p) => (_picked[s.key] ?? {}).contains(p.id)).toList();
          return SoftCard(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            onTap: () => setState(() => _step = def.slots.indexOf(s)),
            child: Row(children: [
              if (chosen.isNotEmpty)
                ProfileAvatar(profile: chosen.first, domain: widget.card.domain, color: color, fallback: domainIcon(dom?.icon), size: 44)
              else
                Icon(Icons.edit_note_rounded, color: color, size: 36),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(chosen.isEmpty ? 'Réponses directes' : chosen.map((p) => p.label).join(' + '), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
                ]),
              ),
              const Icon(Icons.edit_outlined, size: 18),
            ]),
          );
        }),
      const SizedBox(height: 8),
      TextField(
        controller: _unit,
        maxLength: 120,
        decoration: InputDecoration(labelText: unitHint, helperText: 'Évite les doublons : jamais affiché publiquement.', border: const OutlineInputBorder()),
      ),
      if (def.card.needsEvidence)
        Row(children: [
          const Icon(Icons.photo_camera_rounded, size: 18, color: Color(0xFFF59E0B)),
          const SizedBox(width: 8),
          Expanded(child: Text('Une photo vous sera demandée juste après l\'envoi (30 minutes).', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5))),
        ]),
      if (!session.consentOf('survey_data') || !session.consentOf('geolocation'))
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('J\'autorise l\'utilisation de mes réponses et de ma zone', style: TextStyle(fontSize: 13)),
          value: false,
          onChanged: (_) async {
            try {
              if (!session.consentOf('survey_data')) await session.setConsent('survey_data', true);
              if (!session.consentOf('geolocation')) await session.setConsent('geolocation', true);
            } catch (e) {
              if (mounted) showToast(context, errorMessage(e));
            }
          },
        ),
    ];
  }
}

// ============================================================================ carte profil
class _ProfileTile extends StatefulWidget {
  const _ProfileTile({required this.profile, required this.domain, required this.fallback, required this.selected, required this.multi, required this.color, required this.onTap});
  final SurveyProfile profile;
  final String domain;
  final IconData fallback;
  final bool selected, multi;
  final Color color;
  final VoidCallback onTap;
  @override
  State<_ProfileTile> createState() => _ProfileTileState();
}

class _ProfileTileState extends State<_ProfileTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = widget.profile, color = widget.color, sel = widget.selected;
    final rows = _open ? p.summary : p.summary.take(3).toList();
    final chips = p.axes.values.where((v) => v.trim().isNotEmpty).take(3).toList();
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: sel ? LinearGradient(colors: [color.withValues(alpha: 0.18), color.withValues(alpha: 0.05)], begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
        color: sel ? null : cs.surfaceContainerHigh,
        border: Border.all(color: sel ? color : cs.outlineVariant.withValues(alpha: 0.5), width: sel ? 2 : 1),
        boxShadow: sel ? [BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 14, offset: const Offset(0, 5))] : null,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              AnimatedScale(
                scale: sel ? 1.06 : 1,
                duration: const Duration(milliseconds: 220),
                child: ProfileAvatar(profile: p, domain: widget.domain, color: color, fallback: widget.fallback, size: 62),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, height: 1.2)),
                  if (p.description != null && p.description!.isNotEmpty)
                    Padding(padding: const EdgeInsets.only(top: 2), child: Text(p.description!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12, height: 1.3))),
                  if (chips.isNotEmpty || p.supportShare != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Wrap(spacing: 5, runSpacing: 4, children: [
                        for (final c in chips)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                            child: Text(c, style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w700)),
                          ),
                        if (p.supportShare != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
                            child: Text('${(p.supportShare! * 100).round()} % des réponses', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 10.5)),
                          ),
                      ]),
                    ),
                ]),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: Icon(
                  sel ? Icons.check_circle_rounded : (widget.multi ? Icons.add_circle_outline_rounded : Icons.radio_button_unchecked_rounded),
                  key: ValueKey(sel),
                  color: sel ? color : cs.onSurfaceVariant,
                ),
              ),
            ]),
            if (p.summary.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: cs.surface.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(14)),
                child: Column(children: [
                  for (final x in rows)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(flex: 5, child: Text(x.question, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11.5))),
                        const SizedBox(width: 8),
                        Expanded(flex: 4, child: Text(x.answer, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11.5))),
                      ]),
                    ),
                  if (p.summary.length > 3)
                    Align(
                      alignment: Alignment.centerRight,
                      child: GestureDetector(
                        onTap: () => setState(() => _open = !_open),
                        child: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(_open ? 'Réduire' : '+ ${p.summary.length - 3} autre(s)', style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11.5)),
                        ),
                      ),
                    ),
                ]),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

class _NoneTile extends StatelessWidget {
  const _NoneTile({required this.selected, required this.onTap});
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: selected ? cs.primary : cs.outlineVariant, width: selected ? 2 : 1),
        color: selected ? cs.primary.withValues(alpha: 0.08) : null,
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        leading: Icon(Icons.edit_note_rounded, color: selected ? cs.primary : cs.onSurfaceVariant),
        title: const Text('Aucun ne me correspond', style: TextStyle(fontWeight: FontWeight.w700)),
        subtitle: const Text('Je réponds directement'),
        onTap: onTap,
      ),
    );
  }
}

// ============================================================================ champs
class _QField extends StatefulWidget {
  const _QField({super.key, required this.q, required this.value, required this.onChanged, required this.showRequired, this.hint, this.color});
  final SurveyQuestion q;
  final dynamic value;
  final ValueChanged<dynamic> onChanged;
  final bool showRequired;
  final String? hint;
  final Color? color;
  @override
  State<_QField> createState() => _QFieldState();
}

class _QFieldState extends State<_QField> {
  late final TextEditingController _c = TextEditingController(text: widget.value == null ? '' : '${widget.value}');

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  String _fmt(double v) => v % 1 == 0 ? v.toStringAsFixed(0) : v.toString();

  void _step(int dir) {
    final q = widget.q;
    final cur = widget.value is num ? (widget.value as num).toDouble() : null;
    var next = cur == null ? (q.min ?? 0) : cur + dir;
    if (q.min != null) next = next < q.min! ? q.min! : next;
    if (q.max != null) next = next > q.max! ? q.max! : next;
    _c.text = _fmt(next);
    widget.onChanged(next == next.roundToDouble() ? next.toInt() : next);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final q = widget.q;
    final v = widget.value;
    final col = widget.color ?? cs.primary;
    Widget input;
    switch (q.kind) {
      case 'single_choice':
        input = Wrap(spacing: 8, runSpacing: 8, children: [
          for (final o in q.options) ChoiceChip(label: Text(o.label), selected: v == o.value, onSelected: (s) => widget.onChanged(s ? o.value : null)),
        ]);
      case 'multi_choice':
        final cur = (v as List?)?.cast<String>() ?? <String>[];
        input = Wrap(spacing: 8, runSpacing: 8, children: [
          for (final o in q.options)
            FilterChip(
              label: Text(o.label),
              selected: cur.contains(o.value),
              onSelected: (s) {
                final next = [...cur];
                s ? next.add(o.value) : next.remove(o.value);
                widget.onChanged(next.isEmpty ? null : next);
              },
            ),
        ]);
      case 'yes_no':
        input = Row(children: [
          for (final yes in [true, false])
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: yes ? 8 : 0),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: v == yes ? (yes ? const Color(0xFF16A34A) : const Color(0xFFEF4444)).withValues(alpha: 0.15) : null,
                    border: Border.all(color: v == yes ? (yes ? const Color(0xFF16A34A) : const Color(0xFFEF4444)) : cs.outlineVariant, width: v == yes ? 2 : 1),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => widget.onChanged(v == yes ? null : yes),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(yes ? Icons.check_rounded : Icons.close_rounded, color: yes ? const Color(0xFF16A34A) : const Color(0xFFEF4444)),
                        const SizedBox(width: 6),
                        Text(yes ? 'Oui' : 'Non', style: const TextStyle(fontWeight: FontWeight.w800)),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
        ]);
      case 'scale':
        input = Row(children: [
          for (var i = 1; i <= 5; i++)
            GestureDetector(
              onTap: () => widget.onChanged(v == i ? null : i),
              child: AnimatedScale(
                scale: v is int && i <= v ? 1.12 : 1,
                duration: const Duration(milliseconds: 150),
                child: Icon(v is int && i <= v ? Icons.star_rounded : Icons.star_border_rounded, size: 38, color: const Color(0xFFF59E0B)),
              ),
            ),
          const SizedBox(width: 8),
          Text('1 faible · 5 élevé', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11)),
        ]);
      default:
        final err = (v is num && ((q.min != null && v < q.min!) || (q.max != null && v > q.max!))) ? 'Entre ${_fmt(q.min ?? 0)} et ${_fmt(q.max ?? 0)}' : null;
        input = Row(children: [
          IconButton.filledTonal(onPressed: () => _step(-1), icon: const Icon(Icons.remove_rounded)),
          Expanded(
            child: TextField(
              controller: _c,
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: col),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                isDense: true,
                border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
                suffixText: q.unit,
                errorText: err,
                helperText: (q.min != null && q.max != null) ? 'Entre ${_fmt(q.min!)} et ${_fmt(q.max!)}' : null,
              ),
              onChanged: (t) {
                final x = double.tryParse(t.trim().replaceAll(',', '.'));
                widget.onChanged(x == null ? null : (x == x.roundToDouble() ? x.toInt() : x));
              },
            ),
          ),
          IconButton.filledTonal(onPressed: () => _step(1), icon: const Icon(Icons.add_rounded)),
        ]);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 18, top: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${q.text}${(widget.showRequired && q.required) ? ' *' : ''}', style: const TextStyle(fontWeight: FontWeight.w700, height: 1.3)),
        if (q.help != null) Text(q.help!, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
        if (widget.hint != null) Text(widget.hint!, style: TextStyle(color: col, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        input,
      ]),
    );
  }
}