import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../core/models_roads.dart';
import '../core/api.dart';
import '../core/api_ext.dart';
import '../core/models_ext.dart';
import '../core/notifier.dart';
import '../core/util.dart';
import 'session_controller.dart';

class MissionsController extends ChangeNotifier {
  MissionsController(this.api, this.session, this.notifier) {
    session.addListener(_onSession);
  }

  final ApiClient api;
  final SessionController session;
  final Notifier notifier;

  List<Mission> list = [];
  bool loading = false;
  String? error;
  Timer? _timer;
  bool _on = false;
  final Map<String, String> _prev = {};

  int get offeredCount => list.where((m) => m.status == 'offered').length;
  List<Mission> get active => list.where((m) => m.isActive).toList();

  String get _notifKey => 'missions_notified_${session.user?.id}';

  void _onSession() {
    final signed = session.status == AuthStatus.signedIn;
    if (signed && !_on) {
      _on = true;
      refresh();
      _timer = Timer.periodic(const Duration(minutes: 5), (_) => refresh());
    } else if (!signed && _on) {
      _on = false;
      _timer?.cancel();
      list = [];
      _prev.clear();
      notifyListeners();
    }
  }

  Future<Position?> _position() async {
    if (!session.consentOf('geolocation')) return null;
    try {
      final perm = await Geolocator.checkPermission();
      if (perm != LocationPermission.whileInUse && perm != LocationPermission.always) return null;
      return await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 8)),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> refresh({bool sync = true}) async {
    if (session.user == null) return;
    loading = true;
    notifyListeners();
    try {
      final pos = sync ? await _position() : null;
      final r = pos != null ? await api.missionsSync(pos.latitude, pos.longitude) : await api.missions();
      list = r;
      error = null;
      _notify(r);
    } on ApiException catch (e) {
      error = e.code;
    }
    loading = false;
    notifyListeners();
  }

  void _notify(List<Mission> r) {
    final seen = (session.prefs.getStringList(_notifKey) ?? []).toSet();
    var changed = false;
    for (final m in r) {
      if (m.status == 'offered' && seen.add(m.id)) {
        changed = true;
        notifier.proposal(
          m.isRoad ? 'Mission route' : 'Nouvelle mission de mesure',
          m.isRoad
              ? '${m.roadName ?? 'Une route'} · à ${m.distanceKm.toStringAsFixed(1)} km · avant ${fmtTime(m.offerExpiresAt)}'
              : '${m.requiredCount} mesure(s) à ${m.distanceKm.toStringAsFixed(1)} km · à accepter avant ${fmtDay(m.offerExpiresAt)} ${fmtTime(m.offerExpiresAt)}',
        );
      }
      if (_prev[m.id] == 'accepted' && m.status == 'completed') {
        notifier.result('Mission accomplie', '+${m.rewardCredits.toStringAsFixed(1)} crédit(s) ajouté(s) à votre solde.');
      }
      _prev[m.id] = m.status;
    }
    if (changed) {
      final trimmed = seen.toList();
      session.prefs.setStringList(_notifKey, trimmed.length > 200 ? trimmed.sublist(trimmed.length - 200) : trimmed);
    }
  }

  Future<void> respond(String id, bool accept) async {
    await api.missionRespond(id, accept);
    await refresh(sync: false);
  }

  @override
  void dispose() {
    session.removeListener(_onSession);
    _timer?.cancel();
    super.dispose();
  }
}