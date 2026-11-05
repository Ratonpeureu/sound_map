import 'dart:math';
import 'dart:typed_data';

import 'package:latlong2/latlong.dart';

import 'models.dart';

double _n(dynamic v) => (v as num).toDouble();
DateTime? _t(dynamic v) => v == null ? null : DateTime.parse(v as String).toLocal();

// ------------------------------------------------------------------ quota
class QuotaState {
  QuotaState({
    required this.balance,
    required this.measurementsLeft,
    required this.dailyTarget,
    required this.ratePerHour,
    required this.cap,
    required this.reliability,
    required this.utilization,
    required this.missionRate,
    required this.retentionPerDay,
    required this.needNow,
    required this.projected24h,
    required this.todayCredited,
    required this.todayUsed,
    required this.todayDecayed,
  });
  final double balance, dailyTarget, ratePerHour, cap, reliability, utilization, missionRate;
  final double retentionPerDay, needNow, projected24h, todayCredited, todayUsed, todayDecayed;
  final int measurementsLeft;

  factory QuotaState.fromJson(Map<String, dynamic> j) => QuotaState(
        balance: _n(j['balance']),
        measurementsLeft: (j['measurements_left'] as num).toInt(),
        dailyTarget: _n(j['daily_target']),
        ratePerHour: _n(j['rate_per_hour']),
        cap: _n(j['cap']),
        reliability: _n(j['reliability']),
        utilization: _n(j['utilization']),
        missionRate: _n(j['mission_rate']),
        retentionPerDay: _n(j['retention_per_day']),
        needNow: _n(j['need_now']),
        projected24h: _n(j['projected_24h']),
        todayCredited: _n(j['today_credited']),
        todayUsed: _n(j['today_used']),
        todayDecayed: _n(j['today_decayed']),
      );
}

class QuotaCheck {
  QuotaCheck({
    required this.allowed,
    required this.reason,
    required this.cost,
    required this.balance,
    required this.cooldownMinutes,
    required this.cellNeed,
    required this.free,
    this.retryAt,
  });
  final bool allowed, free;
  final String reason;
  final double cost, balance, cooldownMinutes, cellNeed;
  final DateTime? retryAt;

  factory QuotaCheck.fromJson(Map<String, dynamic> j) => QuotaCheck(
        allowed: j['allowed'] as bool,
        reason: j['reason'] as String,
        cost: _n(j['cost']),
        balance: _n(j['balance']),
        cooldownMinutes: _n(j['cooldown_minutes']),
        cellNeed: _n(j['cell_need']),
        free: j['free'] as bool,
        retryAt: _t(j['retry_at']),
      );
}

class Mission {
  Mission({
    required this.id,
    required this.status,
    required this.zoneH3,
    required this.centerLat,
    required this.centerLon,
    required this.radiusM,
    required this.distanceKm,
    required this.requiredCount,
    required this.doneCount,
    required this.confirmedCount,
    required this.rewardCredits,
    required this.priority,
    required this.createdAt,
    required this.offerExpiresAt,
    this.kind = 'zone',
    this.roadSegmentId,
    this.roadName,
    this.roadClass,
    this.targetDayPart,
    this.windowStartAt,
    this.windowEndAt,
    this.acceptedAt,
    this.deadlineAt,
    this.finishedAt,
  });
  final String id, status, zoneH3, kind;
  final String? roadSegmentId, roadName, roadClass, targetDayPart;
  final double centerLat, centerLon, radiusM, distanceKm, rewardCredits, priority;
  final int requiredCount, doneCount, confirmedCount;
  final DateTime createdAt, offerExpiresAt;
  final DateTime? acceptedAt, deadlineAt, finishedAt, windowStartAt, windowEndAt;

  bool get isActive => status == 'offered' || status == 'accepted';
  bool get isRoad => kind == 'road';

  factory Mission.fromJson(Map<String, dynamic> j) => Mission(
        id: j['id'] as String,
        kind: (j['kind'] as String?) ?? 'zone',
        status: j['status'] as String,
        zoneH3: j['zone_h3'] as String,
        centerLat: _n(j['center_lat']),
        centerLon: _n(j['center_lon']),
        radiusM: _n(j['radius_m']),
        distanceKm: _n(j['distance_km']),
        requiredCount: (j['required_count'] as num).toInt(),
        doneCount: (j['done_count'] as num).toInt(),
        confirmedCount: (j['confirmed_count'] as num).toInt(),
        rewardCredits: _n(j['reward_credits']),
        priority: _n(j['priority']),
        roadSegmentId: j['road_segment_id'] as String?,
        roadName: j['road_name'] as String?,
        roadClass: j['road_class'] as String?,
        targetDayPart: j['target_day_part'] as String?,
        windowStartAt: _t(j['window_start_at']),
        windowEndAt: _t(j['window_end_at']),
        createdAt: _t(j['created_at'])!,
        offerExpiresAt: _t(j['offer_expires_at'])!,
        acceptedAt: _t(j['accepted_at']),
        deadlineAt: _t(j['deadline_at']),
        finishedAt: _t(j['finished_at']),
      );
}

// ------------------------------------------------------------------ historique animé
class Timelapse {
  Timelapse._(this.h3s, this.polygons, this.labels, this.levels, this.alphas, this.minDb, this.maxDb);

  final List<String> h3s;
  final List<List<LatLng>> polygons;
  final List<String> labels;
  final List<Float32List> levels; // NaN = inconnu
  final List<Float32List> alphas; // 1 = mesuré ; < 1 = valeur persistante qui s'estompe
  final double? minDb, maxDb;

  int get frameCount => labels.length;

  factory Timelapse.fromJson(Map<String, dynamic> j) {
    final cells = j['cells'] as List;
    final n = cells.length;
    final h3s = <String>[];
    final polys = <List<LatLng>>[];
    for (final c in cells) {
      h3s.add(c['h3'] as String);
      polys.add([
        for (final p in c['polygon'] as List) LatLng(_n((p as List)[1]), _n(p[0])),
      ]);
    }
    final frames = j['frames'] as List;
    final labels = <String>[];
    final levels = <Float32List>[];
    final alphas = <Float32List>[];
    for (var f = 0; f < frames.length; f++) {
      final fr = frames[f] as Map<String, dynamic>;
      final part = fr['part'] as String?;
      final d = DateTime.parse(fr['t'] as String);
      final day = '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
      labels.add(part == null ? day : '$day · ${_part(part)}');
      final lv = Float32List(n)..fillRange(0, n, double.nan);
      final al = Float32List(n);
      for (final c in fr['cells'] as List) {
        final i = (c[0] as num).toInt();
        lv[i] = _n(c[1]);
        al[i] = 1;
      }
      if (f > 0) {
        for (var i = 0; i < n; i++) {
          if (al[i] == 0 && alphas[f - 1][i] > 0) {
            final a = alphas[f - 1][i] * 0.7;
            if (a >= 0.25) {
              lv[i] = levels[f - 1][i];
              al[i] = a;
            }
          }
        }
      }
      levels.add(lv);
      alphas.add(al);
    }
    return Timelapse._(h3s, polys, labels, levels, alphas, (j['min_db'] as num?)?.toDouble(),
        (j['max_db'] as num?)?.toDouble());
  }

  static String _part(String p) => switch (p) {
        'morning' => 'Matin',
        'afternoon' => 'Après-midi',
        'evening' => 'Soirée',
        _ => 'Nuit',
      };

  /// Cellules à l'instant `pos` (indice d'image fractionnaire), interpolées, triées du plus calme au plus bruyant.
  List<NoiseCell> cellsAt(double pos) {
    if (frameCount == 0) return const [];
    final f0 = pos.floor().clamp(0, frameCount - 1);
    final f1 = min(f0 + 1, frameCount - 1);
    final t = (pos - f0).clamp(0.0, 1.0).toDouble();
    final out = <NoiseCell>[];
    for (var i = 0; i < h3s.length; i++) {
      final a0 = alphas[f0][i].toDouble(), a1 = alphas[f1][i].toDouble();
      if (a0 == 0 && a1 == 0) continue;
      final v0 = levels[f0][i].toDouble(), v1 = levels[f1][i].toDouble();
      final level = (a0 > 0 && a1 > 0) ? v0 + (v1 - v0) * t : (a0 > 0 ? v0 : v1);
      final alpha = a0 + (a1 - a0) * t;
      out.add(NoiseCell(
        h3: h3s[i],
        polygon: polygons[i],
        laeq: level,
        lmax: level,
        count: 0,
        devices: 0,
        confidence: alpha,
        calibratedShare: 0,
        last: null,
      ));
    }
    out.sort((a, b) => a.laeq.compareTo(b.laeq));
    return out;
  }
}