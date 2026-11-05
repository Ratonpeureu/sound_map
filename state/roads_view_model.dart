import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../core/api.dart';
import '../core/api_ext.dart';
import '../core/models.dart';
import '../core/models_roads.dart';
import 'session_controller.dart';

class _Net {
  _Net(this.etag, this.segs, this.truncated);
  final String? etag;
  final List<RoadSeg> segs;
  final bool truncated;
}

/// Réseau routier réel : géométrie (mise en cache + ETag) et état de bruit (rafraîchi souvent).
class RoadsViewModel extends ChangeNotifier {
  RoadsViewModel(this.api, this.session) {
    session.addResetHook(() {
      segs = const [];
      states = const {};
      _cache.clear();
      selected = null;
      notifyListeners();
    });
  }

  final ApiClient api;
  final SessionController session;

  /// En dessous, seules les très grandes routes existeraient : on n'affiche rien.
  static const double minZoom = 10.5;

  List<RoadSeg> segs = const [];
  Map<String, RoadState> states = const {};
  bool loading = false, truncated = false;
  String? error, selected;

  final Map<String, _Net> _cache = {};
  bool _busy = false, _again = false;
  MapFilters? _f;
  String? _bbox;
  double _zoom = 0;

  static int rankFor(double z) => z < 8 ? 2 : z < 11 ? 3 : z < 13 ? 4 : z < 15 ? 5 : 6;

  /// bbox calée sur 0,02° : mêmes clés de cache et mêmes ETag pour tous.
  static String _snap(String bbox) {
    final a = bbox.split(',').map(double.parse).toList();
    const s = 0.02;
    String f(double v) => v.toStringAsFixed(5);
    return [
      f((a[0] / s).floorToDouble() * s),
      f((a[1] / s).floorToDouble() * s),
      f((a[2] / s).ceilToDouble() * s),
      f((a[3] / s).ceilToDouble() * s),
    ].join(',');
  }

  void select(String? id) {
    selected = id;
    notifyListeners();
  }

  Future<void> load(MapFilters f, String bbox, double zoom) async {
    _f = f;
    _bbox = bbox;
    _zoom = zoom;
    if (zoom < minZoom) {
      if (segs.isNotEmpty || states.isNotEmpty) {
        segs = const [];
        states = const {};
        truncated = false;
        notifyListeners();
      }
      return;
    }
    if (_busy) {
      _again = true;
      return;
    }
    _busy = true;
    loading = true;
    notifyListeners();
    try {
      final box = _snap(bbox);
      final rank = rankFor(zoom);
      final key = '$box|$rank';
      final old = _cache[key];
      final results = await Future.wait([
        api.getConditional('/roads/network', query: {'bbox': box, 'max_rank': rank}, etag: old?.etag),
        api.roadStates(f, box, zoom, rank),
      ]);
      final r = results[0] as ({int status, dynamic data, String? etag});
      _Net net;
      if (r.status == 304 && old != null) {
        net = old;
      } else {
        final d = r.data as Map<String, dynamic>;
        net = _Net(r.etag, [for (final x in d['features'] as List) RoadSeg.fromFeature(x as Map<String, dynamic>)],
            (d['truncated'] as bool?) ?? false);
        _cache[key] = net;
        if (_cache.length > 8) _cache.remove(_cache.keys.first);
      }
      if (!identical(segs, net.segs)) segs = net.segs;
      truncated = net.truncated;
      states = results[1] as Map<String, RoadState>;
      error = null;
    } on ApiException catch (e) {
      error = e.code;
    } catch (_) {
      error = 'network';
    }
    loading = false;
    _busy = false;
    notifyListeners();
    if (_again) {
      _again = false;
      load(_f!, _bbox!, _zoom);
    }
  }

  Future<void> refreshStates() async {
    final f = _f, b = _bbox;
    if (f == null || b == null) return;
    await load(f, b, _zoom);
  }

  /// Tronçon touché (tolérance ≈ 16 pixels écran), ou null.
  RoadSeg? hit(LatLng p, double zoom) {
    if (segs.isEmpty) return null;
    final cosLat = cos(p.latitude * pi / 180);
    final tol = 156543.03392 * cosLat / pow(2, zoom) * 16;
    final dLat = tol / 110574.0, dLon = tol / (111320.0 * cosLat);
    RoadSeg? best;
    var bd = tol;
    for (final s in segs) {
      if (p.latitude < s.minLat - dLat || p.latitude > s.maxLat + dLat) continue;
      if (p.longitude < s.minLon - dLon || p.longitude > s.maxLon + dLon) continue;
      for (var i = 0; i < s.points.length - 1; i++) {
        final d = _distM(p, s.points[i], s.points[i + 1], cosLat);
        if (d < bd) {
          bd = d;
          best = s;
        }
      }
    }
    return best;
  }

  static double _distM(LatLng p, LatLng a, LatLng b, double cosLat) {
    final ax = (a.longitude - p.longitude) * 111320.0 * cosLat, ay = (a.latitude - p.latitude) * 110574.0;
    final bx = (b.longitude - p.longitude) * 111320.0 * cosLat, by = (b.latitude - p.latitude) * 110574.0;
    final dx = bx - ax, dy = by - ay;
    final l2 = dx * dx + dy * dy;
    final t = l2 == 0 ? 0.0 : ((-ax * dx - ay * dy) / l2).clamp(0.0, 1.0);
    final x = ax + dx * t, y = ay + dy * t;
    return sqrt(x * x + y * y);
  }
}