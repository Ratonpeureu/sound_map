import 'dart:math';

import 'package:flutter/material.dart';

import '../core/models_survey.dart';

String _n(String s) {
  const from = 'àâäéèêëîïôöùûüç';
  const to = 'aaaeeeeiioouuuc';
  var o = s.toLowerCase();
  for (var i = 0; i < from.length; i++) {
    o = o.replaceAll(from[i], to[i]);
  }
  return o;
}

class AvatarSpec {
  bool female = false, male = false, person = false;
  int age = 1; // 0 jeune, 1 adulte, 2 aîné
  int companions = 0;
  IconData? badge;
}

const _personDomains = {'demographie', 'menages', 'emploi', 'genre', 'migration', 'education'};

AvatarSpec avatarSpec(SurveyProfile p, String domain) {
  final s = AvatarSpec();
  String axis(String key) {
    final b = StringBuffer();
    for (final e in p.axes.entries) {
      if (_n(e.key).contains(key)) b.write('${_n(e.value)} ');
    }
    return b.toString();
  }

  final all = _n('${p.axes.entries.map((e) => '${e.key} ${e.value}').join(' ')} ${p.label}');
  bool has(String t, List<String> k) => k.any(t.contains);

  final g = '${axis('genre')} ${axis('sexe')}';
  var f = has(g, ['femme', 'fille', 'feminin']), m = has(g, ['homme', 'garcon', 'masculin']);
  if (!f && !m) {
    f = has(all, ['femme', 'fille', 'feminin']);
    m = has(all, ['homme', 'garcon', 'masculin']);
    if (f && m) f = m = false;
  }
  s.female = f;
  s.male = m;

  final a = axis('age');
  if (has(a, ['jeun', 'enfant', 'ado', 'moins de', 'faible']) || (a.isEmpty && has(all, ['jeune', 'etudiant']))) {
    s.age = 0;
  } else if (has(a, ['ain', 'age', '65', 'senior', 'retrait', 'eleve']) || (a.isEmpty && has(all, ['retrait', 'aine']))) {
    s.age = 2;
  }

  final t = axis('taille');
  if (t.isNotEmpty) {
    s.companions = has(t, ['seul', 'isole', 'faible']) ? 0 : has(t, ['couple']) ? 1 : has(t, ['moyen', 'enfants', 'monoparental']) ? 2 : 3;
  } else if (has(all, ['personne seule'])) {
    s.companions = 0;
  } else if (has(all, ['couple avec enfants', 'monoparental'])) {
    s.companions = 2;
  } else if (has(all, ['elargi', 'collectif'])) {
    s.companions = 3;
  } else if (has(all, ['couple'])) {
    s.companions = 1;
  }

  final job = '${axis('profession')} ${axis('activite')} ${axis('secteur')} $all';
  if (has(job, ['agricul', 'peche', 'elev'])) {
    s.badge = Icons.agriculture_rounded;
  } else if (has(job, ['commerc', 'boutique', 'vente'])) {
    s.badge = Icons.storefront_rounded;
  } else if (has(job, ['artisan'])) {
    s.badge = Icons.handyman_rounded;
  } else if (has(job, ['transport', 'chauffeur'])) {
    s.badge = Icons.local_shipping_rounded;
  } else if (has(job, ['administr', 'fonction'])) {
    s.badge = Icons.account_balance_rounded;
  } else if (has(job, ['btp', 'industrie', 'ouvrier'])) {
    s.badge = Icons.construction_rounded;
  } else if (has(job, ['etudiant', 'eleve', 'scolar'])) {
    s.badge = Icons.school_rounded;
  } else if (has(job, ['service'])) {
    s.badge = Icons.support_agent_rounded;
  } else if (has(job, ['chom', 'recherche'])) {
    s.badge = Icons.search_rounded;
  }
  final mi = '${axis('milieu')} ${axis('localite')} $all';
  s.badge ??= has(mi, ['rural', 'village'])
      ? Icons.landscape_rounded
      : has(mi, ['periurbain'])
          ? Icons.holiday_village_rounded
          : has(mi, ['urbain', 'ville'])
              ? Icons.location_city_rounded
              : null;

  s.person = _personDomains.contains(domain) || s.female || s.male || a.isNotEmpty || axis('profession').isNotEmpty || t.isNotEmpty;
  return s;
}

const _skins = [Color(0xFF8D5524), Color(0xFFC68642), Color(0xFFE0AC69), Color(0xFF6F4518), Color(0xFF4A2C17), Color(0xFFF1C27D)];

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({super.key, required this.profile, required this.domain, required this.color, required this.fallback, this.size = 60});
  final SurveyProfile profile;
  final String domain;
  final Color color;
  final IconData fallback;
  final double size;

  @override
  Widget build(BuildContext context) {
    final spec = avatarSpec(profile, domain);
    final seed = profile.id.hashCode.abs();
    final a = Color.lerp(color, Colors.white, 0.3)!;
    final b = Color.lerp(color, catPalette[seed % catPalette.length], 0.45)!;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned.fill(
          child: ClipOval(
            child: DecoratedBox(
              decoration: BoxDecoration(gradient: LinearGradient(colors: [a, b], begin: Alignment.topLeft, end: Alignment.bottomRight)),
              child: spec.person
                  ? CustomPaint(painter: _PersonPainter(spec, _skins[seed % _skins.length], Color.lerp(color, Colors.black, 0.28)!))
                  : Center(child: Icon(fallback, color: Colors.white, size: size * 0.52)),
            ),
          ),
        ),
        if (spec.badge != null)
          Positioned(
            right: -size * 0.04,
            bottom: -size * 0.04,
            child: Container(
              width: size * 0.4,
              height: size * 0.4,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3)],
              ),
              child: Icon(spec.badge, size: size * 0.25, color: color),
            ),
          ),
      ]),
    );
  }
}

class _PersonPainter extends CustomPainter {
  _PersonPainter(this.spec, this.skin, this.cloth);
  final AvatarSpec spec;
  final Color skin, cloth;

  @override
  void paint(Canvas c, Size z) {
    final s = z.width;
    final k = spec.age == 0 ? 0.84 : (spec.age == 2 ? 0.96 : 1.0);
    final hair = spec.age == 2 ? const Color(0xFFE5E7EB) : const Color(0xFF1F2937);
    const spots = [Offset(0.18, 0.60), Offset(0.82, 0.60), Offset(0.05, 0.68), Offset(0.95, 0.68)];
    for (var i = 0; i < min(spec.companions, 4); i++) {
      final o = spots[i];
      c.drawOval(Rect.fromCenter(center: Offset(o.dx * s, (o.dy + 0.26) * s), width: 0.22 * s, height: 0.3 * s), Paint()..color = Color.lerp(cloth, Colors.white, 0.45)!);
      c.drawCircle(Offset(o.dx * s, o.dy * s), 0.065 * s, Paint()..color = Color.lerp(skin, Colors.white, 0.1)!);
    }
    final cx = 0.5 * s, headY = (0.42 + (1 - k) * 0.12) * s, hr = 0.15 * s * k;
    final bodyTop = (0.62 + (1 - k) * 0.12) * s;
    c.drawOval(Rect.fromLTRB(cx - 0.31 * s * k, bodyTop, cx + 0.31 * s * k, bodyTop + 0.72 * s), Paint()..color = cloth);
    if (spec.female) {
      c.drawOval(Rect.fromCenter(center: Offset(cx, headY + hr * 0.5), width: hr * 2.5, height: hr * 3.2), Paint()..color = hair);
    }
    c.drawCircle(Offset(cx, headY), hr, Paint()..color = skin);
    c.drawArc(Rect.fromCircle(center: Offset(cx, headY), radius: hr * 1.05), pi * 1.04, pi * 0.92, true, Paint()..color = hair);
    final eye = Paint()..color = const Color(0xFF111827);
    c.drawCircle(Offset(cx - hr * 0.38, headY + hr * 0.1), hr * 0.09, eye);
    c.drawCircle(Offset(cx + hr * 0.38, headY + hr * 0.1), hr * 0.09, eye);
    c.drawArc(Rect.fromCenter(center: Offset(cx, headY + hr * 0.38), width: hr * 0.6, height: hr * 0.4), 0.2, pi - 0.4, false,
        Paint()..style = PaintingStyle.stroke..strokeWidth = hr * 0.08..strokeCap = StrokeCap.round..color = const Color(0xFF111827));
  }

  @override
  bool shouldRepaint(covariant _PersonPainter o) => o.spec != spec || o.skin != skin || o.cloth != cloth;
}