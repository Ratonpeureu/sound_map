import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/util.dart';
import '../state/session_controller.dart';
import 'widgets.dart';

class ConsentScreen extends StatefulWidget {
  const ConsentScreen({super.key});
  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  bool _geo = true, _mic = true, _busy = false;

  Future<void> _save() async {
    final s = context.read<SessionController>();
    setState(() => _busy = true);
    try {
      await s.saveConsents(geolocation: _geo, microphone: _mic);
    } catch (e) {
      if (mounted) showToast(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(24), children: [
          const SizedBox(height: 12),
          Icon(Icons.verified_user_rounded, size: 48, color: cs.primary),
          const SizedBox(height: 16),
          Text('Vos données, votre choix',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Text(
            "Pour contribuer à la carte sonore, l'application a besoin de deux autorisations. "
            "Le son est analysé sur votre téléphone : seuls des niveaux en dB(A) sont envoyés, jamais l'audio.",
            style: TextStyle(color: cs.onSurfaceVariant, height: 1.4),
          ),
          const SizedBox(height: 24),
          SoftCard(
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.place_rounded),
              title: const Text('Géolocalisation', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Situer la mesure dans une zone de la carte.'),
              value: _geo,
              onChanged: (v) => setState(() => _geo = v),
            ),
          ),
          const SizedBox(height: 12),
          SoftCard(
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.mic_rounded),
              title: const Text('Microphone', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Mesurer le niveau sonore pendant quelques secondes.'),
              value: _mic,
              onChanged: (v) => setState(() => _mic = v),
            ),
          ),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                : const Text('Continuer'),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => context.read<SessionController>().skipConsents(),
            child: const Text('Plus tard (consultation de la carte uniquement)'),
          ),
        ]),
      ),
    );
  }
}