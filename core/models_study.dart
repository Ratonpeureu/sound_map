import 'package:flutter/material.dart';

double _n(dynamic v) => (v as num).toDouble();
double? _nn(dynamic v) => (v as num?)?.toDouble();
int? _ni(dynamic v) => (v as num?)?.toInt();
DateTime? _t(dynamic v) => v == null ? null : DateTime.parse(v as String).toLocal();
Map<String, dynamic> _m(dynamic v) => (v as Map).cast<String, dynamic>();
List<Map<String, dynamic>> _ml(dynamic v) => [for (final x in (v as List? ?? const [])) _m(x)];
List<String> _ls(dynamic v) => [for (final x in (v as List? ?? const [])) x.toString()];

// ============================================================================ médias
class StudyMedia {
  StudyMedia({this.assetId, this.url, this.kind = 'image', this.caption});
  final String? assetId, url, caption;
  final String kind;
  bool get isVideo => kind == 'video';
  factory StudyMedia.fromJson(Map<String, dynamic> j) => StudyMedia(
      assetId: j['asset_id'] as String?, url: j['url'] as String?, kind: (j['kind'] as String?) ?? 'image', caption: j['caption'] as String?);
}

List<StudyMedia> _media(dynamic v) => [for (final x in _ml(v)) StudyMedia.fromJson(x)];

// ============================================================================ questionnaire dynamique
class StudyOption {
  StudyOption({required this.value, required this.label, this.media, this.exclusive = false, this.other = false});
  final String value, label;
  final StudyMedia? media;
  final bool exclusive, other;
  factory StudyOption.fromJson(Map<String, dynamic> j) => StudyOption(
      value: j['value'].toString(),
      label: (j['label'] as String?) ?? j['value'].toString(),
      media: j['media'] == null ? null : StudyMedia.fromJson(_m(j['media'])),
      exclusive: (j['exclusive'] as bool?) ?? false,
      other: (j['other'] as bool?) ?? false);
}

class StudyItem {
  StudyItem({required this.key, required this.label, this.description, this.media = const []});
  final String key, label;
  final String? description;
  final List<StudyMedia> media;
  factory StudyItem.fromJson(Map<String, dynamic> j) => StudyItem(
      key: j['key'].toString(), label: j['label'] as String, description: j['description'] as String?, media: _media(j['media']));
}

typedef StudyRule = ({String q, String op, dynamic value});

class StudyCond {
  StudyCond(this.mode, this.rules);
  final String mode;
  final List<StudyRule> rules;
  factory StudyCond.fromJson(Map<String, dynamic> j) => StudyCond(
      (j['mode'] as String?) ?? 'all', [for (final r in _ml(j['rules'])) (q: r['q'] as String, op: r['op'] as String, value: r['value'])]);
}

bool _eq(dynamic a, dynamic b) => a is num && b is num ? a == b : a == b;

bool _atom(StudyRule r, Map<String, dynamic> a) {
  final v = a[r.q];
  if (r.op == 'answered') return v != null;
  if (r.op == 'not_answered') return v == null;
  if (v == null) return false;
  final ref = r.value;
  switch (r.op) {
    case 'eq':
      return _eq(v, ref);
    case 'ne':
      return !_eq(v, ref);
    case 'in':
    case 'nin':
      final vs = v is List ? v : [v];
      final rs = ref is List ? ref : [ref];
      final hit = vs.any((x) => rs.any((y) => _eq(x, y)));
      return r.op == 'in' ? hit : !hit;
    case 'has':
      return v is List && v.any((x) => _eq(x, ref));
    case 'has_any':
      return v is List && (ref as List).any((y) => v.any((x) => _eq(x, y)));
    default:
      final x = num.tryParse('$v'), y = num.tryParse('$ref');
      if (x == null || y == null) return false;
      return switch (r.op) { 'gt' => x > y, 'gte' => x >= y, 'lt' => x < y, 'lte' => x <= y, _ => false };
  }
}

/// Même logique d'affichage conditionnel que le serveur.
bool condOk(StudyCond? c, Map<String, dynamic> a) {
  if (c == null) return true;
  final res = [for (final r in c.rules) _atom(r, a)];
  return c.mode == 'all' ? res.every((x) => x) : res.any((x) => x);
}

const answerableKinds = {
  'single_choice', 'multi_choice', 'yes_no', 'number', 'slider', 'scale', 'stars', 'nps', 'text', 'long_text',
  'ranking', 'matrix', 'date', 'product_rating'
};

class StudyBlock {
  StudyBlock({
    required this.key,
    required this.kind,
    this.text,
    this.help,
    this.required = true,
    this.media = const [],
    this.options = const [],
    this.rows = const [],
    this.items = const [],
    this.criteria = const [],
    this.min,
    this.max,
    this.step,
    this.integer = false,
    this.unit,
    this.lowLabel,
    this.highLabel,
    this.minSelect,
    this.maxSelect,
    this.minLength,
    this.maxLength,
    this.display,
    this.randomize = false,
    this.topN,
    this.allowComment = false,
    this.placeholder,
    this.showIf,
    this.screening = false,
  });
  final String key, kind;
  final String? text, help, unit, lowLabel, highLabel, display, placeholder;
  final bool required, integer, randomize, allowComment, screening;
  final List<StudyMedia> media;
  final List<StudyOption> options, rows, criteria;
  final List<StudyItem> items;
  final double? min, max, step;
  final int? minSelect, maxSelect, minLength, maxLength, topN;
  final StudyCond? showIf;

  bool get answerable => answerableKinds.contains(kind);

  factory StudyBlock.fromJson(Map<String, dynamic> j) => StudyBlock(
        key: j['key'] as String,
        kind: j['kind'] as String,
        text: j['text'] as String?,
        help: j['help'] as String?,
        required: (j['required'] as bool?) ?? true,
        media: _media(j['media']),
        options: [for (final o in _ml(j['options'])) StudyOption.fromJson(o)],
        rows: [for (final o in _ml(j['rows'])) StudyOption.fromJson(o)],
        items: [for (final o in _ml(j['items'])) StudyItem.fromJson(o)],
        criteria: [for (final o in _ml(j['criteria'])) StudyOption.fromJson(o)],
        min: _nn(j['min']),
        max: _nn(j['max']),
        step: _nn(j['step']),
        integer: (j['integer'] as bool?) ?? false,
        unit: j['unit'] as String?,
        lowLabel: j['low_label'] as String?,
        highLabel: j['high_label'] as String?,
        minSelect: _ni(j['min_select']),
        maxSelect: _ni(j['max_select']),
        minLength: _ni(j['min_length']),
        maxLength: _ni(j['max_length']),
        display: j['display'] as String?,
        randomize: (j['randomize'] as bool?) ?? false,
        topN: _ni(j['top_n']),
        allowComment: (j['allow_comment'] as bool?) ?? false,
        placeholder: j['placeholder'] as String?,
        showIf: j['show_if'] == null ? null : StudyCond.fromJson(_m(j['show_if'])),
        screening: j['screening'] == true,
      );
}

class StudyPage {
  StudyPage({required this.key, required this.blocks, this.title, this.description, this.showIf});
  final String key;
  final String? title, description;
  final List<StudyBlock> blocks;
  final StudyCond? showIf;
  factory StudyPage.fromJson(Map<String, dynamic> j) => StudyPage(
      key: j['key'] as String,
      title: j['title'] as String?,
      description: j['description'] as String?,
      blocks: [for (final b in _ml(j['blocks'])) StudyBlock.fromJson(b)],
      showIf: j['show_if'] == null ? null : StudyCond.fromJson(_m(j['show_if'])));
}

class StudyIntro {
  StudyIntro({this.title, this.text, this.media = const []});
  final String? title, text;
  final List<StudyMedia> media;
  factory StudyIntro.fromJson(Map<String, dynamic> j) =>
      StudyIntro(title: j['title'] as String?, text: j['text'] as String?, media: _media(j['media']));
}

class StudyDef {
  StudyDef({required this.pages, this.intro, this.outro, this.showProgress = true, this.allowBack = true});
  final List<StudyPage> pages;
  final StudyIntro? intro, outro;
  final bool showProgress, allowBack;
  factory StudyDef.fromJson(Map<String, dynamic> j) => StudyDef(
        pages: [for (final p in _ml(j['pages'])) StudyPage.fromJson(p)],
        intro: j['intro'] == null ? null : StudyIntro.fromJson(_m(j['intro'])),
        outro: j['outro'] == null ? null : StudyIntro.fromJson(_m(j['outro'])),
        showProgress: (j['show_progress'] as bool?) ?? true,
        allowBack: (j['allow_back'] as bool?) ?? true,
      );
}

// ============================================================================ initiateur, récompense, fiche
class SponsorBrief {
  SponsorBrief({required this.id, required this.name, required this.kind, required this.kindLabel, required this.verified, this.logoAssetId, this.sector});
  final String id, name, kind, kindLabel;
  final bool verified;
  final String? logoAssetId, sector;
  factory SponsorBrief.fromJson(Map<String, dynamic> j) => SponsorBrief(
      id: j['id'] as String,
      name: j['name'] as String,
      kind: j['kind'] as String,
      kindLabel: (j['kind_label'] as String?) ?? '',
      verified: (j['verified'] as bool?) ?? false,
      logoAssetId: j['logo_asset_id'] as String?,
      sector: j['sector'] as String?);
}

class SponsorFull {
  SponsorFull({required this.brief, required this.activities, required this.facts, required this.studiesCount, this.tagline, this.description, this.city, this.country, this.website, this.contactPublic, this.coverAssetId, this.memberSince});
  final SponsorBrief brief;
  final List<String> activities;
  final Map<String, String> facts;
  final int studiesCount;
  final String? tagline, description, city, country, website, contactPublic, coverAssetId;
  final DateTime? memberSince;
  factory SponsorFull.fromJson(Map<String, dynamic> j) => SponsorFull(
        brief: SponsorBrief.fromJson(j),
        tagline: j['tagline'] as String?,
        description: j['description'] as String?,
        city: j['city'] as String?,
        country: j['country'] as String?,
        website: j['website'] as String?,
        contactPublic: j['contact_public'] as String?,
        coverAssetId: j['cover_asset_id'] as String?,
        activities: _ls(j['activities']),
        facts: (j['facts'] as Map? ?? {}).map((k, v) => MapEntry(k.toString(), v.toString())),
        studiesCount: _ni(j['studies_count']) ?? 0,
        memberSince: _t(j['member_since']),
      );
}

class RewardCard {
  RewardCard({required this.enabled, required this.kind, required this.mode, required this.headline, required this.validation, required this.requiresContact, this.kindLabel, this.label});
  final bool enabled, requiresContact;
  final String kind, mode, headline, validation;
  final String? kindLabel, label;
  bool get lottery => mode == 'lottery';
  factory RewardCard.fromJson(Map<String, dynamic> j) => RewardCard(
      enabled: (j['enabled'] as bool?) ?? false,
      kind: (j['kind'] as String?) ?? 'points',
      kindLabel: j['kind_label'] as String?,
      mode: (j['mode'] as String?) ?? 'guaranteed',
      label: j['label'] as String?,
      headline: (j['headline'] as String?) ?? '',
      validation: (j['validation'] as String?) ?? 'auto',
      requiresContact: (j['requires_contact'] as bool?) ?? false);
}

class StudyCard {
  StudyCard({
    required this.id,
    required this.title,
    required this.kind,
    required this.kindLabel,
    required this.sponsor,
    required this.reward,
    required this.estimatedMinutes,
    required this.tags,
    required this.invited,
    required this.why,
    this.summary,
    this.coverAssetId,
    this.startsAt,
    this.endsAt,
    this.quotaLeft,
    this.participationStatus,
  });
  final String id, title, kind, kindLabel;
  final String? summary, coverAssetId, participationStatus;
  final SponsorBrief sponsor;
  final RewardCard reward;
  final int estimatedMinutes;
  final int? quotaLeft;
  final DateTime? startsAt, endsAt;
  final List<String> tags, why;
  final bool invited;
  factory StudyCard.fromJson(Map<String, dynamic> j) => StudyCard(
        id: j['id'] as String,
        title: j['title'] as String,
        summary: j['summary'] as String?,
        kind: j['kind'] as String,
        kindLabel: (j['kind_label'] as String?) ?? '',
        sponsor: SponsorBrief.fromJson(_m(j['sponsor'])),
        coverAssetId: j['cover_asset_id'] as String?,
        estimatedMinutes: _ni(j['estimated_minutes']) ?? 5,
        startsAt: _t(j['starts_at']),
        endsAt: _t(j['ends_at']),
        tags: _ls(j['tags']),
        quotaLeft: _ni(j['quota_left']),
        reward: RewardCard.fromJson(_m(j['reward'] ?? {'enabled': false})),
        invited: (j['invited'] as bool?) ?? false,
        why: _ls(j['why']),
        participationStatus: j['participation_status'] as String?,
      );
}

typedef RuleSection = ({String title, String icon, List<String> items});

List<RuleSection> _rules(dynamic v) =>
    [for (final r in _ml(v)) (title: r['title'] as String, icon: (r['icon'] as String?) ?? '', items: _ls(r['items']))];

class StudyDetail {
  StudyDetail({required this.card, required this.version, required this.rules, required this.definition, required this.collectContact, required this.sponsor, this.description, this.terms, this.contactLabel, this.contactPurpose, this.startedAt});
  final StudyCard card;
  final int version;
  final List<RuleSection> rules;
  final StudyDef definition;
  final bool collectContact;
  final SponsorFull sponsor;
  final String? description, terms, contactLabel, contactPurpose;
  final DateTime? startedAt;
  String get id => card.id;
  String get title => card.title;
  factory StudyDetail.fromJson(Map<String, dynamic> j) => StudyDetail(
        card: StudyCard.fromJson(j),
        description: j['description'] as String?,
        terms: j['terms'] as String?,
        version: _ni(j['version']) ?? 1,
        rules: _rules(j['rules']),
        definition: StudyDef.fromJson(_m(j['definition'])),
        collectContact: (j['collect_contact'] as bool?) ?? false,
        contactLabel: j['contact_label'] as String?,
        contactPurpose: j['contact_purpose'] as String?,
        sponsor: SponsorFull.fromJson(_m(j['sponsor_full'])),
        startedAt: _t(j['started_at']),
      );
}

// ============================================================================ récompenses, participations
class RewardItem {
  RewardItem({required this.id, required this.studyId, required this.status, required this.statusLabel, required this.kind, required this.label, required this.amount, required this.headline, required this.needsClaim, this.studyTitle, this.sponsorName, this.kindLabel, this.unit, this.score, this.reasonCode, this.reasonLabel, this.reasonText, this.code, this.claimDeadlineAt, this.validUntil, this.deliveredAt, this.createdAt, this.note, this.mode});
  final String id, studyId, status, statusLabel, kind, label, headline;
  final String? studyTitle, sponsorName, kindLabel, unit, reasonCode, reasonLabel, reasonText, code, note, mode;
  final double amount;
  final double? score;
  final bool needsClaim;
  final DateTime? claimDeadlineAt, validUntil, deliveredAt, createdAt;
  factory RewardItem.fromJson(Map<String, dynamic> j) => RewardItem(
        id: j['id'] as String,
        studyId: j['study_id'] as String,
        studyTitle: j['study_title'] as String?,
        sponsorName: j['sponsor_name'] as String?,
        status: j['status'] as String,
        statusLabel: (j['status_label'] as String?) ?? j['status'] as String,
        kind: j['kind'] as String,
        kindLabel: j['kind_label'] as String?,
        label: (j['label'] as String?) ?? '',
        amount: _n(j['amount'] ?? 0),
        unit: j['unit'] as String?,
        mode: j['mode'] as String?,
        headline: (j['headline'] as String?) ?? (j['label'] as String? ?? ''),
        score: _nn(j['score']),
        reasonCode: j['reason_code'] as String?,
        reasonLabel: j['reason_label'] as String?,
        reasonText: j['reason_text'] as String?,
        code: j['code'] as String?,
        needsClaim: (j['needs_claim'] as bool?) ?? false,
        claimDeadlineAt: _t(j['claim_deadline_at']),
        validUntil: _t(j['valid_until']),
        deliveredAt: _t(j['delivered_at']),
        createdAt: _t(j['created_at']),
        note: j['note'] as String?,
      );
}

class RewardsData {
  RewardsData(this.summary, this.items);
  final Map<String, num> summary;
  final List<RewardItem> items;
  num s(String k) => summary[k] ?? 0;
  factory RewardsData.fromJson(Map<String, dynamic> j) => RewardsData(
      (j['summary'] as Map).map((k, v) => MapEntry(k.toString(), v as num)), [for (final r in _ml(j['items'])) RewardItem.fromJson(r)]);
}

class RewardDetail {
  RewardDetail({required this.item, required this.rules, this.contactLabel, this.phone, this.instructions});
  final RewardItem item;
  final List<RuleSection> rules;
  final String? contactLabel, phone, instructions;
  factory RewardDetail.fromJson(Map<String, dynamic> j) => RewardDetail(
      item: RewardItem.fromJson(j), rules: _rules(j['rules']), contactLabel: j['contact_label'] as String?, phone: j['phone'] as String?, instructions: j['instructions'] as String?);
}

class StudyAck {
  StudyAck({required this.id, required this.status, required this.outcome, required this.screenedOut, required this.duplicate, required this.reasons, this.score, this.message, this.reward});
  final String id, status, outcome;
  final bool screenedOut, duplicate;
  final double? score;
  final String? message;
  final RewardItem? reward;
  final List<String> reasons;
  factory StudyAck.fromJson(Map<String, dynamic> j) => StudyAck(
        id: j['id'] as String,
        status: j['status'] as String,
        outcome: (j['outcome'] as String?) ?? 'completed',
        screenedOut: (j['screened_out'] as bool?) ?? false,
        duplicate: (j['duplicate'] as bool?) ?? false,
        score: _nn(j['score']),
        message: j['message'] as String?,
        reward: j['reward'] == null ? null : RewardItem.fromJson(_m({'study_id': '', ...(j['reward'] as Map).cast<String, dynamic>()})),
        reasons: _ls(j['reasons']),
      );
}

class StudyParticipation {
  StudyParticipation({required this.studyId, required this.title, required this.kindLabel, required this.sponsor, required this.status, this.startedAt, this.finishedAt, this.endsAt, this.reward});
  final String studyId, title, kindLabel, status;
  final SponsorBrief sponsor;
  final DateTime? startedAt, finishedAt, endsAt;
  final RewardItem? reward;
  factory StudyParticipation.fromJson(Map<String, dynamic> j) => StudyParticipation(
        studyId: j['study_id'] as String,
        title: j['title'] as String,
        kindLabel: (j['kind_label'] as String?) ?? '',
        sponsor: SponsorBrief.fromJson(_m(j['sponsor'])),
        status: j['status'] as String,
        startedAt: _t(j['started_at']),
        finishedAt: _t(j['finished_at']),
        endsAt: _t(j['ends_at']),
        reward: j['reward'] == null ? null : RewardItem.fromJson(_m(j['reward'])),
      );
}

class StudyProfile {
  StudyProfile({this.gender, this.occupationGroup, this.educationLevel, this.householdSize, this.incomeBand, this.languages = const [], this.interests = const []});
  String? gender, occupationGroup, educationLevel, incomeBand;
  int? householdSize;
  List<String> languages, interests;
  factory StudyProfile.fromJson(Map<String, dynamic> j) => StudyProfile(
      gender: j['gender'] as String?,
      occupationGroup: j['occupation_group'] as String?,
      educationLevel: j['education_level'] as String?,
      householdSize: _ni(j['household_size']),
      incomeBand: j['income_band'] as String?,
      languages: _ls(j['languages']),
      interests: _ls(j['interests']));
  Map<String, dynamic> toJson() => {
        'gender': gender,
        'occupation_group': occupationGroup,
        'education_level': educationLevel,
        'household_size': householdSize,
        'income_band': incomeBand,
        'languages': languages,
        'interests': interests,
      };
}

// ============================================================================ libellés et couleurs
String studyReasonLabel(String c) => switch (c) {
      'too_fast' => 'Réponses données beaucoup trop vite',
      'fast_answer' => 'Rythme de réponse rapide',
      'straight_lining' => 'Mêmes notes partout',
      'text_low_effort' => 'Réponses libres peu détaillées',
      'copy_pattern' => 'Réponses libres copiées',
      'attention_failed' => 'Question de contrôle manquée',
      'new_participant' => 'Nouveau participant',
      'low_score' => 'Score global trop bas',
      'admin_override' => "Décision de l'organisateur",
      'screened_out' => 'Hors cible',
      _ => c,
    };

Color rewardStatusColor(String s) => switch (s) {
      'delivered' || 'granted' => const Color(0xFF22C55E),
      'pending' || 'entered' => const Color(0xFFF59E0B),
      'refused' || 'revoked' => const Color(0xFFEF4444),
      _ => const Color(0xFF94A3B8),
    };

IconData rewardKindIcon(String k) => switch (k) {
      'points' => Icons.stars_rounded,
      'credits' => Icons.bolt_rounded,
      'voucher' => Icons.confirmation_number_rounded,
      'cash' => Icons.payments_rounded,
      'airtime' => Icons.phone_android_rounded,
      'product' => Icons.redeem_rounded,
      _ => Icons.card_giftcard_rounded,
    };

IconData ruleIcon(String n) => switch (n) {
      'card_giftcard' => Icons.card_giftcard_rounded,
      'task_alt' => Icons.task_alt_rounded,
      'block' => Icons.block_rounded,
      'report' => Icons.report_gmailerrorred_rounded,
      'local_shipping' => Icons.local_shipping_rounded,
      'lock' => Icons.lock_rounded,
      _ => Icons.info_outline_rounded,
    };