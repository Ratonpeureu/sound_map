import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../core/api.dart';
import '../core/api_study.dart';
import '../core/models_study.dart';
import '../core/notifier.dart';
import 'session_controller.dart';

class StudiesController extends ChangeNotifier {
  StudiesController(this.api, this.session, this.notifier) {
    session.addListener(_onSession);
  }

  final ApiClient api;
  final SessionController session;
  final Notifier notifier;

  List<StudyCard> list = [];
  RewardsData? rewards;
  bool loading = false, needsConsent = false, _on = false;
  String? error;
  Timer? _timer;
  final Set<String> _notified = {};

  int get invitedCount => list.where((s) => s.invited).length;
  int get claimCount => rewards?.items.where((r) => r.needsClaim).length ?? 0;

  void _onSession() {
    final signed = session.status == AuthStatus.signedIn;
    if (signed && !_on) {
      _on = true;
      refresh();
      _timer = Timer.periodic(const Duration(minutes: 10), (_) => refresh());
    } else if (!signed && _on) {
      _on = false;
      _timer?.cancel();
      list = [];
      rewards = null;
      _notified.clear();
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    if (session.user == null) return;
    if (!session.consentOf('study_data')) {
      needsConsent = true;
      list = [];
      notifyListeners();
      return;
    }
    needsConsent = false;
    loading = true;
    notifyListeners();
    try {
      Position? p;
      if (session.consentOf('geolocation')) {
        try {
          p = await Geolocator.getLastKnownPosition();
        } catch (_) {}
      }
      list = await api.studiesAvailable(lat: p?.latitude, lon: p?.longitude);
      error = null;
      for (final s in list) {
        if (s.invited && _notified.add(s.id)) {
          notifier.proposal('Étude pour vous', '${s.sponsor.name} · ${s.title}${s.reward.enabled ? ' · ${s.reward.headline}' : ''}');
        }
      }
    } on ApiException catch (e) {
      error = e.code;
    }
    loading = false;
    notifyListeners();
    unawaited(refreshRewards());
  }

  Future<void> refreshRewards() async {
    if (session.user == null || !session.consentOf('study_data')) return;
    try {
      rewards = await api.studyRewards();
      notifyListeners();
    } on ApiException catch (_) {}
  }

  Future<void> allowStudies() async {
    await session.setConsent('study_data', true);
    await refresh();
  }

  @override
  void dispose() {
    session.removeListener(_onSession);
    _timer?.cancel();
    super.dispose();
  }
}