import 'api.dart';
import 'models.dart';
import 'models_ext.dart';
import 'models_field.dart';
import 'models_social.dart';
import 'models_roads.dart';
extension ApiExt on ApiClient {
  // ------------------------------------------------------------------ quota / missions / carte
  Future<QuotaState> quotaMe() async =>
      QuotaState.fromJson(await call('GET', '/quota/me') as Map<String, dynamic>);

  Future<QuotaCheck> quotaCheck(double lat, double lon, {String? proposalId}) async =>
      QuotaCheck.fromJson(await call('POST', '/quota/check', data: {
        'latitude': lat,
        'longitude': lon,
        if (proposalId != null) 'proposal_id': proposalId,
      }) as Map<String, dynamic>);

  Future<List<Mission>> missions() async => [
        for (final m in await call('GET', '/missions') as List) Mission.fromJson(m as Map<String, dynamic>)
      ];

  Future<List<Mission>> missionsSync(double lat, double lon) async => [
        for (final m in await call('POST', '/missions/sync', data: {'latitude': lat, 'longitude': lon}) as List)
          Mission.fromJson(m as Map<String, dynamic>)
      ];

  Future<Mission> missionRespond(String id, bool accept) async => Mission.fromJson(
      await call('POST', '/missions/$id/${accept ? 'accept' : 'decline'}') as Map<String, dynamic>);

  Future<Timelapse> timelapse(MapFilters f, {required String step, String? bbox}) async =>
      Timelapse.fromJson(await call('GET', '/map/timelapse', query: {
        ...f.timeQuery(),
        'step': step,
        'include_indicative': f.includeIndicative,
        if (bbox != null) 'bbox': bbox,
      }) as Map<String, dynamic>);

  Future<FieldGrid> fieldGrid(MapFilters f, String bbox) async =>
      FieldGrid.fromJson(await call('GET', '/map/field', query: {
        ...f.timeQuery(),
        'include_indicative': f.includeIndicative,
        'bbox': bbox,
      }) as Map<String, dynamic>);

  Future<Impact> myImpact({String period = '30d'}) async =>
      Impact.fromJson(await call('GET', '/users/me/impact', query: {'period': period}) as Map<String, dynamic>);

  // ------------------------------------------------------------------ comptes
  /// Inscription complète : renvoie la réponse (dont `recovery_codes`, affichés une seule fois).
  Future<Map<String, dynamic>> registerAccount(Map<String, dynamic> payload) async =>
      await call('POST', '/auth/register', data: payload) as Map<String, dynamic>;

  Future<void> resetPassword(String email, String code, String newPassword) => call(
      'POST', '/auth/password/reset',
      data: {'email': email, 'recovery_code': code, 'new_password': newPassword});

  Future<void> changePassword(String current, String next) =>
      call('POST', '/auth/password/change', data: {'current_password': current, 'new_password': next});

  Future<List<String>> regenerateRecoveryCodes(String password) async =>
      (await call('POST', '/auth/recovery-codes', data: {'password': password}) as List).cast<String>();

  Future<void> logoutAll() => call('POST', '/auth/logout-all');

  Future<AccountProfile> accountMe() async =>
      AccountProfile.fromJson(await call('GET', '/account/me') as Map<String, dynamic>);

  Future<AccountProfile> accountUpdate(Map<String, dynamic> body) async =>
      AccountProfile.fromJson(await call('PATCH', '/account/me', data: body) as Map<String, dynamic>);

  Future<Connections> connections() async =>
      Connections.fromJson(await call('GET', '/account/connections') as Map<String, dynamic>);

  Future<List<Invitation>> invitations() async => [
        for (final i in await call('GET', '/account/invitations') as List)
          Invitation.fromJson((i as Map).cast<String, dynamic>())
      ];

  Future<Invitation> createInvitation() async =>
      Invitation.fromJson(await call('POST', '/account/invitations') as Map<String, dynamic>);

  Future<void> revokeInvitation(String id) => call('DELETE', '/account/invitations/$id');

  // ------------------------------------------------------------------ classement
  Future<LeaderBoard> leaderboard(String period, {int limit = 30}) async => LeaderBoard.fromJson(
      await call('GET', '/leaderboard', query: {'period': period, 'limit': limit}) as Map<String, dynamic>);

  Future<MyBoard> myBoard() async => MyBoard.fromJson(await call('GET', '/leaderboard/me') as Map<String, dynamic>);

  // ------------------------------------------------------------------ analyseur / avis
  Future<AnalystState> analystMe() async =>
      AnalystState.fromJson(await call('GET', '/analyst/me') as Map<String, dynamic>);

  Future<void> analystSet(bool enable) => call('POST', enable ? '/analyst/enable' : '/analyst/disable');

  Future<int> presence(double lat, double lon) async =>
      ((await call('POST', '/presence', data: {'latitude': lat, 'longitude': lon}) as Map)['pending'] as num).toInt();

  Future<List<ReviewRequest>> reviewsPending() async => [
        for (final r in await call('GET', '/reviews/pending') as List)
          ReviewRequest.fromJson((r as Map).cast<String, dynamic>())
      ];

  // ------------------------------------------------------------------ routes
  Future<Map<String, RoadState>> roadStates(MapFilters f, String bbox, double zoom, int rank) async {
    final d = await call('GET', '/roads/state', query: {
      ...f.timeQuery(),
      'include_indicative': f.includeIndicative,
      'bbox': bbox,
      'zoom': zoom,
      'max_rank': rank,
    }) as Map<String, dynamic>;
    final segs = (d['segments'] as Map).cast<String, dynamic>();
    return {for (final e in segs.entries) e.key: RoadState.fromJson((e.value as Map).cast<String, dynamic>())};
  }

  Future<RoadDetail> roadSegment(String id, MapFilters f) async => RoadDetail.fromJson(await call(
      'GET', '/roads/segments/$id',
      query: {...f.timeQuery(), 'include_indicative': f.includeIndicative}) as Map<String, dynamic>);

  /// Itinéraire réel (par les routes) vers le point cible d'une mission.
  Future<MissionRoute> missionRoute(String id, double lat, double lon, {String mode = 'car'}) async =>
      MissionRoute.fromJson(await call('GET', '/missions/$id/route',
          query: {'o_lat': lat, 'o_lon': lon, 'mode': mode}) as Map<String, dynamic>);

  // ------------------------------------------------------------------ guide
  Future<Map<String, dynamic>> guide() async => await call('GET', '/guide') as Map<String, dynamic>;

  Future<void> reviewVote(String id, String vote, bool strong) =>
      call('POST', '/reviews/$id/vote', data: {'vote': vote, 'strong': strong});

  Future<List<ReviewHistoryItem>> reviewsHistory() async => [
        for (final r in await call('GET', '/reviews/history') as List)
          ReviewHistoryItem.fromJson((r as Map).cast<String, dynamic>())
      ];
}