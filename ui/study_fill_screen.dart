import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../core/api.dart';
import '../core/api_study.dart';
import '../core/models_study.dart';
import '../core/util.dart';
import '../state/studies_controller.dart';
import 'study_blocks.dart';
import 'study_result_screen.dart';
import 'study_widgets.dart';
import 'widgets.dart';

enum _Stage { intro, page, contact }

class StudyFillScreen extends StatefulWidget {
  const StudyFillScreen({super.key, required this.detail});
  final StudyDetail detail;
  @override
  State<StudyFillScreen> createState() => _StudyFillScreenState();
}

class _StudyFillScreenState extends State<StudyFillScreen> {
  late final StudyDef _def = widget.detail.definition;
  late _Stage _stage = _def.intro != null ? _Stage.intro : _Stage.page;
  final Map<String, dynamic> _ans = {};
  final Set<String> _bad = {};
  final String _cid = const Uuid().v4();
  final _phone = TextEditingController(), _name = TextEditingController();
  bool _share = false, _busy = false;
  int _pi = 0;

  @override
  void dispose() {
    _phone.dispose();
    _name.dispose();
    super.dispose();
  }

  List<StudyPage> _pages() => _def.pages.where((p) => condOk(p.showIf, _ans)).toList();
  List<StudyBlock> _blocks(StudyPage p) => p.blocks.where((b) => condOk(b.showIf, _ans)).toList();

  void _prune() {
    final keys = <String>{};
    for (final p in _pages()) {
      for (final b in _blocks(p)) {
        keys.add(b.key);
      }
    }
    _ans.removeWhere((k, _) => !keys.contains(k.endsWith('_other') ? k.substring(0, k.length - 6) : k));
  }

  void _set(StudyBlock b, dynamic v) {
    setState(() {
      v == null ? _ans.remove(b.key) : _ans[b.key] = v;
      _bad.remove(b.key);
      _prune();
    });
  }

  Color get _color => Theme.of(context).colorScheme.primary;

  // ------------------------------------------------------------------ navigation
  Future<void> _next() async {
    final pages = _pages();
    if (_pi >= pages.length) return _submit();
    final page = pages[_pi];
    final blocks = _blocks(page);
    final bad = {for (final b in blocks) if (b.answerable && blockError(b, _ans[b.key]) != null) b.key};
    if (bad.isNotEmpty) {
      setState(() => _bad..clear()..addAll(bad));
      showToast(context, 'Complétez les questions marquées en rouge.');
      return;
    }
    _bad.clear();
    if (blocks.any((b) => b.screening)) {
      setState(() => _busy = true);
      try {
        final r = await context.read<ApiClient>().studyCheck(widget.detail.id, _ans);
        if (!r.ok) {
          await _submit();                                      // enregistre la sortie de l'étude côté serveur
          return;
        }
      } on ApiException catch (e) {
        if (mounted) showToast(context, apiErrorLabel(e.code));
        setState(() => _busy = false);
        return;
      }
      if (mounted) setState(() => _busy = false);
    }
    if (_pi < pages.length - 1) {
      setState(() => _pi++);
    } else if (widget.detail.collectContact) {
      setState(() => _stage = _Stage.contact);
    } else {
      await _submit();
    }
  }

  void _back() {
    if (_stage == _Stage.contact) {
      setState(() {
        _stage = _Stage.page;
        _pi = _pages().length - 1;
      });
    } else if (_pi > 0) {
      setState(() => _pi--);
    } else if (_def.intro != null) {
      setState(() => _stage = _Stage.intro);
    }
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      final phone = _phone.text.trim();
      final body = <String, dynamic>{
        'client_response_id': _cid,
        'study_version': widget.detail.version,
        'answers': _ans,
        'share_contact': _share && phone.isNotEmpty,
        if (_share && phone.isNotEmpty) 'contact': {'phone': phone, if (_name.text.trim().isNotEmpty) 'name': _name.text.trim()},
      };
      final ack = await context.read<ApiClient>().studySubmit(widget.detail.id, body);
      if (!mounted) return;
      context.read<StudiesController>().refresh();
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => StudyResultScreen(ack: ack, detail: widget.detail)));
    } on ApiException catch (e) {
      await _handle(e);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _handle(ApiException e) async {
    if (!mounted) return;
    if (e.code == 'missing_answers') {
      final keys = ((e.detail is Map ? e.detail['questions'] : null) as List?)?.cast<String>() ?? const <String>[];
      final pages = _pages();
      final idx = pages.indexWhere((p) => p.blocks.any((b) => keys.contains(b.key)));
      setState(() {
        _bad..clear()..addAll(keys);
        _stage = _Stage.page;
        if (idx >= 0) _pi = idx;
      });
      showToast(context, apiErrorLabel(e.code));
    } else if (e.code == 'invalid_answer') {
      showToast(context, 'Une réponse est invalide : ${(e.detail is Map ? e.detail['error'] : '') ?? ''}');
    } else {
      showToast(context, apiErrorLabel(e.code));
      if (const {'study_closed', 'study_full', 'study_version_changed', 'already_participated'}.contains(e.code)) {
        context.read<StudiesController>().refresh();
        Navigator.pop(context);
      }
    }
  }

  Future<bool> _confirmExit() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Quitter l'étude ?"),
        content: const Text('Vos réponses en cours seront perdues. Vous pourrez reprendre plus tard tant que l\'étude est ouverte.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Continuer')),
          FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(100, 44)), onPressed: () => Navigator.pop(context, true), child: const Text('Quitter')),
        ],
      ),
    );
    return ok == true;
  }

  // ------------------------------------------------------------------ UI
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pages = _pages();
    final total = (_def.intro != null ? 1 : 0) + pages.length + (widget.detail.collectContact ? 1 : 0);
    final idx = _stage == _Stage.intro ? 0 : (_def.intro != null ? 1 : 0) + (_stage == _Stage.contact ? pages.length : _pi);
    final lastPage = _stage == _Stage.page && _pi >= pages.length - 1 && !widget.detail.collectContact;
    final canBack = _def.allowBack && (_stage == _Stage.contact || _pi > 0 || (_stage == _Stage.page && _def.intro != null));

    Widget body;
    switch (_stage) {
      case _Stage.intro:
        body = _intro(cs);
      case _Stage.contact:
        body = _contact(cs);
      case _Stage.page:
        body = _page(pages, cs);
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmExit() && mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.detail.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          bottom: _def.showProgress
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(4),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: total == 0 ? 0 : (idx + 1) / total),
                    duration: const Duration(milliseconds: 300),
                    builder: (_, v, __) => LinearProgressIndicator(minHeight: 4, value: v, color: _color),
                  ))
              : null,
        ),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 28), children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
            child: KeyedSubtree(key: ValueKey('$_stage$_pi'), child: body),
          ),
        ]),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(children: [
              if (canBack) ...[Expanded(child: OutlinedButton(onPressed: _busy ? null : _back, child: const Text('Retour'))), const SizedBox(width: 12)],
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: _busy ? null : () => _stage == _Stage.intro ? setState(() => _stage = _Stage.page) : (_stage == _Stage.contact ? _submit() : _next()),
                  child: _busy
                      ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                      : Text(_stage == _Stage.intro ? 'Commencer' : (_stage == _Stage.contact || lastPage ? 'Envoyer mes réponses' : 'Suivant')),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _intro(ColorScheme cs) {
    final i = _def.intro!;
    final d = widget.detail;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        SponsorAvatar(d.sponsor.brief, size: 40),
        const SizedBox(width: 10),
        Expanded(child: Text('Demandé par ${d.sponsor.brief.name}', style: TextStyle(color: cs.onSurfaceVariant))),
      ]),
      const SizedBox(height: 12),
      if ((i.title ?? '').isNotEmpty) Text(i.title!, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 24, height: 1.2)),
      if ((i.text ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(i.text!, style: const TextStyle(height: 1.5, fontSize: 15))),
      if (i.media.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: MediaStrip(i.media)),
      const SizedBox(height: 14),
      Wrap(spacing: 8, runSpacing: 6, children: [
        StatusChip('~${d.card.estimatedMinutes} min', _color, icon: Icons.timer_outlined),
        if (d.card.reward.enabled) StatusChip(d.card.reward.headline, const Color(0xFFDB2777), icon: Icons.card_giftcard_rounded),
      ]),
    ]);
  }

  Widget _page(List<StudyPage> pages, ColorScheme cs) {
    if (_pi >= pages.length) return const SizedBox.shrink();
    final p = pages[_pi];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Page ${_pi + 1} sur ${pages.length}', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
      if ((p.title ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(p.title!, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 22, letterSpacing: -0.3))),
      if ((p.description ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(p.description!, style: TextStyle(color: cs.onSurfaceVariant, height: 1.35))),
      const SizedBox(height: 14),
      for (final b in _blocks(p))
        BlockView(
          key: ValueKey('${p.key}_${b.key}'),
          block: b,
          value: _ans[b.key],
          other: _ans['${b.key}_other'] as String?,
          color: _color,
          error: _bad.contains(b.key),
          onChanged: (v) => _set(b, v),
          onOther: (t) => setState(() => t.trim().isEmpty ? _ans.remove('${b.key}_other') : _ans['${b.key}_other'] = t),
        ),
    ]);
  }

  Widget _contact(ColorScheme cs) {
    final d = widget.detail;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Vos coordonnées (facultatif)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
      const SizedBox(height: 6),
      Text(d.contactPurpose ?? "L'organisation peut vous contacter, uniquement si vous l'acceptez.", style: TextStyle(color: cs.onSurfaceVariant, height: 1.4)),
      const SizedBox(height: 12),
      SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text("J'accepte de partager mon numéro"), value: _share, onChanged: (v) => setState(() => _share = v)),
      if (_share) ...[
        TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: d.contactLabel ?? 'Numéro de téléphone', border: const OutlineInputBorder(), prefixIcon: const Icon(Icons.phone_rounded))),
        const SizedBox(height: 10),
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nom (facultatif)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.person_outline_rounded))),
      ],
    ]);
  }
}