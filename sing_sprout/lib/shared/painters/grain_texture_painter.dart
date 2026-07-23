import 'dart:math';
import 'package:flutter/material.dart';

/// 宣纸肌理 CustomPainter — 随机小圆点模拟纸张纹理
class GrainTexturePainter extends CustomPainter {
  final int grainCount;
  final double maxOpacity;
  final Color grainColor;

  GrainTexturePainter({
    this.grainCount = 800,
    this.maxOpacity = 0.04,
    this.grainColor = const Color(0xFF8B7355),
  });

  // 预生成点位，避免每帧重算
  late final List<_GrainDot> _dots = List.generate(grainCount, (i) {
    // 使用固定种子保证可复现
    final rand = Random(42 + i * 7);
    return _GrainDot(
      x: rand.nextDouble(),
      y: rand.nextDouble(),
      radius: 0.5 + rand.nextDouble() * 1.0,
      opacity: (maxOpacity * 0.25) + rand.nextDouble() * (maxOpacity * 0.75),
    );
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = grainColor;
    for (final dot in _dots) {
      paint.color = grainColor.withOpacity(dot.opacity);
      canvas.drawCircle(
        Offset(dot.x * size.width, dot.y * size.height),
        dot.radius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant GrainTexturePainter oldDelegate) => false;
}

class _GrainDot {
  final double x;
  final double y;
  final double radius;
  final double opacity;
  const _GrainDot({
    required this.x,
    required this.y,
    required this.radius,
    required this.opacity,
  });
}
