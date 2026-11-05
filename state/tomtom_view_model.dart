import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../core/api.dart';
import '../core/models.dart';
import 'session_controller.dart';

class TomTomViewModel extends ChangeNotifier {
  TomTomViewModel(this.api, this.session);

  final ApiClient api;
  final SessionController session;

  bool _tilesUnavailable = false;
  bool _tilesRequested = false;
  String? _flowUrl;
  String? get flowUrl => _flowUrl;

  List<TrafficIncident> incidents = const [];
  RouteResult? route;

  DateTime? _incidentsAt;
  String? _incidentsBbox;
  bool _loadingIncidents = false;

  Future<void> ensureTiles() async {
    if (_tilesUnavailable || _tilesRequested) return;
    _tilesRequested = true;
    try {
      final s = await api.tileSession();
      // Le backend renvoie plusieurs couches ; on prend 'flow' si dispo, sinon la 1re.
      _flowUrl = s.layers['flow'] ?? (s.layers.isNotEmpty ? s.layers.values.first : null);
      if (_flowUrl == null) {
        _tilesUnavailable = true;
        debugPrint('[TomTom] tile-session vide → désactivé');
      }
      notifyListeners();
    } on ApiException catch (e) {
      if (e.status == 404) {
        _tilesUnavailable = true;
        debugPrint('[TomTom] tile-session 404 → désactivé');
      } else {
        _tilesRequested = false;
      }
    } catch (_) {
      _tilesRequested = false;
    }
  }

  Future<void> loadIncidents(String bbox) async {
    if (_tilesUnavailable || _loadingIncidents) return;
    if (_incidentsAt != null && _incidentsBbox == bbox &&
        DateTime.now().difference(_incidentsAt!) < const Duration(seconds: 60)) {
      return;
    }
    _loadingIncidents = true;
    try {
      incidents = await api.trafficIncidents(bbox);
      _incidentsAt = DateTime.now();
      _incidentsBbox = bbox;
      notifyListeners();
    } on ApiException catch (e) {
      if (e.status == 404) _tilesUnavailable = true;
    } catch (_) {}
    _loadingIncidents = false;
  }

  void clearIncidents() {
    if (incidents.isEmpty) return;
    incidents = const [];
    notifyListeners();
  }

  Future<void> routeTo(LatLng from, LatLng to) async {
    if (_tilesUnavailable) throw ApiException(503, 'tomtom_unavailable');
    route = await api.route(from.latitude, from.longitude, to.latitude, to.longitude);
    notifyListeners();
  }

  void clearRoute() {
    if (route == null) return;
    route = null;
    notifyListeners();
  }
}