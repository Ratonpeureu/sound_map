import 'package:flutter/material.dart';

import 'widgets.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1F2A),
      body: Center(
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) {
            final fade = Curves.easeOut.transform(_c.value);
            return Opacity(
              opacity: fade,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                SunuLogo(size: 120, t: _c.value),
                const SizedBox(height: 28),
                const Text('SunuSound',
                    style: TextStyle(
                        color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                const SizedBox(height: 8),
                Text('Cartographie sonore participative',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 14)),
                const SizedBox(height: 40),
                SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: const Color(0xFF2DD4BF).withValues(alpha: 0.9)),
                ),
              ]),
            );
          },
        ),
      ),
    );
  }
}