import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../painters/grain_texture_painter.dart';

/// 宣纸肌理背景 — 米色底色 + 随机纹理 + 暗角
class GrainBackground extends StatelessWidget {
  final Widget child;
  final bool showVignette;

  const GrainBackground({
    super.key,
    required this.child,
    this.showVignette = true,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 底层：米色背景
        Container(color: AppTheme.chineseBeige),

        // 中层：宣纸肌理
        RepaintBoundary(
          child: CustomPaint(
            painter: GrainTexturePainter(),
            size: Size.infinite,
          ),
        ),

        // 顶层：暗角（增强层次感）
        if (showVignette)
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0.0, -0.2),
                radius: 1.3,
                colors: [
                  Color(0x00000000),
                  Color(0x08000000),
                ],
                stops: [0.6, 1.0],
              ),
            ),
          ),

        // 内容
        Positioned.fill(child: child),
      ],
    );
  }
}
