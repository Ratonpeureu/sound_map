import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

double _n(dynamic v) => (v as num).toDouble();
double? _nn(dynamic v) => (v as num?)?.toDouble();
DateTime? _t(dynamic v) => v == null ? null : DateTime.parse(v as String).toLocal();

Color hexColor(dynamic v, [Color fallback = const Color(0xFF0E9F9A)]) {
  if (v is! String || !v.startsWith('#') || v.length != 7) return fallback;
  final n = int.tryParse(v.substring(1), radix: 16);
  return n == null ? fallback : Color(0xFF000000 | n);
}

IconData domainIcon(String? n) => switch (n) {
      'groups' => Icons.groups_rounded,
      'home' => Icons.home_rounded,
      'apartment' => Icons.apartment_rounded,
      'work' => Icons.work_rounded,
      'storefront' => Icons.storefront_rounded,
      'agriculture' => Icons.agriculture_rounded,
      'school' => Icons.school_rounded,
      'local_hospital' => Icons.local_hospital_rounded,
      'payments' => Icons.payments_rounded,
      'flight_takeoff' => Icons.flight_takeoff_rounded,
      'diversity_1' => Icons.diversity_1_rounded,
      'devices' => Icons.devices_rounded,
      _ => Icons.dataset_rounded,
    };

const catPalette = <Color>[
  Color(0xFF0E9F9A), Color(0xFFF59E0B), Color(0xFF7C3AED), Color(0xFFDB2777), Color(0xFF2563EB),
  Color(0xFF16A34A), Color(0xFFEF4444), Color(0xFF0891B2), Color(0xFF84CC16), Color(0xFF475569),
];

Color catColor(String code, List<String> order) {
  final i = order.indexOf(code);
  return catPalette[(i < 0 ? code.hashCode.abs() : i) % catPalette.length];
}

// ============================================================================ CATALOGUE
class DataIndicator {
  DataIndicator({
    required this.key,
    required this.label,
    required this.kind,
    required this.unit,
    required this.lo,
    required this.hi,
    required this.multi,
    required this.sensitive,
    required this.polarity,
    required this.unitOf,
    required this.categories,
    this.viz,
  });
  final String key, label, kind, unit, unitOf;
  final double lo, hi;
  final bool multi, sensitive;
  final int polarity;
  final String? viz;
  final List<({String code, String label})> categories;

  factory DataIndicator.fromJson(Map<String, dynamic> j) => DataIndicator(
        key: j['key'] as String,
        label: j['label'] as String,
        kind: j['kind'] as String,
        unit: (j['unit'] as String?) ?? '',
        lo: _n(j['lo']),
        hi: _n(j['hi']),
        multi: (j['multi'] as bool?) ?? false,
        sensitive: (j['sensitive'] as bool?) ?? false,
        polarity: (j['polarity'] as num?)?.toInt() ?? 0,
        unitOf: (j['unit_of'] as String?) ?? 'household',
        viz: j['viz'] as String?,
        categories: [
          for (final c in (j['categories'] as List? ?? const [])) (code: c['code'] as String, label: c['label'] as String)
        ],
      );

  List<String> get catOrder => [for (final c in categories) c.code];
}

class DataDerived {
  DataDerived({required this.key, required this.label, required this.unit, this.viz});
  final String key, label, unit;
  final String? viz;
  factory DataDerived.fromJson(Map<String, dynamic> j) => DataDerived(
      key: j['key'] as String, label: j['label'] as String, unit: (j['unit'] as String?) ?? '', viz: j['viz'] as String?);
}

class DataDomain {
  DataDomain({
    required this.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.summary,
    required this.viz,
    required this.indicators,
    required this.derived,
  });
  final String key, label, icon, summary, viz;
  final Color color;
  final List<DataIndicator> indicators;
  final List<DataDerived> derived;

  factory DataDomain.fromJson(Map<String, dynamic> j) => DataDomain(
        key: j['key'] as String,
        label: j['label'] as String,
        icon: (j['icon'] as String?) ?? '',
        color: hexColor(j['color']),
        summary: (j['summary'] as String?) ?? '',
        viz: (j['viz'] as String?) ?? 'zones',
        indicators: [for (final i in j['indicators'] as List) DataIndicator.fromJson((i as Map).cast<String, dynamic>())],
        derived: [for (final i in (j['derived'] as List? ?? const [])) DataDerived.fromJson((i as Map).cast<String, dynamic>())],
      );

  DataIndicator? indicator(String k) {
    for (final i in indicators) {
      if (i.key == k) return i;
    }
    return null;
  }

  DataDerived? derivedOf(String k) {
    for (final i in derived) {
      if (i.key == k) return i;
    }
    return null;
  }
}

class DataCatalog {
  DataCatalog(this.domains);
  final List<DataDomain> domains;
  factory DataCatalog.fromJson(Map<String, dynamic> j) =>
      DataCatalog([for (final d in j['domains'] as List) DataDomain.fromJson((d as Map).cast<String, dynamic>())]);
  DataDomain? domain(String key) {
    for (final d in domains) {
      if (d.key == key) return d;
    }
    return null;
  }
}

class DataSummaryItem {
  DataSummaryItem({
    required this.key,
    required this.responses,
    required this.contributors,
    required this.zones,
    required this.activeSurveys,
    this.lastAt,
  });
  final String key;
  final int responses, contributors, zones, activeSurveys;
  final DateTime? lastAt;
  factory DataSummaryItem.fromJson(Map<String, dynamic> j) => DataSummaryItem(
        key: j['key'] as String,
        responses: (j['responses'] as num).toInt(),
        contributors: (j['contributors'] as num).toInt(),
        zones: (j['zones'] as num).toInt(),
        activeSurveys: (j['active_surveys'] as num).toInt(),
        lastAt: _t(j['last_at']),
      );
}

class DataSummary {
  DataSummary(this.days, this.items);
  final int days;
  final Map<String, DataSummaryItem> items;
  factory DataSummary.fromJson(Map<String, dynamic> j) => DataSummary(
        (j['period_days'] as num).toInt(),
        {
          for (final d in j['domains'] as List)
            (d as Map)['key'] as String: DataSummaryItem.fromJson(d.cast<String, dynamic>())
        },
      );
}

// ============================================================================ CARTE
class DataCategoryShare {
  DataCategoryShare(this.code, this.label, this.share);
  final String code, label;
  final double share; // 0..100
  factory DataCategoryShare.fromJson(Map<String, dynamic> j) =>
      DataCategoryShare(j['code'] as String, j['label'] as String, _n(j['share']));
}

class DataFeature {
  DataFeature({
    required this.h3,
    required this.label,
    required this.polygon,
    required this.center,
    required this.value,
    required this.intensity,
    required this.confidence,
    required this.provedShare,
    required this.n,
    required this.contributors,
    required this.categories,
    this.lastAt,
    this.reference,
    this.deviation,
    this.topCategory,
  });
  final String h3, label;
  final List<LatLng> polygon;
  final LatLng center;
  final double value, intensity, confidence, provedShare;
  final int n, contributors;
  final DateTime? lastAt;
  final double? reference, deviation;
  final String? topCategory;
  final List<DataCategoryShare> categories;

  factory DataFeature.fromFeature(Map<String, dynamic> f) {
    final p = (f['properties'] as Map).cast<String, dynamic>();
    final ring = ((f['geometry'] as Map)['coordinates'] as List).first as List;
    final pts = <LatLng>[for (final c in ring) LatLng(_n((c as List)[1]), _n(c[0]))];
    if (pts.length > 1 && pts.first == pts.last) pts.removeLast();
    final c = (p['center'] as Map).cast<String, dynamic>();
    return DataFeature(
      h3: p['h3'] as String,
      label: (p['label'] as String?) ?? '',
      polygon: pts,
      center: LatLng(_n(c['lat']), _n(c['lon'])),
      value: _n(p['value']),
      intensity: _n(p['intensity']),
      confidence: _n(p['confidence']),
      provedShare: _n(p['proved_share'] ?? 0),
      n: (p['n'] as num).toInt(),
      contributors: (p['contributors'] as num).toInt(),
      lastAt: _t(p['last_at']),
      reference: _nn(p['reference']),
      deviation: _nn(p['deviation']),
      topCategory: p['top_category'] as String?,
      categories: [
        for (final x in (p['categories'] as List? ?? const [])) DataCategoryShare.fromJson((x as Map).cast<String, dynamic>())
      ],
    );
  }
}

class DataStats {
  DataStats({
    required this.cells,
    required this.hiddenCells,
    required this.minContributors,
    required this.responses,
    this.mean,
    this.median,
  });
  final int cells, hiddenCells, minContributors, responses;
  final double? mean, median;
  factory DataStats.fromJson(Map<String, dynamic> j) => DataStats(
        cells: (j['cells'] as num).toInt(),
        hiddenCells: (j['hidden_cells'] as num).toInt(),
        minContributors: (j['min_contributors'] as num).toInt(),
        responses: (j['responses'] as num).toInt(),
        mean: _nn(j['mean']),
        median: _nn(j['median']),
      );
}

class DataMap {
  DataMap({
    required this.features,
    required this.key,
    required this.label,
    required this.domain,
    required this.kind,
    required this.unit,
    required this.polarity,
    required this.color,
    required this.sensitive,
    required this.metric,
    required this.metrics,
    required this.viz,
    required this.resolution,
    required this.stats,
    required this.caveat,
    this.legendMin,
    this.legendMax,
  });
  final List<DataFeature> features;
  final String key, label, domain, kind, unit, metric, viz, caveat;
  final int polarity, resolution;
  final Color color;
  final bool sensitive;
  final List<String> metrics;
  final DataStats stats;
  final double? legendMin, legendMax;

  bool get isCategoryTop => metric == 'top';

  factory DataMap.fromJson(Map<String, dynamic> j) {
    final i = (j['indicator'] as Map).cast<String, dynamic>();
    final lg = (j['legend'] as Map).cast<String, dynamic>();
    return DataMap(
      features: [for (final f in j['features'] as List) DataFeature.fromFeature((f as Map).cast<String, dynamic>())],
      key: i['key'] as String,
      label: i['label'] as String,
      domain: i['domain'] as String,
      kind: i['kind'] as String,
      unit: (i['unit'] as String?) ?? '',
      polarity: (i['polarity'] as num?)?.toInt() ?? 0,
      color: hexColor(i['color']),
      sensitive: (i['sensitive'] as bool?) ?? false,
      metric: j['metric'] as String,
      metrics: [for (final m in j['metrics'] as List) m as String],
      viz: (j['viz'] as String?) ?? 'zones',
      resolution: (j['resolution'] as num).toInt(),
      stats: DataStats.fromJson((j['stats'] as Map).cast<String, dynamic>()),
      caveat: (j['caveat'] as String?) ?? '',
      legendMin: _nn(lg['min']),
      legendMax: _nn(lg['max']),
    );
  }
}

class DataCellItem {
  DataCellItem({
    required this.indicator,
    required this.label,
    required this.kind,
    required this.hidden,
    required this.unit,
    required this.categories,
    this.metric,
    this.value,
    this.labelValue,
    this.n,
    this.contributors,
    this.confidence,
  });
  final String indicator, label, kind, unit;
  final String? metric, labelValue;
  final bool hidden;
  final double? value, confidence;
  final int? n, contributors;
  final List<DataCategoryShare> categories;
  factory DataCellItem.fromJson(Map<String, dynamic> j) => DataCellItem(
        indicator: j['indicator'] as String,
        label: j['label'] as String,
        kind: j['kind'] as String,
        unit: (j['unit'] as String?) ?? '',
        metric: j['metric'] as String?,
        hidden: (j['hidden'] as bool?) ?? false,
        value: _nn(j['value']),
        labelValue: j['label_value'] as String?,
        n: (j['n'] as num?)?.toInt(),
        contributors: (j['contributors'] as num?)?.toInt(),
        confidence: _nn(j['confidence']),
        categories: [
          for (final x in (j['categories'] as List? ?? const [])) DataCategoryShare.fromJson((x as Map).cast<String, dynamic>())
        ],
      );
}

class DataCellDetail {
  DataCellDetail(this.h3, this.items, this.caveat);
  final String h3, caveat;
  final List<DataCellItem> items;
  factory DataCellDetail.fromJson(Map<String, dynamic> j) => DataCellDetail(
        j['h3'] as String,
        [for (final i in j['items'] as List) DataCellItem.fromJson((i as Map).cast<String, dynamic>())],
        (j['caveat'] as String?) ?? '',
      );
}

class TrendPoint {
  TrendPoint(this.month, this.value, this.n, this.contributors);
  final String month;
  final double value;
  final int n, contributors;
}

class DataTrend {
  DataTrend(this.points, this.unit, this.minContributors);
  final List<TrendPoint> points;
  final String unit;
  final int minContributors;
  factory DataTrend.fromJson(Map<String, dynamic> j) => DataTrend(
        [
          for (final p in j['points'] as List)
            TrendPoint(p['month'] as String, _n(p['value']), (p['n'] as num).toInt(), (p['contributors'] as num).toInt())
        ],
        ((j['indicator'] as Map)['unit'] as String?) ?? '',
        (j['min_contributors'] as num).toInt(),
      );
}

class DataAnalysis {
  DataAnalysis(this.summary, this.patterns, this.outliers, this.recommendations, this.limitations);
  final String summary;
  final List<String> patterns, outliers, recommendations, limitations;
  static List<String> _l(dynamic v) => [for (final x in (v as List? ?? const [])) x.toString()];
  factory DataAnalysis.fromJson(Map<String, dynamic> j) => DataAnalysis(
        (j['summary'] as String?) ?? '',
        _l(j['patterns']),
        _l(j['outliers']),
        _l(j['recommendations']),
        _l(j['data_limitations']),
      );
}

// ============================================================================ ENQUÊTES
class SurveyCard {
  SurveyCard({
    required this.id,
    required this.title,
    required this.domain,
    required this.unit,
    required this.nQuestions,
    required this.version,
    required this.estimatedMinutes,
    required this.needsEvidence,
    required this.need,
    this.description,
  });
  final String id, title, domain, unit;
  final String? description;
  final int nQuestions, version, estimatedMinutes;
  final bool needsEvidence;
  final double need;
  factory SurveyCard.fromJson(Map<String, dynamic> j) => SurveyCard(
        id: j['id'] as String,
        title: j['title'] as String,
        description: j['description'] as String?,
        domain: j['domain'] as String,
        unit: (j['unit'] as String?) ?? 'household',
        nQuestions: (j['n_questions'] as num).toInt(),
        version: (j['version'] as num).toInt(),
        estimatedMinutes: (j['estimated_minutes'] as num).toInt(),
        needsEvidence: (j['needs_evidence'] as bool?) ?? false,
        need: _n(j['need'] ?? 0),
      );
}

class SurveyOption {
  SurveyOption(this.value, this.label);
  final String value, label;
  factory SurveyOption.fromJson(Map<String, dynamic> j) =>
      SurveyOption(j['value'] as String, (j['label'] as String?) ?? (j['value'] as String));
}

class SurveyQuestion {
  SurveyQuestion({
    required this.key,
    required this.slot,
    required this.text,
    required this.kind,
    required this.indicator,
    required this.required,
    required this.options,
    required this.unit,
    required this.evidence,
    required this.allowOverride,
    this.short,
    this.help,
    this.min,
    this.max,
    this.evidenceHint,
    this.axis,
  });
  final String key, slot, text, kind, indicator, unit, evidence;
  final String? short, help, evidenceHint, axis;
  final bool required, allowOverride;
  final List<SurveyOption> options;
  final double? min, max;

  String get title => short ?? text;

  factory SurveyQuestion.fromJson(Map<String, dynamic> j) => SurveyQuestion(
        key: j['key'] as String,
        slot: j['slot'] as String,
        text: j['text'] as String,
        short: j['short'] as String?,
        help: j['help'] as String?,
        kind: j['kind'] as String,
        indicator: j['indicator'] as String,
        unit: (j['unit'] as String?) ?? '',
        required: (j['required'] as bool?) ?? true,
        options: [
          for (final o in (j['options'] as List? ?? const [])) SurveyOption.fromJson((o as Map).cast<String, dynamic>())
        ],
        min: _nn(j['min']),
        max: _nn(j['max']),
        evidence: (j['evidence'] as String?) ?? 'none',
        evidenceHint: j['evidence_hint'] as String?,
        allowOverride: (j['allow_override'] as bool?) ?? true,
        axis: j['axis'] as String?,
      );
}

class SurveyProfile {
  SurveyProfile({
    required this.id,
    required this.label,
    required this.axes,
    required this.summary,
    this.description,
    this.supportShare,
  });
  final String id, label;
  final String? description;
  final Map<String, String> axes;
  final List<({String question, String answer})> summary;
  final double? supportShare;
  factory SurveyProfile.fromJson(Map<String, dynamic> j) => SurveyProfile(
        id: j['id'] as String,
        label: j['label'] as String,
        description: j['description'] as String?,
        axes: (j['axes'] as Map? ?? {}).map((k, v) => MapEntry(k.toString(), v.toString())),
        summary: [
          for (final s in (j['summary'] as List? ?? const [])) (question: s['question'] as String, answer: s['answer'] as String)
        ],
        supportShare: _nn(j['support_share']),
      );
}

class SurveySlot {
  SurveySlot({
    required this.key,
    required this.label,
    required this.multi,
    required this.allowNone,
    required this.mode,
    required this.profiles,
    this.help,
  });
  final String key, label, mode;
  final String? help;
  final bool multi, allowNone;
  final List<SurveyProfile> profiles;
  factory SurveySlot.fromJson(Map<String, dynamic> j) => SurveySlot(
        key: j['key'] as String,
        label: j['label'] as String,
        help: j['help'] as String?,
        multi: (j['multi'] as bool?) ?? false,
        allowNone: (j['allow_none'] as bool?) ?? true,
        mode: (j['mode'] as String?) ?? 'profile',
        profiles: [
          for (final p in (j['profiles'] as List? ?? const [])) SurveyProfile.fromJson((p as Map).cast<String, dynamic>())
        ],
      );
}

class SurveyDefinition {
  SurveyDefinition({required this.card, required this.slots, required this.questions});
  final SurveyCard card;
  final List<SurveySlot> slots;
  final List<SurveyQuestion> questions;
  String get id => card.id;
  int get version => card.version;
  String get unit => card.unit;
  List<SurveyQuestion> questionsOf(String slot) => questions.where((q) => q.slot == slot).toList();

  factory SurveyDefinition.fromJson(Map<String, dynamic> j) {
    final d = (j['definition'] as Map).cast<String, dynamic>();
    return SurveyDefinition(
      card: SurveyCard.fromJson(j),
      slots: [for (final s in d['slots'] as List) SurveySlot.fromJson((s as Map).cast<String, dynamic>())],
      questions: [for (final q in d['questions'] as List) SurveyQuestion.fromJson((q as Map).cast<String, dynamic>())],
    );
  }
}

class SubmitAck {
  SubmitAck({required this.id, required this.status, required this.duplicate, required this.evidenceRequired, this.deadline});
  final String id, status;
  final bool duplicate;
  final List<String> evidenceRequired;
  final DateTime? deadline;
  factory SubmitAck.fromJson(Map<String, dynamic> j) => SubmitAck(
        id: j['id'] as String,
        status: j['quality_status'] as String,
        duplicate: (j['duplicate'] as bool?) ?? false,
        evidenceRequired: [for (final x in (j['evidence_required'] as List? ?? const [])) x as String],
        deadline: _t(j['evidence_deadline']),
      );
}

class ReasonItem {
  ReasonItem(this.code, this.label, this.severity, this.tip);
  final String code, label;
  final String? severity, tip;
  factory ReasonItem.fromJson(Map<String, dynamic> j) =>
      ReasonItem(j['code'] as String, (j['label'] as String?) ?? (j['code'] as String), j['severity'] as String?, j['tip'] as String?);
}

class MyResponse {
  MyResponse({
    required this.id,
    required this.title,
    required this.domain,
    required this.submittedAt,
    required this.status,
    required this.mode,
    required this.reasons,
    required this.needsEvidence,
    this.score,
  });
  final String id, title, domain, status, mode;
  final DateTime submittedAt;
  final double? score;
  final bool needsEvidence;
  final List<ReasonItem> reasons;
  factory MyResponse.fromJson(Map<String, dynamic> j) => MyResponse(
        id: j['id'] as String,
        title: j['title'] as String,
        domain: j['domain'] as String,
        submittedAt: _t(j['submitted_at'])!,
        status: j['quality_status'] as String,
        mode: (j['mode'] as String?) ?? '',
        score: _nn(j['score']),
        needsEvidence: (j['needs_evidence'] as bool?) ?? false,
        reasons: [for (final r in (j['reasons'] as List? ?? const [])) ReasonItem.fromJson((r as Map).cast<String, dynamic>())],
      );
}

class ResponseDetail {
  ResponseDetail({
    required this.id,
    required this.title,
    required this.status,
    required this.reasons,
    required this.answers,
    required this.evidence,
    required this.subScores,
    this.submittedAt,
    this.score,
  });
  final String id, title, status;
  final DateTime? submittedAt;
  final double? score;
  final List<ReasonItem> reasons;
  final List<({String question, String answer})> answers;
  final List<({String id, String question, String status})> evidence;
  final Map<String, double> subScores;
  factory ResponseDetail.fromJson(Map<String, dynamic> j) => ResponseDetail(
        id: j['id'] as String,
        title: j['title'] as String,
        submittedAt: _t(j['submitted_at']),
        status: j['quality_status'] as String,
        score: _nn(j['score']),
        reasons: [for (final r in (j['reasons'] as List? ?? const [])) ReasonItem.fromJson((r as Map).cast<String, dynamic>())],
        answers: [for (final a in (j['answers'] as List? ?? const [])) (question: a['question'] as String, answer: a['answer'] as String)],
        evidence: [
          for (final e in (j['evidence'] as List? ?? const []))
            (id: e['id'] as String, question: e['question'] as String, status: e['status'] as String)
        ],
        subScores: (j['sub_scores'] as Map? ?? {}).map((k, v) => MapEntry(k.toString(), (v as num).toDouble())),
      );
}

class TrustView {
  TrustView({required this.persona, required this.label, required this.band, required this.responses, this.trust, this.trend, this.tip});
  final String persona, label, band;
  final double? trust;
  final String? trend, tip;
  final int responses;
  factory TrustView.fromJson(Map<String, dynamic> j) => TrustView(
        persona: j['persona'] as String,
        label: j['label'] as String,
        band: (j['trust_band'] as String?) ?? '',
        trust: _nn(j['trust']),
        trend: j['trend'] as String?,
        tip: j['tip'] as String?,
        responses: (j['responses'] as num?)?.toInt() ?? 0,
      );
}