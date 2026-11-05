import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

double _d(dynamic v) => (v as num).toDouble();
DateTime? _dt(dynamic v) => v == null ? null : DateTime.parse(v as String).toLocal();

// ------------------------------------------------------------------ utilisateur
class UserMe {
  UserMe({
    required this.id,
    required this.pseudonym,
    required this.role,
    required this.hybridCollectionEnabled,
    required this.participationPaused,
    required this.createdAt,
  });
  final String id, pseudonym, role;
  final bool hybridCollectionEnabled, participationPaused;
  final DateTime createdAt;

  factory UserMe.fromJson(Map<String, dynamic> j) => UserMe(
        id: j['id'] as String,
        pseudonym: j['pseudonym'] as String,
        role: j['role'] as String,
        hybridCollectionEnabled: j['hybrid_collection_enabled'] as bool,
        participationPaused: j['participation_paused'] as bool,
        createdAt: _dt(j['created_at'])!,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'pseudonym': pseudonym,
        'role': role,
        'hybrid_collection_enabled': hybridCollectionEnabled,
        'participation_paused': participationPaused,
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  String get roleLabel => switch (role) {
        'tenant_admin' => 'Administrateur',
        'analyst' => 'Analyste',
        _ => 'Contributeur',
      };
}

class ConsentItem {
  ConsentItem({required this.type, required this.granted, required this.policyVersion});
  final String type; // geolocation | microphone
  final bool granted;
  final String policyVersion;
  factory ConsentItem.fromJson(Map<String, dynamic> j) => ConsentItem(
      type: j['consent_type'] as String,
      granted: j['granted'] as bool,
      policyVersion: j['policy_version'] as String);
  Map<String, dynamic> toJson() =>
      {'consent_type': type, 'granted': granted, 'policy_version': policyVersion};
}

class Contributions {
  Contributions({
    required this.total,
    required this.byStatus,
    required this.cellsCovered,
    required this.lastMeasurementAt,
  });
  final int total, cellsCovered;
  final Map<String, int> byStatus;
  final DateTime? lastMeasurementAt;
  factory Contributions.fromJson(Map<String, dynamic> j) => Contributions(
        total: j['total_measurements'] as int,
        byStatus: (j['by_status'] as Map).map((k, v) => MapEntry(k as String, v as int)),
        cellsCovered: j['cells_covered'] as int,
        lastMeasurementAt: _dt(j['last_measurement_at']),
      );
  int count(String s) => byStatus[s] ?? 0;
  double get validationRate => total == 0 ? 0 : count('validated') / total;
}

class DeviceOut {
  DeviceOut({required this.id, required this.calibrationStatus, this.sampleRate});
  final String id, calibrationStatus;
  final int? sampleRate;
  factory DeviceOut.fromJson(Map<String, dynamic> j) => DeviceOut(
      id: j['id'] as String,
      calibrationStatus: j['calibration_status'] as String,
      sampleRate: j['sample_rate_hz'] as int?);
  bool get calibrated => calibrationStatus == 'calibrated';
}

// ------------------------------------------------------------------ historique
class HistoryItem {
  HistoryItem({
    required this.id,
    required this.measuredAt,
    required this.h3,
    required this.laeq,
    required this.lmax,
    required this.dayPart,
    required this.calibrationStatus,
    required this.qualityStatus,
    required this.qualityScore,
    required this.reasons,
    required this.noiseContext,
    required this.locationAnonymized,
  });
  final String id, h3, dayPart, calibrationStatus, qualityStatus;
  final DateTime measuredAt;
  final double laeq, lmax;
  final double? qualityScore;
  final List<String> reasons;
  final String? noiseContext;
  final bool locationAnonymized;

  factory HistoryItem.fromJson(Map<String, dynamic> j) => HistoryItem(
        id: j['id'] as String,
        measuredAt: _dt(j['measured_at'])!,
        h3: j['h3_index'] as String,
        laeq: _d(j['laeq_db']),
        lmax: _d(j['lmax_db']),
        dayPart: j['day_part'] as String,
        calibrationStatus: j['calibration_status'] as String,
        qualityStatus: j['quality_status'] as String,
        qualityScore: j['quality_score'] == null ? null : _d(j['quality_score']),
        reasons: (j['reason_codes'] as List).cast<String>(),
        noiseContext: j['noise_context'] as String?,
        locationAnonymized: j['location_anonymized'] as bool,
      );
}

// ------------------------------------------------------------------ carte
class NoiseCell {
  NoiseCell({
    required this.h3,
    required this.polygon,
    required this.laeq,
    required this.lmax,
    required this.count,
    required this.devices,
    required this.confidence,
    required this.calibratedShare,
    required this.last,
  });
  final String h3;
  final List<LatLng> polygon;
  final double laeq, lmax, confidence, calibratedShare;
  final int count, devices;
  final DateTime? last;

  factory NoiseCell.fromFeature(Map<String, dynamic> f) {
    final p = f['properties'] as Map<String, dynamic>;
    final ring = ((f['geometry'] as Map)['coordinates'] as List).first as List;
    return NoiseCell(
      h3: p['h3_index'] as String,
      polygon: [for (final c in ring) LatLng(_d((c as List)[1]), _d(c[0]))],
      laeq: _d(p['laeq_db']),
      lmax: _d(p['lmax_db']),
      count: p['measurement_count'] as int,
      devices: p['device_count'] as int,
      confidence: _d(p['confidence']),
      calibratedShare: _d(p['calibrated_share']),
      last: _dt(p['last_measurement_at']),
    );
  }

  bool get isHot => last != null && DateTime.now().difference(last!).inMinutes < 60;
}

class MapFilters {
  const MapFilters({
    this.period = '7d',
    this.from,
    this.to,
    this.dayPart = 'all',
    this.includeIndicative = false,
    this.minConfidence = 0,
  });
  final String period; // today | 7d | 30d | custom
  final DateTime? from, to;
  final String dayPart; // all | morning | afternoon | evening | night
  final bool includeIndicative;
  final double minConfidence;

  MapFilters copyWith({
    String? period,
    DateTime? from,
    DateTime? to,
    String? dayPart,
    bool? includeIndicative,
    double? minConfidence,
  }) =>
      MapFilters(
        period: period ?? this.period,
        from: from ?? this.from,
        to: to ?? this.to,
        dayPart: dayPart ?? this.dayPart,
        includeIndicative: includeIndicative ?? this.includeIndicative,
        minConfidence: minConfidence ?? this.minConfidence,
      );

  Map<String, dynamic> timeQuery() {
    final f = DateFormat('yyyy-MM-dd');
    return {
      'period': period,
      'day_part': dayPart,
      if (period == 'custom' && from != null && to != null) ...{
        'date_from': f.format(from!),
        'date_to': f.format(to!),
      },
    };
  }

  String get periodLabel => switch (period) {
        'today' => "Aujourd'hui",
        '30d' => '30 jours',
        'custom' => (from != null && to != null)
            ? '${DateFormat('d MMM', 'fr_FR').format(from!)} → ${DateFormat('d MMM', 'fr_FR').format(to!)}'
            : 'Période',
        _ => '7 jours',
      };
}

class CellDetail {
  CellDetail({
    required this.h3,
    required this.center,
    required this.laeq,
    required this.lmax,
    required this.count,
    required this.devices,
    required this.calibratedShare,
    required this.confidence,
    required this.last,
    required this.byDayPart,
    required this.daily,
    required this.context,
  });
  final String h3;
  final LatLng center;
  final double laeq, lmax, calibratedShare, confidence;
  final int count, devices;
  final DateTime? last;
  final List<({String part, double laeq, int count})> byDayPart;
  final List<({DateTime date, double laeq, double lmax, int count})> daily;
  final Map<String, int> context;

  factory CellDetail.fromJson(Map<String, dynamic> j) {
    final s = j['summary'] as Map<String, dynamic>;
    final c = j['center'] as Map<String, dynamic>;
    return CellDetail(
      h3: j['h3_index'] as String,
      center: LatLng(_d(c['lat']), _d(c['lon'])),
      laeq: _d(s['laeq_db']),
      lmax: _d(s['lmax_db']),
      count: s['measurement_count'] as int,
      devices: s['device_count'] as int,
      calibratedShare: _d(s['calibrated_share']),
      confidence: _d(s['confidence']),
      last: _dt(s['last_measurement_at']),
      byDayPart: [
        for (final p in j['by_day_part'] as List)
          (part: p['day_part'] as String, laeq: _d(p['laeq_db']), count: p['measurement_count'] as int)
      ],
      daily: [
        for (final d in j['daily'] as List)
          (
            date: DateTime.parse(d['date'] as String),
            laeq: _d(d['laeq_db']),
            lmax: _d(d['lmax_db']),
            count: d['measurement_count'] as int
          )
      ],
      context: (j['context_breakdown'] as Map).map((k, v) => MapEntry(k as String, v as int)),
    );
  }
}

// ------------------------------------------------------------------ collecte hybride
class ProposalOut {
  ProposalOut({
    required this.id,
    required this.status,
    required this.trigger,
    required this.h3,
    required this.priority,
    required this.expiresAt,
    required this.sessionSeconds,
  });
  final String id, status, trigger, h3;
  final double priority;
  final DateTime expiresAt;
  final int sessionSeconds;
  factory ProposalOut.fromJson(Map<String, dynamic> j) => ProposalOut(
        id: j['id'] as String,
        status: j['status'] as String,
        trigger: j['trigger'] as String,
        h3: j['h3_index'] as String,
        priority: _d(j['priority']),
        expiresAt: _dt(j['expires_at'])!,
        sessionSeconds: j['session_duration_seconds'] as int,
      );
}

class ProposalDecision {
  ProposalDecision({required this.proposed, required this.reason, this.proposal});
  final bool proposed;
  final String reason;
  final ProposalOut? proposal;
  factory ProposalDecision.fromJson(Map<String, dynamic> j) => ProposalDecision(
        proposed: j['proposed'] as bool,
        reason: j['reason'] as String,
        proposal: j['proposal'] == null
            ? null
            : ProposalOut.fromJson(j['proposal'] as Map<String, dynamic>),
      );
}

class ScheduleModel {
  ScheduleModel({
    required this.days,
    required this.start,
    required this.end,
    required this.preferred,
    required this.mode,
    required this.active,
  });
  final List<int> days;
  final String start, end; // HH:MM:SS
  final List<String> preferred;
  final String mode; // scheduled | contextual | both
  final bool active;
  factory ScheduleModel.fromJson(Map<String, dynamic> j) => ScheduleModel(
        days: (j['days_of_week'] as List).cast<int>(),
        start: j['window_start'] as String,
        end: j['window_end'] as String,
        preferred: (j['preferred_times'] as List).cast<String>(),
        mode: j['mode'] as String,
        active: j['active'] as bool,
      );
  bool get allowsScheduled => mode == 'scheduled' || mode == 'both';
  bool get allowsContextual => mode == 'contextual' || mode == 'both';
}

// ------------------------------------------------------------------ TomTom (réponses du backend)
class TileSession {
  TileSession({required this.expiresAt, required this.layers});
  final DateTime expiresAt;
  final Map<String, String> layers; // chemin relatif au serveur, avec jeton de tuile

  factory TileSession.fromJson(Map<String, dynamic> j) => TileSession(
        expiresAt: _dt(j['expires_at'])!,
        layers: (j['layers'] as Map).map((k, v) => MapEntry(k as String, v as String)),
      );
}

class TrafficFlow {
  TrafficFlow({
    required this.current,
    required this.freeFlow,
    required this.congestion,
    required this.level,
    required this.roadClosure,
  });
  final double current, freeFlow, congestion;
  final String level; // free | moderate | heavy
  final bool roadClosure;
  factory TrafficFlow.fromJson(Map<String, dynamic> j) => TrafficFlow(
        current: _d(j['current_speed_kmh']),
        freeFlow: _d(j['free_flow_speed_kmh']),
        congestion: _d(j['congestion']),
        level: j['level'] as String,
        roadClosure: j['road_closure'] as bool,
      );
  String get levelLabel => switch (level) {
        'free' => 'Fluide',
        'moderate' => 'Dense',
        _ => 'Embouteillé',
      };
}

class TrafficIncident {
  TrafficIncident({
    required this.lat,
    required this.lon,
    this.description,
    this.from,
    this.to,
    this.delayS,
    this.magnitude,
  });
  final double lat, lon;
  final String? description, from, to;
  final int? delayS, magnitude;
  factory TrafficIncident.fromJson(Map<String, dynamic> j) => TrafficIncident(
        lat: _d(j['lat']),
        lon: _d(j['lon']),
        description: j['description'] as String?,
        from: j['from_'] as String?,
        to: j['to'] as String?,
        delayS: (j['delay_s'] as num?)?.toInt(),
        magnitude: (j['delay_magnitude'] as num?)?.toInt(),
      );
}

class PlaceResult {
  PlaceResult({required this.name, required this.lat, required this.lon, this.address, this.category});
  final String name;
  final String? address, category;
  final double lat, lon;
  factory PlaceResult.fromJson(Map<String, dynamic> j) => PlaceResult(
        name: j['name'] as String,
        address: j['address'] as String?,
        category: j['category'] as String?,
        lat: _d(j['lat']),
        lon: _d(j['lon']),
      );
}

class RouteResult {
  RouteResult({required this.points, required this.lengthM, required this.timeS, required this.delayS});
  final List<LatLng> points;
  final int lengthM, timeS, delayS;
  factory RouteResult.fromJson(Map<String, dynamic> j) => RouteResult(
        points: [for (final p in j['points'] as List) LatLng(_d((p as List)[0]), _d(p[1]))],
        lengthM: (j['length_m'] as num?)?.toInt() ?? 0,
        timeS: (j['travel_time_s'] as num?)?.toInt() ?? 0,
        delayS: (j['traffic_delay_s'] as num?)?.toInt() ?? 0,
      );
}