import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// 芽苗生长动画 Painter
/// 三阶段：破土(0-0.3) → 抽茎(0.3-0.7) → 展叶(0.7-1.0)
class SproutGrowthPainter extends CustomPainter {
  final double progress;  // 0.0 ~ 1.0 循环
  final double size;

  SproutGrowthPainter({
    required this.progress,
    this.size = 120,
  });

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final centerX = canvasSize.width / 2;
    final bottomY = canvasSize.height * 0.85;
    final maxHeight = canvasSize.height * 0.55;

    // ── 土壤 ──
    _drawSoil(canvas, centerX, bottomY);

    // ── 阶段计算 ──
    final phase1 = (progress / 0.3).clamp(0.0, 1.0);   // 破土
    final phase2 = ((progress - 0.3) / 0.4).clamp(0.0, 1.0); // 抽茎
    final phase3 = ((progress - 0.7) / 0.3).clamp(0.0, 1.0); // 展叶

    final stemHeight = (phase1 * 0.15 + phase2 * 0.7 + phase3 * 0.15) * maxHeight;
    final stemTop = bottomY - stemHeight;

    // ── 茎干（贝塞尔曲线，带微风摇摆） ──
    final sway = sin(progress * 4 * pi) * 4 * phase2;
    final stemPaint = Paint()
      ..color = AppTheme.chineseGreenMid
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final stemPath = Path()
      ..moveTo(centerX, bottomY)
      ..quadraticBezierTo(
        centerX + sway * 0.5,
        bottomY - stemHeight * 0.5,
        centerX + sway,
        stemTop,
      );
    canvas.drawPath(stemPath, stemPaint);

    // ── 泥土裂纹（破土粒子） ──
    if (phase1 > 0 && stemHeight > 0) {
      _drawSoilCracks(canvas, centerX, bottomY, phase1);
    }

    // ── 子叶（顶部两片小叶子） ──
    if (phase2 > 0.3) {
      final leafAlpha = (phase2 - 0.3).clamp(0.0, 1.0);
      _drawLeaf(
        canvas,
        Offset(centerX + sway, stemTop),
        size: 10 + phase2 * 6,
        angle: -0.6 - phase2 * 0.3,
        color: AppTheme.chineseGreenLight.withOpacity(leafAlpha),
        flip: false,
      );
      _drawLeaf(
        canvas,
        Offset(centerX + sway, stemTop),
        size: 10 + phase2 * 6,
        angle: 0.6 + phase2 * 0.3,
        color: AppTheme.chineseGreenLight.withOpacity(leafAlpha),
        flip: true,
      );
    }

    // ── 真叶（侧边伸展） ──
    if (phase3 > 0.2) {
      final leafScale = (phase3 - 0.2).clamp(0.0, 1.0);
      final leafSize = 14 + leafScale * 10;

      _drawLeaf(
        canvas,
        Offset(centerX + sway * 0.6, bottomY - stemHeight * 0.65),
        size: leafSize,
        angle: -0.8 - leafScale * 0.4,
        color: AppTheme.primaryGreen.withOpacity(leafScale),
        flip: false,
      );
      _drawLeaf(
        canvas,
        Offset(centerX + sway * 0.4, bottomY - stemHeight * 0.45),
        size: leafSize * 0.85,
        angle: 0.7 + leafScale * 0.5,
        color: AppTheme.primaryGreen.withOpacity(leafScale * 0.9),
        flip: true,
      );
    }

    // ── 光点粒子 ──
    if (phase2 > 0) {
      _drawSparkles(canvas, centerX + sway, stemTop, stemHeight, progress);
    }
  }

  void _drawSoil(Canvas canvas, double cx, double bottomY) {
    final soilPaint = Paint()
      ..color = const Color(0xFFC4A882)
      ..style = PaintingStyle.fill;
    final soilPath = Path()
      ..moveTo(cx - 40, bottomY)
      ..quadraticBezierTo(cx - 20, bottomY - 6, cx, bottomY - 4)
      ..quadraticBezierTo(cx + 20, bottomY - 6, cx + 40, bottomY)
      ..lineTo(cx - 40, bottomY);
    canvas.drawPath(soilPath, soilPaint);

    // 土壤暗部
    final darkPaint = Paint()
      ..color = const Color(0xFFB8956E)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx - 25, bottomY - 2), 8, darkPaint);
    canvas.drawCircle(Offset(cx + 20, bottomY - 3), 7, darkPaint);
    canvas.drawCircle(Offset(cx, bottomY - 2), 6, darkPaint);
  }

  void _drawSoilCracks(Canvas canvas, double cx, double by, double intensity) {
    final crackPaint = Paint()
      ..color = const Color(0xFFA08060).withOpacity(intensity * 0.4)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    final rand = Random(7); // fixed seed

    for (int i = 0; i < 5; i++) {
      final x = cx - 30 + rand.nextDouble() * 60;
      final y = by - 2 + rand.nextDouble() * 6;
      final len = 3 + rand.nextDouble() * 6 * intensity;
      canvas.drawLine(
        Offset(x, y),
        Offset(x + (rand.nextDouble() - 0.5) * len, y + len * 0.5),
        crackPaint,
      );
    }
  }

  void _drawLeaf(
    Canvas canvas,
    Offset tip,
    {required double size,
    required double angle,
    required Color color,
    required bool flip}) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();
    final dx = cos(angle);
    final dy = sin(angle);
    final sign = flip ? -1.0 : 1.0;

    path.moveTo(tip.dx, tip.dy);
    path.quadraticBezierTo(
      tip.dx + dx * size * 0.5 + sign * size * 0.3,
      tip.dy + dy * size * 0.5 - size * 0.2,
      tip.dx + dx * size * 0.8 + sign * size * 0.6,
      tip.dy + dy * size * 0.8,
    );
    path.quadraticBezierTo(
      tip.dx + dx * size * 0.4,
      tip.dy + dy * size * 0.6 + size * 0.3,
      tip.dx,
      tip.dy,
    );
    canvas.drawPath(path, paint);

    // 叶脉
    final veinPaint = Paint()
      ..color = color.withOpacity(0.4)
      ..strokeWidth = 0.6
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      tip,
      Offset(
        tip.dx + dx * size * 0.6 + sign * size * 0.2,
        tip.dy + dy * size * 0.5,
      ),
      veinPaint,
    );
  }

  void _drawSparkles(
      Canvas canvas, double cx, double topY, double height, double t) {
    final sparklePaint = Paint()
      ..color = AppTheme.chineseGold.withOpacity(0.6)
      ..style = PaintingStyle.fill;
    final rand = Random(13);

    for (int i = 0; i < 8; i++) {
      final phase = rand.nextDouble() * 2 * pi;
      final baseY = topY + rand.nextDouble() * height;
      final xOffset = (rand.nextDouble() - 0.5) * 60;
      final alpha = (sin(t * 3 * pi + phase) + 1) / 2;

      sparklePaint.color = AppTheme.chineseGold.withOpacity(alpha * 0.5);
      canvas.drawCircle(
        Offset(cx + xOffset + sin(t * 2 + phase) * 8, baseY),
        1.5 + alpha * 2,
        sparklePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant SproutGrowthPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
