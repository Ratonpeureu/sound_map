import 'package:dio/dio.dart';

import 'api.dart';
import 'models_survey.dart';

extension ApiSurvey on ApiClient {
  // ------------------------------------------------------------------ cartes de données
  Future<DataCatalog> dataCatalog() async =>
      DataCatalog.fromJson(await call('GET', '/datamap/catalog') as Map<String, dynamic>);

  Future<DataSummary> dataSummary({int days = 180}) async =>
      DataSummary.fromJson(await call('GET', '/datamap/summary', query: {'days': days}) as Map<String, dynamic>);

  Future<DataMap> dataMap({
    required String indicator,
    String? metric,
    required double zoom,
    required int days,
    required bool includeIndicative,
    required String bbox,
  }) async =>
      DataMap.fromJson(await call('GET', '/datamap/map', query: {
        'indicator': indicator,
        if (metric != null) 'metric': metric,
        'zoom': zoom,
        'days': days,
        'include_indicative': includeIndicative,
        'bbox': bbox,
      }) as Map<String, dynamic>);

  Future<DataCellDetail> dataCell(String h3, String domain, {required int days, required bool includeIndicative}) async =>
      DataCellDetail.fromJson(await call('GET', '/datamap/cells/$h3',
          query: {'domain': domain, 'days': days, 'include_indicative': includeIndicative}) as Map<String, dynamic>);

  Future<DataTrend> dataTrend(String indicator, {String? h3, String? metric, int months = 12, bool includeIndicative = false}) async =>
      DataTrend.fromJson(await call('GET', '/datamap/trend', query: {
        'indicator': indicator,
        if (h3 != null) 'h3_index': h3,
        if (metric != null) 'metric': metric,
        'months': months,
        'include_indicative': includeIndicative,
      }) as Map<String, dynamic>);

  Future<DataAnalysis> dataAnalysis({
    required String indicator,
    String? metric,
    required int res,
    required int days,
    required bool includeIndicative,
    required String bbox,
  }) async =>
      DataAnalysis.fromJson(await call('POST', '/datamap/analysis', query: {
        'indicator': indicator,
        if (metric != null) 'metric': metric,
        'res': res,
        'days': days,
        'include_indicative': includeIndicative,
        'bbox': bbox,
      }) as Map<String, dynamic>);

  // ------------------------------------------------------------------ enquêtes
  Future<List<SurveyCard>> surveysAvailable(double? lat, double? lon) async => [
        for (final s in await call('GET', '/surveys', query: {if (lat != null) 'lat': lat, if (lon != null) 'lon': lon}) as List)
          SurveyCard.fromJson((s as Map).cast<String, dynamic>())
      ];

  Future<SurveyDefinition> surveyGet(String id, double? lat, double? lon) async => SurveyDefinition.fromJson(
      await call('GET', '/surveys/$id', query: {if (lat != null) 'lat': lat, if (lon != null) 'lon': lon}) as Map<String, dynamic>);

  Future<SubmitAck> surveySubmit(Map<String, dynamic> body) async =>
      SubmitAck.fromJson(await call('POST', '/surveys/responses', data: body) as Map<String, dynamic>);

  Future<List<MyResponse>> surveyMine({int limit = 30, int offset = 0}) async => [
        for (final r in await call('GET', '/surveys/responses/mine', query: {'limit': limit, 'offset': offset}) as List)
          MyResponse.fromJson((r as Map).cast<String, dynamic>())
      ];

  Future<ResponseDetail> surveyResponse(String id) async =>
      ResponseDetail.fromJson(await call('GET', '/surveys/responses/$id') as Map<String, dynamic>);

  Future<TrustView> surveyTrust() async => TrustView.fromJson(await call('GET', '/surveys/me/trust') as Map<String, dynamic>);

  Future<void> surveyEvidence(String responseId, String questionKey, String path) async {
    final form = FormData.fromMap({
      'question_key': questionKey,
      'file': await MultipartFile.fromFile(path, filename: 'preuve.jpg'),
    });
    await postForm('/surveys/responses/$responseId/evidence', form);
  }

  Future<void> surveyEvidenceDone(String responseId) => call('POST', '/surveys/responses/$responseId/evidence/done');
}