import 'dart:async';
import 'dart:convert';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../core/api.dart';
import '../core/config.dart';
import '../core/local_store.dart';
import '../core/models.dart';

enum AuthStatus { booting, signedOut, signedIn }

class SessionController extends ChangeNotifier {
  SessionController(this.api, this.prefs)
      : themeMode = _parseTheme(prefs.getString('theme')),
        serverUrl = prefs.getString('server_url') ?? AppConfig.defaultApiBase {
    api.onSessionExpired = () async {
      await _clearLocal();
      status = AuthStatus.signedOut;
      notifyListeners();
    };
  }

  final ApiClient api;
  final SharedPreferences prefs;

  AuthStatus status = AuthStatus.booting;
  UserMe? user;
  List<ConsentItem> consents = [];
  ThemeMode themeMode;
  String serverUrl;
  bool consentSkipped = false;
  String? _deviceId;
  final List<VoidCallback> _hooks = [];

  static ThemeMode _parseTheme(String? v) =>
      v == 'light' ? ThemeMode.light : (v == 'dark' ? ThemeMode.dark : ThemeMode.system);

  bool get consentsGranted =>
      ['geolocation', 'microphone'].every((t) => consents.any((c) => c.type == t && c.granted));
  bool consentOf(String type) => consents.any((c) => c.type == type && c.granted);
  bool get needsConsent => status == AuthStatus.signedIn && !consentsGranted && !consentSkipped;

  LocalStore? get store => user == null ? null : LocalStore(prefs, user!.id);

  void addResetHook(VoidCallback cb) => _hooks.add(cb);

  // ------------------------------------------------------------------ démarrage
  Future<void> boot() async {
    final started = DateTime.now();
    var next = AuthStatus.signedOut;
    if (api.tokens.refresh != null) {
      try {
        await _loadAccount();
        next = AuthStatus.signedIn;
      } on ApiException catch (e) {
        if (e.code == 'network' && _loadCache()) next = AuthStatus.signedIn;
      }
    }
    final elapsed = DateTime.now().difference(started);
    if (elapsed < const Duration(milliseconds: 2000)) {
      await Future.delayed(const Duration(milliseconds: 2000) - elapsed);
    }
    status = next;
    notifyListeners();
  }

  Future<void> _loadAccount() async {
    user = await api.me();
    consents = await api.consents();
    await prefs.setString('account_cache', jsonEncode({
      'user': user!.toJson(),
      'consents': [for (final c in consents) c.toJson()],
    }));
  }

  bool _loadCache() {
    final raw = prefs.getString('account_cache');
    if (raw == null) return false;
    final m = jsonDecode(raw) as Map<String, dynamic>;
    user = UserMe.fromJson(m['user'] as Map<String, dynamic>);
    consents = [
      for (final c in m['consents'] as List) ConsentItem.fromJson((c as Map).cast<String, dynamic>())
    ];
    return true;
  }

  // ------------------------------------------------------------------ auth
  Future<void> signIn(String email, String password) async {
    await api.login(email, password);
    await _loadAccount();
    consentSkipped = false;
    status = AuthStatus.signedIn;
    notifyListeners();
  }

  Future<void> signUp(String email, String password) async {
    await api.register(email, password);
    await signIn(email, password);
  }

  Future<void> signOut() async {
    try {
      await api.logout();
    } catch (_) {}
    await _clearLocal();
    status = AuthStatus.signedOut;
    notifyListeners();
  }

  Future<void> afterAccountDeleted() async {
    final uid = user?.id;
    await _clearLocal();
    if (uid != null) {
      await prefs.remove('pending_$uid');
      await prefs.remove('points_$uid');
      await prefs.remove('install_$uid');
    }
    status = AuthStatus.signedOut;
    notifyListeners();
  }

  Future<void> _clearLocal() async {
    await api.tokens.clear();
    user = null;
    consents = [];
    _deviceId = null;
    consentSkipped = false;
    await prefs.remove('account_cache');
    for (final h in _hooks) {
      h();
    }
  }

  // ------------------------------------------------------------------ préférences
  Future<void> setThemeMode(ThemeMode m) async {
    themeMode = m;
    await prefs.setString('theme', m == ThemeMode.light ? 'light' : (m == ThemeMode.dark ? 'dark' : 'system'));
    notifyListeners();
  }

  Future<void> setServerUrl(String url) async {
    final clean = url.trim();
    if (clean.isEmpty || clean == serverUrl) return;
    serverUrl = clean;
    await prefs.setString('server_url', clean);
    api.setBase(clean);
    notifyListeners();
  }

  // ------------------------------------------------------------------ compte
  Future<void> setConsent(String type, bool granted) async {
    consents = await api.setConsent(type, granted);
    notifyListeners();
  }

  Future<void> saveConsents({required bool geolocation, required bool microphone}) async {
    if (geolocation != consentOf('geolocation')) await setConsent('geolocation', geolocation);
    if (microphone != consentOf('microphone')) await setConsent('microphone', microphone);
  }

  void skipConsents() {
    consentSkipped = true;
    notifyListeners();
  }

  Future<void> setHybrid(bool v) async {
    user = await api.patchMe(hybrid: v);
    notifyListeners();
  }

  Future<void> setPaused(bool v) async {
    user = await api.patchMe(paused: v);
    notifyListeners();
  }

  // ------------------------------------------------------------------ appareil
  Future<String> ensureDevice() async {
    if (_deviceId != null) return _deviceId!;
    final uid = user!.id;
    var install = prefs.getString('install_$uid');
    if (install == null) {
      install = const Uuid().v4();
      await prefs.setString('install_$uid', install);
    }
    final info = await DeviceInfoPlugin().androidInfo;
    final dev = await api.registerDevice(
      installId: install,
      manufacturer: info.manufacturer,
      model: info.model,
      androidVersion: info.version.release,
      sampleRate: AppConfig.sampleRate,
    );
    _deviceId = dev.id;
    return dev.id;
  }
}