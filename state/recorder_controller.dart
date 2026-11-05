import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../core/api_ext.dart';
import '../core/api.dart';
import '../core/audio_meter.dart';
import '../core/config.dart';
import '../core/local_store.dart';
import '../core/models.dart';
import '../core/notifier.dart';
import '../core/util.dart';
import 'session_controller.dart';

enum RecPhase { idle, preparing, recording, sending, done, failed }

class RecError implements Exception {
  RecError(this.code);
  final String code;
}

class RecResult {
  RecResult({
    required this.laeq,
    required this.lmax,
    required this.lmin,
    required this.seconds,
    required this.sent,
    this.tag,
  });
  final double laeq, lmax, lmin, seconds;
  final bool sent;
  final NoiseTag? tag;
}

class RecorderController extends ChangeNotifier {
  RecorderController(this.api, this.session, this.notifier) {
    session.addResetHook(() {
      _resetValues();
      phase = RecPhase.idle;
      pendingCount = 0;
      notifyListeners();
    });
  }

  final ApiClient api;
  final SessionController session;
  final Notifier notifier;
  final AudioRecorder _rec = AudioRecorder();

  RecPhase phase = RecPhase.idle;
  double liveDb = 0, leqDb = 0, maxDb = 0;
  int elapsed = 0;
  int total = AppConfig.defaultSessionSeconds;
  String? errorCode;
  RecResult? result;
  String? qualityStatus;
  double? qualityScore;
  List<String> reasons = [];
  NoiseTag? tag;
  ProposalOut? proposal;
  Position? gps;
  int pendingCount = 0;
  int completedVersion = 0;

  NoiseAccumulator? _acc;
  StreamSubscription<Uint8List>? _sub;
  StreamSubscription<Position>? _gpsSub;
  Timer? _timer;
  Position? _origin;
  double _maxMove = 0;
  DateTime? _startAt;
  String? _deviceId;
  String? _lastServerId;
  bool _finishing = false, _flushing = false, _disposed = false;

  bool get busy =>
      phase == RecPhase.preparing || phase == RecPhase.recording || phase == RecPhase.sending;

  List<double> get wave {
    final b = _acc?.blocks ?? const <double>[];
    return b.length > 48 ? b.sublist(b.length - 48) : b;
  }

  void setTag(NoiseTag? t) {
    tag = t;
    notifyListeners();
  }

  void attachProposal(ProposalOut? p) {
    proposal = p;
    total = p?.sessionSeconds ?? AppConfig.defaultSessionSeconds;
    notifyListeners();
  }

  void resetForNew() {
    if (busy) return;
    _resetValues();
    phase = RecPhase.idle;
    notifyListeners();
  }

  void _resetValues() {
    liveDb = leqDb = maxDb = 0;
    elapsed = 0;
    errorCode = null;
    result = null;
    qualityStatus = null;
    qualityScore = null;
    reasons = [];
    _acc = null;
    _finishing = false;
    _lastServerId = null;
  }

  // ------------------------------------------------------------------ GPS (précision en direct)
  Future<void> startGpsWatch() async {
    if (_gpsSub != null) return;
    if (!await ensureLocationPermission()) return;
    _gpsSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 0),
    ).listen((p) {
      gps = p;
      final o = _origin;
      if (o != null && phase == RecPhase.recording) {
        final d = Geolocator.distanceBetween(o.latitude, o.longitude, p.latitude, p.longitude);
        if (d > _maxMove) _maxMove = d;
      }
      notifyListeners();
    }, onError: (_) {});
  }

  Future<void> stopGpsWatch() async {
    if (busy) return;
    await _gpsSub?.cancel();
    _gpsSub = null;
  }

  // ------------------------------------------------------------------ enregistrement
  Future<void> start() async {
    if (busy) return;
    _resetValues();
    phase = RecPhase.preparing;
    notifyListeners();
    try {
      final u = session.user;
      if (u == null) throw RecError('not_authenticated');
      if (u.participationPaused) throw RecError('participation_paused');
      if (!session.consentsGranted) throw RecError('consent_required');
      if (!await _rec.hasPermission()) throw RecError('mic_denied');
      if (!await ensureLocationPermission()) throw RecError('location_denied');
      final deviceId = await session.ensureDevice();
      await startGpsWatch();

      Position origin;
      try {
        origin = await Geolocator.getCurrentPosition(
          locationSettings:
              const LocationSettings(accuracy: LocationAccuracy.best, timeLimit: Duration(seconds: 20)),
        );
      } catch (_) {
        throw RecError('gps_unavailable');
      }

      await _checkQuota(origin);
      _origin = origin;
      _maxMove = 0;
      _deviceId = deviceId;
      _startAt = DateTime.now().toUtc();
      total = proposal?.sessionSeconds ?? AppConfig.defaultSessionSeconds;
      _acc = NoiseAccumulator(AppConfig.sampleRate);

      final stream = await _rec.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: AppConfig.sampleRate,
        numChannels: 1,
        autoGain: false,
        echoCancel: false,
        noiseSuppress: false,
      ));
      await WakelockPlus.enable();
      phase = RecPhase.recording;
      notifyListeners();
      _sub = stream.listen(_onAudio, onError: (_) => _fail('capture_error'), cancelOnError: true);
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        notifier.recordingProgress(elapsed, total, liveDb);
      });
    } catch (e) {
      await _stopCapture();
      errorCode = e is RecError ? e.code : (e is ApiException ? e.code : 'capture_error');
      phase = RecPhase.failed;
      notifyListeners();
    }
  }

  /// Pré-contrôle du solde et du délai. Hors-ligne ou serveur indisponible : la mesure part en file
  /// et le serveur arbitre à la synchronisation (le solde peut alors passer en négatif).
  Future<void> _checkQuota(Position origin) async {
    try {
      final q = await api.quotaCheck(origin.latitude, origin.longitude, proposalId: proposal?.id);
      if (!q.allowed) throw RecError(q.reason);
    } on ApiException {
      // on laisse passer
    }
  }

  void _onAudio(Uint8List bytes) {
    final a = _acc;
    if (a == null || _finishing) return;
    a.add(bytes);
    liveDb = a.lastBlockDb;
    leqDb = a.leqDb;
    maxDb = a.maxDb;
    elapsed = min(a.seconds.floor(), total);
    notifyListeners();
    if (a.seconds >= total) _finish();
  }

  Future<void> _stopCapture() async {
    await _sub?.cancel();
    _sub = null;
    _timer?.cancel();
    _timer = null;
    try {
      await _rec.stop();
    } catch (_) {}
    try {
      await WakelockPlus.disable();
    } catch (_) {}
  }

  Future<void> _fail(String code) async {
    if (_finishing) return;
    _finishing = true;
    await _stopCapture();
    await notifier.cancelProgress();
    errorCode = code;
    phase = RecPhase.failed;
    notifyListeners();
  }

  Future<void> cancel() async {
    if (phase != RecPhase.recording && phase != RecPhase.preparing) return;
    _finishing = true;
    await _stopCapture();
    await notifier.cancelProgress();
    _resetValues();
    phase = RecPhase.idle;
    notifyListeners();
  }

  Future<void> _finish() async {
    if (_finishing) return;
    _finishing = true;
    phase = RecPhase.sending;
    notifyListeners();
    await _stopCapture();
    await notifier.cancelProgress();

    final s = _acc!.finish();
    final origin = _origin!;
    double c(double v) => v.clamp(0.0, 200.0).toDouble();
    final payload = <String, dynamic>{
      'client_measurement_id': const Uuid().v4(),
      'device_id': _deviceId,
      if (proposal != null) 'proposal_id': proposal!.id,
      'measured_at': _startAt!.toIso8601String(),
      'latitude': origin.latitude,
      'longitude': origin.longitude,
      'gps_accuracy_m': origin.accuracy,
      'duration_seconds': total.toDouble(),
      'effective_duration_seconds': min(s.seconds, total.toDouble()),
      'sample_rate_hz': AppConfig.sampleRate,
      'laeq': c(s.laeq),
      'lmax': c(s.lmax),
      'lmin': c(s.lmin),
      'saturation_ratio': s.saturation.clamp(0.0, 1.0),
      'moved_distance_m': _maxMove,
      if (tag != null) 'noise_context': tag!.name,
    };

    final store = session.store!;
    await store.addPending(payload);
    await store.addPoint(MyPoint(origin.latitude, origin.longitude, c(s.laeq), DateTime.now()));

    final res = await _flush();
    final sentId = res.accepted[payload['client_measurement_id'] as String];
    _lastServerId = sentId;
    result = RecResult(
        laeq: c(s.laeq),
        lmax: c(s.lmax),
        lmin: c(s.lmin),
        seconds: s.seconds,
        sent: sentId != null,
        tag: tag);
    proposal = null;
    phase = RecPhase.done;
    completedVersion++;
    notifyListeners();

    if (sentId != null) {
      notifier.result('Mesure envoyée',
          'LAeq ${c(s.laeq).toStringAsFixed(1)} dB(A) · évaluation en cours…');
      unawaited(_watch({sentId}));
    } else {
      notifier.result('Mesure enregistrée',
          'Elle sera envoyée dès que la connexion le permettra.');
    }
  }

  // ------------------------------------------------------------------ envoi hors-ligne
  Future<FlushResult> _flush() async {
    final store = session.store;
    if (store == null) return FlushResult();
    while (_flushing) {
      await Future.delayed(const Duration(milliseconds: 200));
    }
    _flushing = true;
    try {
      final r = await store.flush(api);
      pendingCount = store.pendingCount;
      if (r.accepted.isNotEmpty) completedVersion++;
      return r;
    } finally {
      _flushing = false;
    }
  }

  Future<void> refreshPending() async {
    pendingCount = session.store?.pendingCount ?? 0;
    notifyListeners();
  }

  Future<void> flushPending() async {
    if (session.store == null || busy) return;
    final before = session.store!.pendingCount;
    if (before == 0) {
      pendingCount = 0;
      notifyListeners();
      return;
    }
    final r = await _flush();
    notifyListeners();
    if (r.accepted.isNotEmpty) {
      notifier.result('Mesures envoyées',
          '${r.accepted.length} mesure(s) hors-ligne synchronisée(s).');
      unawaited(_watch(r.accepted.values.toSet()));
    }
  }

  // ------------------------------------------------------------------ suivi de l'évaluation
  Future<void> _watch(Set<String> ids) async {
    final pending = {...ids};
    for (var i = 0; i < 14 && pending.isNotEmpty && !_disposed; i++) {
      await Future.delayed(const Duration(seconds: 5));
      try {
        final items = await api.history(limit: 50, offset: 0);
        for (final it in items) {
          if (!pending.contains(it.id) || it.qualityStatus == 'pending') continue;
          pending.remove(it.id);
          if (it.id == _lastServerId) {
            qualityStatus = it.qualityStatus;
            qualityScore = it.qualityScore;
            reasons = it.reasons;
          }
          completedVersion++;
          final score = it.qualityScore == null ? '' : 'Score ${(it.qualityScore! * 100).round()} %';
          final why = it.reasons.isNotEmpty ? ' · ${reasonLabel(it.reasons.first)}' : '';
          notifier.result(
            switch (it.qualityStatus) {
              'validated' => 'Mesure validée',
              'indicative' => 'Mesure indicative',
              _ => 'Mesure rejetée',
            },
            '$score$why'.trim().isEmpty ? qualityLabel(it.qualityStatus) : '$score$why',
          );
          notifyListeners();
        }
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _rec.dispose();
    super.dispose();
  }
}