/// The OpenPak mark, drawn rather than imported.
///
/// `website/web/static/icon.svg` is four primitives — a gradient disc, a ring,
/// a three-quarter arc and a dot — so drawing it here costs less than an SVG
/// package and stays sharp at any size. If the logo ever gains detail, replace
/// this with the asset and take the dependency then.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

class OpenPakLogo extends StatelessWidget {
  const OpenPakLogo({super.key, this.size = 96});
  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _LogoPainter());
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final c = Offset(s / 2, s / 2);
    final u = s / 512; // the SVG's viewBox unit

    canvas.drawCircle(
      c,
      256 * u,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6366F1), Color(0xFF4338CA)],
        ).createShader(Rect.fromLTWH(0, 0, s, s)),
    );

    final white = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 20 * u
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(c, 180 * u, white);
    // The open arc: three quarters, starting at nine o'clock.
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: 96 * u),
      math.pi,
      math.pi * 1.5,
      false,
      white,
    );
    canvas.drawCircle(
      c,
      28 * u,
      Paint()..color = Colors.white.withValues(alpha: 0.95),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
