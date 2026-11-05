import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:latlong2/latlong.dart';

double _n(dynamic v) => (v as num).toDouble();
DateTime _t(dynamic v) => DateTime.parse(v as String).toLocal();

// ------------------------------------------------------------------ champ de bruit (nuage) du serveur
class FieldWind {
  FieldWind({required this.u, required this.v, required this.speedKmh, required this.dirFrom});
  final double u, v, speedKmh, dirFrom; // u = vers l'est, v = vers le nord (m/s)
  factory FieldWind.fromJson(Map<String, dynamic> j) => FieldWind(
      u: _n(j['u']), v: _n(j['v']), speedKmh: _n(j['speed_kmh']), dirFrom: _n(j['dir_from']));
}

class FieldGrid {
  FieldGrid({
    required this.west,
    required this.south,
    required this.east,
    required this.north,
    required this.cols,
    required this.rows,
    required this.level,
    required this.support,
    required this.dbOffset,
    required this.dbStep,
    required this.sources,
    this.wind,
    this.minDb,
    this.maxDb,
  });
  final double west, south, east, north, dbOffset, dbStep;
  final int cols, rows, sources;
  final Uint8List level, support; // lignes du sud au nord, colonnes de l'ouest à l'est
  final FieldWind? wind;
  final double? minDb, maxDb;

  factory FieldGrid.fromJson(Map<String, dynamic> j) {
    final b = j['bounds'] as List;
    return FieldGrid(
      west: _n(b[0]),
      south: _n(b[1]),
      east: _n(b[2]),
      north: _n(b[3]),
      cols: (j['cols'] as num).toInt(),
      rows: (j['rows'] as num).toInt(),
      level: base64Decode(j['level_b64'] as String),
      support: base64Decode(j['support_b64'] as String),
      dbOffset: _n(j['db_offset']),
      dbStep: _n(j['db_step']),
      sources: (j['sources'] as num).toInt(),
      wind: j['wind'] == null ? null : FieldWind.fromJson(j['wind'] as Map<String, dynamic>),
      minDb: (j['min_db'] as num?)?.toDouble(),
      maxDb: (j['max_db'] as num?)?.toDouble(),
    );
  }

  /// (niveau dB(A), support 0..1). Niveau NaN et support 0 s'il n'y a aucune donnée.
  (double, double) sample(double lat, double lon) {
    if (lat < south || lat > north || lon < west || lon > east) return (double.nan, 0.0);
    final fx = ((lon - west) / (east - west) * cols - 0.5).clamp(0.0, cols - 1.0).toDouble();
    final fy = ((lat - south) / (north - south) * rows - 0.5).clamp(0.0, rows - 1.0).toDouble();
    final x0 = fx.floor(), y0 = fy.floor();
    final x1 = min(x0 + 1, cols - 1), y1 = min(y0 + 1, rows - 1);
    final tx = fx - x0, ty = fy - y0;
    final i00 = y0 * cols + x0, i10 = y0 * cols + x1, i01 = y1 * cols + x0, i11 = y1 * cols + x1;
    final w00 = (1 - tx) * (1 - ty), w10 = tx * (1 - ty), w01 = (1 - tx) * ty, w11 = tx * ty;
    final s00 = level[i00] == 0 ? 0.0 : support[i00] / 255.0;
    final s10 = level[i10] == 0 ? 0.0 : support[i10] / 255.0;
    final s01 = level[i01] == 0 ? 0.0 : support[i01] / 255.0;
    final s11 = level[i11] == 0 ? 0.0 : support[i11] / 255.0;
    final ws = w00 * s00 + w10 * s10 + w01 * s01 + w11 * s11;
    if (ws <= 0) return (double.nan, 0.0);
    final wl = w00 * s00 * (dbOffset + level[i00] * dbStep) +
        w10 * s10 * (dbOffset + level[i10] * dbStep) +
        w01 * s01 * (dbOffset + level[i01] * dbStep) +
        w11 * s11 * (dbOffset + level[i11] * dbStep);
    return (wl / ws, ws.clamp(0.0, 1.0).toDouble());
  }
}

// ------------------------------------------------------------------ impact de mes mesures sur la carte générale
class ImpactPoint {
  ImpactPoint({
    required this.id,
    required this.measuredAt,
    required this.lat,
    required this.lon,
    required this.h3,
    required this.laeq,
    required this.status,
    this.score,
  });
  final String id, h3, status;
  final DateTime measuredAt;
  final double lat, lon, laeq;
  final double? score;
  factory ImpactPoint.fromJson(Map<String, dynamic> j) => ImpactPoint(
        id: j['id'] as String,
        measuredAt: _t(j['measured_at']),
        lat: _n(j['lat']),
        lon: _n(j['lon']),
        h3: j['h3_index'] as String,
        laeq: _n(j['laeq_db']),
        status: j['quality_status'] as String,
        score: (j['quality_score'] as num?)?.toDouble(),
      );
}

class ImpactCell {
  ImpactCell({
    required this.h3,
    required this.polygon,
    required this.center,
    required this.myCount,
    required this.myValidated,
    required this.myLaeq,
    required this.visible,
    this.mapLaeq,
    this.mapCount,
    this.mapDevices,
    this.share,
    this.delta,
  });
  final String h3;
  final List<LatLng> polygon;
  final LatLng center;
  final int myCount, myValidated;
  final double myLaeq;
  final bool visible;
  final double? mapLaeq, share, delta;
  final int? mapCount, mapDevices;
  factory ImpactCell.fromJson(Map<String, dynamic> j) {
    final c = j['center'] as Map<String, dynamic>;
    return ImpactCell(
      h3: j['h3_index'] as String,
      polygon: [for (final p in j['polygon'] as List) LatLng(_n((p as List)[1]), _n(p[0]))],
      center: LatLng(_n(c['lat']), _n(c['lon'])),
      myCount: (j['my_count'] as num).toInt(),
      myValidated: (j['my_validated'] as num).toInt(),
      myLaeq: _n(j['my_laeq_db']),
      visible: j['visible'] as bool,
      mapLaeq: (j['map_laeq_db'] as num?)?.toDouble(),
      mapCount: (j['map_count'] as num?)?.toInt(),
      mapDevices: (j['map_devices'] as num?)?.toInt(),
      share: (j['my_share'] as num?)?.toDouble(),
      delta: (j['delta_db'] as num?)?.toDouble(),
    );
  }
}

class Impact {
  Impact({
    required this.total,
    required this.byStatus,
    required this.visibleCells,
    required this.onMap,
    required this.minDevices,
    required this.points,
    required this.cells,
  });
  final int total, visibleCells, onMap, minDevices;
  final Map<String, int> byStatus;
  final List<ImpactPoint> points;
  final List<ImpactCell> cells;

  int count(String s) => byStatus[s] ?? 0;

  factory Impact.fromJson(Map<String, dynamic> j) {
    final s = j['summary'] as Map<String, dynamic>;
    return Impact(
      total: (s['total'] as num).toInt(),
      byStatus: (s['by_status'] as Map).map((k, v) => MapEntry(k as String, (v as num).toInt())),
      visibleCells: (s['visible_cells'] as num).toInt(),
      onMap: (s['on_map'] as num).toInt(),
      minDevices: (s['min_devices'] as num).toInt(),
      points: [for (final p in j['points'] as List) ImpactPoint.fromJson(p as Map<String, dynamic>)],
      cells: [for (final c in j['cells'] as List) ImpactCell.fromJson(c as Map<String, dynamic>)],
    );
  }
}