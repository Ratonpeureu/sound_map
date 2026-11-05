import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/api_ext.dart';
//import '../core/config.dart';
import '../core/theme.dart';
import '../core/util.dart';
import '../state/session_controller.dart';
import 'widgets.dart';

bool passwordPolicyOk(String p) {
  final classes = [RegExp(r'[a-z]'), RegExp(r'[A-Z]'), RegExp(r'\d'), RegExp(r'[^A-Za-z0-9]')]
      .where((r) => r.hasMatch(p))
      .length;
  return p.length >= 10 && RegExp(r'[A-Za-z]').hasMatch(p) && RegExp(r'\d').hasMatch(p) && (p.length >= 14 || classes >= 3);
}

({double value, String label, Color color}) passwordStrength(String p) {
  var s = 0;
  if (p.length >= 10) s++;
  if (p.length >= 14) s++;
  if (RegExp(r'[a-z]').hasMatch(p) && RegExp(r'[A-Z]').hasMatch(p)) s++;
  if (RegExp(r'\d').hasMatch(p)) s++;
  if (RegExp(r'[^A-Za-z0-9]').hasMatch(p)) s++;
  return switch (s) {
    <= 1 => (value: 0.2, label: 'Faible', color: const Color(0xFFEF4444)),
    2 => (value: 0.45, label: 'Moyen', color: const Color(0xFFF59E0B)),
    3 => (value: 0.7, label: 'Bon', color: const Color(0xFF84CC16)),
    _ => (value: 1.0, label: 'Excellent', color: const Color(0xFF22C55E)),
  };
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _keys = [GlobalKey<FormState>(), GlobalKey<FormState>(), GlobalKey<FormState>()];
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();
  final _name = TextEditingController();
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _phone = TextEditingController();
  final _city = TextEditingController();
  final _district = TextEditingController();
  final _invite = TextEditingController();
  int? _year;
  bool _register = false, _busy = false, _hide = true, _accept = false;
  int _step = 0;

  @override
  void initState() {
    super.initState();
    _pass.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    for (final c in [_email, _pass, _pass2, _name, _first, _last, _phone, _city, _district, _invite]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _showCodes(List<String> codes) async {
    var saved = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Codes de récupération'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text(
                  'Conservez ces 8 codes en lieu sûr. Chacun permet de réinitialiser votre mot de passe une seule fois (votre e-mail n\'est pas stocké en clair, aucun mail de récupération n\'est possible). Ils ne seront plus affichés.',
                  style: TextStyle(fontSize: 13)),
              const SizedBox(height: 12),
              SelectableText(codes.join('\n'), style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700, fontSize: 16, height: 1.6)),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: codes.join('\n')));
                  showToast(ctx, 'Codes copiés');
                },
                icon: const Icon(Icons.copy_rounded),
                label: const Text('Copier'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: saved,
                onChanged: (v) => setD(() => saved = v ?? false),
                title: const Text("J'ai conservé mes codes", style: TextStyle(fontSize: 13)),
              ),
            ]),
          ),
          actions: [FilledButton(onPressed: saved ? () => Navigator.pop(ctx) : null, child: const Text('Continuer'))],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final s = context.read<SessionController>();
    final api = context.read<ApiClient>();
    setState(() => _busy = true);
    try {
      final email = _email.text.trim();
      if (_register) {
        final res = await api.registerAccount({
          'email': email,
          'password': _pass.text,
          'display_name': _name.text.trim(),
          if (_first.text.trim().isNotEmpty) 'first_name': _first.text.trim(),
          if (_last.text.trim().isNotEmpty) 'last_name': _last.text.trim(),
          if (_phone.text.trim().isNotEmpty) 'phone': _phone.text.trim(),
          if (_city.text.trim().isNotEmpty) 'city': _city.text.trim(),
          if (_district.text.trim().isNotEmpty) 'district': _district.text.trim(),
          if (_year != null) 'birth_year': _year,
          if (_invite.text.trim().isNotEmpty) 'invite_code': _invite.text.trim(),
          'accept_terms': _accept,
        });
        if (!mounted) return;
        await _showCodes((res['recovery_codes'] as List).cast<String>());
      }
      await s.signIn(email, _pass.text);
    } catch (e) {
      if (mounted) showToast(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _next() {
    if (!_keys[_step].currentState!.validate()) return;
    if (_step < 2) {
      setState(() => _step++);
    } else if (!_accept) {
      showToast(context, "Acceptez les conditions d'utilisation pour continuer.");
    } else {
      _submit();
    }
  }

  Widget _gap([double h = 14]) => SizedBox(height: h);

  List<Widget> _loginFields() => [
        TextFormField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          textInputAction: TextInputAction.next,
          decoration: fieldDecoration(context, 'E-mail', Icons.alternate_email_rounded),
          validator: (v) => (v == null || !v.contains('@')) ? 'E-mail invalide' : null,
        ),
        _gap(),
        TextFormField(
          controller: _pass,
          obscureText: _hide,
          onFieldSubmitted: (_) => _submit(),
          decoration: fieldDecoration(context, 'Mot de passe', Icons.lock_outline_rounded,
              suffix: IconButton(
                icon: Icon(_hide ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                onPressed: () => setState(() => _hide = !_hide),
              )),
          validator: (v) => (v == null || v.isEmpty) ? 'Mot de passe requis' : null,
        ),
      ];

  List<Widget> _step0() {
    final st = passwordStrength(_pass.text);
    final cs = Theme.of(context).colorScheme;
    return [
      TextFormField(
        controller: _email,
        keyboardType: TextInputType.emailAddress,
        autocorrect: false,
        decoration: fieldDecoration(context, 'E-mail', Icons.alternate_email_rounded),
        validator: (v) => (v == null || !v.contains('@') || !v.contains('.')) ? 'E-mail invalide' : null,
      ),
      _gap(),
      TextFormField(
        controller: _pass,
        obscureText: _hide,
        decoration: fieldDecoration(context, 'Mot de passe', Icons.lock_outline_rounded,
            suffix: IconButton(
              icon: Icon(_hide ? Icons.visibility_off_outlined : Icons.visibility_outlined),
              onPressed: () => setState(() => _hide = !_hide),
            )),
        validator: (v) => passwordPolicyOk(v ?? '')
            ? null
            : '10 caractères min., lettres + chiffres, et 3 types de caractères (ou 14 caractères)',
      ),
      const SizedBox(height: 8),
      ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: _pass.text.isEmpty ? 0 : st.value, minHeight: 6, color: st.color, backgroundColor: cs.outlineVariant.withValues(alpha: 0.4))),
      Align(alignment: Alignment.centerLeft, child: Padding(padding: const EdgeInsets.only(top: 4), child: Text(_pass.text.isEmpty ? 'Minuscules, majuscules, chiffres, symboles' : 'Force : ${st.label}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)))),
      _gap(),
      TextFormField(
        controller: _pass2,
        obscureText: _hide,
        decoration: fieldDecoration(context, 'Confirmer le mot de passe', Icons.lock_reset_rounded),
        validator: (v) => v == _pass.text ? null : 'Les mots de passe ne correspondent pas',
      ),
    ];
  }

  List<Widget> _step1() => [
        TextFormField(
          controller: _name,
          maxLength: 24,
          decoration: fieldDecoration(context, 'Pseudo public (classement)', Icons.badge_outlined),
          validator: (v) => RegExp(r"^[\w .'-]{3,24}$").hasMatch((v ?? '').trim()) ? null : '3 à 24 caractères (lettres, chiffres, . - \' _)',
        ),
        Row(children: [
          Expanded(child: TextFormField(controller: _first, decoration: fieldDecoration(context, 'Prénom (facultatif)', Icons.person_outline_rounded))),
          const SizedBox(width: 10),
          Expanded(child: TextFormField(controller: _last, decoration: fieldDecoration(context, 'Nom (facultatif)', Icons.person_outline_rounded))),
        ]),
        _gap(),
        TextFormField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: fieldDecoration(context, 'Téléphone (facultatif)', Icons.phone_outlined),
          validator: (v) => (v == null || v.trim().isEmpty || RegExp(r'^\+?[0-9 ()-]{6,20}$').hasMatch(v.trim())) ? null : 'Numéro invalide',
        ),
        _gap(),
        Row(children: [
          Expanded(child: TextFormField(controller: _city, decoration: fieldDecoration(context, 'Ville', Icons.location_city_rounded))),
          const SizedBox(width: 10),
          Expanded(child: TextFormField(controller: _district, decoration: fieldDecoration(context, 'Quartier', Icons.holiday_village_outlined))),
        ]),
        _gap(),
        DropdownButtonFormField<int>(
          initialValue: _year,
          decoration: fieldDecoration(context, 'Année de naissance (facultatif)', Icons.cake_outlined),
          items: [for (var y = DateTime.now().year - 13; y >= 1930; y--) DropdownMenuItem(value: y, child: Text('$y'))],
          onChanged: (v) => setState(() => _year = v),
        ),
      ];

  List<Widget> _step2() => [
        TextFormField(
          controller: _invite,
          textCapitalization: TextCapitalization.characters,
          decoration: fieldDecoration(context, "Code d'invitation (si vous en avez un)", Icons.card_giftcard_rounded),
        ),
        const SizedBox(height: 8),
        Text("L'invitation peut être obligatoire selon l'organisation. Un code d'ami vous rattache à lui : il gagne des points quand vous devenez actif.",
            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        _gap(),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _accept,
          onChanged: (v) => setState(() => _accept = v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text(
              "J'accepte les conditions d'utilisation. Mon e-mail n'est conservé que sous forme chiffrée ; mon nom et mon téléphone restent privés ; seuls des niveaux en dB(A) (jamais l'audio) sont envoyés.",
              style: TextStyle(fontSize: 13)),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const titles = ['Votre compte', 'Votre profil', 'Invitation et conditions'];
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(24, MediaQuery.of(context).padding.top + 28, 24, 28),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFF0B1F2A), Color(0xFF0E5E63)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(36)),
            ),
            child: Column(children: [
              const SunuLogo(size: 72),
              const SizedBox(height: 12),
              const Text('SunuSound', style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('Mesurez, cartographiez, comprenez le bruit autour de vous.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: 0.75))),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              SegmentedButton<bool>(
                segments: const [ButtonSegment(value: false, label: Text('Connexion')), ButtonSegment(value: true, label: Text('Inscription'))],
                selected: {_register},
                onSelectionChanged: (v) => setState(() {
                  _register = v.first;
                  _step = 0;
                }),
                showSelectedIcon: false,
              ),
              const SizedBox(height: 20),
              if (_register) ...[
                Row(children: [
                  for (var i = 0; i < 3; i++) ...[
                    Expanded(child: Container(height: 4, decoration: BoxDecoration(color: i <= _step ? cs.primary : cs.outlineVariant, borderRadius: BorderRadius.circular(2)))),
                    if (i < 2) const SizedBox(width: 6),
                  ]
                ]),
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerLeft, child: Text('Étape ${_step + 1}/3 · ${titles[_step]}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                const SizedBox(height: 14),
                Form(key: _keys[_step], child: Column(children: [if (_step == 0) ..._step0() else if (_step == 1) ..._step1() else ..._step2()])),
              ] else
                Form(key: _keys[0], child: Column(children: _loginFields())),
              const SizedBox(height: 8),
              if (!_register)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ResetPasswordScreen(email: _email.text.trim()))),
                    child: const Text('Mot de passe oublié ?'),
                  ),
                ),
              const SizedBox(height: 12),
              Row(children: [
                if (_register && _step > 0) ...[
                  Expanded(child: OutlinedButton(onPressed: _busy ? null : () => setState(() => _step--), child: const Text('Retour'))),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _busy
                        ? null
                        : () {
                            if (!_register) {
                              if (_keys[0].currentState!.validate()) _submit();
                            } else {
                              _next();
                            }
                          },
                    child: _busy
                        ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                        : Text(!_register ? 'Se connecter' : (_step < 2 ? 'Suivant' : 'Créer mon compte')),
                  ),
                ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, this.email = ''});
  final String email;
  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _form = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.email);
  final _code = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await context.read<ApiClient>().resetPassword(_email.text.trim(), _code.text.trim(), _pass.text);
      if (!mounted) return;
      showToast(context, 'Mot de passe modifié. Connectez-vous.');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) showToast(context, errorMessage(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Mot de passe oublié')),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        Text('Saisissez un de vos codes de récupération (remis à l\'inscription). Chaque code ne sert qu\'une fois.', style: TextStyle(color: cs.onSurfaceVariant)),
        const SizedBox(height: 18),
        Form(
          key: _form,
          child: Column(children: [
            TextFormField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: fieldDecoration(context, 'E-mail', Icons.alternate_email_rounded), validator: (v) => (v == null || !v.contains('@')) ? 'E-mail invalide' : null),
            const SizedBox(height: 14),
            TextFormField(controller: _code, textCapitalization: TextCapitalization.characters, decoration: fieldDecoration(context, 'Code de récupération (XXXXX-XXXXX)', Icons.key_rounded), validator: (v) => (v == null || v.trim().length < 8) ? 'Code invalide' : null),
            const SizedBox(height: 14),
            TextFormField(controller: _pass, obscureText: true, decoration: fieldDecoration(context, 'Nouveau mot de passe', Icons.lock_outline_rounded), validator: (v) => passwordPolicyOk(v ?? '') ? null : '10 caractères min., lettres + chiffres, 3 types (ou 14 caractères)'),
            const SizedBox(height: 24),
            FilledButton(onPressed: _busy ? null : _go, child: _busy ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : const Text('Réinitialiser')),
          ]),
        ),
      ]),
    );
  }
}