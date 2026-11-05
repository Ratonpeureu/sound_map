import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'config.dart';

class PendingMeasurement {
  PendingMeasurement(this.payload, [this.attempts = 0]);
  final Map<String, dynamic> payload;
  int attempts;
  String get clientId => payload['client_measurement_id'] as String;
  Map<String, dynamic> toJson() => {'payload': payload, 'attempts': attempts};
  factory PendingMeasurement.fromJson(Map<String, dynamic> j) =>
      PendingMeasurement((j['payload'] as Map).cast<String, dynamic>(), j['attempts'] as int);
}

class FlushResult {
  final Map<String, String> accepted = {}; // client_measurement_id -> id serveur
  int dropped = 0;
  bool networkError = false;
  String? lastError;
}

class MyPoint {
  MyPoint(this.lat, this.lon, this.laeq, this.at);
  final double lat, lon, laeq;
  final DateTime at;
  Map<String, dynamic> toJson() =>
      {'lat': lat, 'lon': lon, 'laeq': laeq, 'at': at.toUtc().toIso8601String()};
  factory MyPoint.fromJson(Map<String, dynamic> j) => MyPoint(
      (j['lat'] as num).toDouble(),
      (j['lon'] as num).toDouble(),
      (j['laeq'] as num).toDouble(),
      DateTime.parse(j['at'] as String).toLocal());
}

/// File d'envoi hors-ligne + dernières mesures personnelles (affichées sur la carte).
class LocalStore {
  LocalStore(this.prefs, this.userId);
  final SharedPreferences prefs;
  final String userId;

  String get _pendingKey => 'pending_$userId';
  String get _pointsKey => 'points_$userId';

  // Erreurs que l'utilisateur peut corriger : on ne compte pas de tentative.
  static const _userFixable = {'consent_required', 'participation_paused'};

  List<PendingMeasurement> loadPending() {
    final raw = prefs.getString(_pendingKey);
    if (raw == null) return [];
    return [
      for (final e in jsonDecode(raw) as List)
        PendingMeasurement.fromJson((e as Map).cast<String, dynamic>())
    ];
  }

  int get pendingCount => loadPending().length;

  Future<void> _savePending(List<PendingMeasurement> l) =>
      prefs.setString(_pendingKey, jsonEncode([for (final p in l) p.toJson()]));

  Future<void> addPending(Map<String, dynamic> payload) async {
    final l = loadPending()..add(PendingMeasurement(payload));
    await _savePending(l);
  }

  Future<FlushResult> flush(ApiClient api) async {
    final r = FlushResult();
    final all = loadPending();
    if (all.isEmpty) return r;
    final failed = <PendingMeasurement>[];
    for (var i = 0; i < all.length; i += AppConfig.batchMaxItems) {
      final chunk = all.skip(i).take(AppConfig.batchMaxItems).toList();
      List<Map<String, dynamic>> results;
      try {
        results = await api.sendBatch([for (final p in chunk) p.payload]);
      } on ApiException catch (e) {
        r.lastError = e.code;
        if (e.code == 'network') {
          r.networkError = true;
          failed.addAll(all.skip(i));
          break;
        }
        for (final p in chunk) {
          p.attempts++;
          if (p.attempts >= AppConfig.maxAttempts) {
            r.dropped++;
          } else {
            failed.add(p);
          }
        }
        continue;
      }
      final byId = {for (final x in results) x['client_measurement_id'] as String: x};
      for (final p in chunk) {
        final res = byId[p.clientId];
        if (res == null) {
          failed.add(p);
          continue;
        }
        final status = res['result'] as String;
        if (status == 'accepted' || status == 'duplicate') {
          r.accepted[p.clientId] = res['id'] as String;
        } else {
          final err = (res['error'] as String?) ?? 'error';
          r.lastError = err;
          if (!_userFixable.contains(err)) p.attempts++;
          if (p.attempts >= AppConfig.maxAttempts) {
            r.dropped++;
          } else {
            failed.add(p);
          }
        }
      }
    }
    await _savePending(failed);
    return r;
  }

  // ------------------------------------------------------------------ mes points
  List<MyPoint> loadPoints() {
    final raw = prefs.getString(_pointsKey);
    if (raw == null) return [];
    return [
      for (final e in jsonDecode(raw) as List) MyPoint.fromJson((e as Map).cast<String, dynamic>())
    ];
  }

  Future<void> addPoint(MyPoint p) async {
    final l = loadPoints()..add(p);
    final trimmed = l.length > 100 ? l.sublist(l.length - 100) : l;
    await prefs.setString(_pointsKey, jsonEncode([for (final x in trimmed) x.toJson()]));
  }
}