import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'state/session_controller.dart';
import 'ui/auth_screen.dart';
import 'ui/consent_screen.dart';
import 'ui/home_shell.dart';
import 'ui/splash_screen.dart';

class SunuApp extends StatefulWidget {
  const SunuApp({super.key});
  @override
  State<SunuApp> createState() => _SunuAppState();
}

class _SunuAppState extends State<SunuApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<SessionController>().boot());
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    return MaterialApp(
      title: 'SunuSound',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: session.themeMode,
      locale: const Locale('fr'),
      supportedLocales: const [Locale('fr')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        child: _gate(session),
      ),
    );
  }

  Widget _gate(SessionController s) {
    switch (s.status) {
      case AuthStatus.booting:
        return const SplashScreen(key: ValueKey('splash'));
      case AuthStatus.signedOut:
        return const AuthScreen(key: ValueKey('auth'));
      case AuthStatus.signedIn:
        if (s.needsConsent) return const ConsentScreen(key: ValueKey('consent'));
        return const HomeShell(key: ValueKey('home'));
    }
  }
}