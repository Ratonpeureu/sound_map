import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart'; // <-- IMPORT AJOUTÉ

import 'config.dart';
import 'models.dart';
import 'dart:typed_data';

class ApiException implements Exception {
  ApiException(this.status, this.code, [this.detail]);
  final int? status;
  final String code;
  final dynamic detail; // corps `detail` quand le backend renvoie un objet (règles d'incohérence, questions manquantes…)
  @override
  String toString() => 'ApiException($status, $code)';
}

class TokenStore {
  final _s = const FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: true),
  );
  String? access, refresh;

  Future<void> load() async {
    access = await _s.read(key: 'access_token');
    refresh = await _s.read(key: 'refresh_token');
  }

  Future<void> save(String a, String r) async {
    access = a;
    refresh = r;
    await _s.write(key: 'access_token', value: a);
    await _s.write(key: 'refresh_token', value: r);
  }

  Future<void> clear() async {
    access = null;
    refresh = null;
    await _s.delete(key: 'access_token');
    await _s.delete(key: 'refresh_token');
  }
}

class ApiClient {
  ApiClient(String serverUrl)
      : _dio = Dio(BaseOptions(
          baseUrl: _base(serverUrl),
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
          headers: {'Accept': 'application/json'},
        )) {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (o, h) {
        if (!_isAuthPath(o.path) && tokens.access != null) {
          o.headers['Authorization'] = 'Bearer ${tokens.access}';
        }
        h.next(o);
      },
      onError: (e, h) async {
        final opts = e.requestOptions;
        if (e.response?.statusCode == 401 &&
            opts.extra['retried'] != true &&
            !_isAuthPath(opts.path) &&
            tokens.refresh != null) {
          final ok = await _refreshOnce();
          if (ok) {
            opts.extra['retried'] = true;
            opts.headers['Authorization'] = 'Bearer ${tokens.access}';
            try {
              return h.resolve(await _dio.fetch(opts));
            } on DioException catch (e2) {
              return h.next(e2);
            }
          } else {
            onSessionExpired?.call();
          }
        }
        h.next(e);
      },
    ));
  }

  final Dio _dio;
  final TokenStore tokens = TokenStore();
  void Function()? onSessionExpired;
  Future<bool>? _refreshing;

  static String _base(String u) => '${u.trim().replaceAll(RegExp(r'/+$'), '')}${AppConfig.apiPrefix}';
  void setBase(String serverUrl) => _dio.options.baseUrl = _base(serverUrl);

  static bool _isAuthPath(String p) =>
      p.startsWith('/auth/login') || p.startsWith('/auth/register') || p.startsWith('/auth/refresh');

  Future<bool> _refreshOnce() {
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  Future<bool> _doRefresh() async {
    final rt = tokens.refresh;
    if (rt == null) return false;
    try {
      final plain = Dio(BaseOptions(
          baseUrl: _dio.options.baseUrl, connectTimeout: const Duration(seconds: 15)));
      final r = await plain.post('/auth/refresh', data: {'refresh_token': rt});
      await tokens.save(r.data['access_token'] as String, r.data['refresh_token'] as String);
      return true;
    } catch (_) {
      await tokens.clear();
      return false;
    }
  }

  ApiException _wrap(DioException e) {
    final res = e.response;
    if (res == null) return ApiException(null, 'network');
    final data = res.data;
    String code;
    dynamic extra;
    if (data is Map && data['detail'] is String) {
      code = data['detail'] as String;
    } else if (data is Map && data['detail'] is Map) {
      final d = data['detail'] as Map;
      code = (d['code'] as String?) ?? 'validation_error';
      extra = d;
    } else if (data is Map && data['detail'] is List) {
      code = 'validation_error';
    } else {
      code = 'http_${res.statusCode}';
    }
    return ApiException(res.statusCode, code, extra);
  }

  Future<dynamic> _req(String method, String path,
      {Object? data, Map<String, dynamic>? query}) async {
    try {
      final r = await _dio.request(path,
          data: data, queryParameters: query, options: Options(method: method));
      return r.data;
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  String get baseUrl => _dio.options.baseUrl;

  /// Médias protégés (images/vidéos des études) : passent par l'intercepteur (jeton + refresh).
  Future<Uint8List> getBytes(String path) async {
    try {
      final r = await _dio.get<List<int>>(path, options: Options(responseType: ResponseType.bytes));
      return Uint8List.fromList(r.data ?? const []);
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  Future<void> downloadTo(String path, String savePath) async {
    try {
      await _dio.download(path, savePath, options: Options(receiveTimeout: const Duration(minutes: 3)));
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  /// Appel générique (utilisé par api_ext.dart).
  Future<dynamic> call(String method, String path, {Object? data, Map<String, dynamic>? query}) =>
      _req(method, path, data: data, query: query);
    
  Future<dynamic> postForm(String path, FormData form) async {
    try {
      final r = await _dio.post(path,
          data: form, options: Options(sendTimeout: const Duration(seconds: 60), receiveTimeout: const Duration(seconds: 60)));
      return r.data;
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  // ------------------------------------------------------------------ auth
  Future<void> login(String email, String password) async {
    final d = await _req('POST', '/auth/login', data: {'email': email, 'password': password});
    await tokens.save(d['access_token'] as String, d['refresh_token'] as String);
  }

  Future<void> register(String email, String password) =>
      _req('POST', '/auth/register', data: {'email': email, 'password': password});
      
  Future<void> logout() => _req('POST', '/auth/logout', data: {'refresh_token': tokens.refresh});

  // ------------------------------------------------------------------ utilisateur
  Future<UserMe> me() async => UserMe.fromJson(await _req('GET', '/users/me') as Map<String, dynamic>);

  Future<UserMe> patchMe({bool? hybrid, bool? paused}) async => UserMe.fromJson(await _req(
      'PATCH', '/users/me',
      data: {
        if (hybrid != null) 'hybrid_collection_enabled': hybrid,
        if (paused != null) 'participation_paused': paused,
      }) as Map<String, dynamic>);

  Future<List<ConsentItem>> consents() async => [
        for (final c in await _req('GET', '/users/me/consents') as List)
          ConsentItem.fromJson(c as Map<String, dynamic>)
      ];

  Future<List<ConsentItem>> setConsent(String type, bool granted) async => [
        for (final c in await _req('PUT', '/users/me/consents',
            data: {'consent_type': type, 'granted': granted}) as List)
          ConsentItem.fromJson(c as Map<String, dynamic>)
      ];

  Future<Contributions> contributions() async => Contributions.fromJson(
      await _req('GET', '/users/me/contributions') as Map<String, dynamic>);

  Future<void> deleteMe(String password) => _req('DELETE', '/users/me', data: {'password': password});

  // ------------------------------------------------------------------ appareils
  Future<DeviceOut> registerDevice({
    required String installId,
    required String manufacturer,
    required String model,
    required String androidVersion,
    required int sampleRate,
  }) async =>
      DeviceOut.fromJson(await _req('POST', '/devices/register', data: {
        'install_id': installId,
        'manufacturer': manufacturer,
        'model': model,
        'android_version': androidVersion,
        'microphone': 'internal',
        'sample_rate_hz': sampleRate,
      }) as Map<String, dynamic>);

  Future<List<DeviceOut>> myDevices() async => [
        for (final d in await _req('GET', '/devices/me') as List)
          DeviceOut.fromJson(d as Map<String, dynamic>)
      ];

  // ------------------------------------------------------------------ mesures
  Future<List<Map<String, dynamic>>> sendBatch(List<Map<String, dynamic>> items) async {
    final d = await _req('POST', '/measurements/batch', data: {'items': items});
    return (d['results'] as List).cast<Map<String, dynamic>>();
  }

  Future<List<HistoryItem>> history({int limit = 30, int offset = 0}) async => [
        for (final h in await _req('GET', '/measurements/history',
            query: {'limit': limit, 'offset': offset}) as List)
          HistoryItem.fromJson(h as Map<String, dynamic>)
      ];

  // ------------------------------------------------------------------ carte
  Future<List<NoiseCell>> mapNoise(MapFilters f, {String? bbox}) async {
    final d = await _req('GET', '/map/noise', query: {
      ...f.timeQuery(),
      'include_indicative': f.includeIndicative,
      'min_confidence': f.minConfidence,
      if (bbox != null) 'bbox': bbox,
    });
    return [
      for (final feat in d['features'] as List) NoiseCell.fromFeature(feat as Map<String, dynamic>)
    ];
  }

  Future<CellDetail> cellDetail(String h3, MapFilters f) async => CellDetail.fromJson(await _req(
      'GET', '/map/cells/$h3',
      query: {...f.timeQuery(), 'include_indicative': f.includeIndicative}) as Map<String, dynamic>);

  // ------------------------------------------------------------------ collecte hybride
  Future<ScheduleModel?> getSchedule() async {
    try {
      return ScheduleModel.fromJson(await _req('GET', '/collection/schedule') as Map<String, dynamic>);
    } on ApiException catch (e) {
      if (e.code == 'schedule_not_set') return null;
      rethrow;
    }
  }

  Future<ScheduleModel> putSchedule(Map<String, dynamic> body) async => ScheduleModel.fromJson(
      await _req('PUT', '/collection/schedule', data: body) as Map<String, dynamic>);

  Future<ProposalDecision> requestProposal(
          String trigger, double lat, double lon, int battery) async =>
      ProposalDecision.fromJson(await _req('POST', '/collection/proposals/request', data: {
        'trigger': trigger,
        'latitude': lat,
        'longitude': lon,
        'battery_level': battery,
      }) as Map<String, dynamic>);

  Future<List<ProposalOut>> proposals() async => [
        for (final p in await _req('GET', '/collection/proposals') as List)
          ProposalOut.fromJson(p as Map<String, dynamic>)
      ];

  Future<ProposalOut> respondProposal(String id, bool accept) async => ProposalOut.fromJson(
      await _req('POST', '/collection/proposals/$id/${accept ? 'accept' : 'decline'}')
          as Map<String, dynamic>);

  // ------------------------------------------------------------------ TomTom (via le backend)
  Future<TileSession> tileSession() async =>
      TileSession.fromJson(await _req('GET', '/tomtom/tile-session') as Map<String, dynamic>);

  Future<List<TrafficIncident>> trafficIncidents(String bbox) async => [
        for (final i in await _req('GET', '/tomtom/traffic/incidents', query: {'bbox': bbox}) as List)
          TrafficIncident.fromJson(i as Map<String, dynamic>)
      ];

  Future<TrafficFlow?> cellTraffic(String h3) async {
    try {
      return TrafficFlow.fromJson(await _req('GET', '/tomtom/cells/$h3/traffic') as Map<String, dynamic>);
    } on ApiException catch (e) {
      if (e.code == 'no_traffic_data') return null;
      rethrow;
    }
  }

  Future<List<PlaceResult>> searchPlaces(String q, {double? lat, double? lon}) async => [
        for (final p in await _req('GET', '/tomtom/search', query: {
          'q': q,
          if (lat != null) 'lat': lat,
          if (lon != null) 'lon': lon,
        }) as List)
          PlaceResult.fromJson(p as Map<String, dynamic>)
      ];

  Future<RouteResult> route(double oLat, double oLon, double dLat, double dLon, {String mode = 'car'}) async =>
      RouteResult.fromJson(await _req('GET', '/tomtom/route', query: {
        'o_lat': oLat,
        'o_lon': oLon,
        'd_lat': dLat,
        'd_lon': dLon,
        'mode': mode,
      }) as Map<String, dynamic>);

  // ------------------------------------------------------------------ OSRM (gratuit, sans clé)
  Future<OsrmRoute> getOsrmRoute(LatLng from, LatLng to, {String profile = 'driving'}) async {
    final baseUrl = 'https://router.project-osrm.org/route/v1';
    final coords = '${from.longitude},${from.latitude};${to.longitude},${to.latitude}';
    final uri = Uri.parse('$baseUrl/$profile/$coords?geometries=geojson&overview=full&alternatives=false&continue_straight=false');

    final response = await http.get(uri).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) throw ApiException(response.statusCode, 'osrm_error');

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['code'] != 'Ok' || (data['routes'] as List).isEmpty) {
      throw ApiException(500, 'osrm_no_route');
    }

    final route = (data['routes'] as List).first as Map<String, dynamic>;
    final geometry = route['geometry'] as Map<String, dynamic>;
    final coordinates = (geometry['coordinates'] as List).cast<List<dynamic>>();

    final points = [
      for (final c in coordinates) LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble())
    ];

    return OsrmRoute(
      points: points,
      distanceM: (route['distance'] as num).toDouble(),
      durationS: (route['duration'] as num).toDouble(),
    );
  }

  Future<({int status, dynamic data, String? etag})> getConditional(String path,
      {Map<String, dynamic>? query, String? etag}) async {
    try {
      final r = await _dio.get(path,
          queryParameters: query,
          options: Options(
            headers: {if (etag != null) 'If-None-Match': etag},
            validateStatus: (s) => s != null && (s < 400 || s == 304),
          ));
      return (status: r.statusCode ?? 200, data: r.data, etag: r.headers.value('etag'));
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }
}

class OsrmRoute {
  OsrmRoute({required this.points, required this.distanceM, required this.durationS});
  final List<LatLng> points;
  final double distanceM;
  final double durationS;
}




  