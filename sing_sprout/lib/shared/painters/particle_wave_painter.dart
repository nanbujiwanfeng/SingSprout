import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// 录音粒子波形 Painter
/// 根据动画进度和音量幅值绘制动态粒子环
class ParticleWavePainter extends CustomPainter {
  final double animationValue; // 0.0 ~ 1.0 循环
  final double amplitude;      // 0.0 ~ 1.0 音量归一化值
  final double buttonRadius;   // 按钮半径

  ParticleWavePainter({
    required this.animationValue,
    required this.amplitude,
    required this.buttonRadius,
  });

  static const int _particleCount = 50;
  static const double _baseRingOffset = 16;  // 粒子环距按钮边缘的基础距离
  static const double _maxDisplacement = 36;  // 最大波动距离

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final rand = Random(42); // 固定种子

    for (int i = 0; i < _particleCount; i++) {
      final angle = (i / _particleCount) * 2 * pi;
      final phase = rand.nextDouble() * 2 * pi;
      final baseRadius = buttonRadius + _baseRingOffset + rand.nextDouble() * 12;

      // 半径 = 基础半径 + sin 波动 * 音量 * 最大位移
      final displacement =
          sin(animationValue * 2 * pi + phase) * amplitude * _maxDisplacement;
      final radius = baseRadius + displacement;

      final x = center.dx + cos(angle) * radius;
      final y = center.dy + sin(angle) * radius;

      // 颜色插值：安静(深绿) → 中等(淡绿) → 大声(金色)
      final color = _lerpParticleColor(amplitude);

      // 透明度随音量变化，最低也有 0.15
      final opacity = 0.15 + amplitude * 0.55;
      // 大小随音量变化
      final dotRadius = 1.5 + amplitude * 2.0 + rand.nextDouble() * 0.5;

      final paint = Paint()
        ..color = color.withOpacity(opacity)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(Offset(x, y), dotRadius, paint);
    }
  }

  /// 根据音量在深绿 → 淡绿 → 金色之间插值
  Color _lerpParticleColor(double amp) {
    if (amp < 0.4) {
      // 安静：深绿 → 淡绿
      final t = amp / 0.4;
      return Color.lerp(AppTheme.chineseGreenDark, AppTheme.chineseGreenLight, t)!;
    } else if (amp < 0.7) {
      // 中等：淡绿 → 主绿
      final t = (amp - 0.4) / 0.3;
      return Color.lerp(AppTheme.chineseGreenLight, AppTheme.primaryGreen, t)!;
    } else {
      // 大声：主绿 → 淡金
      final t = ((amp - 0.7) / 0.3).clamp(0.0, 1.0);
      return Color.lerp(AppTheme.primaryGreen, AppTheme.chineseGold, t)!;
    }
  }

  @override
  bool shouldRepaint(covariant ParticleWavePainter oldDelegate) =>
      oldDelegate.animationValue != animationValue ||
      oldDelegate.amplitude != amplitude;
}
