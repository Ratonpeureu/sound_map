import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/util.dart';
import '../state/proposals_controller.dart';
import 'widgets.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});
  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  static const _days = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
  bool _loading = true, _saving = false, _active = true;
  String _mode = 'both';
  Set<int> _sel = {0, 1, 2, 3, 4, 5, 6};
  TimeOfDay _start = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 20, minute: 0);
  final List<TimeOfDay> _pref = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  TimeOfDay _parse(String s) {
    final p = s.split(':');
    return TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';
  String _show(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    try {
      final s = await context.read<ApiClient>().getSchedule();
      if (s != null) {
        _active = s.active;
        _mode = s.mode;
        _sel = s.days.toSet();
        _start = _parse(s.start);
        _end = _parse(s.end);
        _pref
          ..clear()
          ..addAll(s.preferred.map(_parse));
      }
    } catch (e) {
      if (mounted) showToast(context, errorMessage(e));
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (_sel.isEmpty) {
      showToast(context, 'Choisissez au moins un jour.');
      return;
    }
    setState(() => _saving = true);
    try {
      await context.read<ApiClient>().putSchedule({
        'days_of_week': _sel.toList()..sort(),
        'window_start': _fmt(_start),
        'window_end': _fmt(_end),
        'preferred_times': [for (final t in _pref) _fmt(t)],
        'mode': _mode,
        'active': _active,
      });
      if (mounted) {
        context.read<ProposalsController>().scheduleChanged();
        showToast(context, 'Planning enregistré.');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) showToast(context, errorMessage(e));
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<TimeOfDay?> _pick(TimeOfDay initial) =>
      showTimePicker(context: context, initialTime: initial, builder: (c, w) => MediaQuery(
          data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true), child: w!));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Mon planning')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
              SoftCard(
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Planning actif', style: TextStyle(fontWeight: FontWeight.w700)),
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                ),
              ),
              const SectionTitle('Mode'),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'scheduled', label: Text('Planifié')),
                  ButtonSegment(value: 'contextual', label: Text('Contextuel')),
                  ButtonSegment(value: 'both', label: Text('Les deux')),
                ],
                selected: {_mode},
                onSelectionChanged: (v) => setState(() => _mode = v.first),
                showSelectedIcon: false,
              ),
              const SectionTitle('Jours'),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (var i = 0; i < 7; i++)
                  FilterChip(
                    label: Text(_days[i]),
                    selected: _sel.contains(i),
                    showCheckmark: false,
                    onSelected: (v) => setState(() => v ? _sel.add(i) : _sel.remove(i)),
                  ),
              ]),
              const SectionTitle('Fenêtre horaire'),
              Row(children: [
                Expanded(
                    child: OutlinedButton.icon(
                        icon: const Icon(Icons.wb_twilight_rounded),
                        label: Text('Début ${_show(_start)}'),
                        onPressed: () async {
                          final t = await _pick(_start);
                          if (t != null) setState(() => _start = t);
                        })),
                const SizedBox(width: 10),
                Expanded(
                    child: OutlinedButton.icon(
                        icon: const Icon(Icons.nights_stay_outlined),
                        label: Text('Fin ${_show(_end)}'),
                        onPressed: () async {
                          final t = await _pick(_end);
                          if (t != null) setState(() => _end = t);
                        })),
              ]),
              SectionTitle(
                'Horaires préférés (${_pref.length}/12)',
                trailing: TextButton.icon(
                  onPressed: _pref.length >= 12
                      ? null
                      : () async {
                          final t = await _pick(const TimeOfDay(hour: 12, minute: 0));
                          if (t != null && !_pref.contains(t)) setState(() => _pref.add(t));
                        },
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Ajouter'),
                ),
              ),
              if (_pref.isEmpty)
                Text('Utilisés par le mode « planifié ».', style: TextStyle(color: cs.onSurfaceVariant))
              else
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final t in _pref)
                    InputChip(
                      label: Text(_show(t)),
                      onDeleted: () => setState(() => _pref.remove(t)),
                    ),
                ]),
              const SizedBox(height: 28),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                    : const Text('Enregistrer'),
              ),
            ]),
    );
  }
}