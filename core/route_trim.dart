import 'dart:math';

import 'package:latlong2/latlong.dart';

/// Coupe l'itinéraire à l'entrée du cercle de tolérance de la cible : plus de dépassement ni de boucle.
({List<LatLng> points, double ratio}) trimRoute(List<LatLng> pts, LatLng target, double radiusM) {
  if (pts.length < 2) return (points: pts, ratio: 1.0);
  const dist = Distance();
  double len(List<LatLng> l) {
    var s = 0.0;
    for (var i = 0; i < l.length - 1; i++) {
      s += dist.as(LengthUnit.Meter, l[i], l[i + 1]);
    }
    return s;
  }

  final stop = max(15.0, radiusM * 0.6);
  final cosL = cos(target.latitude * pi / 180);
  double x(LatLng p) => (p.longitude - target.longitude) * 111320.0 * cosL;
  double y(LatLng p) => (p.latitude - target.latitude) * 110574.0;

  for (var i = 0; i < pts.length - 1; i++) {
    final ax = x(pts[i]), ay = y(pts[i]), bx = x(pts[i + 1]), by = y(pts[i + 1]);
    double? t;
    if (ax * ax + ay * ay <= stop * stop) {
      t = 0;
    } else {
      final dx = bx - ax, dy = by - ay;
      final a = dx * dx + dy * dy;
      if (a > 0) {
        final b = 2 * (ax * dx + ay * dy);
        final c = ax * ax + ay * ay - stop * stop;
        final disc = b * b - 4 * a * c;
        if (disc >= 0) {
          final tt = (-b - sqrt(disc)) / (2 * a);
          if (tt >= 0 && tt <= 1) t = tt;
        }
      }
    }
    if (t == null) continue;
    final out = pts.sublist(0, i + 1);
    if (t > 0) {
      out.add(LatLng(pts[i].latitude + (pts[i + 1].latitude - pts[i].latitude) * t,
          pts[i].longitude + (pts[i + 1].longitude - pts[i].longitude) * t));
    }
    final res = out.length < 2 ? [pts.first, pts.first] : out;
    final full = len(pts);
    return (points: res, ratio: full <= 0 ? 1.0 : (len(res) / full).clamp(0.0, 1.0).toDouble());
  }
  return (points: pts, ratio: 1.0);
}