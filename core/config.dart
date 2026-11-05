import 'package:latlong2/latlong.dart';

class AppConfig {
  /// Surchargeable : --dart-define=API_BASE=https://ton-api
  static const String defaultApiBase =
      String.fromEnvironment('API_BASE', defaultValue: 'https://soundmaps.rhmanager.site');
  static const String apiPrefix = '/api/v1';

  /// À remplacer par ton applicationId (User-Agent des tuiles).
  static const String packageName =
      String.fromEnvironment('PACKAGE_NAME', defaultValue: 'com.nagora.sunusound');

  /// Niveau (dB) correspondant à une puissance quadratique moyenne de 1.0 (0 dBFS) après pondération A.
  static const double micReferenceOffsetDb = 90.0;

  // --- CORRECTION ICI ---
  // On met ta clé API directement comme valeur par défaut.
  // Comme ça, même si tu oublies --dart-define, la carte fonctionne.
  static const String cartoApiKey = String.fromEnvironment(
    'CARTO_API_KEY',
    defaultValue: 'cb1_50kr_1_9cd5f225ac0a2c59e3c90a47', 
  );

  static const int sampleRate = 44100;
  static const int defaultSessionSeconds = 15; // SESSION_DURATION_SECONDS côté backend
  static const int mapRefreshSeconds = 30;
  static const int proposalPollMinutes = 5;
  static const int batchMaxItems = 200; // BATCH_MAX_ITEMS côté backend
  static const int maxAttempts = 5;

  // --- UTILISATION DE LA CLE DANS LES URLS ---
  static const String tileLight = 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png?key=$cartoApiKey';
  static const String tileDark = 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png?key=$cartoApiKey';

  /// Centre de repli tant que le GPS n'a pas répondu (Dakar).
  static const LatLng fallbackCenter = LatLng(14.6937, -17.4441);
}