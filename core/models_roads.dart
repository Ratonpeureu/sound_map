import 'dart:math';

import 'package:latlong2/latlong.dart';

import 'models.dart';
import 'models_ext.dart';

double _n(dynamic v) => (v as num).toDouble();
DateTime? _t(dynamic v) => v == null ? null : DateTime.parse(v as String).toLocal();

String roadClassLabel(String? h) => switch (h) {
      'motorway' || 'motorway_link' => 'Autoroute',
      'trunk' || 'trunk_link' => 'Route nationale',
      'primary' || 'primary_link' => 'Route principale',
      'secondary' || 'secondary_link' => 'Route secondaire',
      'tertiary' || 'tertiary_link' => 'Route de quartier',
      'unclassified' => 'Route locale',
      'residential' => 'Rue résidentielle',
      'living_street' => 'Rue apaisée',
      _ => 'Route',
    };

class RoadSeg {
  RoadSeg({
    required this.id,
    required this.highway,
    required this.rank,
    required this.points,
    this.name,
    this.ref,
    this.lengthM = 0,
    this.oneway = false,
    this.maxspeed,
  }) {
    var a = 90.0, b = -90.0, c = 180.0, d = -180.0;
    for (final p in points) {
      a = min(a, p.latitude);
      b = max(b, p.latitude);
      c = min(c, p.longitude);
      d = max(d, p.longitude);
    }
    minLat = a;
    maxLat = b;
    minLon = c;
    maxLon = d;
  }
  final String id, highway;
  final int rank;
  final List<LatLng> points;
  final String? name, ref, maxspeed;
  final double lengthM;
  final bool oneway;
  late final double minLat, maxLat, minLon, maxLon;

  String get title => name ?? ref ?? roadClassLabel(highway);

  factory RoadSeg.fromFeature(Map<String, dynamic> f) {
    final p = f['properties'] as Map<String, dynamic>;
    final coords = (f['geometry'] as Map)['coordinates'] as List;
    return RoadSeg(
      id: p['id'] as String,
      highway: (p['highway'] as String?) ?? 'residential',
      rank: (p['rank'] as num?)?.toInt() ?? 6,
      name: p['name'] as String?,
      ref: p['ref'] as String?,
      lengthM: (p['length_m'] as num?)?.toDouble() ?? 0,
      oneway: (p['oneway'] as bool?) ?? false,
      maxspeed: p['maxspeed'] as String?,
      points: [for (final c in coords) LatLng(_n((c as List)[1]), _n(c[0]))],
    );
  }
}

class RoadState {
  RoadState({
    required this.hasData,
    required this.laeq,
    required this.count,
    required this.devices,
    required this.confidence,
    required this.intensity,
    this.lmax,
    this.last,
  });
  final bool hasData;
  final double laeq, confidence, intensity;
  final double? lmax;
  final int count, devices;
  final DateTime? last;
  factory RoadState.fromJson(Map<String, dynamic> j) => RoadState(
        hasData: (j['has_data'] as bool?) ?? false,
        laeq: _n(j['laeq_db']),
        lmax: (j['lmax_db'] as num?)?.toDouble(),
        count: (j['measurement_count'] as num?)?.toInt() ?? 0,
        devices: (j['device_count'] as num?)?.toInt() ?? 0,
        confidence: _n(j['confidence'] ?? 0),
        intensity: _n(j['intensity'] ?? 0),
        last: _t(j['last_measurement_at']),
      );
}

class RoadDetail {
  RoadDetail({
    required this.id,
    required this.title,
    required this.highway,
    required this.state,
    required this.byPart,
    required this.connected,
    required this.lengthM,
    this.maxspeed,
    this.lanes,
    this.oneway = false,
  });
  final String id, title, highway;
  final RoadState state;
  final List<({String part, double laeq, int count})> byPart;
  final List<({String id, String name, String highway})> connected;
  final double lengthM;
  final String? maxspeed;
  final int? lanes;
  final bool oneway;
  factory RoadDetail.fromJson(Map<String, dynamic> j) => RoadDetail(
        id: j['id'] as String,
        title: (j['name'] ?? j['ref'] ?? roadClassLabel(j['highway'] as String?)) as String,
        highway: j['highway'] as String,
        lengthM: _n(j['length_m']),
        maxspeed: j['maxspeed'] as String?,
        lanes: (j['lanes'] as num?)?.toInt(),
        oneway: (j['oneway'] as bool?) ?? false,
        state: RoadState.fromJson((j['state'] as Map).cast<String, dynamic>()),
        byPart: [
          for (final p in j['by_day_part'] as List)
            (part: p['day_part'] as String, laeq: _n(p['laeq_db']), count: (p['measurement_count'] as num).toInt())
        ],
        connected: [
          for (final c in j['connected'] as List)
            (id: c['id'] as String, name: (c['name'] as String?) ?? roadClassLabel(c['highway'] as String?), highway: c['highway'] as String)
        ],
      );
}

class MissionTarget {
  MissionTarget({required this.lat, required this.lon, required this.radiusM, this.dayPart, this.windowEnd, this.roadName, this.roadClass});
  final double lat, lon, radiusM;
  final String? dayPart, roadName, roadClass;
  final DateTime? windowEnd;
  LatLng get point => LatLng(lat, lon);
  factory MissionTarget.fromJson(Map<String, dynamic> j) => MissionTarget(
        lat: _n(j['lat']),
        lon: _n(j['lon']),
        radiusM: _n(j['radius_m']),
        dayPart: j['day_part'] as String?,
        windowEnd: _t(j['window_end_at']),
        roadName: j['road_name'] as String?,
        roadClass: j['road_class'] as String?,
      );
}

/// Itinéraire vers le point cible d'une mission (route réelle, calculée côté serveur).
class MissionRoute {
  MissionRoute({required this.missionId, required this.target, required this.points, required this.lengthM, required this.timeS});
  final String missionId;
  final MissionTarget target;
  final List<LatLng> points;
  final int lengthM, timeS;
  factory MissionRoute.fromJson(Map<String, dynamic> j) {
    final r = RouteResult.fromJson((j['route'] as Map).cast<String, dynamic>());
    return MissionRoute(
        missionId: j['mission_id'] as String,
        target: MissionTarget.fromJson((j['target'] as Map).cast<String, dynamic>()),
        points: r.points,
        lengthM: r.lengthM,
        timeS: r.timeS);
  }
}

/// Résultat renvoyé par l'écran des missions à la carte.
class MissionFocus {
  MissionFocus(this.mission, {this.route = false});
  final Mission mission;
  final bool route;
}


