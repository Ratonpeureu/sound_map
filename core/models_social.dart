double _n(dynamic v) => (v as num).toDouble();
DateTime? _t(dynamic v) => v == null ? null : DateTime.parse(v as String).toLocal();

class Level {
  Level({required this.index, required this.name, required this.xp, required this.progress, this.nextXp});
  final int index, xp;
  final String name;
  final int? nextXp;
  final double progress;
  factory Level.fromJson(Map<String, dynamic> j) => Level(
      index: (j['index'] as num).toInt(),
      name: j['name'] as String,
      xp: (j['xp'] as num).toInt(),
      nextXp: (j['next_xp'] as num?)?.toInt(),
      progress: _n(j['progress']));
}

class AccountProfile {
  AccountProfile({
    required this.displayName,
    required this.showInLeaderboard,
    required this.analystEnabled,
    required this.level,
    this.firstName,
    this.lastName,
    this.phone,
    this.city,
    this.district,
    this.birthYear,
    this.memberSince,
  });
  final String displayName;
  final String? firstName, lastName, phone, city, district;
  final int? birthYear;
  final bool showInLeaderboard, analystEnabled;
  final DateTime? memberSince;
  final Level level;
  factory AccountProfile.fromJson(Map<String, dynamic> j) => AccountProfile(
        displayName: j['display_name'] as String,
        firstName: j['first_name'] as String?,
        lastName: j['last_name'] as String?,
        phone: j['phone'] as String?,
        city: j['city'] as String?,
        district: j['district'] as String?,
        birthYear: (j['birth_year'] as num?)?.toInt(),
        showInLeaderboard: j['show_in_leaderboard'] as bool,
        analystEnabled: j['analyst_enabled'] as bool,
        memberSince: _t(j['member_since']),
        level: Level.fromJson(j['level'] as Map<String, dynamic>),
      );
}

class BadgeInfo {
  BadgeInfo({required this.code, required this.label, required this.description, required this.icon, required this.tier, required this.earned, this.awardedAt});
  final String code, label, description, icon;
  final int tier;
  final bool earned;
  final DateTime? awardedAt;
  factory BadgeInfo.fromJson(Map<String, dynamic> j) => BadgeInfo(
      code: j['code'] as String,
      label: j['label'] as String,
      description: j['description'] as String,
      icon: j['icon'] as String,
      tier: (j['tier'] as num).toInt(),
      earned: j['earned'] as bool,
      awardedAt: _t(j['awarded_at']));
}

class PeriodScore {
  PeriodScore({required this.rank, required this.score, required this.reliability, required this.components});
  final int rank;
  final double score, reliability;
  final Map<String, dynamic> components;
  factory PeriodScore.fromJson(Map<String, dynamic> j) => PeriodScore(
      rank: (j['rank'] as num).toInt(),
      score: _n(j['score']),
      reliability: _n(j['reliability']),
      components: (j['components'] as Map).cast<String, dynamic>());
  num comp(String k) => (components[k] as num?) ?? 0;
}

class MyBoard {
  MyBoard({required this.level, required this.periods, required this.badges, required this.history});
  final Level level;
  final Map<String, PeriodScore?> periods;
  final List<BadgeInfo> badges;
  final List<({DateTime date, int rank, double score})> history;
  factory MyBoard.fromJson(Map<String, dynamic> j) => MyBoard(
        level: Level.fromJson(j['level'] as Map<String, dynamic>),
        periods: (j['periods'] as Map).map((k, v) => MapEntry(k as String, v == null ? null : PeriodScore.fromJson((v as Map).cast<String, dynamic>()))),
        badges: [for (final b in j['badges'] as List) BadgeInfo.fromJson((b as Map).cast<String, dynamic>())],
        history: [for (final h in j['history'] as List) (date: DateTime.parse(h['date'] as String), rank: (h['rank'] as num).toInt(), score: _n(h['score']))],
      );
}

class LeaderEntry {
  LeaderEntry({required this.rank, required this.name, required this.level, required this.score, required this.reliability, required this.isMe, required this.badges, required this.validated, required this.missions, required this.days, this.delta});
  final int rank, validated, missions, days;
  final String name;
  final Level level;
  final double score, reliability;
  final int? delta;
  final bool isMe;
  final List<String> badges;
  factory LeaderEntry.fromJson(Map<String, dynamic> j) => LeaderEntry(
        rank: (j['rank'] as num).toInt(),
        name: j['display_name'] as String,
        level: Level.fromJson(j['level'] as Map<String, dynamic>),
        score: _n(j['score']),
        reliability: _n(j['reliability']),
        delta: (j['delta'] as num?)?.toInt(),
        isMe: j['is_me'] as bool,
        badges: (j['badges'] as List).cast<String>(),
        validated: (j['validated'] as num).toInt(),
        missions: (j['missions'] as num).toInt(),
        days: (j['days'] as num).toInt(),
      );
}

class LeaderBoard {
  LeaderBoard({required this.kind, required this.label, required this.total, required this.entries, required this.around, this.me});
  final String kind, label;
  final int total;
  final List<LeaderEntry> entries, around;
  final LeaderEntry? me;
  factory LeaderBoard.fromJson(Map<String, dynamic> j) => LeaderBoard(
        kind: j['kind'] as String,
        label: j['label'] as String,
        total: (j['total'] as num).toInt(),
        entries: [for (final e in j['entries'] as List) LeaderEntry.fromJson((e as Map).cast<String, dynamic>())],
        around: [for (final e in j['around'] as List) LeaderEntry.fromJson((e as Map).cast<String, dynamic>())],
        me: j['me'] == null ? null : LeaderEntry.fromJson((j['me'] as Map).cast<String, dynamic>()),
      );
}

class Connections {
  Connections({required this.events, required this.sessions, required this.devices, this.lastLoginAt});
  final DateTime? lastLoginAt;
  final List<({DateTime? at, bool success, String platform})> events;
  final List<({DateTime? created, DateTime? lastUsed, String platform})> sessions;
  final List<({String name, String android, DateTime? lastSeen})> devices;
  factory Connections.fromJson(Map<String, dynamic> j) => Connections(
        lastLoginAt: _t(j['last_login_at']),
        events: [for (final e in j['events'] as List) (at: _t(e['at']), success: e['success'] as bool, platform: (e['platform'] as String?) ?? '—')],
        sessions: [for (final s in j['sessions'] as List) (created: _t(s['created']), lastUsed: _t(s['last_used']), platform: (s['platform'] as String?) ?? '—')],
        devices: [for (final d in j['devices'] as List) (name: '${d['manufacturer']} ${d['model']}', android: '${d['android_version']}', lastSeen: _t(d['last_seen_at']))],
      );
}

class Invitation {
  Invitation({required this.id, required this.code, required this.uses, required this.maxUses, required this.active, this.expiresAt});
  final String id, code;
  final int uses, maxUses;
  final bool active;
  final DateTime? expiresAt;
  factory Invitation.fromJson(Map<String, dynamic> j) => Invitation(
      id: j['id'] as String,
      code: j['code'] as String,
      uses: (j['uses'] as num).toInt(),
      maxUses: (j['max_uses'] as num).toInt(),
      active: j['active'] as bool,
      expiresAt: _t(j['expires_at']));
}

class Criterion {
  Criterion({required this.label, required this.value, required this.required, required this.ok, required this.reverse});
  final String label;
  final num value, required;
  final bool ok, reverse;
  factory Criterion.fromJson(Map<String, dynamic> j) => Criterion(
      label: j['label'] as String, value: j['value'] as num, required: j['required'] as num, ok: j['ok'] as bool, reverse: j['reverse'] as bool);
}

class AnalystState {
  AnalystState({required this.enabled, required this.eligible, required this.criteria, required this.votes, required this.matched, required this.agreement, this.suspendedUntil});
  final bool enabled, eligible;
  final DateTime? suspendedUntil;
  final List<Criterion> criteria;
  final int votes, matched;
  final double agreement;
  bool get suspended => suspendedUntil != null && suspendedUntil!.isAfter(DateTime.now());
  factory AnalystState.fromJson(Map<String, dynamic> j) {
    final e = j['eligibility'] as Map<String, dynamic>, s = j['stats'] as Map<String, dynamic>;
    return AnalystState(
      enabled: j['enabled'] as bool,
      suspendedUntil: _t(j['suspended_until']),
      eligible: e['eligible'] as bool,
      criteria: [for (final c in e['criteria'] as List) Criterion.fromJson((c as Map).cast<String, dynamic>())],
      votes: (s['votes'] as num).toInt(),
      matched: (s['matched'] as num).toInt(),
      agreement: _n(s['agreement']),
    );
  }
}

class ReviewRequest {
  ReviewRequest({required this.id, required this.levelDb, required this.distanceM, required this.measuredAt, required this.expiresAt});
  final String id;
  final double levelDb, distanceM;
  final DateTime measuredAt, expiresAt;
  factory ReviewRequest.fromJson(Map<String, dynamic> j) => ReviewRequest(
      id: j['id'] as String,
      levelDb: _n(j['level_db']),
      distanceM: _n(j['distance_m']),
      measuredAt: _t(j['measured_at'])!,
      expiresAt: _t(j['expires_at'])!);
}

class ReviewHistoryItem {
  ReviewHistoryItem({required this.id, required this.levelDb, required this.status, this.vote, this.strong = false, this.outcome, this.matched, this.votedAt});
  final String id, status;
  final String? vote, outcome;
  final bool strong;
  final bool? matched;
  final double levelDb;
  final DateTime? votedAt;
  factory ReviewHistoryItem.fromJson(Map<String, dynamic> j) => ReviewHistoryItem(
      id: j['id'] as String,
      levelDb: _n(j['level_db']),
      status: j['status'] as String,
      vote: j['vote'] as String?,
      strong: j['strong'] as bool,
      outcome: j['outcome'] as String?,
      matched: j['matched'] as bool?,
      votedAt: _t(j['voted_at']));
}