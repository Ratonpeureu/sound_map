import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/api_study.dart';
import '../core/models_study.dart';
import '../core/util.dart';
import '../state/studies_controller.dart';
import 'widgets.dart';

class StudyProfileScreen extends StatefulWidget {
  const StudyProfileScreen({super.key});
  @override
  State<StudyProfileScreen> createState() => _StudyProfileScreenState();
}

class _StudyProfileScreenState extends State<StudyProfileScreen> {
  StudyProfile? _p;
  Map<String, List<({String value, String label})>> _o = {};
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<ApiClient>();
    try {
      final r = await Future.wait([api.studyProfile(), api.studyProfileOptions()]);
      if (!mounted) return;
      setState(() {
        _p = r[0] as StudyProfile;
        _o = r[1] as Map<String, List<({String value, String label})>>;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.code);
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await context.read<ApiClient>().studyProfileSave(_p!);
      if (!mounted) return;
      showToast(context, 'Profil enregistré.');
      context.read<StudiesController>().refresh();
      Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) showToast(context, apiErrorLabel(e.code));
    }
    if (mounted) setState(() => _busy = false);
  }

  Widget _drop(String label, String key, String? cur, ValueChanged<String?> on) {
    final opts = _o[key] ?? const [];
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DropdownButtonFormField<String>(
        key: ValueKey('$key$cur'),
        initialValue: opts.any((o) => o.value == cur) ? cur : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        items: [for (final o in opts) DropdownMenuItem(value: o.value, child: Text(o.label))],
        onChanged: (v) => setState(() => on(v)),
      ),
    );
  }

  Widget _multi(String title, String key, List<String> cur) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final o in _o[key] ?? const [])
            FilterChip(label: Text(o.label), selected: cur.contains(o.value), onSelected: (s) => setState(() => s ? cur.add(o.value) : cur.remove(o.value))),
        ]),
        const SizedBox(height: 16),
      ]);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = _p;
    return Scaffold(
      appBar: AppBar(title: const Text('Mon profil études')),
      body: p == null
          ? Center(child: _error == null ? const CircularProgressIndicator() : Text(apiErrorLabel(_error!), style: TextStyle(color: cs.error)))
          : ListView(padding: const EdgeInsets.all(20), children: [
              SoftCard(
                child: Row(children: [
                  Icon(Icons.shield_rounded, color: cs.primary),
                  const SizedBox(width: 12),
                  Expanded(child: Text("Ces informations servent uniquement à vous proposer des études qui vous correspondent. Elles ne sont jamais transmises telles quelles aux organisations et jamais affichées sur une carte. Tout est facultatif.", style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5, height: 1.35))),
                ]),
              ),
              const SizedBox(height: 16),
              _drop('Genre', 'gender', p.gender, (v) => p.gender = v),
              _drop("Secteur d'activité", 'occupation_group', p.occupationGroup, (v) => p.occupationGroup = v),
              _drop("Niveau d'études", 'education_level', p.educationLevel, (v) => p.educationLevel = v),
              _drop('Revenu mensuel du ménage', 'income_band', p.incomeBand, (v) => p.incomeBand = v),
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: TextFormField(
                  initialValue: p.householdSize?.toString(),
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Personnes dans le ménage', border: OutlineInputBorder()),
                  onChanged: (t) => p.householdSize = int.tryParse(t.trim()),
                ),
              ),
              _multi('Langues parlées', 'languages', p.languages),
              _multi("Centres d'intérêt", 'interests', p.interests),
              FilledButton(onPressed: _busy ? null : _save, child: _busy ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : const Text('Enregistrer')),
            ]),
    );
  }
}