import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../models/user_profile.dart';

/// 守护动物头像 — 国风渐变外圈 + 悬浮阴影 + 圆角气泡
class AnimalAvatar extends StatelessWidget {
  final GuardianAnimal animal;
  final double size;
  final String? speechBubble;

  const AnimalAvatar({
    super.key,
    this.animal = GuardianAnimal.panda,
    this.size = 72,
    this.speechBubble,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 对话气泡
        if (speechBubble != null) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            constraints: const BoxConstraints(maxWidth: 220),
            decoration: BoxDecoration(
              color: AppTheme.primaryGreen.withOpacity(0.04),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: AppTheme.greenStroke,
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              speechBubble!,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textPrimary,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ),

          // 气泡小三角
          CustomPaint(
            size: const Size(14, 8),
            painter: _BubbleTrianglePainter(
              color: AppTheme.primaryGreen.withOpacity(0.04),
              strokeColor: AppTheme.greenStroke,
              strokeWidth: 1.5,
            ),
          ),
        ],

        // 动物头像 — 渐变外圈
        Container(
          width: size + 6,
          height: size + 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [
                AppTheme.chineseGreenLight,
                AppTheme.primaryGreen,
                AppTheme.chineseGreenDark,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryGreen.withOpacity(0.25),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: Container(
              width: size,
              height: size,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
              child: Center(
                child: Text(
                  animal.emoji,
                  style: TextStyle(fontSize: size * 0.45),
                ),
              ),
            ),
          ),
        ),

        const SizedBox(height: 4),
        Text(
          animal.displayName,
          style: const TextStyle(
            fontSize: 11,
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// 气泡底部小三角 Painter
class _BubbleTrianglePainter extends CustomPainter {
  final Color color;
  final Color strokeColor;
  final double strokeWidth;

  _BubbleTrianglePainter({
    required this.color,
    required this.strokeColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width / 2, size.height) // 底部尖角
      ..lineTo(size.width * 0.3, 0)
      ..lineTo(size.width * 0.7, 0)
      ..close();

    // 填充
    canvas.drawPath(path, Paint()..color = color);
    // 描边（仅左右上边，下边不描）
    canvas.drawLine(
      Offset(size.width * 0.3, 0),
      Offset(size.width * 0.7, 0),
      Paint()
        ..color = strokeColor
        ..strokeWidth = strokeWidth,
    );
  }

  @override
  bool shouldRepaint(covariant _BubbleTrianglePainter oldDelegate) => false;
}
