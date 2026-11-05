import 'dart:math';

import 'package:flutter/material.dart';

import '../core/util.dart';

class SoftCard extends StatelessWidget {
  const SoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.onTap,
    this.glass = false,
  });
  final Widget child;
  final EdgeInsets padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final bool glass;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(20);
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: glass ? cs.surface.withValues(alpha: 0.9) : cs.surfaceContainerHigh,
        borderRadius: radius,
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
        boxShadow: glass
            ? [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 18, offset: const Offset(0, 6))]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
        child: Row(children: [
          Expanded(
              child: Text(text,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.2))),
          if (trailing != null) trailing!,
        ]),
      );
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.label, this.color, {super.key, this.icon});
  final String label;
  final Color color;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 14, color: color), const SizedBox(width: 4)],
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
        ]),
      );
}

class NoiseTagChip extends StatelessWidget {
  const NoiseTagChip(this.tag, {super.key, this.count});
  final NoiseTag tag;
  final int? count;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
          color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(tag.icon, size: 16, color: cs.primary),
        const SizedBox(width: 6),
        Text(count == null ? tag.label : '${tag.label} · $count',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      ]),
    );
  }
}

/// Anneau de progression / score.
class ScoreRing extends StatelessWidget {
  const ScoreRing({
    super.key,
    required this.value,
    required this.color,
    this.size = 56,
    this.stroke = 6,
    this.child,
  });
  final double value;
  final Color color;
  final double size, stroke;
  final Widget? child;
  @override
  Widget build(BuildContext context) {
    final track = Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4);
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        builder: (_, v, __) => CustomPaint(
          painter: _RingPainter(v, color, track, stroke),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.v, this.color, this.track, this.stroke);
  final double v, stroke;
  final Color color, track;
  @override
  void paint(Canvas c, Size s) {
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, s.width - stroke, s.height - stroke);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    c.drawArc(rect, 0, 2 * pi, false, p..color = track);
    c.drawArc(rect, -pi / 2, 2 * pi * v, false, p..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.v != v || o.color != color;
}

/// Logo : point central + ondes sonores. `t` (0..1) anime les ondes.
class SunuLogo extends StatelessWidget {
  const SunuLogo({super.key, this.size = 96, this.t = 1});
  final double size, t;
  @override
  Widget build(BuildContext context) =>
      SizedBox(width: size, height: size, child: CustomPaint(painter: _LogoPainter(t)));
}

class _LogoPainter extends CustomPainter {
  _LogoPainter(this.t);
  final double t;
  @override
  void paint(Canvas c, Size s) {
    final center = s.center(Offset.zero);
    final r = s.width / 2;
    c.drawCircle(
        center,
        r,
        Paint()
          ..shader = const LinearGradient(
            colors: [Color(0xFF0E9F9A), Color(0xFF0B1F2A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(Rect.fromCircle(center: center, radius: r)));
    c.drawCircle(center, r * 0.11, Paint()..color = const Color(0xFF2DD4BF));
    for (var i = 0; i < 2; i++) {
      final rad = r * (0.30 + 0.22 * i);
      final a = (t * 2 - i * 0.6).clamp(0.0, 1.0);
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.075
        ..strokeCap = StrokeCap.round
        ..color = (i == 0 ? Colors.white : const Color(0xFF2DD4BF)).withValues(alpha: a);
      final rect = Rect.fromCircle(center: center, radius: rad);
      c.drawArc(rect, -pi / 4, pi / 2, false, p);
      c.drawArc(rect, 3 * pi / 4, pi / 2, false, p);
    }
  }

  @override
  bool shouldRepaint(_LogoPainter o) => o.t != t;
}