import 'package:flutter/foundation.dart';

import '../core/api.dart';
import '../core/api_ext.dart';
import '../core/models_social.dart';
import 'session_controller.dart';

class AccountController extends ChangeNotifier {
  AccountController(this.api, this.session) {
    session.addListener(_onSession);
  }

  final ApiClient api;
  final SessionController session;

  AccountProfile? profile;
  MyBoard? board;
  AnalystState? analyst;
  Connections? connections;
  List<Invitation> invitations = [];
  bool loading = false;
  bool _on = false;

  void _onSession() {
    final signed = session.status == AuthStatus.signedIn;
    if (signed && !_on) {
      _on = true;
      loadAll();
    } else if (!signed && _on) {
      _on = false;
      profile = null;
      board = null;
      analyst = null;
      connections = null;
      invitations = [];
      notifyListeners();
    }
  }

  Future<void> _safe(Future<void> Function() f) async {
    try {
      await f();
    } on ApiException catch (_) {}
  }

  Future<void> loadAll() async {
    if (session.user == null) return;
    loading = true;
    notifyListeners();
    await Future.wait([
      _safe(() async => profile = await api.accountMe()),
      _safe(() async => board = await api.myBoard()),
      _safe(() async => analyst = await api.analystMe()),
      _safe(() async => connections = await api.connections()),
      _safe(() async => invitations = await api.invitations()),
    ]);
    loading = false;
    notifyListeners();
  }

  Future<void> saveProfile(Map<String, dynamic> body) async {
    profile = await api.accountUpdate(body);
    notifyListeners();
  }

  Future<void> setAnalyst(bool enable) async {
    await api.analystSet(enable);
    await _safe(() async => analyst = await api.analystMe());
    await _safe(() async => profile = await api.accountMe());
    notifyListeners();
  }

  Future<void> newInvitation() async {
    await api.createInvitation();
    invitations = await api.invitations();
    notifyListeners();
  }

  Future<void> revoke(String id) async {
    await api.revokeInvitation(id);
    invitations = await api.invitations();
    notifyListeners();
  }

  @override
  void dispose() {
    session.removeListener(_onSession);
    super.dispose();
  }
}