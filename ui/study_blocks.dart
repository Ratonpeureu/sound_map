import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/models_study.dart';
import 'study_widgets.dart';
import 'widgets.dart';

/// Message d'erreur d'un bloc (null = valide).
String? blockError(StudyBlock b, dynamic v) {
  if (!b.answerable) return null;
  final empty = v == null || (v is String && v.trim().isEmpty) || (v is List && v.isEmpty) || (v is Map && v.isEmpty);
  if (empty) return b.required ? 'Réponse requise' : null;
  switch (b.kind) {
    case 'multi_choice':
      final n = (v as List).length;
      if (b.minSelect != null && n < b.minSelect!) return 'Choisissez au moins ${b.minSelect}';
      if (b.maxSelect != null && n > b.maxSelect!) return 'Maximum ${b.maxSelect}';
      return null;
    case 'text':
    case 'long_text':
      if ((v as String).trim().length < (b.minLength ?? 0)) return 'Au moins ${b.minLength} caractères';
      return null;
    case 'number':
    case 'slider':
      final x = v as num;
      if (b.min != null && x < b.min!) return 'Minimum ${b.min}';
      if (b.max != null && x > b.max!) return 'Maximum ${b.max}';
      if (b.integer && x != x.roundToDouble()) return 'Nombre entier attendu';
      return null;
    case 'matrix':
      final m = v as Map;
      return b.rows.every((r) => m.containsKey(r.value)) ? null : 'Complétez chaque ligne';
    case 'product_rating':
      final m = v as Map;
      for (final it in b.items) {
        final x = m[it.key] as Map?;
        if (x == null || !b.criteria.every((c) => x.containsKey(c.value))) return 'Notez tous les produits';
      }
      return null;
    case 'ranking':
      final need = min(b.topN ?? b.options.length, b.options.length);
      return (v as List).length == need ? null : 'Classement incomplet';
    default:
      return null;
  }
}

class BlockView extends StatelessWidget {
  const BlockView({super.key, required this.block, required this.value, required this.other, required this.onChanged, required this.onOther, required this.color, this.error = false});
  final StudyBlock block;
  final dynamic value;
  final String? other;
  final ValueChanged<dynamic> onChanged;
  final ValueChanged<String> onOther;
  final Color color;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final b = block;
    if (b.kind == 'info') {
      return SoftCard(
        margin: const EdgeInsets.only(bottom: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if ((b.text ?? '').isNotEmpty) Text(b.text!, style: const TextStyle(height: 1.45)),
          if (b.media.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: MediaStrip(b.media)),
        ]),
      );
    }
    if (b.kind == 'media') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if ((b.text ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(b.text!, style: const TextStyle(fontWeight: FontWeight.w700))),
          MediaStrip(b.media),
        ]),
      );
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 22),
      padding: error ? const EdgeInsets.all(10) : EdgeInsets.zero,
      decoration: error ? BoxDecoration(border: Border.all(color: cs.error), borderRadius: BorderRadius.circular(16)) : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${b.text ?? ''}${b.required ? ' *' : ''}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, height: 1.3)),
        if (b.help != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(b.help!, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5))),
        if (b.media.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: MediaStrip(b.media)),
        const SizedBox(height: 10),
        _input(context, cs),
        if (error) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Réponse requise ou incomplète', style: TextStyle(color: cs.error, fontSize: 12))),
      ]),
    );
  }

  Widget _input(BuildContext context, ColorScheme cs) => switch (block.kind) {
        'single_choice' => _single(cs),
        'multi_choice' => _multi(cs),
        'yes_no' => _yesNo(cs),
        'number' => _NumField(block: block, value: value, onChanged: onChanged, color: color),
        'slider' => _slider(cs),
        'scale' => _scale(cs),
        'stars' => _stars(),
        'nps' => _nps(cs),
        'text' || 'long_text' => _TxtField(block: block, value: value, onChanged: onChanged),
        'ranking' => _RankField(block: block, value: value, onChanged: onChanged, color: color),
        'matrix' => _matrix(cs),
        'date' => _date(context),
        'product_rating' => _product(cs),
        _ => const SizedBox.shrink(),
      };

  // ------------------------------------------------------------------ choix
  Widget _tile(ColorScheme cs, StudyOption o, bool sel, bool multi, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: sel ? color.withValues(alpha: 0.12) : null,
        border: Border.all(color: sel ? color : cs.outlineVariant, width: sel ? 2 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            Icon(multi ? (sel ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded) : (sel ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded), color: sel ? color : cs.onSurfaceVariant),
            const SizedBox(width: 10),
            if (o.media != null && !o.media!.isVideo) Padding(padding: const EdgeInsets.only(right: 10), child: StudyImage(assetId: o.media!.assetId, url: o.media!.url, width: 46, height: 46, radius: 10)),
            Expanded(child: Text(o.label, style: TextStyle(fontWeight: sel ? FontWeight.w800 : FontWeight.w600))),
          ]),
        ),
      ),
    );
  }

  Widget _imageGrid(ColorScheme cs, bool Function(StudyOption) selected, void Function(StudyOption) tap) {
    return GridView.count(
      crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 0.9,
      children: [
        for (final o in block.options)
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => tap(o),
            child: Container(
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: selected(o) ? color : cs.outlineVariant, width: selected(o) ? 3 : 1), color: selected(o) ? color.withValues(alpha: 0.10) : null),
              padding: const EdgeInsets.all(6),
              child: Column(children: [
                Expanded(child: StudyImage(assetId: o.media?.assetId, url: o.media?.url, width: double.infinity, radius: 12)),
                const SizedBox(height: 6),
                Text(o.label, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
              ]),
            ),
          ),
      ],
    );
  }

  Widget _otherField(StudyOption o) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextFormField(key: ValueKey('o_${block.key}_${o.value}'), initialValue: other, onChanged: onOther, maxLength: 200, decoration: InputDecoration(hintText: 'Précisez…', border: const OutlineInputBorder(), isDense: true, counterText: '')),
      );

  Widget _single(ColorScheme cs) {
    final b = block;
    final v = value as String?;
    Widget list;
    switch (b.display) {
      case 'dropdown':
        list = DropdownButtonFormField<String>(
          key: ValueKey('dd_${b.key}_$v'),
          initialValue: v,
          isExpanded: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          items: [for (final o in b.options) DropdownMenuItem(value: o.value, child: Text(o.label))],
          onChanged: onChanged,
        );
      case 'buttons':
        list = Wrap(spacing: 8, runSpacing: 8, children: [
          for (final o in b.options) ChoiceChip(label: Text(o.label), selected: v == o.value, onSelected: (_) => onChanged(v == o.value ? null : o.value)),
        ]);
      case 'images':
        list = _imageGrid(cs, (o) => v == o.value, (o) => onChanged(v == o.value ? null : o.value));
      default:
        list = Column(children: [for (final o in b.options) _tile(cs, o, v == o.value, false, () => onChanged(v == o.value ? null : o.value))]);
    }
    final sel = b.options.where((o) => o.value == v && o.other).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [list, if (sel.isNotEmpty) ...[const SizedBox(height: 8), _otherField(sel.first)]]);
  }

  void _toggleMulti(StudyOption o) {
    final cur = [...((value as List?)?.cast<String>() ?? <String>[])];
    if (cur.contains(o.value)) {
      cur.remove(o.value);
    } else {
      if (o.exclusive) {
        cur.clear();
      } else {
        cur.removeWhere((x) => block.options.any((p) => p.value == x && p.exclusive));
      }
      if (block.maxSelect != null && cur.length >= block.maxSelect!) return;
      cur.add(o.value);
    }
    onChanged(cur.isEmpty ? null : cur);
  }

  Widget _multi(ColorScheme cs) {
    final b = block;
    final cur = (value as List?)?.cast<String>() ?? <String>[];
    final hint = [if (b.minSelect != null) 'min. ${b.minSelect}', if (b.maxSelect != null) 'max. ${b.maxSelect}'].join(' · ');
    final sel = b.options.where((o) => cur.contains(o.value) && o.other).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (hint.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('Choix multiple ($hint)', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12))),
      if (b.display == 'images')
        _imageGrid(cs, (o) => cur.contains(o.value), _toggleMulti)
      else
        for (final o in b.options) _tile(cs, o, cur.contains(o.value), true, () => _toggleMulti(o)),
      if (sel.isNotEmpty) _otherField(sel.first),
    ]);
  }

  Widget _yesNo(ColorScheme cs) {
    return Row(children: [
      for (final yes in [true, false])
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: yes ? 8 : 0),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: value == yes ? (yes ? const Color(0xFF16A34A) : const Color(0xFFEF4444)).withValues(alpha: 0.15) : null,
                border: Border.all(color: value == yes ? (yes ? const Color(0xFF16A34A) : const Color(0xFFEF4444)) : cs.outlineVariant, width: value == yes ? 2 : 1),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => onChanged(value == yes ? null : yes),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
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
  }

  // ------------------------------------------------------------------ échelles
  Widget _numBtn(ColorScheme cs, int i, bool sel, VoidCallback tap, {Color? c}) {
    final col = c ?? color;
    return GestureDetector(
      onTap: tap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 44, height: 44, alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, color: sel ? col : null, border: Border.all(color: sel ? col : cs.outlineVariant, width: 1.5)),
        child: Text('$i', style: TextStyle(fontWeight: FontWeight.w800, color: sel ? Colors.white : null)),
      ),
    );
  }

  Widget _ends(ColorScheme cs) => (block.lowLabel == null && block.highLabel == null)
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Flexible(child: Text(block.lowLabel ?? '', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11.5))),
            Flexible(child: Text(block.highLabel ?? '', textAlign: TextAlign.right, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11.5))),
          ]));

  Widget _scale(ColorScheme cs) {
    final lo = (block.min ?? 1).toInt(), hi = (block.max ?? 5).toInt();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 8, runSpacing: 8, children: [for (var i = lo; i <= hi; i++) _numBtn(cs, i, value == i, () => onChanged(value == i ? null : i))]),
      _ends(cs),
    ]);
  }

  Widget _nps(ColorScheme cs) {
    Color c(int i) => i <= 6 ? const Color(0xFFEF4444) : (i <= 8 ? const Color(0xFFF59E0B) : const Color(0xFF16A34A));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 6, runSpacing: 6, children: [for (var i = 0; i <= 10; i++) _numBtn(cs, i, value == i, () => onChanged(value == i ? null : i), c: c(i))]),
      _ends(cs),
    ]);
  }

  Widget _stars() {
    final n = (block.max ?? 5).toInt();
    final v = value is int ? value as int : 0;
    return Wrap(children: [
      for (var i = 1; i <= n; i++)
        GestureDetector(onTap: () => onChanged(value == i ? null : i), child: Icon(i <= v ? Icons.star_rounded : Icons.star_border_rounded, size: 42, color: const Color(0xFFF59E0B))),
    ]);
  }

  Widget _slider(ColorScheme cs) {
    final b = block;
    final lo = b.min ?? 0, hi = b.max ?? 100, step = b.step ?? 1;
    final v = (value as num?)?.toDouble() ?? (lo + hi) / 2;
    final div = ((hi - lo) / step).round();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Opacity(
        opacity: value == null ? 0.55 : 1,
        child: Slider(
          value: v.clamp(lo, hi).toDouble(), min: lo, max: hi, divisions: div > 0 ? div : null, activeColor: color,
          label: v.toStringAsFixed(step % 1 == 0 ? 0 : 1),
          onChanged: (x) {
            final r = (x / step).round() * step;
            onChanged(step % 1 == 0 ? r.round() : r);
          },
        ),
      ),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(value == null ? 'Déplacez le curseur' : '${v.toStringAsFixed(step % 1 == 0 ? 0 : 1)} ${b.unit ?? ''}'.trim(), style: TextStyle(fontWeight: FontWeight.w800, color: value == null ? cs.onSurfaceVariant : color)),
      ]),
      _ends(cs),
    ]);
  }

  // ------------------------------------------------------------------ grille, date, produits
  Widget _matrix(ColorScheme cs) {
    final b = block;
    final v = Map<String, dynamic>.from((value as Map?) ?? {});
    return Column(children: [
      for (final r in b.rows)
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(16), border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r.label, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final c in b.options)
                ChoiceChip(
                  label: Text(c.label, style: const TextStyle(fontSize: 12)),
                  selected: v[r.value] == c.value,
                  onSelected: (_) {
                    final n = {...v};
                    v[r.value] == c.value ? n.remove(r.value) : n[r.value] = c.value;
                    onChanged(n.isEmpty ? null : n);
                  },
                ),
            ]),
          ]),
        ),
    ]);
  }

  Widget _date(BuildContext context) {
    final d = value == null ? null : DateTime.tryParse(value as String);
    return OutlinedButton.icon(
      icon: const Icon(Icons.event_rounded),
      label: Text(d == null ? 'Choisir une date' : DateFormat('d MMMM y', 'fr_FR').format(d)),
      onPressed: () async {
        final p = await showDatePicker(context: context, initialDate: d ?? DateTime.now(), firstDate: DateTime(1920), lastDate: DateTime(2100), locale: const Locale('fr'));
        if (p != null) onChanged(DateFormat('yyyy-MM-dd').format(p));
      },
    );
  }

  Widget _product(ColorScheme cs) {
    final b = block;
    final v = Map<String, dynamic>.from((value as Map?) ?? {});
    final lo = (b.min ?? 1).toInt(), hi = (b.max ?? 5).toInt();
    void setItem(String key, String k, dynamic x) {
      final it = Map<String, dynamic>.from((v[key] as Map?) ?? {});
      if (x == null || (x is String && x.trim().isEmpty)) {
        it.remove(k);
      } else {
        it[k] = x;
      }
      final n = {...v};
      it.isEmpty ? n.remove(key) : n[key] = it;
      onChanged(n.isEmpty ? null : n);
    }

    return Column(children: [
      for (final it in b.items)
        SoftCard(
          margin: const EdgeInsets.only(bottom: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (it.media.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 10), child: MediaStrip(it.media, height: 170)),
            Text(it.label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            if (it.description != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(it.description!, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5, height: 1.3))),
            const SizedBox(height: 8),
            for (final c in b.criteria)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                    if (b.criteria.length > 1 || c.value != 'overall') Expanded(flex: 4, child: Text(c.label, style: const TextStyle(fontSize: 13))) else const SizedBox.shrink(),
                  Expanded(
                    flex: 6,
                    child: Wrap(alignment: b.criteria.length > 1 ? WrapAlignment.end : WrapAlignment.start, children: [
                      for (var i = lo; i <= hi; i++)
                        GestureDetector(
                          onTap: () => setItem(it.key, c.value, ((v[it.key] as Map?)?[c.value]) == i ? null : i),
                          child: Icon(i <= (((v[it.key] as Map?)?[c.value] as int?) ?? 0) ? Icons.star_rounded : Icons.star_border_rounded, size: 34, color: const Color(0xFFF59E0B)),
                        ),
                    ]),
                  ),
                ]),
              ),
            if (b.allowComment)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: TextFormField(
                  key: ValueKey('c_${b.key}_${it.key}'),
                  initialValue: ((v[it.key] as Map?)?['comment']) as String?,
                  maxLength: 500, maxLines: 2,
                  decoration: const InputDecoration(hintText: 'Commentaire (facultatif)', border: OutlineInputBorder(), isDense: true),
                  onChanged: (t) => setItem(it.key, 'comment', t),
                ),
              ),
          ]),
        ),
    ]);
  }
}

// ============================================================================ champs avec état
class _NumField extends StatefulWidget {
  const _NumField({required this.block, required this.value, required this.onChanged, required this.color});
  final StudyBlock block;
  final dynamic value;
  final ValueChanged<dynamic> onChanged;
  final Color color;
  @override
  State<_NumField> createState() => _NumFieldState();
}

class _NumFieldState extends State<_NumField> {
  late final TextEditingController _c = TextEditingController(text: widget.value == null ? '' : _f((widget.value as num).toDouble()));
  String _f(double v) => v % 1 == 0 ? v.toStringAsFixed(0) : v.toString();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _step(int d) {
    final b = widget.block;
    final cur = widget.value is num ? (widget.value as num).toDouble() : null;
    var n = cur == null ? (b.min ?? 0) : cur + d;
    if (b.min != null && n < b.min!) n = b.min!;
    if (b.max != null && n > b.max!) n = b.max!;
    _c.text = _f(n);
    widget.onChanged(n == n.roundToDouble() ? n.toInt() : n);
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.block;
    final v = widget.value;
    final err = (v is num && ((b.min != null && v < b.min!) || (b.max != null && v > b.max!))) ? 'Entre ${_f(b.min ?? 0)} et ${_f(b.max ?? 0)}' : null;
    return Row(children: [
      IconButton.filledTonal(onPressed: () => _step(-1), icon: const Icon(Icons.remove_rounded)),
      Expanded(
        child: TextField(
          controller: _c,
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: widget.color),
          keyboardType: TextInputType.numberWithOptions(decimal: !b.integer),
          decoration: InputDecoration(isDense: true, border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14))), suffixText: b.unit, hintText: b.placeholder, errorText: err),
          onChanged: (t) {
            final x = double.tryParse(t.trim().replaceAll(',', '.'));
            widget.onChanged(x == null ? null : (x == x.roundToDouble() ? x.toInt() : x));
          },
        ),
      ),
      IconButton.filledTonal(onPressed: () => _step(1), icon: const Icon(Icons.add_rounded)),
    ]);
  }
}

class _TxtField extends StatefulWidget {
  const _TxtField({required this.block, required this.value, required this.onChanged});
  final StudyBlock block;
  final dynamic value;
  final ValueChanged<dynamic> onChanged;
  @override
  State<_TxtField> createState() => _TxtFieldState();
}

class _TxtFieldState extends State<_TxtField> {
  late final TextEditingController _c = TextEditingController(text: (widget.value as String?) ?? '');

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.block;
    final long = b.kind == 'long_text';
    return TextField(
      controller: _c,
      maxLength: b.maxLength ?? (long ? 4000 : 300),
      minLines: long ? 4 : 1,
      maxLines: long ? 8 : 2,
      decoration: InputDecoration(hintText: b.placeholder ?? (b.minLength != null ? 'Au moins ${b.minLength} caractères' : null), border: const OutlineInputBorder()),
      onChanged: (t) => widget.onChanged(t.trim().isEmpty ? null : t),
    );
  }
}

class _RankField extends StatefulWidget {
  const _RankField({required this.block, required this.value, required this.onChanged, required this.color});
  final StudyBlock block;
  final dynamic value;
  final ValueChanged<dynamic> onChanged;
  final Color color;
  @override
  State<_RankField> createState() => _RankFieldState();
}

class _RankFieldState extends State<_RankField> {
  late List<String> _order;

  @override
  void initState() {
    super.initState();
    final all = [for (final o in widget.block.options) o.value];
    final v = (widget.value as List?)?.cast<String>();
    if (v != null) {
      _order = [...v, ...all.where((x) => !v.contains(x))];
    } else {
      _order = [...all];
      if (widget.block.randomize) _order.shuffle(Random(widget.block.key.hashCode));
    }
  }

  int get _n => min(widget.block.topN ?? widget.block.options.length, widget.block.options.length);
  void _emit() => widget.onChanged(_order.take(_n).toList());

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final b = widget.block;
    final byVal = {for (final o in b.options) o.value: o};
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(_n < b.options.length ? 'Faites glisser pour classer : seuls les $_n premiers comptent.' : 'Faites glisser pour classer du 1er au dernier.', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
      const SizedBox(height: 8),
      ReorderableListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        onReorder: (a, c) {
          setState(() => _order.insert(c, _order.removeAt(a)));
          _emit();
        },

        children: [
          for (var i = 0; i < _order.length; i++)
            Opacity(
              key: ValueKey(_order[i]),
              opacity: i < _n ? 1 : 0.45,
              child: Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  leading: Row(mainAxisSize: MainAxisSize.min, children: [
                    CircleAvatar(radius: 14, backgroundColor: i < _n ? widget.color : cs.outlineVariant, child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800))),
                    if (byVal[_order[i]]?.media != null && !byVal[_order[i]]!.media!.isVideo)
                      Padding(padding: const EdgeInsets.only(left: 8), child: StudyImage(assetId: byVal[_order[i]]!.media!.assetId, url: byVal[_order[i]]!.media!.url, width: 40, height: 40, radius: 8)),
                  ]),
                  title: Text(byVal[_order[i]]?.label ?? _order[i], style: const TextStyle(fontWeight: FontWeight.w700)),
                  trailing: ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_handle_rounded)),
                ),
              )
            ),
        ],
      ),
      if (widget.value == null) FilledButton.tonalIcon(onPressed: _emit, icon: const Icon(Icons.check_rounded), label: const Text('Confirmer cet ordre')),
    ]);
  }
}