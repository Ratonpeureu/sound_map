import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

import 'api.dart';

// ------------------------------------------------------------------ tags de contexte sonore
enum NoiseTag { traffic, commerce, construction, music, gathering, other }

extension NoiseTagX on NoiseTag {
  String get label => switch (this) {
        NoiseTag.traffic => 'Circulation',
        NoiseTag.commerce => 'Commerce',
        NoiseTag.construction => 'Chantier',
        NoiseTag.music => 'Musique',
        NoiseTag.gathering => 'Rassemblement',
        NoiseTag.other => 'Autre',
      };
  IconData get icon => switch (this) {
        NoiseTag.traffic => Icons.directions_car_rounded,
        NoiseTag.commerce => Icons.storefront_rounded,
        NoiseTag.construction => Icons.construction_rounded,
        NoiseTag.music => Icons.music_note_rounded,
        NoiseTag.gathering => Icons.groups_rounded,
        NoiseTag.other => Icons.more_horiz_rounded,
      };
  static NoiseTag? parse(String? v) {
    for (final t in NoiseTag.values) {
      if (t.name == v) return t;
    }
    return null;
  }
}

// ------------------------------------------------------------------ niveaux sonores
Color noiseColor(double db) {
  const stops = <double>[35, 50, 60, 70, 80, 95];
  const cols = <Color>[
    Color(0xFF22C55E),
    Color(0xFF84CC16),
    Color(0xFFFACC15),
    Color(0xFFF97316),
    Color(0xFFEF4444),
    Color(0xFF9333EA),
  ];
  if (db <= stops.first) return cols.first;
  if (db >= stops.last) return cols.last;
  for (var i = 0; i < stops.length - 1; i++) {
    if (db <= stops[i + 1]) {
      final t = (db - stops[i]) / (stops[i + 1] - stops[i]);
      return Color.lerp(cols[i], cols[i + 1], t)!;
    }
  }
  return cols.last;
}

String noiseLabel(double db) => db < 45
    ? 'Calme'
    : db < 60
        ? 'Modéré'
        : db < 70
            ? 'Bruyant'
            : db < 80
                ? 'Très bruyant'
                : 'Intense';

String dayPartLabel(String v) => switch (v) {
      'morning' => 'Matin',
      'afternoon' => 'Après-midi',
      'evening' => 'Soirée',
      'night' => 'Nuit',
      _ => 'Tout',
    };

// ------------------------------------------------------------------ qualité / scoring
String qualityLabel(String s) => switch (s) {
      'validated' => 'Validée',
      'indicative' => 'Indicative',
      'rejected' => 'Rejetée',
      _ => 'En évaluation',
    };

Color qualityColor(String s) => switch (s) {
      'validated' => const Color(0xFF22C55E),
      'indicative' => const Color(0xFFF59E0B),
      'rejected' => const Color(0xFFEF4444),
      _ => const Color(0xFF94A3B8),
    };

String reasonLabel(String code) => switch (code) {
      'level_out_of_range' => 'Niveau hors plage plausible',
      'inconsistent_levels' => 'Niveaux Lmin / LAeq / Lmax incohérents',
      'timestamp_in_future' => 'Horodatage dans le futur',
      'measurement_too_old' => 'Mesure trop ancienne',
      'gps_accuracy_too_low' => 'Précision GPS insuffisante',
      'capture_too_short' => 'Capture trop courte',
      'audio_saturation' => 'Saturation du micro',
      'moved_during_capture' => 'Déplacement pendant la mesure',
      'uncalibrated_device' => 'Téléphone non calibré',
      'neighbor_outlier' => 'Écart important avec les zones voisines',
      'insufficient_neighbors' => 'Peu de mesures voisines pour comparer',
      'low_score' => 'Score global trop bas',
      'peer_confirmed' => 'Confirmée par des analyseurs',
      'peer_rejected' => 'Rejetée par des analyseurs',
      'peer_adjusted_up' => 'Niveau relevé par des analyseurs',
      'peer_adjusted_down' => 'Niveau abaissé par des analyseurs',
      'admin_override' => "Décision d'un administrateur",
      _ => code,
    };

String? reasonTip(String code) => switch (code) {
      'gps_accuracy_too_low' => 'Attendez un meilleur signal GPS avant de mesurer.',
      'audio_saturation' => 'Éloignez le téléphone de la source sonore.',
      'moved_during_capture' => 'Restez immobile pendant toute la mesure.',
      'capture_too_short' => 'Ne quittez pas l\'écran avant la fin du compte à rebours.',
      'uncalibrated_device' => "Le modèle de votre téléphone n'a pas encore été calibré.",
      _ => null,
    };

// ------------------------------------------------------------------ messages d'erreur
String apiErrorLabel(String code) => switch (code) {
      'network' => 'Serveur injoignable. Vérifiez votre connexion.',
      'invalid_credentials' => 'Identifiants incorrects.',
      'account_temporarily_locked' => 'Compte temporairement verrouillé. Réessayez plus tard.',
      'registration_unavailable' => "Inscription indisponible pour cette organisation.",
      'password_policy_violation' =>
        'Le mot de passe ne respecte pas la politique (longueur minimale, lettres et chiffres).',
      'account_exists' => 'Un compte existe déjà avec cet e-mail.',
      'rate_limited' => 'Trop de requêtes. Patientez un instant.',
      'consent_required' => 'Les consentements géolocalisation et micro sont requis.',
      'participation_paused' => 'Votre participation est en pause.',
      'device_not_found' => 'Appareil introuvable. Réessayez.',
      'device_belongs_to_another_account' => 'Cet appareil est lié à un autre compte.',
      'proposal_not_accepted' => "La proposition n'a pas été acceptée.",
      'proposal_not_pending' => "Cette proposition n'est plus disponible.",
      'proposal_not_found' => 'Proposition introuvable.',
      'schedule_not_set' => 'Aucun planning défini.',
      'insufficient_data' => 'Pas assez de données pour cette zone.',
      'invalid_password' => 'Mot de passe incorrect.',
      'tenant_inactive' => 'Organisation désactivée.',
      'user_inactive' => 'Compte désactivé.',
      'invalid_token' || 'not_authenticated' || 'token_revoked' || 'refresh_token_reuse_detected' =>
        'Session expirée. Reconnectez-vous.',
      'payload_too_large' => 'Envoi trop volumineux.',
      'period_too_long' => 'Période trop longue.',
      'validation_error' => 'Données invalides.',
      'invalid_timezone' => 'Fuseau horaire invalide.',
      'mic_denied' => "L'accès au micro est nécessaire.",
      'location_denied' => "L'accès à la localisation est nécessaire.",
      'gps_unavailable' => 'Position GPS indisponible. Réessayez en extérieur.',
      'capture_error' => "Erreur pendant l'enregistrement.",
      'quota_exhausted' => 'Solde de prélèvements épuisé. Il se recharge au fil de la journée.',
      'cell_cooldown' => 'Vous avez déjà mesuré ici. Attendez un peu ou changez de zone.',
      'too_many_frames' => "Période trop longue pour l'historique animé.",
      'mission_not_found' => 'Mission introuvable.',
      'mission_not_offered' => "Cette mission n'est plus disponible.",
      'mission_limit_reached' => "Trop de missions en cours : terminez-en une avant d'en accepter une autre.",
      'display_name_taken' => 'Ce pseudo est déjà pris.',
      'display_name_reserved' => 'Ce pseudo est réservé.',
      'invitation_required' => "Un code d'invitation est nécessaire.",
      'invalid_invitation' => "Code d'invitation invalide ou expiré.",
      'invite_limit_reached' => "Vous avez déjà le maximum de codes actifs.",
      'invitation_not_found' => 'Invitation introuvable.',
      'analyst_not_eligible' => "Vous ne remplissez pas encore les conditions d'analyseur.",
      'not_analyst' => "Le rôle d'analyseur n'est pas actif.",
      'review_expired' => 'Cet avis a expiré.',
      'review_not_found' => 'Avis introuvable.',
      'invalid_recovery_code' => 'Code de récupération invalide.',
      'invalid_current_password' => 'Mot de passe actuel incorrect.',
      'password_too_common' => 'Mot de passe trop courant.',
      'password_contains_identity' => 'Le mot de passe ne doit pas contenir votre nom ou pseudo.',
      'terms_not_accepted' => "Acceptez les conditions d'utilisation.",
      'road_segment_not_found' => 'Route introuvable.',
      'mission_closed' => 'Cette mission est terminée.',

      'conflict' => 'Conflit lors de l\'envoi.',
      _ => 'Une erreur est survenue ($code).',
    };

String errorMessage(Object e) {
  if (e is ApiException) return apiErrorLabel(e.code);
  return 'Une erreur est survenue.';
}

String proposalReasonLabel(String r) => switch (r) {
      'scheduled_slot' => 'Créneau planifié : une mesure vous est proposée.',
      'priority' => 'Zone prioritaire : une mesure vous est proposée.',
      'exploration' => 'Zone à explorer : une mesure vous est proposée.',
      'existing_proposal' => 'Vous avez déjà une proposition en cours.',
      'participation_paused' => 'Votre participation est en pause.',
      'hybrid_disabled' => 'La collecte hybride est désactivée.',
      'consent_missing' => 'Consentements manquants.',
      'battery_low' => 'Batterie trop faible.',
      'outside_schedule' => 'En dehors de votre planning.',
      'trigger_not_enabled' => "Ce mode n'est pas activé dans votre planning.",
      'not_a_scheduled_slot' => "Ce n'est pas un de vos horaires préférés.",
      'daily_cap_reached' => 'Limite quotidienne atteinte.',
      'too_soon' => 'Trop tôt depuis la dernière proposition.',
      'tomtom_not_configured' || 'tomtom_unavailable' || 'tomtom_unreachable' ||
      'tomtom_key_rejected' || 'tomtom_upstream_error' => 'Service trafic indisponible.',
      'tomtom_rate_limited' => 'Service trafic saturé. Réessayez dans un instant.',
      'no_traffic_data' => 'Pas de données de trafic ici.',
      'route_not_found' => 'Aucun itinéraire trouvé.',
      'invalid_bbox' || 'bbox_too_large' => 'Zone trop grande. Zoomez davantage.',
      'low_priority' => 'Aucune zone prioritaire autour de vous pour le moment.',
      _ => r,
    };

// ------------------------------------------------------------------ formats
String fmtDateTime(DateTime d) => DateFormat('d MMM · HH:mm', 'fr_FR').format(d);
String fmtTime(DateTime d) => DateFormat('HH:mm', 'fr_FR').format(d);
String fmtDay(DateTime d) => DateFormat('d MMM', 'fr_FR').format(d);

String fmtAgo(DateTime d) {
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return "à l'instant";
  if (diff.inMinutes < 60) return 'il y a ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'il y a ${diff.inHours} h';
  return 'il y a ${diff.inDays} j';
}

void showToast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

// ------------------------------------------------------------------ permissions
Future<bool> ensureLocationPermission() async {
  if (!await Geolocator.isLocationServiceEnabled()) return false;
  var p = await Geolocator.checkPermission();
  if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
  return p == LocationPermission.whileInUse || p == LocationPermission.always;
}