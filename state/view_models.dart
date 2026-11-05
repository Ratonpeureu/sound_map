import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../core/api.dart';
import '../core/config.dart';
import '../core/local_store.dart';
import '../core/models.dart';
import 'session_controller.dart';

class MapViewModel extends ChangeNotifier {
  MapViewModel(this.api, this.session) {
    session.addResetHook(() {
      cells = [];
      myPoints = [];
      selected = null;
      error = null;
      stopAuto();
      notifyListeners();
    });
  }

  final ApiClient api;
  final SessionController session;

  MapFilters filters = const MapFilters();
  List<NoiseCell> cells = [];
  List<MyPoint> myPoints = [];
  bool loading = false;
  String? error;
  DateTime? updatedAt;
  String? selected;
  String? _bbox;
  Timer? _auto;
  bool _loadingNow = false;

  List<NoiseCell> get hot => cells.where((c) => c.isHot).toList();

  void select(String? h3) {
    selected = h3;
    notifyListeners();
  }

  Future<void> load({String? bbox}) async {
    if (bbox != null) _bbox = bbox;
    if (_loadingNow) return;
    _loadingNow = true;
    loading = true;
    notifyListeners();
    try {
      cells = await api.mapNoise(filters, bbox: _bbox);
      error = null;
      updatedAt = DateTime.now();
    } on ApiException catch (e) {
      error = e.code;
    }
    myPoints = session.store?.loadPoints() ?? [];
    loading = false;
    _loadingNow = false;
    notifyListeners();
  }

  void setFilters(MapFilters f) {
    filters = f;
    load();
  }

  void startAuto() {
    _auto?.cancel();
    _auto = Timer.periodic(const Duration(seconds: AppConfig.mapRefreshSeconds), (_) => load());
  }

  void stopAuto() {
    _auto?.cancel();
    _auto = null;
  }

  void refreshMine() {
    myPoints = session.store?.loadPoints() ?? [];
    notifyListeners();
  }

  NoiseCell? cellAt(LatLng p) {
    for (final c in cells) {
      if (_inPolygon(p, c.polygon)) return c;
    }
    return null;
  }

  static bool _inPolygon(LatLng p, List<LatLng> poly) {
    var inside = false;
    for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      final xi = poly[i].longitude, yi = poly[i].latitude;
      final xj = poly[j].longitude, yj = poly[j].latitude;
      final cross = ((yi > p.latitude) != (yj > p.latitude)) &&
          (p.longitude < (xj - xi) * (p.latitude - yi) / (yj - yi) + xi);
      if (cross) inside = !inside;
    }
    return inside;
  }
}

class HistoryViewModel extends ChangeNotifier {
  HistoryViewModel(this.api, this.session) {
    session.addResetHook(() {
      items = [];
      stats = null;
      hasMore = true;
      error = null;
      notifyListeners();
    });
  }

  final ApiClient api;
  final SessionController session;
  static const _page = 30;

  List<HistoryItem> items = [];
  Contributions? stats;
  bool loading = false, hasMore = true;
  String? error;

  Future<void> reload() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final r = await Future.wait([api.history(limit: _page, offset: 0), api.contributions()]);
      items = r[0] as List<HistoryItem>;
      stats = r[1] as Contributions;
      hasMore = items.length == _page;
    } on ApiException catch (e) {
      error = e.code;
    }
    loading = false;
    notifyListeners();
  }

  Future<void> loadMore() async {
    if (loading || !hasMore) return;
    loading = true;
    notifyListeners();
    try {
      final more = await api.history(limit: _page, offset: items.length);
      items = [...items, ...more];
      hasMore = more.length == _page;
    } on ApiException catch (e) {
      error = e.code;
    }
    loading = false;
    notifyListeners();
  }
}