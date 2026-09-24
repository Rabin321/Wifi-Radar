import 'dart:math' as math;

import 'package:flutter/material.dart';

class RadarPainter extends CustomPainter {
  const RadarPainter({required this.signalLevel});

  final int signalLevel;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.34;
    final paint = Paint()..style = PaintingStyle.stroke;

    final baseRings = [
      const Color(0xFF65E7FF),
      const Color(0xFF75F1C8),
      const Color(0xFF9EF8D3),
    ];

    for (var i = 0; i < baseRings.length; i++) {
      paint.color = baseRings[i].withValues(alpha: 0.18 + (i * 0.08));
      paint.strokeWidth = 1.6 + (i * 0.5);
      canvas.drawCircle(center, radius * ((i + 1) / 4.2), paint);
    }

    final linePaint = Paint()
      ..color = const Color(0xFF6FEAFF).withValues(alpha: 0.82)
      ..strokeWidth = 2.0;

    final angle = (math.pi * 2) * 0.76;
    final end = Offset(
      center.dx + math.cos(angle) * radius,
      center.dy + math.sin(angle) * radius,
    );
    canvas.drawLine(center, end, linePaint);

    final intensity = ((signalLevel + 100) / 70).clamp(0.15, 1.0);

    final signalColor = switch (signalLevel) {
      >= -60 => const Color(0xFF76F3D5),
      >= -70 => const Color(0xFFFFCF5A),
      _ => const Color(0xFFFF8A80),
    };

    final ringPaint = Paint()
      ..color = signalColor.withValues(alpha: 0.18 + (0.26 * intensity))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;
    canvas.drawCircle(center, radius * (0.28 + (intensity * 0.38)), ringPaint);

    final signalDotPaint = Paint()
      ..color = signalColor.withValues(alpha: 0.82)
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(Offset(center.dx, center.dy), 7.0, signalDotPaint);

    final coreDotPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(center.dx, center.dy), 3.2, coreDotPaint);
  }

  @override
  bool shouldRepaint(covariant RadarPainter oldDelegate) =>
      oldDelegate.signalLevel != signalLevel;
}
