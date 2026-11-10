import 'dart:typed_data';

import 'api.dart';
import 'models_study.dart';

extension ApiStudy on ApiClient {
  Map<String, dynamic> _pos(double? lat, double? lon) => {if (lat != null) 'lat': lat, if (lon != null) 'lon': lon};

  Future<List<StudyCard>> studiesAvailable({double? lat, double? lon}) async => [
        for (final s in await call('GET', '/studies', query: _pos(lat, lon)) as List) StudyCard.fromJson((s as Map).cast<String, dynamic>())
      ];

  Future<StudyDetail> studyGet(String id, {double? lat, double? lon}) async =>
      StudyDetail.fromJson(await call('GET', '/studies/$id', query: _pos(lat, lon)) as Map<String, dynamic>);

  Future<void> studyStart(String id, {double? lat, double? lon}) => call('POST', '/studies/$id/start', query: _pos(lat, lon));

  Future<void> studyDecline(String id) => call('POST', '/studies/$id/decline');

  Future<({bool ok, String? message})> studyCheck(String id, Map<String, dynamic> answers) async {
    final r = await call('POST', '/studies/$id/check', data: {'answers': answers}) as Map;
    return (ok: r['ok'] as bool, message: r['message'] as String?);
  }

  Future<StudyAck> studySubmit(String id, Map<String, dynamic> body) async =>
      StudyAck.fromJson(await call('POST', '/studies/$id/submit', data: body) as Map<String, dynamic>);

  Future<List<StudyParticipation>> studyParticipations() async => [
        for (final p in await call('GET', '/studies/participations') as List) StudyParticipation.fromJson((p as Map).cast<String, dynamic>())
      ];

  Future<RewardsData> studyRewards() async => RewardsData.fromJson(await call('GET', '/studies/rewards') as Map<String, dynamic>);

  Future<RewardDetail> studyReward(String id) async =>
      RewardDetail.fromJson(await call('GET', '/studies/rewards/$id') as Map<String, dynamic>);

  Future<void> studyClaim(String id, String phone, String? name) =>
      call('POST', '/studies/rewards/$id/claim', data: {'phone': phone, if (name != null && name.isNotEmpty) 'name': name});

  Future<StudyProfile> studyProfile() async => StudyProfile.fromJson(await call('GET', '/studies/profile') as Map<String, dynamic>);

  Future<StudyProfile> studyProfileSave(StudyProfile p) async =>
      StudyProfile.fromJson(await call('PUT', '/studies/profile', data: p.toJson()) as Map<String, dynamic>);

  Future<Map<String, List<({String value, String label})>>> studyProfileOptions() async {
    final d = await call('GET', '/studies/profile/options') as Map;
    return {
      for (final e in d.entries)
        e.key.toString(): [for (final o in e.value as List) (value: o['value'] as String, label: o['label'] as String)]
    };
  }

  Future<SponsorFull> studySponsor(String id) async =>
      SponsorFull.fromJson(await call('GET', '/studies/sponsors/$id') as Map<String, dynamic>);

  Future<Uint8List> studyMediaBytes(String assetId) => getBytes('/study-assets/$assetId');

  Future<void> studyMediaFile(String assetId, String savePath) => downloadTo('/study-assets/$assetId', savePath);
}