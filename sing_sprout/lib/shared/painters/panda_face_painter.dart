import 'dart:math';
import 'package:flutter/material.dart';

/// 熊猫脸部 — 正圆脸 + 大黑眼圈豆豆眼 + 麦穗 + 八分音符
class PandaFacePainter extends CustomPainter {
  final double blinkProgress;
  final double sparklePhase;
  final bool showSparkles;
  final double leafSway;
  final double noteBounce;
  final double wheatSway;
  final double growScale;

  PandaFacePainter({
    this.blinkProgress = 0.0,
    this.sparklePhase = 0.0,
    this.showSparkles = false,
    this.leafSway = 0.0,
    this.noteBounce = 0.0,
    this.wheatSway = 0.0,
    this.growScale = 1.0,
  });

  // 配色
  static const black = Color(0xFF1A1A1A);
  static const white = Color(0xFFFFFFFF);
  static const blushColor = Color(0xFFE8B4B4);  // 低饱和哑光裸粉
  static const stemGreen = Color(0xFF8BC34A);    // 嫩草绿
  static const leafGreen = Color(0xFFAED581);    // 浅薄荷绿
  static const wheatGold = Color(0xFFE8D44D);    // 浅黄麦穗
  static const noteGreen = Color(0xFF66BB6A);    // 音符绿
  static const starGold = Color(0xFFFFD54F);     // 星星金

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2, cy = size.height / 2, r = size.width / 2;

    _drawFace(canvas, cx, cy, r);               // 1. 先画白脸
    _drawEars(canvas, cx, cy, r);               // 2. 耳朵在脸上层
    _drawDecorations(canvas, cx, cy, r);         // 3. 麦穗音符在最上层
    _drawEyePatches(canvas, cx, cy, r);
    _drawEyes(canvas, cx, cy, r);
    _drawBlush(canvas, cx, cy, r);
    _drawNoseMouth(canvas, cx, cy, r);
    if (showSparkles) _drawSparkles(canvas, cx, cy, r);
  }

  // ── 头顶装饰 ──
  void _drawDecorations(Canvas c, double cx, double cy, double r) {
    final top = cy - r * 0.88;

    // 左：麦穗幼苗（头顶中间偏左）
    c.save();
    c.translate(cx - r * 0.35, top - r * 0.02);
    c.rotate(sin(wheatSway * 2 * pi) * 0.1 - 0.08);
    c.scale(growScale);
    _drawWheatSprout(c, r * 0.3);
    c.restore();

    // 右：八分音符（头顶右侧，像音乐种子发芽）
    c.save();
    c.translate(cx + r * 0.38, top + r * 0.06);
    final bounceY = sin(noteBounce * 2 * pi) * r * 0.05;
    c.translate(0, bounceY);
    final s = (1.0 + sin(noteBounce * 2 * pi) * 0.05) * growScale;
    c.scale(s);
    _drawEighthNote(c, r * 0.24);
    c.restore();

    // 小片草叶（音符旁边点缀）
    c.save();
    c.translate(cx + r * 0.58, top - r * 0.1);
    c.rotate(sin(leafSway * 2 * pi) * 0.15 + 0.2);
    c.scale(growScale);
    _drawSmallLeaf(c, r * 0.14);
    c.restore();
  }

  void _drawWheatSprout(Canvas c, double sz) {
    // 花茎
    final stem = Paint()..color = stemGreen..style = PaintingStyle.stroke..strokeWidth = 1.6..strokeCap = StrokeCap.round;
    c.drawLine(Offset(0, sz * 0.25), Offset(0, -sz * 0.55), stem);
    // 嫩叶
    final leaf = Paint()..color = leafGreen..style = PaintingStyle.fill;
    final lPath = Path()..moveTo(0, -sz * 0.15)..quadraticBezierTo(-sz * 0.3, -sz * 0.3, -sz * 0.12, -sz * 0.5)
        ..quadraticBezierTo(-sz * 0.02, -sz * 0.25, 0, -sz * 0.15);
    final rPath = Path()..moveTo(0, -sz * 0.2)..quadraticBezierTo(sz * 0.28, -sz * 0.35, sz * 0.1, -sz * 0.55)
        ..quadraticBezierTo(sz * 0.01, -sz * 0.3, 0, -sz * 0.2);
    c.drawPath(lPath, leaf);
    c.drawPath(rPath, leaf);
    // 麦穗颗粒（清晰可见，扁平圆点）
    final grain = Paint()..color = wheatGold..style = PaintingStyle.fill;
    for (int i = 0; i < 4; i++) {
      final y = -sz * (0.25 + i * 0.11);
      c.drawCircle(Offset(-sz * 0.09, y), sz * 0.05, grain);
      c.drawCircle(Offset(sz * 0.09, y), sz * 0.05, grain);
    }
  }

  void _drawEighthNote(Canvas c, double sz) {
    final body = Paint()..color = noteGreen..style = PaintingStyle.fill;
    // 符头椭圆
    c.drawOval(Rect.fromCenter(center: Offset(sz * 0.3, sz * 0.05), width: sz * 0.34, height: sz * 0.24), body);
    // 符干
    c.drawLine(Offset(sz * 0.47, sz * 0.0), Offset(sz * 0.47, -sz * 0.58),
        Paint()..color = noteGreen..style = PaintingStyle.stroke..strokeWidth = 1.8..strokeCap = StrokeCap.round);
    // 音符旗（简洁弧线）
    final flag = Path()..moveTo(sz * 0.47, -sz * 0.5)..quadraticBezierTo(sz * 0.10, -sz * 0.35, sz * 0.12, -sz * 0.0);
    c.drawPath(flag, Paint()..color = noteGreen..style = PaintingStyle.stroke..strokeWidth = 1.2..strokeCap = StrokeCap.round);
  }

  void _drawSmallLeaf(Canvas c, double sz) {
    final body = Paint()..color = leafGreen..style = PaintingStyle.fill;
    final path = Path()..moveTo(0, sz * 0.2)..quadraticBezierTo(sz * 0.4, -sz * 0.4, 0, -sz * 0.7)
        ..quadraticBezierTo(-sz * 0.4, -sz * 0.4, 0, sz * 0.2);
    c.drawPath(path, body);
  }

  // ── 半圆耳朵（不大不小，圆润不尖） ──
  void _drawEars(Canvas c, double cx, double cy, double r) {
    final ear = Paint()..color = black..style = PaintingStyle.fill;
    for (final dx in [-0.5, 0.5]) {
      final center = Offset(cx + dx * r, cy - r * 0.7);
      final path = Path()
        ..moveTo(center.dx - r * 0.34, center.dy)
        ..arcTo(Rect.fromCircle(center: center, radius: r * 0.34), pi, pi, false)
        ..close();
      c.drawPath(path, ear);
    }
  }

  // ── 正圆脸（稍小，给耳朵和装饰留空间） ──
  void _drawFace(Canvas c, double cx, double cy, double r) {
    final face = Paint()..color = white..style = PaintingStyle.fill;
    final outline = Paint()..color = black..style = PaintingStyle.stroke..strokeWidth = 2.2;
    c.drawCircle(Offset(cx, cy), r * 0.82, face);
    c.drawCircle(Offset(cx, cy), r * 0.82, outline);
  }

  // ── 超大椭圆黑眼圈（熊猫眼镜） ──
  void _drawEyePatches(Canvas c, double cx, double cy, double r) {
    final patch = Paint()..color = black..style = PaintingStyle.fill;
    for (final (dx, tilt) in [(-0.28, -0.12), (0.28, 0.12)]) {
      c.save();
      c.translate(cx + dx * r, cy - r * 0.02);
      c.rotate(tilt);
      c.drawOval(Rect.fromCenter(center: Offset.zero, width: r * 0.46, height: r * 0.52), patch);
      c.restore();
    }
  }

  // ── 豆豆眼（单个小白点高光） ──
  void _drawEyes(Canvas c, double cx, double cy, double r) {
    final highlight = Paint()..color = white..style = PaintingStyle.fill;
    if (blinkProgress < 0.9) {
      for (final dx in [-0.28, 0.28]) {
        final eyeCtr = Offset(cx + dx * r, cy - r * 0.03);
        // 小黑豆眼
        c.drawCircle(eyeCtr, r * 0.05, Paint()..color = black..style = PaintingStyle.fill);
        // 唯一白色高光点
        c.drawCircle(Offset(eyeCtr.dx - r * 0.015, eyeCtr.dy - r * 0.015), r * 0.015, highlight);
      }
    } else {
      for (final dx in [-0.28, 0.28]) {
        final eyeCtr = Offset(cx + dx * r, cy - r * 0.03);
        c.drawLine(Offset(eyeCtr.dx - r * 0.06, eyeCtr.dy), Offset(eyeCtr.dx + r * 0.06, eyeCtr.dy),
            Paint()..color = black..style = PaintingStyle.stroke..strokeWidth = 1.2..strokeCap = StrokeCap.round);
      }
    }
  }

  // ── 低饱和哑光粉腮红 ──
  void _drawBlush(Canvas c, double cx, double cy, double r) {
    final blush = Paint()..color = blushColor..style = PaintingStyle.fill;
    for (final dx in [-0.44, 0.44]) {
      c.drawOval(
        Rect.fromCenter(center: Offset(cx + dx * r, cy + r * 0.2), width: r * 0.2, height: r * 0.12),
        blush,
      );
    }
  }

  // ── 倒三角鼻 + 弧线嘴 ──
  void _drawNoseMouth(Canvas c, double cx, double cy, double r) {
    final nose = Paint()..color = black..style = PaintingStyle.fill;
    // 倒三角鼻
    final nosePath = Path()
      ..moveTo(cx, cy + r * 0.08)
      ..lineTo(cx - r * 0.06, cy + r * 0.16)
      ..lineTo(cx + r * 0.06, cy + r * 0.16)
      ..close();
    c.drawPath(nosePath, nose);

    // 微笑弧线
    c.drawArc(
      Rect.fromCenter(center: Offset(cx, cy + r * 0.22), width: r * 0.22, height: r * 0.12),
      pi * 0.15, pi * 0.7, false,
      Paint()..color = black..style = PaintingStyle.stroke..strokeWidth = 1.0..strokeCap = StrokeCap.round,
    );
  }

  // ── 星星 ──
  void _drawSparkles(Canvas c, double cx, double cy, double r) {
    for (final sp in [
      (dx: -0.72, dy: -0.42, sz: 0.08, ph: 0.0),
      (dx: 0.6, dy: -0.55, sz: 0.065, ph: 0.35),
      (dx: 0.75, dy: -0.05, sz: 0.055, ph: 0.65),
    ]) {
      final alpha = (sin((sparklePhase + sp.ph) * 2 * pi) + 1) / 2;
      final path = Path();
      for (int i = 0; i < 8; i++) {
        final a = i * pi / 4 - pi / 2;
        final rad = i.isEven ? sp.sz : sp.sz * 0.3;
        path.lineTo(cx + sp.dx * r + cos(a) * rad * r, cy + sp.dy * r + sin(a) * rad * r);
      }
      path.close();
      c.drawPath(path, Paint()..color = starGold.withOpacity(0.25 + alpha * 0.45)..style = PaintingStyle.fill);
    }
  }

  @override
  bool shouldRepaint(covariant PandaFacePainter old) =>
      old.blinkProgress != blinkProgress || old.sparklePhase != sparklePhase ||
      old.showSparkles != showSparkles || old.leafSway != leafSway ||
      old.noteBounce != noteBounce || old.wheatSway != wheatSway ||
      old.growScale != growScale;
}
