import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/api_ext.dart';
import '../core/util.dart';
import '../state/session_controller.dart';
import 'widgets.dart';

IconData guideIcon(String? n) => switch (n) {
      'waving_hand' => Icons.waving_hand_rounded,
      'mic' => Icons.mic_rounded,
      'map' => Icons.map_rounded,
      'route' => Icons.add_road_rounded,
      'verified' => Icons.verified_rounded,
      'calculate' => Icons.calculate_rounded,
      'bolt' => Icons.bolt_rounded,
      'auto_awesome' => Icons.auto_awesome_rounded,
      'flag' => Icons.flag_rounded,
      'hearing' => Icons.hearing_rounded,
      'emoji_events' => Icons.emoji_events_rounded,
      'lock' => Icons.lock_rounded,
      'person' => Icons.person_rounded,
      'admin' => Icons.admin_panel_settings_rounded,
      'help' => Icons.help_rounded,
      _ => Icons.menu_book_rounded,
    };

Color? _hex(dynamic v) {
  if (v is! String || !v.startsWith('#') || v.length != 7) return null;
  final n = int.tryParse(v.substring(1), radix: 16);
  return n == null ? null : Color(0xFF000000 | n);
}

class GuideScreen extends StatefulWidget {
  const GuideScreen({super.key, this.section});
  final String? section;
  @override
  State<GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends State<GuideScreen> {
  final _scroll = ScrollController();
  final _q = TextEditingController();
  final Map<String, GlobalKey> _keys = {};
  Map<String, dynamic>? _doc;
  bool _loading = true, _offline = false;
  String? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final prefs = context.read<SessionController>().prefs;
    try {
      final d = await context.read<ApiClient>().guide();
      await prefs.setString('guide_cache', jsonEncode(d));
      _doc = d;
      _offline = false;
      _error = null;
    } catch (e) {
      final raw = prefs.getString('guide_cache');
      if (raw != null) {
        _doc = (jsonDecode(raw) as Map).cast<String, dynamic>();
        _offline = true;
      } else {
        _error = errorMessage(e);
      }
    }
    if (!mounted) return;
    setState(() => _loading = false);
    if (widget.section != null) WidgetsBinding.instance.addPostFrameCallback((_) => _jump(widget.section!));
  }

  void _jump(String id) {
    final c = _keys[id]?.currentContext;
    if (c != null) Scrollable.ensureVisible(c, duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic, alignment: 0.02);
  }

  List<Map<String, dynamic>> get _sections => ((_doc?['sections'] as List?) ?? const []).cast<Map<String, dynamic>>();

  static void _collect(dynamic v, StringBuffer b) {
    if (v is String) {
      b.write('${v.toLowerCase()} ');
    } else if (v is List) {
      for (final x in v) {
        _collect(x, b);
      }
    } else if (v is Map) {
      for (final e in v.entries) {
        if (e.key == 'type' || e.key == 'color' || e.key == 'icon') continue;
        _collect(e.value, b);
      }
    }
  }

  bool _match(Map<String, dynamic> s) {
    if (_query.isEmpty) return true;
    final b = StringBuffer();
    _collect(s, b);
    return b.toString().contains(_query);
  }

  Widget _rich(String t, {TextStyle? style}) {
    final parts = t.split('**');
    return Text.rich(
      TextSpan(children: [
        for (var i = 0; i < parts.length; i++) TextSpan(text: parts[i], style: i.isOdd ? const TextStyle(fontWeight: FontWeight.w800) : null),
      ]),
      style: style ?? const TextStyle(height: 1.5, fontSize: 14),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final secs = _sections.where(_match).toList();
    return Scaffold(
      body: _loading && _doc == null
          ? const Center(child: CircularProgressIndicator())
          : _doc == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.cloud_off_rounded, size: 44, color: cs.error),
                      const SizedBox(height: 10),
                      Text(_error ?? 'Guide indisponible', textAlign: TextAlign.center),
                      const SizedBox(height: 14),
                      FilledButton(onPressed: _load, child: const Text('Réessayer')),
                    ]),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: CustomScrollView(controller: _scroll, physics: const AlwaysScrollableScrollPhysics(), slivers: [
                    SliverToBoxAdapter(child: _hero(context, cs)),
                    SliverToBoxAdapter(child: _toc(cs)),
                    if (_query.isNotEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                          child: Text('${secs.length} section(s) pour « $_query »', style: TextStyle(color: cs.onSurfaceVariant)),
                        ),
                      ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 60),
                      sliver: SliverList.builder(
                        itemCount: secs.length + 1,
                        itemBuilder: (_, i) => i == secs.length ? _footer(cs) : _section(secs[i], cs),
                      ),
                    ),
                  ]),
                ),
    );
  }

  Widget _hero(BuildContext context, ColorScheme cs) {
    return Container(
      padding: EdgeInsets.fromLTRB(8, MediaQuery.of(context).padding.top + 4, 16, 22),
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [Color(0xFF0B1F2A), Color(0xFF0E5E63)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_rounded, color: Colors.white)),
          const Spacer(),
          if (_offline) const StatusChip('Hors-ligne', Color(0xFFF59E0B), icon: Icons.cloud_off_rounded),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded, color: Colors.white)),
        ]),
        Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [SunuLogo(size: 36), SizedBox(width: 10), Text('Guide', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700, fontSize: 16))]),
            const SizedBox(height: 10),
            Text((_doc!['title'] as String?) ?? 'Guide', style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
            const SizedBox(height: 4),
            Text((_doc!['subtitle'] as String?) ?? '', style: TextStyle(color: Colors.white.withValues(alpha: 0.78), height: 1.35)),
          ]),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.only(left: 8),
          child: TextField(
            controller: _q,
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            style: const TextStyle(color: Colors.white),
            cursorColor: Colors.white,
            decoration: InputDecoration(
              hintText: 'Rechercher : crédits, mission, GPS, routes…',
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
              prefixIcon: const Icon(Icons.search_rounded, color: Colors.white70),
              suffixIcon: _query.isEmpty ? null : IconButton(icon: const Icon(Icons.close_rounded, color: Colors.white70), onPressed: () => setState(() { _q.clear(); _query = ''; })),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.14),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
            ),
          ),
        ),
        if ((_doc!['note'] as String?) != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 0, 0),
            child: Row(children: [
              const Icon(Icons.circle, size: 8, color: Color(0xFF22C55E)),
              const SizedBox(width: 6),
              Expanded(child: Text(_doc!['note'] as String, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11))),
            ]),
          ),
      ]),
    );
  }

  Widget _toc(ColorScheme cs) {
    return SizedBox(
      height: 54,
      child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(16, 10, 16, 6), children: [
        for (final s in _sections)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ActionChip(
              avatar: Icon(guideIcon(s['icon'] as String?), size: 16, color: _hex(s['color']) ?? cs.primary),
              label: Text(s['title'] as String, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              onPressed: () {
                if (_query.isNotEmpty) setState(() { _q.clear(); _query = ''; });
                WidgetsBinding.instance.addPostFrameCallback((_) => _jump(s['id'] as String));
              },
            ),
          ),
      ]),
    );
  }

  Widget _footer(ColorScheme cs) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text('Mis à jour par le serveur · ${_doc!['generated_at'] ?? ''}'.split('.').first.replaceAll('T', ' '),
            textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11)),
      );

  Widget _section(Map<String, dynamic> s, ColorScheme cs) {
    final color = _hex(s['color']) ?? cs.primary;
    final id = s['id'] as String;
    final blocks = (s['blocks'] as List).cast<Map<String, dynamic>>();
    return Container(
      key: _keys.putIfAbsent(id, () => GlobalKey()),
      margin: const EdgeInsets.only(bottom: 16),
      child: SoftCard(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(15)),
              child: Icon(guideIcon(s['icon'] as String?), color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s['title'] as String, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, letterSpacing: -0.2)),
                Text(s['summary'] as String, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5, height: 1.3)),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          for (final b in blocks) _block(b, color, cs),
        ]),
      ),
    );
  }

  Widget _block(Map<String, dynamic> b, Color color, ColorScheme cs) {
    switch (b['type']) {
      case 'h':
        return Padding(padding: const EdgeInsets.only(top: 14, bottom: 6), child: Text(b['text'] as String, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)));
      case 'p':
        return Padding(padding: const EdgeInsets.only(bottom: 8), child: _rich(b['text'] as String));
      case 'list':
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final t in (b['items'] as List).cast<String>())
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(padding: const EdgeInsets.only(top: 7, right: 10), child: Icon(Icons.circle, size: 6, color: color)),
                  Expanded(child: _rich(t)),
                ]),
              ),
          ]),
        );
      case 'steps':
        final items = (b['items'] as List).cast<Map<String, dynamic>>();
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(children: [
            for (var i = 0; i < items.length; i++)
              IntrinsicHeight(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  SizedBox(
                    width: 34,
                    child: Column(children: [
                      CircleAvatar(radius: 13, backgroundColor: color, child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12))),
                      if (i < items.length - 1) Expanded(child: Container(width: 2, margin: const EdgeInsets.symmetric(vertical: 3), color: color.withValues(alpha: 0.25))),
                    ]),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12, left: 4),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(items[i]['title'] as String, style: const TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        _rich(items[i]['text'] as String, style: TextStyle(height: 1.45, fontSize: 13.5, color: cs.onSurfaceVariant)),
                      ]),
                    ),
                  ),
                ]),
              ),
          ]),
        );
      case 'facts':
        final items = (b['items'] as List).cast<Map<String, dynamic>>();
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(16)),
          child: Column(children: [
            for (var i = 0; i < items.length; i++) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    flex: 5,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(items[i]['label'] as String, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      if (items[i]['hint'] != null) Text(items[i]['hint'] as String, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11.5)),
                    ]),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 5,
                    child: Row(mainAxisAlignment: MainAxisAlignment.end, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (items[i]['live'] == true) const Padding(padding: EdgeInsets.only(top: 5, right: 6), child: Icon(Icons.circle, size: 7, color: Color(0xFF22C55E))),
                      Flexible(child: Text(items[i]['value'] as String, textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: color))),
                    ]),
                  ),
                ]),
              ),
              if (i < items.length - 1) Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
            ],
          ]),
        );
      case 'callout':
        final tone = b['tone'] as String? ?? 'info';
        final (c, ic) = switch (tone) {
          'tip' => (const Color(0xFF16A34A), Icons.lightbulb_rounded),
          'warn' => (const Color(0xFFD97706), Icons.warning_amber_rounded),
          _ => (const Color(0xFF2563EB), Icons.info_rounded),
        };
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: c.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(14), border: Border(left: BorderSide(color: c, width: 4))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(ic, color: c, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(b['title'] as String, style: TextStyle(fontWeight: FontWeight.w800, color: c)),
                const SizedBox(height: 2),
                _rich(b['text'] as String, style: const TextStyle(height: 1.4, fontSize: 13)),
              ]),
            ),
          ]),
        );
      case 'example':
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withValues(alpha: 0.35))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Icon(Icons.science_rounded, size: 16, color: color), const SizedBox(width: 6), Text(b['title'] as String, style: TextStyle(fontWeight: FontWeight.w800, color: color))]),
            const SizedBox(height: 6),
            _rich(b['text'] as String, style: const TextStyle(height: 1.45, fontSize: 13.5)),
          ]),
        );
      case 'scale':
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(children: [
            for (final r in (b['items'] as List).cast<Map<String, dynamic>>())
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Container(width: 14, height: 34, decoration: BoxDecoration(color: _hex(r['color']), borderRadius: BorderRadius.circular(5))),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [Text(r['label'] as String, style: const TextStyle(fontWeight: FontWeight.w800)), const SizedBox(width: 8), Text(r['range'] as String, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12))]),
                      Text(r['hint'] as String, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                    ]),
                  ),
                ]),
              ),
          ]),
        );
      case 'faq':
        final items = (b['items'] as List).cast<Map<String, dynamic>>().where((x) {
          if (_query.isEmpty) return true;
          return '${x['q']} ${x['a']}'.toLowerCase().contains(_query);
        });
        return Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: Column(children: [
            for (final x in items)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(14)),
                child: ExpansionTile(
                  initiallyExpanded: _query.isNotEmpty,
                  tilePadding: const EdgeInsets.symmetric(horizontal: 14),
                  childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  title: Text(x['q'] as String, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  children: [_rich(x['a'] as String)],
                ),
              ),
          ]),
        );
      default:
        return const SizedBox.shrink();
    }
  }
}