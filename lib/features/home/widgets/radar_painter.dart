import 'dart:math' as math;

import 'package:flutter/material.dart';

class RadarPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.34;
    final paint = Paint()..style = PaintingStyle.stroke;

    for (var i = 1; i <= 4; i++) {
      paint.color = Colors.greenAccent.withOpacity(0.18 + (0.08 * i));
      paint.strokeWidth = 1.2;
      canvas.drawCircle(center, radius * (i / 4), paint);
    }

    final linePaint = Paint()
      ..color = Colors.greenAccent.withOpacity(0.75)
      ..strokeWidth = 2.4;

    final angle = (math.pi * 2) * 0.78;
    final end = Offset(
      center.dx + math.cos(angle) * radius,
      center.dy + math.sin(angle) * radius,
    );
    canvas.drawLine(center, end, linePaint);

    final targetPaint = Paint()
      ..color = Colors.white.withOpacity(0.16)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(center.dx + radius * 0.45, center.dy + radius * 0.18),
      12,
      targetPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
