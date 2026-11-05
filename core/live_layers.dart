import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Trafic : seule couche qui demande une clé (lancer avec --dart-define=TOMTOM_KEY=...).
class LiveConfig {
  static const String trafficKey = String.fromEnvironment('TOMTOM_KEY');
  static bool get trafficEnabled => trafficKey.isNotEmpty;
  static String get trafficTiles =>
      'https://api.tomtom.com/traffic/map/4/tile/flow/relative/{z}/{x}/{y}.png?key=$trafficKey';
}

class WeatherPoint {
  const WeatherPoint({
    required this.pos,
    required this.temp,
    required this.feels,
    required this.humidity,
    required this.precip,
    required this.cloud,
    required this.wind,
    required this.windDir,
    required this.code,
    required this.isDay,
    this.soil,
  });
  final LatLng pos;
  final double temp, feels, precip, wind, windDir;
  final int humidity, cloud, code;
  final bool isDay;
  final double? soil; // température du sol (°C), si disponible

  WeatherPoint withSoil(double? s) => WeatherPoint(
        pos: pos,
        temp: temp,
        feels: feels,
        humidity: humidity,
        precip: precip,
        cloud: cloud,
        wind: wind,
        windDir: windDir,
        code: code,
        isDay: isDay,
        soil: s,
      );
}

class _WeatherCacheEntry {
  _WeatherCacheEntry(this.points, this.at);
  final List<WeatherPoint> points;
  final DateTime at;
}

/// Météo en direct Open-Meteo (sans clé) sur une grille régulière couvrant la zone demandée.
/// Les points sont renvoyés ligne par ligne (sud -> nord), colonne par colonne (ouest -> est).
class LiveWeatherService {
  static const _base = 'https://api.open-meteo.com/v1/forecast';
  static const _ttl = Duration(minutes: 15);
  static final Map<String, _WeatherCacheEntry> _cache = {};

  static double _n(dynamic v) => (v as num?)?.toDouble() ?? 0.0;

  static String _key(LatLngBounds b, int c, int r, bool soil) =>
      '${b.south.toStringAsFixed(2)}_${b.north.toStringAsFixed(2)}_'
      '${b.west.toStringAsFixed(2)}_${b.east.toStringAsFixed(2)}_${c}x${r}_$soil';

  static Future<List<WeatherPoint>> fetchGrid(LatLngBounds b,
      {int cols = 5, int rows = 5, bool soil = false}) async {
    final key = _key(b, cols, rows, soil);
    final now = DateTime.now();
    final cached = _cache[key];
    if (cached != null && now.difference(cached.at) < _ttl) return cached.points;
    try {
      var pts = await _fetch(b, cols, rows);
      if (soil && pts.isNotEmpty) pts = await _attachSoil(pts);
      _cache[key] = _WeatherCacheEntry(pts, now);
      if (_cache.length > 10) _cache.remove(_cache.keys.first);
      return pts;
    } catch (e) {
      debugPrint('Weather API error: $e');
      if (cached != null) return cached.points;
      return [];
    }
  }

  static List<LatLng> _gridPoints(LatLngBounds b, int cols, int rows) {
    final pts = <LatLng>[];
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final lat = b.south + (b.north - b.south) * (r + 0.5) / rows;
        final lon = b.west + (b.east - b.west) * (c + 0.5) / cols;
        pts.add(LatLng(lat.clamp(-89.9, 89.9).toDouble(), lon.clamp(-179.9, 179.9).toDouble()));
      }
    }
    return pts;
  }

  static List<List<LatLng>> _chunks(List<LatLng> pts) => [
        for (var i = 0; i < pts.length; i += 30) pts.sublist(i, i + 30 > pts.length ? pts.length : i + 30)
      ];

  static Uri _uri(List<LatLng> chunk, String current) => Uri.parse(_base).replace(queryParameters: {
        'latitude': chunk.map((p) => p.latitude.toStringAsFixed(3)).join(','),
        'longitude': chunk.map((p) => p.longitude.toStringAsFixed(3)).join(','),
        'current': current,
        'wind_speed_unit': 'kmh',
        'timezone': 'auto',
      });

  static Future<List<WeatherPoint>> _fetch(LatLngBounds b, int cols, int rows) async {
    final out = <WeatherPoint>[];
    for (final chunk in _chunks(_gridPoints(b, cols, rows))) {
      final res = await http
          .get(_uri(
              chunk,
              'temperature_2m,apparent_temperature,relative_humidity_2m,precipitation,'
              'weather_code,cloud_cover,wind_speed_10m,wind_direction_10m,is_day'))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) throw Exception('open-meteo ${res.statusCode}');
      final body = jsonDecode(res.body);
      final list = body is List ? body : [body];
      for (var i = 0; i < list.length && i < chunk.length; i++) {
        final cur = (list[i] as Map)['current'] as Map?;
        if (cur == null) continue;
        out.add(WeatherPoint(
          pos: chunk[i],
          temp: _n(cur['temperature_2m']),
          feels: _n(cur['apparent_temperature']),
          humidity: _n(cur['relative_humidity_2m']).round(),
          precip: _n(cur['precipitation']),
          cloud: _n(cur['cloud_cover']).round(),
          wind: _n(cur['wind_speed_10m']),
          windDir: _n(cur['wind_direction_10m']),
          code: _n(cur['weather_code']).round(),
          isDay: _n(cur['is_day']) == 1,
        ));
      }
    }
    return out;
  }

  /// Requête séparée et facultative : si elle échoue, le reste de la météo n'est pas affecté.
  static Future<List<WeatherPoint>> _attachSoil(List<WeatherPoint> pts) async {
    try {
      final soil = <double?>[];
      for (var i = 0; i < pts.length; i += 30) {
        final chunk = pts.sublist(i, i + 30 > pts.length ? pts.length : i + 30);
        final res = await http
            .get(_uri([for (final p in chunk) p.pos], 'soil_temperature_0cm'))
            .timeout(const Duration(seconds: 10));
        if (res.statusCode != 200) return pts;
        final body = jsonDecode(res.body);
        final list = body is List ? body : [body];
        for (var k = 0; k < chunk.length; k++) {
          final cur = k < list.length ? (list[k] as Map)['current'] as Map? : null;
          soil.add((cur?['soil_temperature_0cm'] as num?)?.toDouble());
        }
      }
      if (soil.length != pts.length) return pts;
      return [for (var i = 0; i < pts.length; i++) pts[i].withSoil(soil[i])];
    } catch (_) {
      return pts;
    }
  }
}

Color tempColor(double t) {
  const stops = [
    (10.0, Color(0xFF3B82F6)),
    (20.0, Color(0xFF22C55E)),
    (28.0, Color(0xFFF59E0B)),
    (34.0, Color(0xFFEF4444)),
    (42.0, Color(0xFF9333EA)),
  ];
  if (t <= stops.first.$1) return stops.first.$2;
  for (var i = 1; i < stops.length; i++) {
    if (t <= stops[i].$1) {
      final a = stops[i - 1], b = stops[i];
      return Color.lerp(a.$2, b.$2, (t - a.$1) / (b.$1 - a.$1))!;
    }
  }
  return stops.last.$2;
}

Color windColor(double kmh) =>
    Color.lerp(const Color(0xFF38BDF8), const Color(0xFF9333EA), (kmh / 60).clamp(0.0, 1.0))!;

IconData weatherIcon(int code, bool day) {
  if (code == 0) return day ? Icons.wb_sunny_rounded : Icons.nightlight_round;
  if (code <= 3) return day ? Icons.wb_cloudy_rounded : Icons.cloud_rounded;
  if (code == 45 || code == 48) return Icons.blur_on_rounded;
  if (code >= 51 && code <= 57) return Icons.grain_rounded;
  if ((code >= 61 && code <= 67) || (code >= 80 && code <= 82)) return Icons.water_drop_rounded;
  if ((code >= 71 && code <= 77) || code == 85 || code == 86) return Icons.ac_unit_rounded;
  if (code >= 95) return Icons.thunderstorm_rounded;
  return Icons.cloud_rounded;
}

String weatherLabel(int code) {
  if (code == 0) return 'Dégagé';
  if (code <= 3) return 'Nuageux';
  if (code == 45 || code == 48) return 'Brouillard';
  if (code >= 51 && code <= 57) return 'Bruine';
  if ((code >= 61 && code <= 67) || (code >= 80 && code <= 82)) return 'Pluie';
  if ((code >= 71 && code <= 77) || code == 85 || code == 86) return 'Neige';
  if (code >= 95) return 'Orage';
  return 'Couvert';
}

String compass(double deg) {
  const d = ['N', 'NE', 'E', 'SE', 'S', 'SO', 'O', 'NO'];
  return d[((deg % 360) / 45).round() % 8];
}