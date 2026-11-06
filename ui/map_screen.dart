import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:provider/provider.dart';
import '../core/route_trim.dart';
import '../core/api.dart';
import '../core/api_ext.dart';
import '../core/config.dart';
import '../core/live_layers.dart';
import '../core/models.dart';
import '../core/models_ext.dart';
import '../core/models_field.dart';
import '../core/util.dart';
import '../state/missions_controller.dart';
import '../state/proposals_controller.dart';
import '../state/quota_controller.dart';
import '../state/recorder_controller.dart';
import '../state/session_controller.dart';
import '../state/view_models.dart';
import 'cell_sheet.dart';
import 'missions_screen.dart';
import 'search_sheet.dart';
import 'widgets.dart';
import '../core/models_roads.dart';
import '../state/roads_view_model.dart';
import 'road_sheet.dart';
// ============================================================================
// Palette du bruit : bandes de 5 dB, plus foncé = plus bruyant
// ============================================================================
const _bandColors = <Color>[
  Color(0xFFBFDCE0), // < 40
  Color(0xFFCFE6CE), // 40-45
  Color(0xFFE4F0BE), // 45-50
  Color(0xFFF6E3A0), // 50-55
  Color(0xFFF2BD78), // 55-60
  Color(0xFFE8884F), // 60-65
  Color(0xFFCC4A3C), // 65-70
  Color(0xFF9E1B4C), // 70-75
  Color(0xFF6A0B63), // 75-80
  Color(0xFF3E0A4F), // >= 80
];

int noiseBandIndex(double db) => ((db - 35) / 5).floor().clamp(0, 9).toInt();
double noiseBandAlpha(double db) => 0.50 + 0.04 * noiseBandIndex(db);

/// Couleur d'un niveau : bande (fond clair) ou dégradé lumineux (fond sombre).
Color noiseBandColor(double db, {bool glow = false}) =>
    glow ? noiseHeat(db, glow: true) : _bandColors[noiseBandIndex(db)];

Color noiseHeat(double db, {bool glow = false}) {
  const stops = <double>[35, 50, 60, 70, 80, 90, 100];
  const onLight = <Color>[
    Color(0xFFFDE047),
    Color(0xFFFBBF24),
    Color(0xFFF97316),
    Color(0xFFDC2626),
    Color(0xFF9F1239),
    Color(0xFF4C0519),
    Color(0xFF1E0A2E),
  ];
  const onDark = <Color>[
    Color(0xFF164E63),
    Color(0xFF0891B2),
    Color(0xFF22D3EE),
    Color(0xFFFDE047),
    Color(0xFFFB923C),
    Color(0xFFF43F5E),
    Color(0xFFFFFFFF),
  ];
  final cols = glow ? onDark : onLight;
  if (db <= stops.first) return cols.first;
  if (db >= stops.last) return cols.last;
  for (var i = 0; i < stops.length - 1; i++) {
    if (db <= stops[i + 1]) {
      return Color.lerp(cols[i], cols[i + 1], (db - stops[i]) / (stops[i + 1] - stops[i]))!;
    }
  }
  return cols.last;
}

enum _NoiseMode { cloud, grid }

enum _Veil { none, temp, rain, cloud, soil }

// ============================================================================
// Voiles météo : champs continus interpolés
// ============================================================================
double? Function(WeatherPoint) _pick(_Veil v) => switch (v) {
      _Veil.temp => (WeatherPoint w) => w.temp,
      _Veil.rain => (WeatherPoint w) => w.precip,
      _Veil.cloud => (WeatherPoint w) => w.cloud.toDouble(),
      _Veil.soil => (WeatherPoint w) => w.soil,
      _Veil.none => (WeatherPoint w) => null,
    };

Color _rainRamp(double t) => Color.lerp(const Color(0xFF7DD3FC), const Color(0xFF4F46E5), t)!;

Color? _veilColor(_Veil v, double x, bool dark) {
  switch (v) {
    case _Veil.temp:
    case _Veil.soil:
      return tempColor(x).withValues(alpha: 0.52);
    case _Veil.rain:
      if (x < 0.05) return null;
      final t = (log(1 + x) / log(21)).clamp(0.0, 1.0).toDouble();
      return _rainRamp(t).withValues(alpha: 0.22 + 0.55 * t);
    case _Veil.cloud:
      final t = (x / 100).clamp(0.0, 1.0).toDouble();
      if (t < 0.08) return null;
      final base = dark ? const Color(0xFFE2E8F0) : const Color(0xFF475569);
      return base.withValues(alpha: 0.6 * pow(t, 1.3).toDouble());
    case _Veil.none:
      return null;
  }
}

({String title, List<Color> colors, String lo, String hi}) _veilInfo(_Veil v) => switch (v) {
      _Veil.temp => (
          title: 'Température',
          colors: [for (final t in const [10.0, 18.0, 26.0, 34.0, 42.0]) tempColor(t)],
          lo: '10°',
          hi: '42°C'
        ),
      _Veil.soil => (
          title: 'Température du sol',
          colors: [for (final t in const [10.0, 18.0, 26.0, 34.0, 42.0]) tempColor(t)],
          lo: '10°',
          hi: '42°C'
        ),
      _Veil.rain => (
          title: 'Précipitations',
          colors: [_rainRamp(0), _rainRamp(0.5), _rainRamp(1)],
          lo: '0',
          hi: '20 mm'
        ),
      _Veil.cloud => (
          title: 'Couverture nuageuse',
          colors: [const Color(0xFFE2E8F0), const Color(0xFF475569)],
          lo: '0',
          hi: '100 %'
        ),
      _Veil.none => (title: '', colors: const [Colors.transparent, Colors.transparent], lo: '', hi: ''),
    };

String _veilValue(_Veil v, double x) => switch (v) {
      _Veil.rain => '${x.toStringAsFixed(1)} mm',
      _Veil.cloud => '${x.round()} %',
      _ => '${x.round()} °C',
    };

class _WxField {
  _WxField(this.pts, this.area, this.cols, this.rows);
  final List<WeatherPoint> pts;
  final LatLngBounds area;
  final int cols, rows;

  bool get _lattice => pts.length == cols * rows;

  double? at(double lat, double lon, double? Function(WeatherPoint) pick) {
    if (pts.isEmpty) return null;
    if (_lattice) {
      final fx = ((lon - area.west) / (area.east - area.west) * cols - 0.5).clamp(0.0, cols - 1.0).toDouble();
      final fy = ((lat - area.south) / (area.north - area.south) * rows - 0.5).clamp(0.0, rows - 1.0).toDouble();
      final x0 = fx.floor(), y0 = fy.floor();
      final x1 = min(x0 + 1, cols - 1), y1 = min(y0 + 1, rows - 1);
      final tx = fx - x0, ty = fy - y0;
      final v00 = pick(pts[y0 * cols + x0]), v10 = pick(pts[y0 * cols + x1]);
      final v01 = pick(pts[y1 * cols + x0]), v11 = pick(pts[y1 * cols + x1]);
      if (v00 == null || v10 == null || v01 == null || v11 == null) return null;
      return (v00 * (1 - tx) + v10 * tx) * (1 - ty) + (v01 * (1 - tx) + v11 * tx) * ty;
    }
    var sum = 0.0, wsum = 0.0;
    for (final w in pts) {
      final v = pick(w);
      if (v == null) continue;
      final dx = lon - w.pos.longitude, dy = lat - w.pos.latitude;
      final k = 1 / (dx * dx + dy * dy + 1e-6);
      sum += v * k;
      wsum += k;
    }
    return wsum == 0 ? null : sum / wsum;
  }
}

// ============================================================================
// Simulation du flux (particules portées par le vent du serveur)
// ============================================================================
class _Src {
  _Src(this.lat, this.lon, this.db, this.rM);
  final double lat, lon, db, rM;
}

class _WindSample {
  _WindSample(this.lat, this.lon, this.u, this.v);
  final double lat, lon, u, v;
}

class _Particle {
  double lat = 0, lon = 0, age = 0, life = 1, db = 50, u = 0, v = 0;
  bool alive = false;
}

class _FlowSim {
  /// 1 seconde réelle = 45 secondes simulées (sinon le mouvement serait invisible).
  static const double timeLapse = 45.0;
  static const int maxParticles = 650;

  final Random _rnd = Random();
  final List<_Src> sources = [];
  final List<double> _cum = [];
  final List<_WindSample> _wind = [];
  final List<_Particle> ps = [];
  final Stopwatch _sw = Stopwatch()..start();

  double _last = 0, elapsed = 0, dt = 0;
  double meanU = 0, meanV = 0;

  bool get hasWind => _wind.isNotEmpty;
  bool get hasSources => sources.isNotEmpty;
  double get meanSpeedMs => sqrt(meanU * meanU + meanV * meanV);
  double get bearingTo => (atan2(meanU, meanV) * 180 / pi + 360) % 360;

  void tick() {
    elapsed = _sw.elapsedMicroseconds / 1e6;
    dt = (elapsed - _last).clamp(0.0, 0.05).toDouble();
    _last = elapsed;
  }

  void setCells(List<NoiseCell> cells) {
    sources.clear();
    _cum.clear();
    for (final c in cells) {
      if (c.laeq < 50 || c.polygon.length < 4) continue;
      final n = c.polygon.length - 1;
      var la = 0.0, lo = 0.0;
      for (var i = 0; i < n; i++) {
        la += c.polygon[i].latitude;
        lo += c.polygon[i].longitude;
      }
      la /= n;
      lo /= n;
      final dLat = (c.polygon[0].latitude - la) * 111320.0;
      final dLon = (c.polygon[0].longitude - lo) * 111320.0 * cos(la * pi / 180);
      sources.add(_Src(la, lo, c.laeq, max(30.0, sqrt(dLat * dLat + dLon * dLon))));
    }
    sources.sort((a, b) => b.db.compareTo(a.db));
    if (sources.length > 400) sources.removeRange(400, sources.length);
    var acc = 0.0;
    for (final s in sources) {
      acc += pow(s.db - 45, 2).toDouble();
      _cum.add(acc);
    }
    if (sources.isEmpty) {
      ps.clear();
      return;
    }
    final target = min(maxParticles, 80 + sources.length * 8);
    while (ps.length < target) {
      ps.add(_Particle());
    }
    if (ps.length > target) ps.removeRange(target, ps.length);
  }

  /// Vent fourni par le serveur (identique pour tous) : un seul vecteur pour la zone.
  void setUniform(double lat, double lon, double u, double v) {
    _wind
      ..clear()
      ..add(_WindSample(lat, lon, u, v));
    meanU = u;
    meanV = v;
  }

  /// Vent d'une grille Open-Meteo récupérée par le client (repli si le serveur n'en fournit pas).
  void setWind(List<WeatherPoint> pts) {
    _wind.clear();
    var su = 0.0, sv = 0.0;
    for (final w in pts) {
      final to = (w.windDir + 180) * pi / 180;
      final ms = w.wind / 3.6;
      final u = sin(to) * ms;
      final v = cos(to) * ms;
      _wind.add(_WindSample(w.pos.latitude, w.pos.longitude, u, v));
      su += u;
      sv += v;
    }
    if (_wind.isEmpty) {
      meanU = 0;
      meanV = 0;
    } else {
      meanU = su / _wind.length;
      meanV = sv / _wind.length;
    }
  }

  (double, double) windAt(double lat, double lon) {
    if (_wind.isEmpty) return (0.0, 0.0);
    if (_wind.length == 1) return (_wind.first.u, _wind.first.v);
    var wu = 0.0, wv = 0.0, ws = 0.0;
    for (final w in _wind) {
      final dx = lon - w.lon, dy = lat - w.lat;
      final k = 1 / (dx * dx + dy * dy + 1e-8);
      wu += w.u * k;
      wv += w.v * k;
      ws += k;
    }
    return (wu / ws, wv / ws);
  }

  void _spawn(_Particle p, {required bool stagger}) {
    final r = _rnd.nextDouble() * _cum.last;
    var lo = 0, hi = _cum.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_cum[mid] >= r) {
        hi = mid;
      } else {
        lo = mid + 1;
      }
    }
    final s = sources[lo];
    final ang = _rnd.nextDouble() * 2 * pi;
    final rad = sqrt(_rnd.nextDouble()) * s.rM;
    p.lat = s.lat + (sin(ang) * rad) / 111320.0;
    p.lon = s.lon + (cos(ang) * rad) / (111320.0 * cos(s.lat * pi / 180));
    p.db = s.db;
    p.life = 3.5 + _rnd.nextDouble() * 3.5;
    p.age = stagger ? _rnd.nextDouble() * p.life : 0;
    p.alive = true;
  }

  void advance() {
    if (sources.isEmpty) return;
    final k = dt * timeLapse;
    for (final p in ps) {
      if (!p.alive || p.age >= p.life) _spawn(p, stagger: !p.alive);
      final w = windAt(p.lat, p.lon);
      p.u = w.$1;
      p.v = w.$2;
      final cosLat = cos(p.lat * pi / 180);
      p.lat += ((p.v + (_rnd.nextDouble() - 0.5) * 1.2) * k) / 111320.0;
      p.lon += ((p.u + (_rnd.nextDouble() - 0.5) * 1.2) * k) / (111320.0 * cosLat);
      p.age += dt;
    }
  }
}

// ============================================================================
// Projection Web Mercator (tuiles de 256 px), identique à celle de flutter_map
// ============================================================================
class _Proj {
  _Proj(LatLng center, this.zoom, this.size) : _scale = pow(2.0, zoom).toDouble() {
    _ws = 256.0 * _scale;
    _cx = _x(center.longitude);
    _cy = _y(center.latitude);
  }

  final double zoom;
  final Size size;
  final double _scale;
  late final double _ws, _cx, _cy;

  double _x(double lon) => (lon + 180) / 360 * _ws;

  double _y(double lat) {
    final s = sin(lat * pi / 180).clamp(-0.9999, 0.9999).toDouble();
    return (0.5 - log((1 + s) / (1 - s)) / (4 * pi)) * _ws;
  }

  Offset at(double lat, double lon) =>
      Offset(size.width / 2 + _x(lon) - _cx, size.height / 2 + _y(lat) - _cy);

  double lonAt(double sx) => (_cx + (sx - size.width / 2)) / _ws * 360 - 180;

  double latAt(double sy) {
    final wy = _cy + (sy - size.height / 2);
    final n = pi - 2 * pi * wy / _ws;
    return 180 / pi * atan(0.5 * (exp(n) - exp(-n)));
  }

  double px(double meters, double lat) => meters * _scale / (156543.03392 * cos(lat * pi / 180));
}

// ============================================================================
// Scène dessinée par le calque (la carte du bruit vient uniquement du serveur)
// ============================================================================
class _Scene {
  _Scene({
    required this.clock,
    required this.sim,
    required this.cells,
    required this.selected,
    required this.mode,
    required this.showNoise,
    required this.showFlow,
    required this.dark,
    required this.field,
    required this.fieldPrev,
    required this.fieldSwapAt,
    required this.veil,
    required this.wxField,
    required this.tl,
    required this.tlPos,
    required this.missions,
    required this.me,
    required this.route,
    required this.accent,
    required this.roads,
    required this.roadStates,
    required this.showRoads,
    required this.selectedRoad,
    required this.mTarget,
  });
  final Listenable clock;
  final _FlowSim sim;
  final List<NoiseCell> cells;
  final String? selected;
  final _NoiseMode mode;
  final bool showNoise, showFlow, dark;
  final FieldGrid? field, fieldPrev;
  final double fieldSwapAt;
  final _Veil veil;
  final _WxField? wxField;
  final Timelapse? tl;
  final ValueNotifier<double> tlPos;
  final List<Mission> missions;
  final LatLng? me;
  final List<RoadSeg> roads;
  final Map<String, RoadState> roadStates;
  final bool showRoads;
  final String? selectedRoad;
  final MissionTarget? mTarget;
  final List<LatLng>? route;
  final Color accent;
}

class _Drawn {
  _Drawn(this.cell, this.path, this.rect);
  final NoiseCell cell;
  final Path path;
  final Rect rect;
}

class _FlowLayer extends StatelessWidget {
  const _FlowLayer({required this.scene});
  final _Scene scene;

  @override
  Widget build(BuildContext context) {
    final cam = MapCamera.of(context);
    return IgnorePointer(
      child: SizedBox.expand(child: CustomPaint(painter: _ScenePainter(cam, scene))),
    );
  }
}

class _ScenePainter extends CustomPainter {
  _ScenePainter(this.camera, this.s) : super(repaint: s.clock);
  final MapCamera camera;
  final _Scene s;

  @override
  void paint(Canvas canvas, Size size) {
    s.sim.tick();
    final pr = _Proj(camera.center, camera.zoom, size);
    final clip = (Offset.zero & size).inflate(60);
    if (s.veil != _Veil.none) _veil(canvas, pr, size, clip);
    if (s.showNoise) {
      if (s.tl != null) {
        _noise(canvas, pr, clip, s.tl!.cellsAt(s.tlPos.value), blur: true);
      } else if (s.mode == _NoiseMode.cloud) {
        if (s.field != null) {
          _cloud(canvas, pr, size, clip);
        } else {
          _noise(canvas, pr, clip, s.cells, blur: true);
        }
      } else {
        _noise(canvas, pr, clip, s.cells, blur: false);
      }
    }
    if (s.showRoads) _roads(canvas, pr, size, clip);
    _missions(canvas, pr, clip);
    if (s.showFlow) _flow(canvas, pr, clip);
    _route(canvas, pr);
    _target(canvas, pr);
    _me(canvas, pr);
  }

  @override
  bool shouldRepaint(covariant _ScenePainter old) => true;

  void _text(Canvas c, String t, Offset center,
      {double size = 10, Color color = Colors.white, bool shadow = true}) {
    final tp = TextPainter(
      text: TextSpan(
        text: t,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: FontWeight.w800,
          shadows: shadow ? const [Shadow(color: Colors.black54, blurRadius: 3)] : null,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, center - Offset(tp.width / 2, tp.height / 2));
  }

  // -------------------------------------------------------------- nuage de bruit (champ du serveur)
  void _cloud(Canvas canvas, _Proj pr, Size size, Rect clip) {
    final cur = s.field!;
    final blend = ((s.sim.elapsed - s.fieldSwapAt) / 1.5).clamp(0.0, 1.0).toDouble();
    final prev = blend < 1 ? s.fieldPrev : null;
    const step = 6.0;
    canvas.saveLayer(
      clip,
      Paint()
        ..imageFilter = ui.ImageFilter.blur(sigmaX: 2.4, sigmaY: 2.4, tileMode: ui.TileMode.decal),
    );
    final xs = <double>[], lons = <double>[];
    for (var x = -step; x <= size.width + step; x += step) {
      xs.add(x);
      lons.add(pr.lonAt(x));
    }
    final p = Paint()..style = PaintingStyle.fill;
    for (var y = -step; y <= size.height + step; y += step) {
      final lat = pr.latAt(y);
      for (var i = 0; i < xs.length; i++) {
        final a = cur.sample(lat, lons[i]);
        var lv = a.$1, sup = a.$2;
        if (prev != null) {
          final b = prev.sample(lat, lons[i]);
          if (b.$2 > 0 && sup > 0) {
            lv = b.$1 + (lv - b.$1) * blend;
            sup = b.$2 + (sup - b.$2) * blend;
          } else if (b.$2 > 0) {
            lv = b.$1;
            sup = b.$2 * (1 - blend);
          } else {
            sup = sup * blend;
          }
        }
        if (sup < 0.04 || lv.isNaN || lv < 36) continue;
        final alpha = (s.dark ? 0.8 : noiseBandAlpha(lv)) * pow(sup, 0.5).toDouble();
        p.color = noiseBandColor(lv, glow: s.dark).withValues(alpha: alpha);
        canvas.drawRect(Rect.fromLTWH(xs[i] - step / 2, y - step / 2, step + 0.5, step + 0.5), p);
      }
    }
    canvas.restore();
  }


  // -------------------------------------------------------------- routes réelles (nuage + trait net)
  static Object? _rkSegs, _rkStates;
  static List<double>? _rkCam;
  static bool? _rkDark, _rkCloud;
  static ui.Picture? _rkPic;

  /// Courbe lissée passant par les extrémités exactes (la connexion avec le tronçon voisin est conservée).
  static void _smooth(Path path, List<Offset> o) {
    if (o.length < 2) return;
    path.moveTo(o[0].dx, o[0].dy);
    if (o.length == 2) {
      path.lineTo(o[1].dx, o[1].dy);
      return;
    }
    path.lineTo((o[0].dx + o[1].dx) / 2, (o[0].dy + o[1].dy) / 2);
    for (var i = 1; i < o.length - 1; i++) {
      path.quadraticBezierTo(o[i].dx, o[i].dy, (o[i].dx + o[i + 1].dx) / 2, (o[i].dy + o[i + 1].dy) / 2);
    }
    path.lineTo(o.last.dx, o.last.dy);
  }

  Color _roadColor(double db) {
    if (s.dark) return noiseHeat(db, glow: true);
    final x = ((db - 35) / 5).clamp(0.0, 9.0).toDouble();
    final i = x.floor().clamp(0, 8);
    return Color.lerp(Color.lerp(_bandColors[i], _bandColors[i + 1], x - i)!, const Color(0xFF1E293B), 0.14)!;
  }

  ui.Picture _roadPicture(_Proj pr, Size size, Rect clip) {
    final cam = [camera.center.latitude, camera.center.longitude, camera.zoom, size.width, size.height];
    final cloud = s.mode == _NoiseMode.cloud;
    bool same() {
      final k = _rkCam;
      if (k == null || _rkPic == null || !identical(_rkSegs, s.roads) || !identical(_rkStates, s.roadStates)) return false;
      if (_rkDark != s.dark || _rkCloud != cloud) return false;
      for (var i = 0; i < cam.length; i++) {
        if (k[i] != cam[i]) return false;
      }
      return true;
    }

    if (same()) return _rkPic!;

    final vb = camera.visibleBounds;
    const m = 0.002;
    final buckets = <int, Path>{};
    for (final seg in s.roads) {
      if (seg.maxLat < vb.south - m || seg.minLat > vb.north + m || seg.maxLon < vb.west - m || seg.minLon > vb.east + m) continue;
      final st = s.roadStates[seg.id];
      final ci = (st == null || !st.hasData) ? 0 : 1 + ((st.laeq - 35) / 2).round().clamp(0, 40).toInt();
      final wc = seg.rank <= 2 ? 0 : (seg.rank <= 4 ? 1 : 2);
      _smooth(buckets.putIfAbsent(ci * 3 + wc, () => Path()), [for (final p in seg.points) pr.at(p.latitude, p.longitude)]);
    }

    final z = camera.zoom;
    final base = (0.9 + (z - 11) * 0.32).clamp(0.9, 4.0).toDouble();
    double wOf(int wc) => base * (wc == 0 ? 1.5 : wc == 1 ? 1.15 : 0.85);
    final keys = buckets.keys.toList()..sort();
    final rec = ui.PictureRecorder();
    final c = Canvas(rec, clip);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // halo léger : seulement les routes mesurées
    final sigma = max(2.0, base * 1.2);
    c.saveLayer(clip, Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: ui.TileMode.decal));
    for (final k in keys) {
      final ci = k ~/ 3;
      if (ci == 0) continue;
      paint
        ..color = _roadColor(35 + 2.0 * (ci - 1)).withValues(alpha: cloud ? 0.30 : 0.20)
        ..strokeWidth = wOf(k % 3) * 2.6;
      c.drawPath(buckets[k]!, paint);
    }
    c.restore();

    // trait fin : non mesuré = vert très discret, mesuré = couleur continue
    for (final k in keys) {
      final ci = k ~/ 3;
      paint
        ..color = ci == 0 ? const Color(0xFF6FCF97).withValues(alpha: 0.28) : _roadColor(35 + 2.0 * (ci - 1)).withValues(alpha: 0.72)
        ..strokeWidth = wOf(k % 3) * (ci == 0 ? 0.7 : 0.85);
      c.drawPath(buckets[k]!, paint);
    }

    _rkPic?.dispose();
    _rkPic = rec.endRecording();
    _rkSegs = s.roads;
    _rkStates = s.roadStates;
    _rkCam = cam;
    _rkDark = s.dark;
    _rkCloud = cloud;
    return _rkPic!;
  }

  void _roads(Canvas canvas, _Proj pr, Size size, Rect clip) {
    if (s.roads.isEmpty) return;
    canvas.drawPicture(_roadPicture(pr, size, clip));
    final sel = s.selectedRoad;
    if (sel == null) return;
    final base = (0.9 + (camera.zoom - 11) * 0.32).clamp(0.9, 4.0).toDouble();
    for (final seg in s.roads) {
      if (seg.id != sel) continue;
      final path = Path();
      _smooth(path, [for (final p in seg.points) pr.at(p.latitude, p.longitude)]);
      final line = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(path, line..color = Colors.black45..strokeWidth = base * 2.2 + 3);
      canvas.drawPath(path, line..color = Colors.white..strokeWidth = base * 2.2);
      break;
    }
  }

  // -------------------------------------------------------------- point cible d'une mission route
  void _target(Canvas canvas, _Proj pr) {
    final t = s.mTarget;
    if (t == null) return;
    final o = pr.at(t.lat, t.lon);
    final r = max(pr.px(t.radiusM, t.lat), 14.0);
    final pulse = (s.sim.elapsed % 1.8) / 1.8;
    canvas.drawCircle(o, r + 14 * pulse, Paint()..color = s.accent.withValues(alpha: 0.30 * (1 - pulse)));
    canvas.drawCircle(o, r, Paint()..color = s.accent.withValues(alpha: 0.16));
    canvas.drawCircle(o, r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = s.accent);
    canvas.drawCircle(o, 11, Paint()..color = Colors.white);
    canvas.drawCircle(o, 8.5, Paint()..color = s.accent);
    _text(canvas, '⚑', o, size: 11);
  }

  // -------------------------------------------------------------- voile météo
  void _veil(Canvas canvas, _Proj pr, Size size, Rect clip) {
    final f = s.wxField;
    if (f == null) return;
    const step = 24.0;
    final pick = _pick(s.veil);
    final t = s.sim.elapsed;
    canvas.saveLayer(
      clip,
      Paint()
        ..imageFilter =
            ui.ImageFilter.blur(sigmaX: step * 0.8, sigmaY: step * 0.8, tileMode: ui.TileMode.decal),
    );
    final xs = <double>[], lons = <double>[];
    for (var x = -step; x <= size.width + step; x += step) {
      xs.add(x);
      lons.add(pr.lonAt(x));
    }
    final p = Paint()..style = PaintingStyle.fill;
    for (var y = -step; y <= size.height + step; y += step) {
      final lat = pr.latAt(y);
      for (var i = 0; i < xs.length; i++) {
        final v = f.at(lat, lons[i], pick);
        if (v == null) continue;
        var c = _veilColor(s.veil, v, s.dark);
        if (c == null) continue;
        if (s.veil == _Veil.rain) {
          c = c.withValues(alpha: c.a * (0.9 + 0.1 * sin(xs[i] * 0.02 + y * 0.015 + t * 1.5)));
        }
        p.color = c;
        canvas.drawRect(Rect.fromLTWH(xs[i] - step / 2, y - step / 2, step + 0.5, step + 0.5), p);
      }
    }
    canvas.restore();
  }

  // -------------------------------------------------------------- cellules (grille, repli, historique)
  void _noise(Canvas canvas, _Proj pr, Rect clip, List<NoiseCell> cells, {required bool blur}) {
    final items = <_Drawn>[];
    for (var i = cells.length - 1; i >= 0 && items.length < 1500; i--) {
      final c = cells[i];
      final path = Path();
      var x0 = double.infinity, y0 = double.infinity;
      var x1 = -double.infinity, y1 = -double.infinity;
      for (var k = 0; k < c.polygon.length; k++) {
        final o = pr.at(c.polygon[k].latitude, c.polygon[k].longitude);
        if (k == 0) {
          path.moveTo(o.dx, o.dy);
        } else {
          path.lineTo(o.dx, o.dy);
        }
        if (o.dx < x0) x0 = o.dx;
        if (o.dy < y0) y0 = o.dy;
        if (o.dx > x1) x1 = o.dx;
        if (o.dy > y1) y1 = o.dy;
      }
      path.close();
      final rect = Rect.fromLTRB(x0, y0, x1, y1);
      if (!rect.overlaps(clip)) continue;
      items.add(_Drawn(c, path, rect));
    }
    if (items.isEmpty) return;
    final ordered = items.reversed.toList();
    final r = ordered.first.rect.shortestSide / 2;
    Color fillOf(NoiseCell c) => noiseBandColor(c.laeq, glow: s.dark)
        .withValues(alpha: min(0.92, (s.dark ? 0.8 : noiseBandAlpha(c.laeq)) * (0.8 + 0.2 * c.confidence.clamp(0.0, 1.0))));

    if (blur) {
      final sigma = max(2.5, r * 0.42);
      canvas.saveLayer(
        clip,
        Paint()
          ..imageFilter =
              ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: ui.TileMode.decal),
      );
      final p = Paint()..style = PaintingStyle.fill;
      for (final d in ordered) {
        p.color = fillOf(d.cell);
        canvas.drawPath(d.path, p);
      }
      canvas.restore();
    } else {
      final fill = Paint()..style = PaintingStyle.fill;
      final border = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..strokeJoin = StrokeJoin.round;
      for (final d in ordered) {
        fill.color = fillOf(d.cell);
        border.color = noiseBandColor(d.cell.laeq, glow: s.dark).withValues(alpha: 0.9);
        canvas.drawPath(d.path, fill);
        canvas.drawPath(d.path, border);
      }
    }

    if (s.selected != null && s.tl == null) {
      for (final d in ordered) {
        if (d.cell.h3 != s.selected) continue;
        canvas.drawPath(
            d.path,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 6
              ..color = Colors.black54
              ..strokeJoin = StrokeJoin.round);
        canvas.drawPath(
            d.path,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3
              ..color = Colors.white
              ..strokeJoin = StrokeJoin.round);
      }
    }

    if (r > 26 && ordered.length <= 80) {
      for (final d in ordered) {
        final lowOnLight = noiseBandIndex(d.cell.laeq) <= 3 && !s.dark;
        _text(canvas, d.cell.laeq.toStringAsFixed(0), d.rect.center,
            size: min(18.0, r * 0.5),
            color: lowOnLight ? const Color(0xFF5B2A00) : Colors.white,
            shadow: !lowOnLight);
      }
    }
  }

  // -------------------------------------------------------------- zones de missions
  void _missions(Canvas canvas, _Proj pr, Rect clip) {
    for (final m in s.missions) {
      if (!m.isActive) continue;
      //final o = pr.at(m.centerLat, m.centerLon);
      //final r = pr.px(m.radiusM, m.centerLat);
      //if (!clip.inflate(r).contains(o)) continue;
      final o = pr.at(m.centerLat, m.centerLon);
      final r = max(pr.px(m.radiusM, m.centerLat), m.isRoad ? 12.0 : 0.0);
      final acc = m.status == 'accepted';
      final col = acc ? s.accent : const Color(0xFFF59E0B);
      canvas.drawCircle(o, r, Paint()..color = col.withValues(alpha: acc ? 0.10 : 0.06));
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = col.withValues(alpha: 0.9);
      if (acc) {
        canvas.drawCircle(o, r, ring);
      } else {
        final rect = Rect.fromCircle(center: o, radius: r);
        const n = 36;
        for (var i = 0; i < n; i++) {
          canvas.drawArc(rect, i * 2 * pi / n, pi / n, false, ring);
        }
      }
      _text(canvas, '${m.confirmedCount}/${m.requiredCount}', o,
          size: 12, color: Color.lerp(col, Colors.black, 0.35)!, shadow: false);
    }
  }

  // -------------------------------------------------------------- flux du vent
  void _flow(Canvas canvas, _Proj pr, Rect clip) {
    final sim = s.sim;
    if (!sim.hasSources) return;
    final t = sim.elapsed;

    final ripple = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    var count = 0;
    for (var i = 0; i < sim.sources.length && count < 24; i++) {
      final src = sim.sources[i];
      final c0 = pr.at(src.lat, src.lon);
      if (!clip.contains(c0)) continue;
      count++;
      final w = sim.windAt(src.lat, src.lon);
      final speed = sqrt(w.$1 * w.$1 + w.$2 * w.$2);
      final ang = speed < 0.05 ? 0.0 : atan2(-w.$2, w.$1);
      final r0 = max(6.0, pr.px(src.rM, src.lat) * 0.55);
      final stretch = 1 + min(speed / 5.0, 1.6);
      final lvl = ((src.db - 45) / 45).clamp(0.25, 1.0).toDouble();
      for (var k = 0; k < 2; k++) {
        final ph = (t * 0.30 + i * 0.173 + k * 0.5) % 1.0;
        final shift = pr.px(speed * _FlowSim.timeLapse * 2.2 * ph, src.lat);
        final ctr = c0 + Offset(cos(ang), sin(ang)) * shift;
        final a = r0 * (1 + 2.2 * ph) * stretch;
        final b = r0 * (1 + 1.8 * ph);
        ripple.color = noiseBandColor(max(src.db, 62), glow: s.dark).withValues(alpha: (1 - ph) * 0.6 * lvl);
        canvas.save();
        canvas.translate(ctr.dx, ctr.dy);
        canvas.rotate(ang);
        canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: a * 2, height: b * 2), ripple);
        canvas.restore();
      }
    }

    sim.advance();
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final dot = Paint()..style = PaintingStyle.fill;
    const trail = _FlowSim.timeLapse * 0.55;
    for (final p in sim.ps) {
      if (!p.alive) continue;
      final pos = pr.at(p.lat, p.lon);
      if (!clip.contains(pos)) continue;
      final f = (p.age / p.life).clamp(0.0, 1.0).toDouble();
      final a = sin(pi * f) * 0.85;
      if (a <= 0.02) continue;
      final col = noiseBandColor(max(p.db - 8 * f, 66), glow: s.dark).withValues(alpha: a);
      final tail = Offset(pr.px(p.u * trail, p.lat), -pr.px(p.v * trail, p.lat));
      line
        ..color = col
        ..strokeWidth = 1.2 + 2.0 * (1 - f);
      canvas.drawLine(pos - tail, pos, line);
      dot.color = col;
      canvas.drawCircle(pos, 1.3 + 1.6 * (1 - f), dot);
    }
  }

  // -------------------------------------------------------------- itinéraire
  void _route(Canvas canvas, _Proj pr) {
    final pts = s.route;
    if (pts == null || pts.length < 2) return;
    final path = Path();
    for (var i = 0; i < pts.length; i++) {
      final o = pr.at(pts[i].latitude, pts[i].longitude);
      if (i == 0) {
        path.moveTo(o.dx, o.dy);
      } else {
        path.lineTo(o.dx, o.dy);
      }
    }
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, base..strokeWidth = 9..color = Colors.white);
    canvas.drawPath(path, base..strokeWidth = 5..color = s.accent);
  }

  void _me(Canvas canvas, _Proj pr) {
    final me = s.me;
    if (me == null) return;
    final o = pr.at(me.latitude, me.longitude);
    final t = (s.sim.elapsed % 2.4) / 2.4;
    canvas.drawCircle(o, 10 + 36 * t, Paint()..color = s.accent.withValues(alpha: 0.35 * (1 - t)));
    canvas.drawCircle(o, 9, Paint()..color = Colors.white);
    canvas.drawCircle(o, 6.5, Paint()..color = s.accent);
  }
}

// ============================================================================
// Écran
// ============================================================================
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with SingleTickerProviderStateMixin {
  static const int _gridCols = 5, _gridRows = 5;

  final MapController _map = MapController();
  late final AnimationController _clock =
      AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();
  final _FlowSim _sim = _FlowSim();
  late final MapViewModel _vm;

  StreamSubscription<Position>? _posSub;
  Timer? _debounce;
  Timer? _windTimer;
  Timer? _fieldTimer;

  LatLng? _me;
  bool _ready = false;
  bool _centered = false;

  bool _showNoise = true;
  bool _showFlow = true;
  bool _darkBase = false;
  _NoiseMode _mode = _NoiseMode.cloud;
  _Veil _veil = _Veil.none;
  bool _showRoads = true;
  MissionRoute? _mRoute;

  // nuage de bruit du serveur
  FieldGrid? _fieldGrid;
  FieldGrid? _fieldPrev;
  double _fieldSwapAt = -10;
  bool _fieldBusy = false;
  String? _fieldError;

  // météo (voiles)
  List<WeatherPoint> _weather = const [];
  _WxField? _wxField;
  LatLngBounds? _windArea;
  DateTime? _windAt;
  DateTime? _windTry;
  bool _windBusy = false;
  bool _windFailed = false;

  OsrmRoute? _route;

  List<NoiseCell>? _cellsKey;
  List<NoiseCell> _sorted = const [];
  int _seenVersion = -1;

  // historique animé
  bool _tlOpen = false;
  Timelapse? _tl;
  bool _tlPlaying = true;
  bool _tlLoading = false;
  double _tlSpeed = 1;
  String _tlStep = 'day';
  String? _tlError;
  int _tlFrame = -1;
  DateTime _tlLast = DateTime.now();
  final ValueNotifier<double> _tlPos = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    _vm = context.read<MapViewModel>();
    _vm.startAuto();
    _initLocation();
    _clock.addListener(_tlTick);
    _windTimer = Timer.periodic(const Duration(minutes: 10), (_) => _loadWind(force: true));
    _fieldTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _loadField();
      _reloadRoads();
    });
    //_fieldTimer = Timer.periodic(const Duration(seconds: 30), (_) => _loadField());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _windTimer?.cancel();
    _fieldTimer?.cancel();
    _posSub?.cancel();
    _clock.removeListener(_tlTick);
    _clock.dispose();
    _tlPos.dispose();
    _vm.stopAuto();
    super.dispose();
  }
  void _reloadRoads() {
    if (!_ready || !mounted || !_showRoads) return;
    context.read<RoadsViewModel>().load(_vm.filters, _bbox(), _map.camera.zoom);
  }

  // ------------------------------------------------------------------ position
  Future<void> _initLocation() async {
    if (!await ensureLocationPermission()) return;
    try {
      final p = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      _setMe(p, recenter: true);
    } catch (_) {}
    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 8),
    ).listen((p) => _setMe(p), onError: (_) {});
  }

  void _setMe(Position p, {bool recenter = false}) {
    if (!mounted) return;
    setState(() => _me = LatLng(p.latitude, p.longitude));
    if ((recenter || !_centered) && _ready) {
      _centered = true;
      _map.move(_me!, 15);
      Future.delayed(const Duration(milliseconds: 350), _reload);
    }
  }

  // ------------------------------------------------------------------ données (source de vérité : serveur)
  String _bbox() {
    final b = _map.camera.visibleBounds;
    final dLat = (b.north - b.south) * 0.25;
    final dLon = (b.east - b.west) * 0.25;
    double cl(double v, double lo, double hi) => v.clamp(lo, hi).toDouble();
    return '${cl(b.west - dLon, -179.9, 179.9)},${cl(b.south - dLat, -89.9, 89.9)},'
        '${cl(b.east + dLon, -179.9, 179.9)},${cl(b.north + dLat, -89.9, 89.9)}';
  }

  void _reload() {
    if (!_ready || !mounted) return;
    _vm.load(bbox: _bbox());
    _loadField();
    _loadWind();
    _reloadRoads();
  }

  void _scheduleReload() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _reload);
  }

  void _onReady() {
    _ready = true;
    if (_me != null) {
      _centered = true;
      _map.move(_me!, 15);
    }
    _reload();
  }

  Future<void> _loadField() async {
    if (!_ready || !mounted || _fieldBusy || !_showNoise || _tlOpen || _mode != _NoiseMode.cloud) return;
    _fieldBusy = true;
    try {
      final g = await context.read<ApiClient>().fieldGrid(_vm.filters, _bbox());
      if (!mounted) return;
      setState(() {
        _fieldPrev = _fieldGrid;
        _fieldGrid = g;
        _fieldSwapAt = _sim.elapsed;
        _fieldError = null;
      });
      final w = g.wind;
      if (w != null) {
        final c = _map.camera.center;
        _sim.setUniform(c.latitude, c.longitude, w.u, w.v);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _fieldError = e.code);
    } finally {
      _fieldBusy = false;
    }
  }

  Future<void> _loadWind({bool force = false}) async {
    if (!_ready || !mounted || _windBusy) return;
    if (_veil == _Veil.none && !(_showFlow && _fieldGrid?.wind == null)) return;
    final b = _map.camera.visibleBounds;
    final a = _windArea;
    final covered =
        a != null && b.south >= a.south && b.north <= a.north && b.west >= a.west && b.east <= a.east;
    final fresh = _windAt != null && DateTime.now().difference(_windAt!) < const Duration(minutes: 10);
    if (!force && covered && fresh) return;
    if (!force && _windTry != null && DateTime.now().difference(_windTry!) < const Duration(seconds: 30)) {
      return;
    }
    _windTry = DateTime.now();
    _windBusy = true;
    double lo(double v) => (v / 0.1).floor() * 0.1;
    double hi(double v) => (v / 0.1).ceil() * 0.1;
    final wide = LatLngBounds(
      LatLng((lo(b.south) - 0.1).clamp(-89.9, 89.9).toDouble(),
          (lo(b.west) - 0.1).clamp(-179.9, 179.9).toDouble()),
      LatLng((hi(b.north) + 0.1).clamp(-89.9, 89.9).toDouble(),
          (hi(b.east) + 0.1).clamp(-179.9, 179.9).toDouble()),
    );
    try {
      final pts = await LiveWeatherService.fetchGrid(wide,
          cols: _gridCols, rows: _gridRows, soil: _veil == _Veil.soil);
      if (!mounted) return;
      if (pts.isNotEmpty) {
        if (_fieldGrid?.wind == null) _sim.setWind(pts);
        setState(() {
          _weather = pts;
          _wxField = _WxField(pts, wide, _gridCols, _gridRows);
          _windArea = wide;
          _windAt = DateTime.now();
          _windFailed = false;
        });
      } else {
        setState(() => _windFailed = true);
      }
    } finally {
      _windBusy = false;
    }
  }

  // ------------------------------------------------------------------ historique animé
  void _tlTick() {
    final now = DateTime.now();
    final dt = now.difference(_tlLast).inMicroseconds / 1e6;
    _tlLast = now;
    final tl = _tl;
    if (tl == null || !_tlPlaying || tl.frameCount < 2) return;
    var p = _tlPos.value + min(dt, 0.1) * 1.5 * _tlSpeed;
    if (p >= tl.frameCount - 1) p = 0;
    _tlSet(p);
  }

  void _tlSet(double p) {
    _tlPos.value = p;
    final f = p.round();
    final tl = _tl;
    if (tl != null && f != _tlFrame) {
      _tlFrame = f;
      _sim.setCells(tl.cellsAt(f.toDouble()));
    }
  }

  Future<void> _openTimelapse([String? step]) async {
    if (!_ready) return;
    if (step != null) _tlStep = step;
    setState(() {
      _tlOpen = true;
      _tlLoading = true;
      _tlError = null;
    });
    try {
      var f = _vm.filters;
      if (f.period == 'today') f = f.copyWith(period: '7d');
      final tl = await context.read<ApiClient>().timelapse(f, step: _tlStep, bbox: _bbox());
      if (!mounted) return;
      _tlFrame = -1;
      _tlPlaying = true;
      _tlLast = DateTime.now();
      setState(() {
        _tl = tl;
        _tlLoading = false;
      });
      _tlSet(0);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _tlLoading = false;
        _tlError = errorMessage(e);
      });
    }
  }

  void _closeTimelapse() {
    setState(() {
      _tlOpen = false;
      _tl = null;
      _tlError = null;
      _tlLoading = false;
    });
    _sim.setCells(_vm.cells);
    _loadField();
  }

  // ------------------------------------------------------------------ interactions
  void _onTap(LatLng p) {
    if (_tlOpen) return;
    if (_showNoise) {
      final c = _vm.cellAt(p);
      if (c != null) {
        _vm.select(c.h3);
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
          builder: (_) => CellSheet(
            cell: c,
            filters: _vm.filters,
            store: context.read<SessionController>().store,
          ),
        ).whenComplete(() => _vm.select(null));
        return;
      }
    }
    if (_showRoads) {
      final rv = context.read<RoadsViewModel>();
      final seg = rv.hit(p, _map.camera.zoom);
      if (seg != null) {
        rv.select(seg.id);
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
          builder: (_) => RoadSheet(seg: seg, state: rv.states[seg.id], filters: _vm.filters),
        ).whenComplete(() => rv.select(null));
        return;
      }
    }
    for (final m in context.read<MissionsController>().list) {
      if (!m.isActive) continue;
      if (const Distance().as(LengthUnit.Meter, p, LatLng(m.centerLat, m.centerLon)) <= max(m.radiusM, 60.0)) {
        _openMissions();
        return;
      }
    }
    _vm.select(null);
  }

  Future<void> _openMissions() async {
    final r = await Navigator.of(context)
        .push<MissionFocus>(MaterialPageRoute(builder: (_) => const MissionsScreen()));
    if (r == null || !mounted || !_ready) return;
    final m = r.mission;
    final target = LatLng(m.centerLat, m.centerLon);
    if (!r.route) {
      setState(() => _mRoute = null);
      _map.move(target, m.isRoad ? 16 : 14);
      _reload();
      return;
    }
    await _routeToMission(m);
  }

  /// Trace le chemin réel par les routes jusqu'au point cible (TomTom via le serveur, OSRM en secours).
  Future<void> _routeToMission(Mission m) async {
    final target = LatLng(m.centerLat, m.centerLon);
    if (_me == null) {
      _map.move(target, 16);
      showToast(context, apiErrorLabel('gps_unavailable'));
      return;
    }
    final api = context.read<ApiClient>();
    MissionRoute? mr;
    try {
      mr = await api.missionRoute(m.id, _me!.latitude, _me!.longitude);
    } catch (_) {
      try {
        final o = await api.getOsrmRoute(_me!, target);
        mr = MissionRoute(
            missionId: m.id,
            target: MissionTarget(lat: m.centerLat, lon: m.centerLon, radiusM: m.radiusM, roadName: m.roadName, roadClass: m.roadClass, dayPart: m.targetDayPart),
            points: o.points,
            lengthM: o.distanceM.round(),
            timeS: o.durationS.round());
      } catch (e) {
        if (!mounted) return;
        _map.move(target, 16);
        showToast(context, errorMessage(e));
        return;
      }
    }
    if (!mounted) return;
    final t = trimRoute(mr.points, target, m.radiusM);
    final trimmed = MissionRoute(
        missionId: mr.missionId,
        target: mr.target,
        points: t.points,
        lengthM: (mr.lengthM * t.ratio).round(),
        timeS: (mr.timeS * t.ratio).round());
    setState(() {
      _mRoute = trimmed;
      _route = null;
    });
    _map.fitCamera(CameraFit.bounds(
      bounds: LatLngBounds.fromPoints([...trimmed.points, target]),
      padding: const EdgeInsets.fromLTRB(40, 170, 40, 200),
    ));
    _reload();
  }

  Future<void> _openSearch() async {
    final r = await showModalBottomSheet<(PlaceResult, bool)>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SearchSheet(near: _me ?? _map.camera.center),
    );
    if (r == null || !mounted) return;
    final (p, go) = r;
    final dest = LatLng(p.lat, p.lon);

    if (!go) {
      _map.move(dest, 16);
      _reload();
      return;
    }
    if (_me == null) {
      _map.move(dest, 16);
      showToast(context, apiErrorLabel('gps_unavailable'));
      return;
    }
    try {
      final route = await context.read<ApiClient>().getOsrmRoute(_me!, dest);
      if (!mounted) return;
      setState(() => _route = route);
      _map.fitCamera(CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(route.points),
        padding: const EdgeInsets.fromLTRB(40, 150, 40, 180),
      ));
      _reload();
    } catch (e) {
      if (!mounted) return;
      _map.move(dest, 16);
      showToast(context, errorMessage(e));
    }
  }

  // ------------------------------------------------------------------ feuilles
  void _showLayersSheet() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(builder: (ctx, setM) {
        void both(VoidCallback f) {
          setState(f);
          setM(() {});
        }

        const veilLabels = {
          _Veil.none: 'Aucun',
          _Veil.temp: 'Température',
          _Veil.rain: 'Pluie',
          _Veil.cloud: 'Nuages',
          _Veil.soil: 'Sol',
        };

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Couches de la carte', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              const SizedBox(height: 4),
              Text('La carte du bruit est calculée par le serveur : identique pour tous les utilisateurs.',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.graphic_eq_rounded),
                title: const Text('Bruit'),
                value: _showNoise,
                onChanged: (v) {
                  both(() => _showNoise = v);
                  if (v) _loadField();
                },
              ),
              if (_showNoise)
                SegmentedButton<_NoiseMode>(
                  segments: const [
                    ButtonSegment(value: _NoiseMode.cloud, label: Text('Nuage'), icon: Icon(Icons.cloud_rounded)),
                    ButtonSegment(value: _NoiseMode.grid, label: Text('Grille'), icon: Icon(Icons.hexagon_outlined)),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (v) {
                    both(() => _mode = v.first);
                    _loadField();
                  },
                  showSelectedIcon: false,
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.air_rounded),
                title: const Text('Flux du vent animé'),
                subtitle: const Text('Propagation indicative du bruit selon le vent'),
                value: _showFlow,
                onChanged: (v) {
                  both(() => _showFlow = v);
                  if (v) _loadWind(force: true);
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.add_road_rounded),
                title: const Text('Routes (tracé réel)'),
                subtitle: const Text('Vert = pas encore mesuré · zoomez pour voir les petites rues'),
                value: _showRoads,
                onChanged: (v) {
                  both(() => _showRoads = v);
                  if (v) _reloadRoads();
                },
              ),
              const SizedBox(height: 8),
              const Text('Voile météo', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final v in _Veil.values)
                  ChoiceChip(
                    label: Text(veilLabels[v]!),
                    selected: _veil == v,
                    onSelected: (_) {
                      both(() => _veil = v);
                      if (v != _Veil.none) _loadWind(force: true);
                    },
                  ),
              ]),
              const SizedBox(height: 16),
              const Text('Fond de carte', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 8),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Clair'), icon: Icon(Icons.light_mode_rounded)),
                  ButtonSegment(value: true, label: Text('Sombre'), icon: Icon(Icons.dark_mode_rounded)),
                ],
                selected: {_darkBase},
                onSelectionChanged: (v) => both(() => _darkBase = v.first),
                showSelectedIcon: false,
              ),
            ]),
          ),
        );
      }),
    );
  }

  void _showFiltersSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FiltersSheet(
        initial: _vm.filters,
        onApply: (f) {
          _vm.setFilters(f);
          Future.delayed(const Duration(milliseconds: 200), _loadField);
          Future.delayed(const Duration(milliseconds: 250), _reloadRoads);
        },
      ),
    );
  }

  WeatherPoint? _nearestWeather() {
    if (_weather.isEmpty || !_ready) return null;
    final c = _map.camera.center;
    WeatherPoint? best;
    var bd = double.infinity;
    for (final w in _weather) {
      final dx = w.pos.latitude - c.latitude;
      final dy = w.pos.longitude - c.longitude;
      final d = dx * dx + dy * dy;
      if (d < bd) {
        bd = d;
        best = w;
      }
    }
    return best;
  }
  // ------------------------------------------------------------------ build
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cells = context.select<MapViewModel, List<NoiseCell>>((v) => v.cells);
    final selected = context.select<MapViewModel, String?>((v) => v.selected);
    final loading = context.select<MapViewModel, bool>((v) => v.loading);
    final error = context.select<MapViewModel, String?>((v) => v.error);
    final version = context.select<RecorderController, int>((r) => r.completedVersion);
    final proposalCount = context.select<ProposalsController, int>((p) => p.list.length);
    final missions = context.select<MissionsController, List<Mission>>((c) => c.list);
    final offeredCount = context.select<MissionsController, int>((c) => c.offeredCount);
    final quota = context.select<QuotaController, QuotaState?>((c) => c.state);

    final roadSegs = context.select<RoadsViewModel, List<RoadSeg>>((v) => v.segs);
    final roadStates = context.select<RoadsViewModel, Map<String, RoadState>>((v) => v.states);
    final roadSel = context.select<RoadsViewModel, String?>((v) => v.selected);

    if (version != _seenVersion) {
      _seenVersion = version;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<QuotaController>().refresh();
        context.read<MissionsController>().refresh(sync: false);
      });
    }
    if (!identical(_cellsKey, cells)) {
      _cellsKey = cells;
      _sorted = [...cells]..sort((a, b) => a.laeq.compareTo(b.laeq));
      if (!_tlOpen) _sim.setCells(cells);
    }

    final scene = _Scene(
      clock: _clock,
      sim: _sim,
      cells: _sorted,
      selected: selected,
      mode: _mode,
      showNoise: _showNoise,
      showFlow: _showFlow,
      dark: _darkBase,
      field: _fieldGrid,
      fieldPrev: _fieldPrev,
      fieldSwapAt: _fieldSwapAt,
      veil: _veil,
      wxField: _wxField,
      tl: _tl,
      tlPos: _tlPos,
      missions: missions,
      me: _me,
      accent: cs.primary,
      roads: roadSegs,
      roadStates: roadStates,
      showRoads: _showRoads,
      selectedRoad: roadSel,
      mTarget: _mRoute?.target,
      route: _mRoute?.points ?? _route?.points,
    );

    final badge = proposalCount + offeredCount;
    final near = (_showFlow && _sim.hasWind) ? _nearestWeather() : null;
    double? veilNow;
    if (_veil != _Veil.none && _wxField != null && _ready) {
      final c = _map.camera.center;
      veilNow = _wxField!.at(c.latitude, c.longitude, _pick(_veil));
    }
    final bottomShift = _tlOpen ? 250.0 : 30.0;

    return Scaffold(
      body: Stack(children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: AppConfig.fallbackCenter,
            initialZoom: 13,
            minZoom: 3,
            maxZoom: 19,
            backgroundColor: _darkBase ? const Color(0xFF0B1116) : const Color(0xFFEFF3F5),
            interactionOptions:
                const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
            onMapReady: _onReady,
            onTap: (_, p) => _onTap(p),
            onPositionChanged: (cam, gesture) {
              if (gesture) _scheduleReload();
            },
          ),
          children: [
            TileLayer(
              urlTemplate: _darkBase ? AppConfig.tileDark : AppConfig.tileLight,
              subdomains: const ['a', 'b', 'c', 'd'],
              userAgentPackageName: AppConfig.packageName,
              maxNativeZoom: 19,
              panBuffer: 2,
            ),
            _FlowLayer(scene: scene),
          ],
        ),

        // ---------------------------------------------------------------- barre du haut
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(children: [
              SoftCard(
                glass: true,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(children: [
                  const SunuLogo(size: 24),
                  const SizedBox(width: 8),
                  const Text('SunuSound', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  const SizedBox(width: 8),
                  _LiveDot(clock: _clock),
                ]),
              ),
              if (quota != null) ...[
                const SizedBox(width: 8),
                SoftCard(
                  glass: true,
                  onTap: _openMissions,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.bolt_rounded, size: 18, color: quota.balance < 1 ? const Color(0xFFEF4444) : cs.primary),
                    const SizedBox(width: 2),
                    Text(quota.balance.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.w800)),
                  ]),
                ),
              ],
              const Spacer(),
              FloatingActionButton.small(
                heroTag: 'search',
                onPressed: _openSearch,
                child: const Icon(Icons.search_rounded),
              ),
              const SizedBox(width: 8),
              FloatingActionButton.small(
                heroTag: 'missions',
                onPressed: _openMissions,
                child: Badge(
                  isLabelVisible: badge > 0,
                  label: Text('$badge'),
                  child: const Icon(Icons.notifications_none_rounded),
                ),
              ),
            ]),
          ),
        ),

        // ---------------------------------------------------------------- infos sous la barre
        Positioned(
          top: MediaQuery.of(context).padding.top + 64,
          left: 16,
          right: 16,
          child: Column(children: [
            if (loading)
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: const LinearProgressIndicator(minHeight: 3),
              ),
            if (_route != null)
              SoftCard(
                glass: true,
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                child: Row(children: [
                  Icon(Icons.directions_car_rounded, color: cs.primary, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(
                        '${(_route!.durationS / 60).round()} min · ${(_route!.distanceM / 1000).toStringAsFixed(1)} km',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                      const Text('Itinéraire le plus rapide', style: TextStyle(fontSize: 12)),
                    ]),
                  ),
                  IconButton(
                    onPressed: () => setState(() => _route = null),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ]),
              ),

            if (_mRoute != null)
              SoftCard(
                glass: true,
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                child: Row(children: [
                  Icon(Icons.flag_rounded, color: cs.primary, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(
                          _mRoute!.target.roadName != null
                              ? 'Mission : ${_mRoute!.target.roadName}'
                              : 'Mission : point cible',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      Text(
                          '${(_mRoute!.timeS / 60).round()} min · ${(_mRoute!.lengthM / 1000).toStringAsFixed(1)} km par la route'
                          '${_mRoute!.target.dayPart != null ? ' · mesurer en ${dayPartLabel(_mRoute!.target.dayPart!).toLowerCase()}' : ''}',
                          style: const TextStyle(fontSize: 12)),
                    ]),
                  ),
                  IconButton(onPressed: () => setState(() => _mRoute = null), icon: const Icon(Icons.close_rounded)),
                ]),
              ),


            if (error != null)
              SoftCard(
                glass: true,
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(children: [
                  Icon(Icons.cloud_off_rounded, color: cs.error, size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Text(apiErrorLabel(error), style: TextStyle(color: cs.error, fontSize: 13))),
                ]),
              ),
            if (_showNoise && !_tlOpen && _mode == _NoiseMode.cloud && _fieldError == 'bbox_too_large')
              SoftCard(
                glass: true,
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(children: [
                  Icon(Icons.zoom_in_rounded, color: cs.primary, size: 20),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('Zoomez pour afficher le nuage de bruit (cellules affichées en attendant).',
                        style: TextStyle(fontSize: 13)),
                  ),
                ]),
              ),
            if (!loading && error == null && _showNoise && !_tlOpen && cells.isEmpty)
              SoftCard(
                glass: true,
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(children: [
                  Icon(Icons.info_outline_rounded, color: cs.primary, size: 20),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('Aucune mesure validée dans cette zone pour la période choisie.',
                        style: TextStyle(fontSize: 13)),
                  ),
                ]),
              ),
          ]),
        ),

        // ---------------------------------------------------------------- cartes en bas à gauche
        Positioned(
          left: 16,
          bottom: bottomShift,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            spacing: 8,
            children: [
              if (near != null) _windCard(cs, near),
              if (_showFlow && !_sim.hasWind && _windFailed)
                const SoftCard(
                  glass: true,
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text('Vent indisponible : ondes sans direction', style: TextStyle(fontSize: 12)),
                ),
              if (_veil != _Veil.none) _veilCard(cs, veilNow),
              if (_showNoise) _noiseLegend(cs),
            ],
          ),
        ),

        // ---------------------------------------------------------------- lecteur d'historique
        if (_tlOpen) Positioned(left: 16, right: 16, bottom: 84, child: _timelapseBar(cs)),

        // ---------------------------------------------------------------- boutons
        Positioned(
          right: 16,
          bottom: bottomShift,
          child: Column(children: [
            FloatingActionButton.small(
              heroTag: 'layers',
              onPressed: _showLayersSheet,
              child: const Icon(Icons.layers_rounded),
            ),
            const SizedBox(height: 10),
            FloatingActionButton.small(
              heroTag: 'filters',
              onPressed: _showFiltersSheet,
              child: const Icon(Icons.tune_rounded),
            ),
            const SizedBox(height: 10),
            FloatingActionButton.small(
              heroTag: 'history',
              onPressed: _tlOpen ? _closeTimelapse : () => _openTimelapse(),
              child: Icon(_tlOpen ? Icons.history_toggle_off_rounded : Icons.history_rounded),
            ),
            const SizedBox(height: 10),
            FloatingActionButton.small(
              heroTag: 'locate',
              onPressed: () async {
                if (_me == null) {
                  await _initLocation();
                } else if (_ready) {
                  _map.move(_me!, 16);
                  _reload();
                }
              },
              child: const Icon(Icons.my_location_rounded),
            ),
          ]),
        ),
      ]),
    );
  }

  // ------------------------------------------------------------------ widgets annexes
  Widget _windCard(ColorScheme cs, WeatherPoint near) {
    return SoftCard(
      glass: true,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Transform.rotate(
            angle: _sim.bearingTo * pi / 180,
            child: Icon(Icons.navigation_rounded, color: windColor(_sim.meanSpeedMs * 3.6), size: 24),
          ),
          const SizedBox(width: 8),
          Text('${(_sim.meanSpeedMs * 3.6).round()} km/h',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        ]),
        Text('${compass((_sim.bearingTo + 180) % 360)} → ${compass(_sim.bearingTo)}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        Text('${near.temp.round()}°C · ${weatherLabel(near.code)}', style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 2),
        Text('Flux indicatif · animation accélérée',
            style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant)),
      ]),
    );
  }

  Widget _veilCard(ColorScheme cs, double? value) {
    final info = _veilInfo(_veil);
    final soilMissing = _veil == _Veil.soil && _weather.isNotEmpty && _weather.first.soil == null;
    return SoftCard(
      glass: true,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Text(info.title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
          if (value != null) ...[
            const SizedBox(width: 8),
            Text(_veilValue(_veil, value), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          ],
        ]),
        const SizedBox(height: 4),
        Container(
          width: 130,
          height: 8,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            gradient: LinearGradient(colors: info.colors),
          ),
        ),
        const SizedBox(height: 2),
        SizedBox(
          width: 130,
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(info.lo, style: const TextStyle(fontSize: 9)),
            Text(info.hi, style: const TextStyle(fontSize: 9)),
          ]),
        ),
        if (soilMissing)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('Donnée sol indisponible', style: TextStyle(fontSize: 9, color: cs.error)),
          ),
      ]),
    );
  }

  Widget _noiseLegend(ColorScheme cs) {
    return SoftCard(
      glass: true,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        const Text('Niveau sonore dB(A)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: SizedBox(
            width: 140,
            height: 9,
            child: _darkBase
                ? DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        for (final v in const [35, 50, 60, 70, 80, 90, 100]) noiseHeat(v.toDouble(), glow: true)
                      ]),
                    ),
                  )
                : Row(children: [for (final c in _bandColors) Expanded(child: ColoredBox(color: c, child: const SizedBox.expand()))]),
          ),
        ),
        const SizedBox(height: 2),
        const SizedBox(
          width: 140,
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('<40', style: TextStyle(fontSize: 9)),
            Text('60', style: TextStyle(fontSize: 9)),
            Text('80+', style: TextStyle(fontSize: 9)),
          ]),
        ),
        const SizedBox(height: 2),
        if (_showRoads)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 18, height: 3, decoration: BoxDecoration(color: const Color(0xFF22C55E), borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 6),
              const Text('Routes · vert = non mesuré', style: TextStyle(fontSize: 9)),
            ]),
          ),
        Text(_darkBase ? 'Plus clair = plus bruyant' : 'Plus foncé = plus bruyant',
            style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant)),
      ]),
    );
  }

  Widget _timelapseBar(ColorScheme cs) {
    final tl = _tl;
    final hasFrames = tl != null && tl.frameCount > 0;
    return SoftCard(
      glass: true,
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.history_rounded, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: ValueListenableBuilder<double>(
              valueListenable: _tlPos,
              builder: (_, p, __) {
                final label = hasFrames ? tl.labels[p.round().clamp(0, tl.frameCount - 1)] : 'Historique';
                return Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15));
              },
            ),
          ),
          ChoiceChip(
            label: const Text('Jour'),
            selected: _tlStep == 'day',
            onSelected: (_) {
              if (_tlStep != 'day') _openTimelapse('day');
            },
          ),
          const SizedBox(width: 6),
          ChoiceChip(
            label: const Text('Plage'),
            selected: _tlStep == 'daypart',
            onSelected: (_) {
              if (_tlStep != 'daypart') _openTimelapse('daypart');
            },
          ),
          IconButton(onPressed: _closeTimelapse, icon: const Icon(Icons.close_rounded)),
        ]),
        if (_tlLoading)
          const Padding(
            padding: EdgeInsets.only(top: 6, right: 6),
            child: LinearProgressIndicator(minHeight: 3),
          )
        else if (_tlError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 6),
            child: Text(_tlError!, style: TextStyle(color: cs.error, fontSize: 13)),
          )
        else if (!hasFrames)
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 6),
            child: Text('Aucune donnée sur cette période et cette zone.',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
          )
        else ...[
          if (tl.frameCount >= 2)
            ValueListenableBuilder<double>(
              valueListenable: _tlPos,
              builder: (_, p, __) => Slider(
                value: p.clamp(0.0, tl.frameCount - 1.0).toDouble(),
                min: 0,
                max: tl.frameCount - 1.0,
                onChanged: _tlSet,
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Row(children: [
              IconButton.filledTonal(
                onPressed: () => setState(() => _tlPlaying = !_tlPlaying),
                icon: Icon(_tlPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
              ),
              const SizedBox(width: 8),
              SegmentedButton<double>(
                segments: const [
                  ButtonSegment(value: 1.0, label: Text('×1')),
                  ButtonSegment(value: 2.0, label: Text('×2')),
                  ButtonSegment(value: 4.0, label: Text('×4')),
                ],
                selected: {_tlSpeed},
                onSelectionChanged: (v) => setState(() => _tlSpeed = v.first),
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
              ),
              const Spacer(),
              if (tl.minDb != null && tl.maxDb != null)
                Text('${tl.minDb!.toStringAsFixed(0)}–${tl.maxDb!.toStringAsFixed(0)} dB(A)',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
            ]),
          ),
        ],
      ]),
    );
  }
}

class _LiveDot extends StatelessWidget {
  const _LiveDot({required this.clock});
  final Animation<double> clock;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: clock,
        builder: (_, __) {
          final a = 0.4 + 0.6 * (0.5 - 0.5 * cos(2 * pi * clock.value));
          return Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: const Color(0xFF22C55E).withValues(alpha: a),
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: const Color(0xFF22C55E).withValues(alpha: a * 0.6), blurRadius: 4)],
            ),
          );
        },
      );
}

class _FiltersSheet extends StatefulWidget {
  const _FiltersSheet({required this.initial, required this.onApply});
  final MapFilters initial;
  final Function(MapFilters) onApply;

  @override
  State<_FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends State<_FiltersSheet> {
  late MapFilters f = widget.initial;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Filtres de la carte',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          const Text('Période', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            for (final p in const [('today', "Aujourd'hui"), ('7d', '7 jours'), ('30d', '30 jours')])
              ChoiceChip(
                label: Text(p.$2),
                selected: f.period == p.$1,
                onSelected: (_) => setState(() => f = f.copyWith(period: p.$1)),
              ),
          ]),
          const SizedBox(height: 16),
          const Text('Plage horaire', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            for (final d in const ['all', 'morning', 'afternoon', 'evening', 'night'])
              ChoiceChip(
                label: Text(dayPartLabel(d)),
                selected: f.dayPart == d,
                onSelected: (_) => setState(() => f = f.copyWith(dayPart: d)),
              ),
          ]),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Inclure les mesures indicatives'),
            value: f.includeIndicative,
            onChanged: (v) => setState(() => f = f.copyWith(includeIndicative: v)),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () {
              widget.onApply(f);
              Navigator.pop(context);
            },
            child: const Text('Appliquer'),
          ),
        ]),
      ),
    );
  }
}