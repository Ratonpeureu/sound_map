import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../core/api.dart';
import '../core/config.dart';
import '../core/models.dart';
import '../core/notifier.dart';
import '../core/util.dart';
import 'session_controller.dart';

class ProposalsController extends ChangeNotifier {
  ProposalsController(this.api, this.session, this.notifier) {
    session.addResetHook(() {
      list = [];
      lastReason = null;
      error = null;
      _sched = null;
      _schedLoaded = false;
      _notified.clear();
      stopPolling();
      notifyListeners();
    });
  }

  final ApiClient api;
  final SessionController session;
  final Notifier notifier;

  List<ProposalOut> list = [];
  bool loading = false;
  String? lastReason;
  String? error;

  Timer? _timer;
  ScheduleModel? _sched;
  bool _schedLoaded = false;
  final Set<String> _notified = {};

  void startPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(Duration(minutes: AppConfig.proposalPollMinutes), (_) => poll());
    poll();
  }

  void stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  void scheduleChanged() {
    _schedLoaded = false;
    _sched = null;
  }

  Future<void> refresh() async {
    loading = true;
    notifyListeners();
    try {
      list = await api.proposals();
      error = null;
    } on ApiException catch (e) {
      error = e.code;
    }
    loading = false;
    notifyListeners();
  }

  Future<ProposalDecision> _ask(String trigger) async {
    if (!await ensureLocationPermission()) throw ApiException(null, 'location_denied');
    final p = await Geolocator.getCurrentPosition(
      locationSettings:
          const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
    );
    final bat = await Battery().batteryLevel;
    return api.requestProposal(trigger, p.latitude, p.longitude, bat);
  }

  /// Demande manuelle depuis l'écran des propositions.
  Future<void> requestNow(String trigger) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final d = await _ask(trigger);
      lastReason = d.reason;
      list = await api.proposals();
      if (d.proposed && d.proposal != null) _notifyNew(d.proposal!);
    } on ApiException catch (e) {
      error = e.code;
    } catch (_) {
      error = 'gps_unavailable';
    }
    loading = false;
    notifyListeners();
  }

  Future<ProposalOut> respond(String id, bool accept) async {
    final p = await api.respondProposal(id, accept);
    await refresh();
    return p;
  }

  void _notifyNew(ProposalOut p) {
    if (_notified.add(p.id) && p.status == 'pending') {
      notifier.proposal('Mesure proposée près de vous',
          'Zone prioritaire · à accepter avant ${fmtTime(p.expiresAt)}');
    }
  }

  /// Sondage périodique (application ouverte) : demande une proposition selon le planning de l'utilisateur.
  Future<void> poll() async {
    final u = session.user;
    if (u == null || !u.hybridCollectionEnabled || u.participationPaused || !session.consentsGranted) {
      return;
    }
    try {
      list = await api.proposals();
      notifyListeners();
      for (final p in list) {
        _notifyNew(p);
      }
      if (list.isNotEmpty) return;
      if (!_schedLoaded) {
        _sched = await api.getSchedule();
        _schedLoaded = true;
      }
      final s = _sched;
      if (s == null || !s.active) return;
      for (final t in [
        if (s.allowsScheduled) 'scheduled',
        if (s.allowsContextual) 'contextual',
      ]) {
        final d = await _ask(t);
        lastReason = d.reason;
        if (d.proposed && d.proposal != null) {
          list = [d.proposal!];
          _notifyNew(d.proposal!);
          break;
        }
      }
      notifyListeners();
    } catch (_) {}
  }
}