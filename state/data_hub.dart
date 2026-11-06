import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../core/api.dart';
import '../core/api_survey.dart';
import '../core/models_survey.dart';
import 'session_controller.dart';

class DataHub extends ChangeNotifier {
  DataHub(this.api, this.session) {
    session.addResetHook(() {
      catalog = null;
      summary = null;
      available = [];
      error = null;
      notifyListeners();
    });
  }

  final ApiClient api;
  final SessionController session;

  DataCatalog? catalog;
  DataSummary? summary;
  List<SurveyCard> available = [];
  bool loading = false;
  String? error;
  int days = 180;

  List<SurveyCard> todoOf(String domain) => available.where((s) => s.domain == domain).toList();
  int todo(String domain) => todoOf(domain).length;

  Future<void> ensure() async {
    if (catalog == null) {
      await refresh();
    } else {
      await loadAvailable();
    }
  }

  Future<void> refresh() async {
    if (loading) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final r = await Future.wait([api.dataCatalog(), api.dataSummary(days: days)]);
      catalog = r[0] as DataCatalog;
      summary = r[1] as DataSummary;
    } on ApiException catch (e) {
      error = e.code;
    }
    loading = false;
    notifyListeners();
    await loadAvailable();
  }

  /// Enquêtes que l'utilisateur peut encore faire (délai de repos et zone déjà filtrés par le serveur).
  Future<void> loadAvailable() async {
    try {
      Position? p;
      if (session.consentOf('geolocation')) {
        try {
          p = await Geolocator.getLastKnownPosition();
        } catch (_) {}
      }
      available = await api.surveysAvailable(p?.latitude, p?.longitude);
      notifyListeners();
    } on ApiException catch (_) {}
  }

  Future<void> setDays(int d) async {
    days = d;
    notifyListeners();
    try {
      summary = await api.dataSummary(days: d);
    } on ApiException catch (e) {
      error = e.code;
    }
    notifyListeners();
  }
}