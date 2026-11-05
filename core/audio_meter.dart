import 'dart:math';
import 'dart:typed_data';

import 'config.dart';

class _Biquad {
  _Biquad(this.b0, this.b1, this.b2, this.a1, this.a2);
  final double b0, b1, b2, a1, a2;
  double _z1 = 0, _z2 = 0;

  /// Transformée bilinéaire d'une section analogique (nb2 s² + nb1 s + nb0) / (da2 s² + da1 s + da0).
  factory _Biquad.fromAnalog(
      double nb2, double nb1, double nb0, double da2, double da1, double da0, double fs) {
    final c = 2 * fs, c2 = c * c;
    final n0 = nb2 * c2 + nb1 * c + nb0;
    final n1 = -2 * nb2 * c2 + 2 * nb0;
    final n2 = nb2 * c2 - nb1 * c + nb0;
    final d0 = da2 * c2 + da1 * c + da0;
    final d1 = -2 * da2 * c2 + 2 * da0;
    final d2 = da2 * c2 - da1 * c + da0;
    return _Biquad(n0 / d0, n1 / d0, n2 / d0, d1 / d0, d2 / d0);
  }

  double process(double x) {
    final y = b0 * x + _z1;
    _z1 = b1 * x - a1 * y + _z2;
    _z2 = b2 * x - a2 * y;
    return y;
  }

  double magnitude(double f, double fs) {
    final w = 2 * pi * f / fs;
    final nr = b0 + b1 * cos(w) + b2 * cos(2 * w);
    final ni = -b1 * sin(w) - b2 * sin(2 * w);
    final dr = 1 + a1 * cos(w) + a2 * cos(2 * w);
    final di = -a1 * sin(w) - a2 * sin(2 * w);
    return sqrt(nr * nr + ni * ni) / sqrt(dr * dr + di * di);
  }
}

/// Pondération A (pôles normalisés IEC 61672), gain normalisé à 0 dB à 1 kHz.
class AWeighting {
  AWeighting(double fs) {
    final w1 = 2 * pi * 20.598997;
    final w2 = 2 * pi * 107.65265;
    final w3 = 2 * pi * 737.86223;
    final w4 = 2 * pi * 12194.217;
    _sections = [
      _Biquad.fromAnalog(1, 0, 0, 1, 2 * w1, w1 * w1, fs),
      _Biquad.fromAnalog(1, 0, 0, 1, w2 + w3, w2 * w3, fs),
      _Biquad.fromAnalog(0, 0, 1, 1, 2 * w4, w4 * w4, fs),
    ];
    var m = 1.0;
    for (final s in _sections) {
      m *= s.magnitude(1000, fs);
    }
    _gain = 1 / m;
  }
  late final List<_Biquad> _sections;
  late final double _gain;

  double process(double x) {
    var y = x;
    for (final s in _sections) {
      y = s.process(y);
    }
    return y * _gain;
  }
}

class NoiseStats {
  NoiseStats(this.laeq, this.lmax, this.lmin, this.saturation, this.seconds);
  final double laeq, lmax, lmin, saturation, seconds;
}

/// Accumule du PCM16 mono little-endian ; calcule LAeq (moyenne énergétique), Lmax / Lmin sur blocs de 125 ms.
class NoiseAccumulator {
  NoiseAccumulator(this.sampleRate)
      : _w = AWeighting(sampleRate.toDouble()),
        _blockSize = (sampleRate * 0.125).round();

  final int sampleRate;
  final AWeighting _w;
  final int _blockSize;

  double _sumSq = 0, _blockSum = 0;
  int _n = 0, _blockN = 0, _clipped = 0;
  double _lmax = double.negativeInfinity, _lmin = double.infinity;
  int? _carry;
  double lastBlockDb = 0;
  final List<double> blocks = [];

  double get seconds => _n / sampleRate;
  double get leqDb => _n == 0 ? 0 : toDb(_sumSq / _n);
  double get maxDb => _lmax.isFinite ? _lmax : leqDb;

  static double toDb(double meanSquare) =>
      10 * (log(max(meanSquare, 1e-12)) / ln10) + AppConfig.micReferenceOffsetDb;

  void add(Uint8List data) {
    var start = 0;
    if (_carry != null && data.isNotEmpty) {
      _push(_toSample(_carry!, data[0]));
      _carry = null;
      start = 1;
    }
    final remaining = data.length - start;
    final usable = (remaining ~/ 2) * 2;
    if (usable > 0) {
      final bd = ByteData.sublistView(data, start, start + usable);
      for (var i = 0; i < usable; i += 2) {
        _push(bd.getInt16(i, Endian.little));
      }
    }
    if (remaining % 2 == 1) _carry = data[data.length - 1];
  }

  int _toSample(int lo, int hi) {
    final v = (hi << 8) | lo;
    return v >= 0x8000 ? v - 0x10000 : v;
  }

  void _push(int s) {
    if (s.abs() >= 32700) _clipped++;
    final y = _w.process(s / 32768.0);
    final p = y * y;
    _sumSq += p;
    _n++;
    _blockSum += p;
    _blockN++;
    if (_blockN >= _blockSize) _closeBlock();
  }

  void _closeBlock() {
    final db = toDb(_blockSum / _blockN);
    lastBlockDb = db;
    if (db > _lmax) _lmax = db;
    if (db < _lmin) _lmin = db;
    blocks.add(db);
    _blockSum = 0;
    _blockN = 0;
  }

  NoiseStats finish() {
    if (_blockN > 0) _closeBlock();
    final laeq = leqDb;
    final mx = max(_lmax.isFinite ? _lmax : laeq, laeq);
    final mn = min(_lmin.isFinite ? _lmin : laeq, laeq);
    return NoiseStats(laeq, mx, mn, _n == 0 ? 0 : _clipped / _n, seconds);
  }
}