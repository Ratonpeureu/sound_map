import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/api_survey.dart';
import '../core/config.dart';
import '../core/models_survey.dart';
import '../core/util.dart';
import '../state/session_controller.dart';
import 'data_cell_sheet.dart';
import 'widgets.dart';

// ============================================================================ styles de rendu
enum DataStyle { auto, zones, relief, batons, vagues, chaleur, marqueurs }

extension DataStyleX on DataStyle {
  String get label => switch (this) {
        DataStyle.auto => 'Auto',
        DataStyle.zones => 'Zones',
        DataStyle.relief => 'Relief 3D',
        DataStyle.batons => 'Bâtons',
        DataStyle.vagues => 'Vagues',
        DataStyle.chaleur => 'Chaleur',
        DataStyle.marqueurs => 'Marqueurs',
      };
  IconData get icon => switch (this) {
        DataStyle.auto => Icons.auto_awesome_rounded,
        DataStyle.zones => Icons.hexagon_outlined,
        DataStyle.relief => Icons.view_in_ar_rounded,
        DataStyle.batons => Icons.bar_chart_rounded,
        DataStyle.vagues => Icons.waves_rounded,
        DataStyle.chaleur => Icons.local_fire_department_rounded,
        DataStyle.marqueurs => Icons.place_rounded,
      };
}

DataStyle resolveStyle(DataStyle s, DataMap d) {
  if (s != DataStyle.auto) return s;
  if (d.isCategoryTop) return DataStyle.zones;
  return switch (d.viz) {
    'bars' => DataStyle.relief,
    'markers' => DataStyle.marqueurs,
    'heat' => DataStyle.chaleur,
    _ => DataStyle.zones,
  };
}

String metricLabel(String m, DataIndicator? ind) {
  switch (m) {
    case 'mean':
      return 'Moyenne';
    case 'sum':
      return 'Total déclaré';
    case 'share':
      return 'Part';
    case 'top':
      return 'Dominante';
    case 'ratio':
      return 'Ratio';
  }
  if (m.startsWith('cat:')) {
    final code = m.substring(4);
    if (ind != null) {
      for (final c in ind.categories) {
        if (c.code == code) return c.label;
      }
    }
    return code;
  }
  return m;
}

// ============================================================================ couleurs
Color dataColor(double t, {required int polarity, required Color base, required bool dark, bool heat = false}) {
  final tt = t.clamp(0.0, 1.0).toDouble();
  final List<Color> cols;
  if (polarity > 0) {
    cols = const [Color(0xFFEF4444), Color(0xFFFACC15), Color(0xFF22C55E)];
  } else if (polarity < 0) {
    cols = const [Color(0xFF22C55E), Color(0xFFFACC15), Color(0xFFEF4444)];
  } else if (heat) {
    cols = const [Color(0xFF38BDF8), Color(0xFFFACC15), Color(0xFFF97316), Color(0xFFDC2626), Color(0xFF7F1D1D)];
  } else if (dark) {
    cols = [Color.lerp(base, Colors.black, 0.6)!, base, Color.lerp(base, Colors.white, 0.6)!];
  } else {
    cols = [Color.lerp(base, Colors.white, 0.75)!, base, Color.lerp(base, Colors.black, 0.55)!];
  }
  final x = tt * (cols.length - 1);
  final i = x.floor().clamp(0, cols.length - 2);
  return Color.lerp(cols[i], cols[i + 1], x - i)!;
}

String shortValue(double v, String unit) {
  if (unit == '%') return '${v.round()}%';
  if (v.abs() >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
  if (v.abs() >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
  return v.abs() < 10 ? v.toStringAsFixed(1) : v.toStringAsFixed(0);
}

// ============================================================================ projection Web Mercator
class _Mx {
  _Mx(LatLng center, double zoom, this.size) {
    _scale = pow(2.0, zoom).toDouble();
    _ws = 256.0 * _scale;
    _cx = _x(center.longitude);
    _cy = _y(center.latitude);
  }
  final Size size;
  late final double _scale, _ws, _cx, _cy;
  double _x(double lon) => (lon + 180) / 360 * _ws;
  double _y(double lat) {
    final s = sin(lat * pi / 180).clamp(-0.9999, 0.9999).toDouble();
    return (0.5 - log((1 + s) / (1 - s)) / (4 * pi)) * _ws;
  }

  Offset at(double lat, double lon) => Offset(size.width / 2 + _x(lon) - _cx, size.height / 2 + _y(lat) - _cy);
}

class _Item {
  _Item(this.f, this.pts, this.c, this.r, this.t);
  final DataFeature f;
  final List<Offset> pts;
  final Offset c;
  final double r, t;
}

Path _path(List<Offset> pts) {
  final p = Path();
  for (var i = 0; i < pts.length; i++) {
    i == 0 ? p.moveTo(pts[i].dx, pts[i].dy) : p.lineTo(pts[i].dx, pts[i].dy);
  }
  return p..close();
}

// ============================================================================ peintre
class _DataPainter extends CustomPainter {
  _DataPainter({
    required this.camera,
    required this.data,
    required this.style,
    required this.dark,
    required this.selected,
    required this.catOrder,
    required this.born,
    required Listenable clock,
  }) : super(repaint: clock);

  final MapCamera camera;
  final DataMap data;
  final DataStyle style;
  final bool dark;
  final String? selected;
  final List<String> catOrder;
  final DateTime born;

  bool get _cat => data.isCategoryTop;

  Color _col(_Item it) => _cat && it.f.topCategory != null
      ? catColor(it.f.topCategory!, catOrder)
      : dataColor(it.t, polarity: data.polarity, base: data.color, dark: dark, heat: style == DataStyle.chaleur);

  @override
  void paint(Canvas canvas, Size size) {
    final pr = _Mx(camera.center, camera.zoom, size);
    final clip = (Offset.zero & size).inflate(90);
    final items = <_Item>[];
    for (final f in data.features) {
      if (items.length >= 1800) break;
      if (f.polygon.length < 3) continue;
      final pts = [for (final p in f.polygon) pr.at(p.latitude, p.longitude)];
      var x0 = double.infinity, y0 = double.infinity, x1 = -double.infinity, y1 = -double.infinity;
      for (final o in pts) {
        x0 = min(x0, o.dx);
        y0 = min(y0, o.dy);
        x1 = max(x1, o.dx);
        y1 = max(y1, o.dy);
      }
      final rect = Rect.fromLTRB(x0, y0, x1, y1);
      if (!rect.overlaps(clip)) continue;
      items.add(_Item(f, pts, pr.at(f.center.latitude, f.center.longitude), max(4.0, min(rect.width, rect.height) / 2),
          f.intensity.clamp(0.0, 1.0).toDouble()));
    }
    if (items.isEmpty) return;
    final grow = Curves.easeOutCubic.transform((DateTime.now().difference(born).inMilliseconds / 900).clamp(0.0, 1.0).toDouble());
    final ts = DateTime.now().millisecondsSinceEpoch / 1000.0;
    switch (style) {
      case DataStyle.relief:
        _relief(canvas, items, grow);
      case DataStyle.batons:
        _batons(canvas, items, grow, ts);
      case DataStyle.vagues:
        _vagues(canvas, items, clip, ts);
      case DataStyle.chaleur:
        _chaleur(canvas, items, clip, ts);
      case DataStyle.marqueurs:
        _marqueurs(canvas, items, ts);
      default:
        _zones(canvas, items, clip);
    }
    if (selected != null) {
      for (final it in items) {
        if (it.f.h3 != selected) continue;
        canvas.drawPath(_path(it.pts), Paint()..style = PaintingStyle.stroke..strokeWidth = 6..color = Colors.black54..strokeJoin = StrokeJoin.round);
        canvas.drawPath(_path(it.pts), Paint()..style = PaintingStyle.stroke..strokeWidth = 3..color = Colors.white..strokeJoin = StrokeJoin.round);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DataPainter old) => true;

  // ---------------------------------------------------------------- utilitaires
  void _text(Canvas c, String t, Offset center, {double size = 10, Color color = Colors.white, bool shadow = true}) {
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

  void _donut(Canvas canvas, Offset c, double radius, List<DataCategoryShare> cats, {bool ring = true}) {
    if (ring) canvas.drawCircle(c, radius, Paint()..color = Colors.white.withValues(alpha: 0.78));
    final rect = Rect.fromCircle(center: c, radius: radius * 0.68);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.34;
    var a = -pi / 2;
    for (final s in cats) {
      final sweep = 2 * pi * (s.share / 100.0);
      p.color = catColor(s.code, catOrder);
      canvas.drawArc(rect, a, max(0.0, sweep - 0.04), false, p);
      a += sweep;
    }
  }

  // ---------------------------------------------------------------- ZONES (nuage + contours + donuts)
  void _zones(Canvas canvas, List<_Item> items, Rect clip) {
    final r0 = items.first.r;
    canvas.saveLayer(
      clip,
      Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: max(2.0, r0 * 0.30), sigmaY: max(2.0, r0 * 0.30), tileMode: ui.TileMode.decal),
    );
    final p = Paint()..style = PaintingStyle.fill;
    for (final it in items) {
      final a = (0.36 + 0.54 * it.t) * (0.75 + 0.25 * it.f.confidence.clamp(0.0, 1.0));
      p.color = _col(it).withValues(alpha: min(0.92, a));
      canvas.drawPath(_path(it.pts), p);
    }
    canvas.restore();
    final b = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..strokeJoin = StrokeJoin.round;
    for (final it in items) {
      b.color = _col(it).withValues(alpha: 0.5);
      canvas.drawPath(_path(it.pts), b);
    }
    var labels = 0;
    for (final it in items) {
      if (_cat && it.f.categories.isNotEmpty && it.r > 13) {
        _donut(canvas, it.c, it.r * 0.62, it.f.categories);
      } else if (it.r > 24 && labels < 80) {
        labels++;
        _text(canvas, shortValue(it.f.value, data.unit), it.c, size: min(16.0, it.r * 0.5));
      }
    }
  }

  // ---------------------------------------------------------------- RELIEF 3D (prismes hexagonaux)
  void _relief(Canvas canvas, List<_Item> items, double grow) {
    final sorted = [...items]..sort((a, b) => a.c.dy.compareTo(b.c.dy));
    for (final it in sorted) {
      final col = _col(it);
      final hMax = (it.r * 2.8).clamp(16.0, 130.0).toDouble();
      final h = (6 + (hMax - 6) * it.t) * grow;
      final base = [for (final q in it.pts) it.c + (q - it.c) * 0.84];
      canvas.drawPath(
        _path([for (final q in base) q + Offset(h * 0.18, h * 0.10)]),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.2)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      for (var i = 0; i < base.length; i++) {
        final a = base[i], b = base[(i + 1) % base.length];
        final nrm = (a + b) / 2 - it.c;
        final d = max(nrm.distance, 0.001);
        if (nrm.dy < -d * 0.25) continue;
        final shade = (0.55 + 0.25 * (nrm.dx / d)).clamp(0.2, 0.95).toDouble();
        final side = Path()
          ..moveTo(a.dx, a.dy)
          ..lineTo(b.dx, b.dy)
          ..lineTo(b.dx, b.dy - h)
          ..lineTo(a.dx, a.dy - h)
          ..close();
        canvas.drawPath(side, Paint()..color = Color.lerp(Colors.black, col, shade)!);
      }
      final top = _path([for (final q in base) q - Offset(0, h)]);
      canvas.drawPath(top, Paint()..color = Color.lerp(col, Colors.white, 0.15)!.withValues(alpha: 0.96));
      canvas.drawPath(top, Paint()..style = PaintingStyle.stroke..strokeWidth = 1..color = Colors.white.withValues(alpha: 0.55));
      if (it.r > 20) _text(canvas, shortValue(it.f.value, data.unit), it.c - Offset(0, h), size: min(14.0, it.r * 0.45));
    }
  }

  // ---------------------------------------------------------------- BÂTONS (lollipops animés)
  void _batons(Canvas canvas, List<_Item> items, double grow, double ts) {
    final sorted = [...items]..sort((a, b) => a.c.dy.compareTo(b.c.dy));
    for (final it in sorted) {
      final col = _col(it);
      final hMax = (it.r * 3.2).clamp(22.0, 150.0).toDouble();
      final h = (4 + (hMax - 4) * it.t) * grow;
      final sway = sin(ts * 1.4 + it.c.dx * 0.05) * 2.0 * it.t * grow;
      final top = it.c + Offset(sway, -h);
      canvas.drawOval(Rect.fromCenter(center: it.c, width: 16, height: 6), Paint()..color = Colors.black.withValues(alpha: 0.25));
      canvas.drawLine(
        it.c,
        top,
        Paint()
          ..strokeWidth = 2.5 + 2.5 * it.t
          ..strokeCap = StrokeCap.round
          ..shader = ui.Gradient.linear(it.c, top, [col.withValues(alpha: 0.35), col]),
      );
      final rad = 4 + 7 * it.t;
      canvas.drawCircle(top, rad + 2, Paint()..color = Colors.white);
      canvas.drawCircle(top, rad, Paint()..color = col);
      if (it.r > 16 || it.t > 0.6) _text(canvas, shortValue(it.f.value, data.unit), top - Offset(0, rad + 9), size: 10);
    }
  }

  // ---------------------------------------------------------------- VAGUES (ondes animées)
  void _vagues(Canvas canvas, List<_Item> items, Rect clip, double ts) {
    canvas.saveLayer(
      clip,
      Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: max(2.0, items.first.r * 0.3), sigmaY: max(2.0, items.first.r * 0.3), tileMode: ui.TileMode.decal),
    );
    final fill = Paint()..style = PaintingStyle.fill;
    for (final it in items) {
      fill.color = _col(it).withValues(alpha: 0.22 + 0.38 * it.t);
      canvas.drawPath(_path(it.pts), fill);
    }
    canvas.restore();
    final ring = Paint()..style = PaintingStyle.stroke;
    for (final it in items) {
      final col = _col(it);
      for (var k = 0; k < 3; k++) {
        final ph = (ts * (0.18 + 0.45 * it.t) + k / 3.0 + it.c.dx * 0.0013) % 1.0;
        final rad = it.r * (0.4 + (1.2 + 2.2 * it.t) * ph);
        ring
          ..color = col.withValues(alpha: (1 - ph) * (0.25 + 0.55 * it.t))
          ..strokeWidth = 1.2 + 2 * (1 - ph);
        canvas.drawCircle(it.c, rad, ring);
      }
      canvas.drawCircle(it.c, 2.5 + 3 * it.t, Paint()..color = col);
    }
  }

  // ---------------------------------------------------------------- CHALEUR (dégradés radiaux)
  void _chaleur(Canvas canvas, List<_Item> items, Rect clip, double ts) {
    canvas.saveLayer(
      clip,
      Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: max(3.0, items.first.r * 0.35), sigmaY: max(3.0, items.first.r * 0.35), tileMode: ui.TileMode.decal),
    );
    for (final it in items) {
      final rad = it.r * (1.5 + 1.3 * it.t);
      final col = _col(it);
      canvas.drawCircle(
        it.c,
        rad,
        Paint()..shader = ui.Gradient.radial(it.c, rad, [col.withValues(alpha: 0.35 + 0.5 * it.t), col.withValues(alpha: 0)]),
      );
    }
    canvas.restore();
    for (final it in items) {
      if (it.t < 0.7) continue;
      final ph = (ts * 0.5 + it.c.dy * 0.002) % 1.0;
      canvas.drawCircle(
        it.c,
        it.r * (0.5 + 1.2 * ph),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = _col(it).withValues(alpha: (1 - ph) * 0.7),
      );
    }
    var labels = 0;
    for (final it in items) {
      if (it.r > 26 && labels++ < 60) _text(canvas, shortValue(it.f.value, data.unit), it.c, size: min(15.0, it.r * 0.45));
    }
  }

  // ---------------------------------------------------------------- MARQUEURS (épingles + donuts)
  void _marqueurs(Canvas canvas, List<_Item> items, double ts) {
    var maxN = 1;
    for (final it in items) {
      maxN = max(maxN, it.f.n);
    }
    final sorted = [...items]..sort((a, b) => a.c.dy.compareTo(b.c.dy));
    for (final it in sorted) {
      final col = _col(it);
      final rad = 9 + 11 * sqrt(it.f.n / maxN);
      final pin = it.c + Offset(0, -rad - 5);
      final ph = (ts * 0.6 + (it.f.h3.hashCode % 100) / 100.0) % 1.0;
      canvas.drawCircle(it.c, 4 + 14 * ph, Paint()..color = col.withValues(alpha: (1 - ph) * 0.35 * it.f.confidence.clamp(0.2, 1.0)));
      final tail = Path()
        ..moveTo(it.c.dx, it.c.dy)
        ..lineTo(pin.dx - rad * 0.6, pin.dy + rad * 0.5)
        ..lineTo(pin.dx + rad * 0.6, pin.dy + rad * 0.5)
        ..close();
      canvas.drawPath(tail, Paint()..color = col);
      canvas.drawCircle(pin, rad + 2, Paint()..color = Colors.white);
      canvas.drawCircle(pin, rad, Paint()..color = col);
      if (it.f.categories.isNotEmpty && rad >= 12) {
        _donut(canvas, pin, rad * 0.8, it.f.categories);
      } else {
        _text(canvas, shortValue(it.f.value, data.unit), pin, size: max(8.0, rad * 0.62));
      }
    }
  }
}

class _DataLayer extends StatelessWidget {
  const _DataLayer({required this.data, required this.style, required this.dark, required this.selected, required this.catOrder, required this.born, required this.clock});
  final DataMap? data;
  final DataStyle style;
  final bool dark;
  final String? selected;
  final List<String> catOrder;
  final DateTime born;
  final Listenable clock;
  @override
  Widget build(BuildContext context) {
    final d = data;
    if (d == null) return const SizedBox.shrink();
    final cam = MapCamera.of(context);
    return IgnorePointer(
      child: SizedBox.expand(
        child: CustomPaint(
          painter: _DataPainter(camera: cam, data: d, style: resolveStyle(style, d), dark: dark, selected: selected, catOrder: catOrder, born: born, clock: clock),
        ),
      ),
    );
  }
}

// ============================================================================ écran
class DataMapScreen extends StatefulWidget {
  const DataMapScreen({super.key, required this.domain, this.indicatorKey});
  final DataDomain domain;
  final String? indicatorKey;
  @override
  State<DataMapScreen> createState() => _DataMapScreenState();
}

class _DataMapScreenState extends State<DataMapScreen> with SingleTickerProviderStateMixin {
  final MapController _map = MapController();
  late final AnimationController _clock = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();
  late String _key = widget.indicatorKey ?? widget.domain.indicators.first.key;
  String? _metric;
  DataStyle _style = DataStyle.auto;
  int _days = 180;
  bool _indic = false, _dark = false, _ready = false, _loading = false, _again = false, _regrow = true;
  DataMap? _data;
  DateTime _born = DateTime.now();
  String? _error, _selected;
  LatLng? _me;
  Timer? _debounce;

  DataDomain get _dom => widget.domain;
  DataIndicator? get _ind => _dom.indicator(_key);
  String get _title => _ind?.label ?? _dom.derivedOf(_key)?.label ?? _key;

  @override
  void dispose() {
    _debounce?.cancel();
    _clock.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ données
  String _bbox() {
    final b = _map.camera.visibleBounds;
    final dLat = (b.north - b.south) * 0.25, dLon = (b.east - b.west) * 0.25;
    double cl(double v, double lo, double hi) => v.clamp(lo, hi).toDouble();
    return '${cl(b.west - dLon, -179.9, 179.9)},${cl(b.south - dLat, -89.9, 89.9)},${cl(b.east + dLon, -179.9, 179.9)},${cl(b.north + dLat, -89.9, 89.9)}';
  }

  Future<void> _load() async {
    if (!_ready || !mounted) return;
    if (_loading) {
      _again = true;
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await context.read<ApiClient>().dataMap(
          indicator: _key, metric: _metric, zoom: _map.camera.zoom, days: _days, includeIndicative: _indic, bbox: _bbox());
      if (!mounted) return;
      setState(() {
        _data = d;
        _metric = d.metric;
        if (_regrow) {
          _born = DateTime.now();
          _regrow = false;
        }
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.code);
    }
    if (mounted) setState(() => _loading = false);
    if (_again) {
      _again = false;
      _load();
    }
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _load);
  }

  Future<void> _onReady() async {
    _ready = true;
    _load();
    try {
      if (await ensureLocationPermission()) {
        final p = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 6)));
        _me = LatLng(p.latitude, p.longitude);
        if (mounted) {
          _map.move(_me!, 12);
          _load();
        }
      }
    } catch (_) {}
  }

  void _change({String? key, String? metric, bool resetMetric = false}) {
    setState(() {
      if (key != null) _key = key;
      _metric = resetMetric ? null : (metric ?? _metric);
      _regrow = true;
      if (key != null) _data = null;
    });
    _load();
  }

  // ------------------------------------------------------------------ interactions
  static bool _inPoly(LatLng p, List<LatLng> poly) {
    var inside = false;
    for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      final xi = poly[i].longitude, yi = poly[i].latitude, xj = poly[j].longitude, yj = poly[j].latitude;
      if (((yi > p.latitude) != (yj > p.latitude)) && (p.longitude < (xj - xi) * (p.latitude - yi) / (yj - yi) + xi)) inside = !inside;
    }
    return inside;
  }

  void _onTap(LatLng p) {
    final d = _data;
    if (d == null) return;
    DataFeature? hit;
    for (final f in d.features) {
      if (_inPoly(p, f.polygon)) {
        hit = f;
        break;
      }
    }
    if (hit == null) {
      setState(() => _selected = null);
      return;
    }
    final feat = hit;
    setState(() => _selected = feat.h3);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
      builder: (_) => DataCellSheet(feature: feat, map: d, domain: _dom, days: _days, includeIndicative: _indic),
    ).whenComplete(() {
      if (mounted) setState(() => _selected = null);
    });
  }

  void _pickIndicator() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.78),
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(8, 0, 8, 16), children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text('Indicateurs · ${_dom.label}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            ),
            for (final i in _dom.indicators)
              ListTile(
                selected: i.key == _key,
                leading: Icon(_kindIcon(i.kind), color: _dom.color),
                title: Text(i.label),
                subtitle: Text(_kindLabel(i.kind)),
                trailing: i.sensitive ? const Tooltip(message: 'Sujet sensible : seuil de confidentialité renforcé', child: Icon(Icons.lock_outline_rounded, size: 18)) : null,
                onTap: () {
                  Navigator.pop(context);
                  _change(key: i.key, resetMetric: true);
                },
              ),
            if (_dom.derived.isNotEmpty) ...[
              const Padding(padding: EdgeInsets.fromLTRB(12, 12, 12, 4), child: Text('Indicateurs calculés', style: TextStyle(fontWeight: FontWeight.w800))),
              for (final d in _dom.derived)
                ListTile(
                  selected: d.key == _key,
                  leading: Icon(Icons.functions_rounded, color: _dom.color),
                  title: Text(d.label),
                  subtitle: Text(d.unit),
                  onTap: () {
                    Navigator.pop(context);
                    _change(key: d.key, resetMetric: true);
                  },
                ),
            ],
          ]),
        ),
      ),
    );
  }

  IconData _kindIcon(String k) => switch (k) {
        'number' => Icons.numbers_rounded,
        'share' => Icons.pie_chart_rounded,
        'scale' => Icons.star_rate_rounded,
        _ => Icons.category_rounded,
      };
  String _kindLabel(String k) => switch (k) {
        'number' => 'Nombre',
        'share' => 'Part (oui / non)',
        'scale' => 'Note sur 5',
        _ => 'Catégories',
      };

  void _filters() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => StatefulBuilder(builder: (ctx, setM) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Filtres et fond de carte', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              const SizedBox(height: 12),
              const Text('Période', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                for (final d in const [30, 90, 180, 365, 730])
                  ChoiceChip(
                    label: Text(d >= 365 ? '${d ~/ 365} an${d >= 730 ? 's' : ''}' : '$d j'),
                    selected: _days == d,
                    onSelected: (_) {
                      setM(() {});
                      setState(() => _days = d);
                      _regrow = true;
                      _load();
                    },
                  ),
              ]),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Inclure les réponses indicatives'),
                value: _indic,
                onChanged: (v) {
                  setM(() {});
                  setState(() => _indic = v);
                  _regrow = true;
                  _load();
                },
              ),
              const SizedBox(height: 4),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Fond clair'), icon: Icon(Icons.light_mode_rounded)),
                  ButtonSegment(value: true, label: Text('Fond sombre'), icon: Icon(Icons.dark_mode_rounded)),
                ],
                selected: {_dark},
                onSelectionChanged: (v) {
                  setM(() {});
                  setState(() => _dark = v.first);
                },
                showSelectedIcon: false,
              ),
            ]),
          ),
        );
      }),
    );
  }

  void _analyze() {
    final d = _data;
    if (d == null) return;
    final api = context.read<ApiClient>();
    final bbox = _bbox();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      builder: (_) => _AnalysisView(
        loader: () => api.dataAnalysis(indicator: _key, metric: _metric, res: d.resolution.clamp(5, 9), days: _days, includeIndicative: _indic, bbox: bbox),
      ),
    );
  }

  // ------------------------------------------------------------------ build
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final d = _data;
    final role = context.read<SessionController>().user?.role;
    final staff = role == 'tenant_admin' || role == 'analyst';
    final catOrder = _ind?.catOrder ?? const <String>[];
    final resolved = d == null ? DataStyle.zones : resolveStyle(_style, d);
    return Scaffold(
      body: Stack(children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: AppConfig.fallbackCenter,
            initialZoom: 12,
            minZoom: 6,
            maxZoom: 18,
            backgroundColor: _dark ? const Color(0xFF0B1116) : const Color(0xFFEFF3F5),
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
            onMapReady: _onReady,
            onTap: (_, p) => _onTap(p),
            onPositionChanged: (cam, gesture) {
              if (gesture) _schedule();
            },
          ),
          children: [
            TileLayer(
              urlTemplate: _dark ? AppConfig.tileDark : AppConfig.tileLight,
              subdomains: const ['a', 'b', 'c', 'd'],
              userAgentPackageName: AppConfig.packageName,
              maxNativeZoom: 19,
              panBuffer: 2,
            ),
            _DataLayer(data: d, style: _style, dark: _dark, selected: _selected, catOrder: catOrder, born: _born, clock: _clock),
          ],
        ),

        // ---------------------------------------------------------------- haut
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Column(children: [
              Row(children: [
                FloatingActionButton.small(heroTag: 'dm_back', onPressed: () => Navigator.pop(context), child: const Icon(Icons.arrow_back_rounded)),
                const SizedBox(width: 8),
                Expanded(
                  child: SoftCard(
                    glass: true,
                    onTap: _pickIndicator,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(children: [
                      Icon(domainIcon(_dom.icon), color: _dom.color),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(_dom.label, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                          Text(_title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                        ]),
                      ),
                      const Icon(Icons.unfold_more_rounded),
                    ]),
                  ),
                ),
              ]),
              if (d != null && d.metrics.length > 1) ...[
                const SizedBox(height: 8),
                SizedBox(
                  height: 36,
                  child: ListView(scrollDirection: Axis.horizontal, children: [
                    for (final m in d.metrics)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(metricLabel(m, _ind), style: const TextStyle(fontSize: 12)),
                          selected: d.metric == m,
                          onSelected: (_) => _change(metric: m),
                        ),
                      ),
                  ]),
                ),
              ],
              const SizedBox(height: 6),
              SizedBox(
                height: 36,
                child: ListView(scrollDirection: Axis.horizontal, children: [
                  for (final s in DataStyle.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        avatar: Icon(s.icon, size: 16),
                        label: Text(s.label, style: const TextStyle(fontSize: 12)),
                        selected: _style == s,
                        showCheckmark: false,
                        onSelected: (_) => setState(() {
                          _style = s;
                          _born = DateTime.now();
                        }),
                      ),
                    ),
                ]),
              ),
              if (_loading) const Padding(padding: EdgeInsets.only(top: 6), child: LinearProgressIndicator(minHeight: 3)),
              if (_error != null)
                SoftCard(
                  glass: true,
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(children: [
                    Icon(Icons.cloud_off_rounded, color: cs.error, size: 20),
                    const SizedBox(width: 10),
                    Expanded(child: Text(apiErrorLabel(_error!), style: TextStyle(color: cs.error, fontSize: 13))),
                  ]),
                ),
              if (!_loading && _error == null && d != null && d.features.isEmpty)
                SoftCard(
                  glass: true,
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(children: [
                    Icon(Icons.info_outline_rounded, color: cs.primary, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        d.stats.hiddenCells > 0
                            ? '${d.stats.hiddenCells} zone(s) masquée(s) : il faut au moins ${d.stats.minContributors} contributeurs différents.'
                            : 'Aucune réponse validée ici pour cette période. Zoomez ailleurs ou élargissez la période.',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ]),
                ),
            ]),
          ),
        ),

        // ---------------------------------------------------------------- légende (bas gauche)
        if (d != null)
          Positioned(
            left: 12,
            bottom: 24,
            right: 80,
            child: _Legend(data: d, style: resolved, dark: _dark, catOrder: catOrder, indicator: _ind),
          ),

        // ---------------------------------------------------------------- boutons (bas droite)
        Positioned(
          right: 12,
          bottom: 24,
          child: Column(children: [
            if (staff && d != null) ...[
              FloatingActionButton.small(heroTag: 'dm_ai', onPressed: _analyze, child: const Icon(Icons.auto_awesome_rounded)),
              const SizedBox(height: 10),
            ],
            FloatingActionButton.small(heroTag: 'dm_filters', onPressed: _filters, child: const Icon(Icons.tune_rounded)),
            const SizedBox(height: 10),
            FloatingActionButton.small(
              heroTag: 'dm_locate',
              onPressed: () {
                if (_me != null && _ready) {
                  _map.move(_me!, 13);
                  _load();
                }
              },
              child: const Icon(Icons.my_location_rounded),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ============================================================================ légende
class _Legend extends StatelessWidget {
  const _Legend({required this.data, required this.style, required this.dark, required this.catOrder, required this.indicator});
  final DataMap data;
  final DataStyle style;
  final bool dark;
  final List<String> catOrder;
  final DataIndicator? indicator;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = data.stats;
    return SoftCard(
      glass: true,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text('${data.label}${data.unit.isEmpty ? '' : ' (${data.unit})'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        if (data.isCategoryTop && indicator != null)
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final c in indicator!.categories.take(8))
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 9, height: 9, decoration: BoxDecoration(color: catColor(c.code, catOrder), shape: BoxShape.circle)),
                const SizedBox(width: 4),
                Text(c.label, style: const TextStyle(fontSize: 9.5)),
              ]),
          ])
        else ...[
          Container(
            height: 8,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              gradient: LinearGradient(colors: [
                for (var i = 0; i <= 8; i++) dataColor(i / 8, polarity: data.polarity, base: data.color, dark: dark, heat: style == DataStyle.chaleur)
              ]),
            ),
          ),
          const SizedBox(height: 2),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(data.legendMin == null ? '–' : shortValue(data.legendMin!, data.unit), style: const TextStyle(fontSize: 9.5)),
            Text(data.polarity > 0 ? 'plus favorable →' : data.polarity < 0 ? 'plus défavorable →' : 'plus élevé →', style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant)),
            Text(data.legendMax == null ? '–' : shortValue(data.legendMax!, data.unit), style: const TextStyle(fontSize: 9.5)),
          ]),
        ],
        const SizedBox(height: 6),
        Text(
          '${s.cells} zone(s) · ${s.responses} réponse(s)'
          '${s.hiddenCells > 0 ? ' · ${s.hiddenCells} masquée(s) (min ${s.minContributors} contributeurs)' : ''}',
          style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
        ),
        if (data.caveat.isNotEmpty) Text(data.caveat, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant)),
      ]),
    );
  }
}

// ============================================================================ analyse IA (staff)
class _AnalysisView extends StatefulWidget {
  const _AnalysisView({required this.loader});
  final Future<DataAnalysis> Function() loader;
  @override
  State<_AnalysisView> createState() => _AnalysisViewState();
}

class _AnalysisViewState extends State<_AnalysisView> {
  DataAnalysis? _a;
  String? _err;

  @override
  void initState() {
    super.initState();
    widget.loader().then((v) {
      if (mounted) setState(() => _a = v);
    }).catchError((e) {
      if (mounted) setState(() => _err = errorMessage(e));
    });
  }

  Widget _block(String title, List<String> items, ColorScheme cs) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionTitle(title),
      for (final t in items)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.only(top: 7, right: 8), child: Icon(Icons.circle, size: 6, color: cs.primary)),
            Expanded(child: Text(t, style: const TextStyle(height: 1.4, fontSize: 13.5))),
          ]),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final a = _a;
    return SafeArea(
      child: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [
        Row(children: [
          Icon(Icons.auto_awesome_rounded, color: cs.primary),
          const SizedBox(width: 8),
          const Text('Lecture assistée par IA', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        ]),
        const SizedBox(height: 4),
        Text('Agrégats anonymes uniquement. Les explications sont des hypothèses.', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
        const SizedBox(height: 12),
        if (_err != null)
          Text(_err!, style: TextStyle(color: cs.error))
        else if (a == null)
          const Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator()))
        else ...[
          Text(a.summary, style: const TextStyle(height: 1.45)),
          _block('Tendances', a.patterns, cs),
          _block('Zones atypiques', a.outliers, cs),
          _block('Recommandations', a.recommendations, cs),
          _block('Limites des données', a.limitations, cs),
        ],
      ]),
    );
  }
}