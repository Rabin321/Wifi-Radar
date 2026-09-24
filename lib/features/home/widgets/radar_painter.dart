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
      const Color(0xFF3BE3D3),
      const Color(0xFF5EE6C5),
      const Color(0xFF7BFF9B),
      const Color(0xFFB9FFAA),
    ];

    for (var i = 0; i < baseRings.length; i++) {
      paint.color = baseRings[i].withValues(alpha: 0.18 + (i * 0.08));
      paint.strokeWidth = 1.4 + (i * 0.5);
      canvas.drawCircle(center, radius * ((i + 1) / 4.2), paint);
    }

    final linePaint = Paint()
      ..color = const Color(0xFF7BFF9B).withValues(alpha: 0.9)
      ..strokeWidth = 2.8;

    final angle = (math.pi * 2) * 0.76;
    final end = Offset(
      center.dx + math.cos(angle) * radius,
      center.dy + math.sin(angle) * radius,
    );
    canvas.drawLine(center, end, linePaint);

    final intensity = ((signalLevel + 100) / 70).clamp(0.15, 1.0);

    final signalColor = switch (signalLevel) {
      >= -60 => const Color(0xFF79F7D2),
      >= -70 => const Color(0xFFF9D978),
      _ => const Color(0xFFFF7A7A),
    };

    final glowPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.18, -0.12),
        radius: 1.35,
        colors: [
          signalColor.withValues(alpha: 0.92),
          signalColor.withValues(alpha: 0.48),
          signalColor.withValues(alpha: 0.18),
          Colors.transparent,
        ],
        stops: const [0.0, 0.32, 0.72, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius * 1.45));
    canvas.drawCircle(center, radius * 1.2, glowPaint);

    final ringPaint = Paint()
      ..color = signalColor.withValues(alpha: 0.30 + (0.45 * intensity))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8;
    canvas.drawCircle(center, radius * (0.28 + (intensity * 0.38)), ringPaint);

    final blobPaint = Paint()
      ..color = signalColor.withValues(alpha: 0.28 + (0.34 * intensity))
      ..style = PaintingStyle.fill;
    final blobPositions = [
      Offset(center.dx + radius * 0.30, center.dy - radius * 0.20),
      Offset(center.dx - radius * 0.26, center.dy + radius * 0.12),
      Offset(center.dx + radius * 0.37, center.dy + radius * 0.18),
      Offset(center.dx - radius * 0.03, center.dy - radius * 0.38),
    ];

    for (final blob in blobPositions) {
      canvas.drawCircle(blob, radius * 0.22, blobPaint);
    }

    final signalDotPaint = Paint()
      ..color = signalColor.withValues(alpha: 0.96)
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawCircle(Offset(center.dx, center.dy), 10.0, signalDotPaint);

    final coreDotPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(center.dx, center.dy), 4.5, coreDotPaint);
  }

  @override
  bool shouldRepaint(covariant RadarPainter oldDelegate) =>
      oldDelegate.signalLevel != signalLevel;
}
