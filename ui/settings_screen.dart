import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/models.dart';
import '../core/theme.dart'; 
import '../core/util.dart';
import '../state/session_controller.dart';
import 'schedule_screen.dart';
import 'widgets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Future<List<DeviceOut>> _devices;

  @override
  void initState() {
    super.initState();
    _devices = context.read<ApiClient>().myDevices();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _run(Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      if (mounted) showToast(context, errorMessage(e));
    }
  }

  Future<void> _logout() async {
    final s = context.read<SessionController>();
    await s.signOut();
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Future<void> _delete() async {
    final ctl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer mon compte'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text("Action irréversible. Entrez votre mot de passe pour confirmer."),
          const SizedBox(height: 12),
          TextField(
            controller: ctl,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Mot de passe'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(100, 44), backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    final password = ctl.text;
    ctl.dispose();
    if (ok != true || !mounted) return;
    final api = context.read<ApiClient>();
    final s = context.read<SessionController>();
    try {
      await api.deleteMe(password);
      await s.afterAccountDeleted();
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (mounted) showToast(context, errorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SessionController>();
    final cs = Theme.of(context).colorScheme;
    final u = s.user!;

    return Scaffold(
      appBar: AppBar(title: const Text('Paramètres')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
        // ---------------------------------------------------------------- apparence
        const SectionTitle('Apparence'),
        SoftCard(
          child: SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto_rounded), label: Text('Auto')),
              ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_rounded), label: Text('Clair')),
              ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_rounded), label: Text('Sombre')),
            ],
            selected: {s.themeMode},
            onSelectionChanged: (v) => s.setThemeMode(v.first),
          ),
        ),

        // ---------------------------------------------------------------- confidentialité
        const SectionTitle('Confidentialité et participation'),
        SoftCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            SwitchListTile(
              secondary: const Icon(Icons.place_rounded),
              title: const Text('Géolocalisation'),
              value: s.consentOf('geolocation'),
              onChanged: (v) => _run(() => s.setConsent('geolocation', v)),
            ),
            const Divider(height: 1),
            SwitchListTile(
              secondary: const Icon(Icons.mic_rounded),
              title: const Text('Microphone'),
              subtitle: const Text("Seuls des niveaux en dB(A) sont envoyés, jamais l'audio."),
              value: s.consentOf('microphone'),
              onChanged: (v) => _run(() => s.setConsent('microphone', v)),
            ),
            const Divider(height: 1),
            SwitchListTile(
              secondary: const Icon(Icons.assignment_rounded),
              title: const Text('Enquêtes (Sunu Données)'),
              subtitle: const Text('Vos réponses sont anonymisées et agrégées par zone.'),
              value: s.consentOf('survey_data'),
              onChanged: (v) => _run(() => s.setConsent('survey_data', v)),
            ),
            const Divider(height: 1),
            SwitchListTile(
              secondary: const Icon(Icons.photo_camera_rounded),
              title: const Text('Photos de preuve'),
              subtitle: const Text('Conservées 90 jours, vues uniquement par les administrateurs.'),
              value: s.consentOf('photo'),
              onChanged: (v) => _run(() => s.setConsent('photo', v)),
            ),
            const Divider(height: 1),
            SwitchListTile(
              secondary: const Icon(Icons.pause_circle_outline_rounded),
              title: const Text('Mettre ma participation en pause'),
              value: u.participationPaused,
              onChanged: (v) => _run(() => s.setPaused(v)),
            ),
          ]),
        ),

        // ---------------------------------------------------------------- collecte hybride
        const SectionTitle('Collecte hybride'),
        SoftCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            SwitchListTile(
              secondary: const Icon(Icons.auto_awesome_rounded),
              title: const Text('Propositions de mesure'),
              value: u.hybridCollectionEnabled,
              onChanged: (v) => _run(() => s.setHybrid(v)),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.event_available_rounded),
              title: const Text('Mon planning'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const ScheduleScreen())),
            ),
          ]),
        ),

        // ---------------------------------------------------------------- appareils
        const SectionTitle('Mes appareils'),
        SoftCard(
          child: FutureBuilder<List<DeviceOut>>(
            future: _devices,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()));
              }
              if (snap.hasError) {
                return Text(errorMessage(snap.error!), style: TextStyle(color: cs.error));
              }
              final list = snap.data!;
              if (list.isEmpty) {
                return Text("Aucun appareil enregistré. Il le sera à la première mesure.",
                    style: TextStyle(color: cs.onSurfaceVariant));
              }
              return Column(children: [
                for (final d in list)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.smartphone_rounded),
                    title: Text(d.sampleRate != null ? 'Téléphone · ${d.sampleRate} Hz' : 'Téléphone'),
                    trailing: StatusChip(
                      d.calibrated ? 'Calibré' : 'Non calibré',
                      d.calibrated ? const Color(0xFF22C55E) : const Color(0xFFF59E0B),
                    ),
                  ),
              ]);
            },
          ),
        ),


        // ---------------------------------------------------------------- compte
        const SectionTitle('Compte'),
        SoftCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            ListTile(
              leading: const Icon(Icons.logout_rounded),
              title: const Text('Se déconnecter'),
              onTap: _logout,
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.delete_forever_rounded, color: Colors.red),
              title: const Text('Supprimer mon compte', style: TextStyle(color: Colors.red)),
              onTap: _delete,
            ),
          ]),
        ),
      ]),
    );
  }
}