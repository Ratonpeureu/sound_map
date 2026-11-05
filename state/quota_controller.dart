import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/api.dart';
import '../core/api_ext.dart';
import '../core/models_ext.dart';
import 'session_controller.dart';

class QuotaController extends ChangeNotifier {
  QuotaController(this.api, this.session) {
    session.addListener(_onSession);
  }

  final ApiClient api;
  final SessionController session;

  QuotaState? state;
  String? error;
  Timer? _timer;
  bool _on = false;

  void _onSession() {
    final signed = session.status == AuthStatus.signedIn;
    if (signed && !_on) {
      _on = true;
      refresh();
      _timer = Timer.periodic(const Duration(minutes: 5), (_) => refresh());
    } else if (!signed && _on) {
      _on = false;
      _timer?.cancel();
      state = null;
      error = null;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    if (session.user == null) return;
    try {
      state = await api.quotaMe();
      error = null;
    } on ApiException catch (e) {
      error = e.code;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    session.removeListener(_onSession);
    _timer?.cancel();
    super.dispose();
  }
}