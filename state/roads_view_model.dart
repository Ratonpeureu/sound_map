import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';

import '../core/api.dart';
import '../core/api_ext.dart';
import '../core/models.dart';
import '../core/models_roads.dart';
import 'session_controller.dart';




// ============================================================================
// Structures et travail hors du thread UI
// ============================================================================
class _Net {
  _Net(this.segs, this.truncated);
  final List<RoadSeg> segs;
  final bool truncated;
}

class _Job {
  _Job(this.data, this.path, this.etag);
  final Map<String, dynamic> data;
  final String? path;
  final String? etag;
}

_Net _buildNet(_Job j) {
  final segs = [
    for (final x in j.data['features'] as List) RoadSeg.fromFeature((x as Map).cast<String, dynamic>())
  ];
  if (j.path != null) {
    try {
      File(j.path!).writeAsStringSync(jsonEncode(j.data));
      if (j.etag != null) File('${j.path}.etag').writeAsStringSync(j.etag!);
    } catch (_) {}
  }
  return _Net(segs, (j.data['truncated'] as bool?) ?? false);
}

_Net? _readNet(String path) {
  try {
    final f = File(path);
    if (!f.existsSync()) return null;
    final d = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    return _Net(
      [for (final x in d['features'] as List) RoadSeg.fromFeature((x as Map).cast<String, dynamic>())],
      (d['truncated'] as bool?) ?? false,
    );
  } catch (_) {
    return null;
  }
}

/// Supprime les tuiles plus vieilles que 14 jours (exécuté hors du thread UI).
void _cleanDir(String path) {
  try {
    final lim = DateTime.now().subtract(const Duration(days: 14));
    for (final f in Directory(path).listSync()) {
      if (f is File && f.statSync().modified.isBefore(lim)) f.deleteSync();
    }
  } catch (_) {}
}

class _Tile {
  _Tile(this.size, this.ix, this.iy, this.rank, this.net, this.etag) : v = ++_counter;
  static int _counter = 0;
  final double size;
  final int ix, iy, rank, v;
  final _Net net;
  final String? etag;
  DateTime at = DateTime.now();
  bool checked = false, checking = false;
  String get key => '$size|$ix|$iy|$rank';
}

// ============================================================================
// ViewModel
// ============================================================================
/// Réseau routier : tuiles en cache (mémoire + disque persistant, ETag) et état de bruit (rafraîchi souvent).
/// Les tuiles déjà vues s'affichent instantanément ; le réseau ne sert qu'à revalider.
class RoadsViewModel extends ChangeNotifier {
  RoadsViewModel(this.api, this.session) {
    session.addResetHook(() {
      segs = const [];
      states = const {};
      _mem.clear();
      _cur = const [];
      _sig = '';
      _stBox = null;
      _stSig = '';
      selected = null;
      notifyListeners();
    });
  }

  final ApiClient api;
  final SessionController session;

  /// En dessous, seules les très grandes routes existeraient : on n'affiche rien.
  static const double minZoom = 10.5;

  List<RoadSeg> segs = const [];
  Map<String, RoadState> states = const {};
  bool loading = false, truncated = false;
  String? error, selected;

  // cache
  final Map<String, _Tile> _mem = {}; // LRU (ordre d'insertion)
  final Map<String, Future<_Tile?>> _inflight = {};
  static String? _dir; // renseigné par _ready() ; null = pas de cache disque (mémoire seule)
  static Future<void>? _dirInit;

  // requête courante
  List<(int, int)> _cur = const [];
  double _curSize = 0.04;
  int _curRank = 6;
  String _sig = '';
  int _gen = 0;
  MapFilters? _f;
  String? _bbox;
  double _zoom = 0;

  // états de bruit
  List<double>? _stBox;
  String _stSig = '';
  int _stRank = -1;
  DateTime? _stAt;
  bool _stBusy = false, _stAgain = false;

  static int rankFor(double z) => z < 8 ? 2 : z < 11 ? 3 : z < 13 ? 4 : z < 15 ? 5 : 6;

  /// Tuiles plus grandes quand on dézoome (moins de requêtes), petites en zoom serré.
  static double tileSize(double z) => z < 12.5 ? 0.16 : (z < 14.5 ? 0.08 : 0.04);

  // ------------------------------------------------------------------ disque
  /// Résout une seule fois le dossier persistant de l'app (`.../sunu_roads`).
  static Future<void> _ready() => _dirInit ??= _resolveDir();

  static Future<void> _resolveDir() async {
    try {
      final base = await getApplicationSupportDirectory();
      final d = Directory('${base.path}/sunu_roads');
      if (!await d.exists()) await d.create(recursive: true);
      _dir = d.path;
      unawaited(compute(_cleanDir, d.path));
    } catch (_) {
      _dir = null; // repli : cache mémoire uniquement
    }
  }

  static String? _path(double size, int ix, int iy, int rank) =>
      _dir == null ? null : '$_dir/r_${size}_${ix}_${iy}_$rank.json';

  // ------------------------------------------------------------------ mémoire
  _Tile? _peek(double size, int ix, int iy, int rank) {
    for (var r = rank; r <= 6; r++) {
      final k = '$size|$ix|$iy|$r';
      final t = _mem.remove(k);
      if (t != null) {
        _mem[k] = t;
        return t;
      }
    }
    return null;
  }

  void _put(_Tile t) {
    _mem.remove(t.key);
    _mem[t.key] = t;
    while (_mem.length > 48) {
      _mem.remove(_mem.keys.first);
    }
  }

  void select(String? id) {
    selected = id;
    notifyListeners();
  }

  // ------------------------------------------------------------------ tuiles
  Future<_Tile?> _tile(double size, int ix, int iy, int rank) async {
    final hit = _peek(size, ix, iy, rank);
    if (hit != null) {
      _revalidate(hit);
      return hit;
    }
    final k = '$size|$ix|$iy|$rank';
    return _inflight[k] ??= _loadTile(size, ix, iy, rank).whenComplete(() => _inflight.remove(k));
  }

  Future<_Tile?> _loadTile(double size, int ix, int iy, int rank) async {
    final path = _path(size, ix, iy, rank);
    if (path != null) {
      final net = await compute(_readNet, path);
      if (net != null) {
        String? etag;
        try {
          final f = File('$path.etag');
          if (f.existsSync()) etag = f.readAsStringSync();
        } catch (_) {}
        final t = _Tile(size, ix, iy, rank, net, etag);
        _put(t);
        _revalidate(t);
        return t;
      }
    }
    return _fetch(size, ix, iy, rank, null);
  }

  Future<_Tile?> _fetch(double size, int ix, int iy, int rank, _Tile? old) async {
    try {
      final box = [ix * size, iy * size, (ix + 1) * size, (iy + 1) * size].map((v) => v.toStringAsFixed(5)).join(',');
      final r = await api.getConditional('/roads/network', query: {'bbox': box, 'max_rank': rank}, etag: old?.etag);
      if (r.status == 304 && old != null) {
        old.at = DateTime.now();
        return old;
      }
      final net = await compute(_buildNet, _Job(r.data as Map<String, dynamic>, _path(size, ix, iy, rank), r.etag));
      final t = _Tile(size, ix, iy, rank, net, r.etag)..checked = true;
      _put(t);
      return t;
    } catch (_) {
      return old;
    }
  }

  /// Revalidation silencieuse (ETag) : on affiche le cache tout de suite, puis on met à jour si le serveur a changé.
  void _revalidate(_Tile t) {
    if (t.checking) return;
    final stale = !t.checked || DateTime.now().difference(t.at) > const Duration(minutes: 15);
    if (!stale) return;
    t.checking = true;
    _fetch(t.size, t.ix, t.iy, t.rank, t).then((n) {
      t.checking = false;
      t.checked = true;
      if (n != null && !identical(n, t)) _mergeCurrent();
    });
  }

  void _mergeCurrent() {
    final parts = <String>[];
    final seen = <String>{};
    final out = <RoadSeg>[];
    var trunc = false;
    for (final c in _cur) {
      final tile = _peek(_curSize, c.$1, c.$2, _curRank);
      if (tile == null) continue;
      parts.add('${tile.key}:${tile.v}');
      trunc |= tile.net.truncated;
      for (final s in tile.net.segs) {
        if (s.rank <= _curRank && seen.add(s.id)) out.add(s);
      }
    }
    final sig = parts.join(',');
    if (sig == _sig) return; // rien n'a changé : on garde la même liste (le dessin reste en cache)
    _sig = sig;
    segs = out;
    truncated = trunc;
    notifyListeners();
  }

  // ------------------------------------------------------------------ chargement
  Future<void> load(MapFilters f, String bbox, double zoom, {bool force = false}) async {
    _f = f;
    _bbox = bbox;
    _zoom = zoom;
    if (zoom < minZoom) {
      if (segs.isNotEmpty || states.isNotEmpty) {
        segs = const [];
        states = const {};
        truncated = false;
        _cur = const [];
        _sig = '';
        notifyListeners();
      }
      return;
    }

    await _ready(); // dossier de cache persistant prêt (résolu une seule fois)

    final gen = ++_gen;
    final rank = rankFor(zoom);
    final size = tileSize(zoom);
    final b = bbox.split(',').map(double.parse).toList();
    final x0 = (b[0] / size).floor(), x1 = (b[2] / size).floor();
    final y0 = (b[1] / size).floor(), y1 = (b[3] / size).floor();
    final cx = (b[0] + b[2]) / 2 / size, cy = (b[1] + b[3]) / 2 / size;
    final tiles = <(int, int)>[
      for (var x = x0; x <= x1; x++)
        for (var y = y0; y <= y1; y++) (x, y)
    ]..sort((a, c) {
        double d((int, int) t) => pow(t.$1 + 0.5 - cx, 2).toDouble() + pow(t.$2 + 0.5 - cy, 2).toDouble();
        return d(a).compareTo(d(c));
      });
    if (tiles.length > 20) tiles.removeRange(20, tiles.length);

    _cur = tiles;
    _curSize = size;
    _curRank = rank;

    final missing = <(int, int)>{
      for (final t in tiles)
        if (_peek(size, t.$1, t.$2, rank) == null) t
    };
    _mergeCurrent(); // affiche tout de suite ce qui est déjà en cache
    if (missing.isNotEmpty) {
      loading = true;
      notifyListeners();
    }

    var failed = 0;
    var minX = 1 << 30, minY = 1 << 30, maxX = -(1 << 30), maxY = -(1 << 30);
    for (final t in tiles) {
      minX = min(minX, t.$1);
      maxX = max(maxX, t.$1);
      minY = min(minY, t.$2);
      maxY = max(maxY, t.$2);
    }
    final box = [minX * size, minY * size, (maxX + 1) * size, (maxY + 1) * size];

    await Future.wait([
      for (final t in tiles)
        _tile(size, t.$1, t.$2, rank).then((r) {
          if (r == null) failed++;
          if (gen == _gen && missing.contains(t)) _mergeCurrent();
        }),
      _loadStates(f, box, zoom, rank, force: force),
    ]);

    if (gen == _gen) {
      loading = false;
      error = (failed == tiles.length && segs.isEmpty) ? 'network' : null;
      notifyListeners();
    }
  }

  Future<void> _loadStates(MapFilters f, List<double> box, double zoom, int rank, {bool force = false}) async {
    final sig = '${f.period}|${f.dayPart}|${f.includeIndicative}';
    final b = _stBox;
    final covered = b != null && box[0] >= b[0] && box[1] >= b[1] && box[2] <= b[2] && box[3] <= b[3];
    final fresh = _stAt != null && DateTime.now().difference(_stAt!) < const Duration(seconds: 25);
    if (!force && sig == _stSig && rank == _stRank && covered && fresh) return;
    if (_stBusy) {
      _stAgain = true;
      return;
    }
    _stBusy = true;
    try {
      final s = box.map((v) => v.toStringAsFixed(5)).join(',');
      final r = await api.roadStates(f, s, zoom, rank);
      if (sig != _stSig) {
        states = r;
      } else {
        final m = {...states, ...r}; // on garde les zones déjà vues : pas de clignotement
        states = m.length > 30000 ? r : m;
      }
      _stBox = box;
      _stSig = sig;
      _stRank = rank;
      _stAt = DateTime.now();
      notifyListeners();
    } catch (_) {}
    _stBusy = false;
    if (_stAgain) {
      _stAgain = false;
      final ff = _f, bb = _bbox;
      if (ff != null && bb != null) load(ff, bb, _zoom);
    }
  }

  Future<void> refreshStates() async {
    final f = _f, b = _bbox;
    if (f == null || b == null) return;
    await load(f, b, _zoom, force: true);
  }

  // ------------------------------------------------------------------ sélection
  /// Tronçon touché (tolérance ≈ 16 pixels écran), ou null.
  RoadSeg? hit(LatLng p, double zoom) {
    if (segs.isEmpty) return null;
    final cosLat = cos(p.latitude * pi / 180);
    final tol = 156543.03392 * cosLat / pow(2, zoom) * 16;
    final dLat = tol / 110574.0, dLon = tol / (111320.0 * cosLat);
    RoadSeg? best;
    var bd = tol;
    for (final s in segs) {
      if (p.latitude < s.minLat - dLat || p.latitude > s.maxLat + dLat) continue;
      if (p.longitude < s.minLon - dLon || p.longitude > s.maxLon + dLon) continue;
      for (var i = 0; i < s.points.length - 1; i++) {
        final d = _distM(p, s.points[i], s.points[i + 1], cosLat);
        if (d < bd) {
          bd = d;
          best = s;
        }
      }
    }
    return best;
  }

  static double _distM(LatLng p, LatLng a, LatLng b, double cosLat) {
    final ax = (a.longitude - p.longitude) * 111320.0 * cosLat, ay = (a.latitude - p.latitude) * 110574.0;
    final bx = (b.longitude - p.longitude) * 111320.0 * cosLat, by = (b.latitude - p.latitude) * 110574.0;
    final dx = bx - ax, dy = by - ay;
    final l2 = dx * dx + dy * dy;
    final t = l2 == 0 ? 0.0 : ((-ax * dx - ay * dy) / l2).clamp(0.0, 1.0);
    final x = ax + dx * t, y = ay + dy * t;
    return sqrt(x * x + y * y);
  }
}