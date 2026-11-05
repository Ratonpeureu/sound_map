import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';

import '../core/api.dart';
import '../core/api_ext.dart';
import '../core/models_social.dart';
import '../core/notifier.dart';
import '../core/util.dart';
import 'account_controller.dart';
import 'session_controller.dart';

class ReviewsController extends ChangeNotifier with WidgetsBindingObserver {
  ReviewsController(this.api, this.session, this.notifier, this.account) {
    WidgetsBinding.instance.addObserver(this);
    account.addListener(_sync);
  }

  final ApiClient api;
  final SessionController session;
  final Notifier notifier;
  final AccountController account;

  List<ReviewRequest> pending = [];
  List<ReviewHistoryItem> history = [];
  Timer? _poll;
  Timer? _beat;
  bool _foreground = true;
  final Set<String> _notified = {};

  bool get active {
    final p = account.profile, a = account.analyst;
    return session.status == AuthStatus.signedIn && p != null && p.analystEnabled && !(a?.suspended ?? false);
  }

  void _sync() {
    if (active && _foreground) {
      _poll ??= Timer.periodic(const Duration(seconds: 15), (_) => refresh());
      _beat ??= Timer.periodic(const Duration(seconds: 60), (_) => _heartbeat());
      _heartbeat();
      refresh();
    } else {
      _poll?.cancel();
      _beat?.cancel();
      _poll = _beat = null;
      if (pending.isNotEmpty && !active) {
        pending = [];
        notifyListeners();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  Future<void> _heartbeat() async {
    if (!active || !session.consentOf('geolocation')) return;
    try {
      final perm = await Geolocator.checkPermission();
      if (perm != LocationPermission.whileInUse && perm != LocationPermission.always) return;
      final p = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 8)));
      await api.presence(p.latitude, p.longitude);
    } catch (_) {}
  }

  Future<void> refresh() async {
    if (!active) return;
    try {
      final r = await api.reviewsPending();
      for (final q in r) {
        if (_notified.add(q.id)) {
          notifier.proposal('Avis demandé près de vous',
              'Ce niveau de ${q.levelDb.toStringAsFixed(0)} dB(A) correspond-il à ce que vous entendez ? Répondez avant ${fmtTime(q.expiresAt)}.');
        }
      }
      pending = r;
      notifyListeners();
    } on ApiException catch (_) {}
  }

  Future<void> loadHistory() async {
    try {
      history = await api.reviewsHistory();
      notifyListeners();
    } on ApiException catch (_) {}
  }

  Future<void> vote(String id, String vote, bool strong) async {
    await api.reviewVote(id, vote, strong);
    pending = pending.where((p) => p.id != id).toList();
    notifyListeners();
    account.loadAll();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    account.removeListener(_sync);
    _poll?.cancel();
    _beat?.cancel();
    super.dispose();
  }
}