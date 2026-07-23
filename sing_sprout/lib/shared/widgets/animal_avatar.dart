import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../models/user_profile.dart';
import '../painters/panda_face_painter.dart';

/// 熊猫状态
enum PandaState { idle, recording, generating }

/// 守护动物头像 — 动画熊猫 + 国风渐变外圈
class AnimalAvatar extends StatefulWidget {
  final GuardianAnimal animal;
  final double size;
  final String? speechBubble;
  final PandaState pandaState;
  final double recordingAmplitude; // 0~1，录音音量

  const AnimalAvatar({
    super.key,
    this.animal = GuardianAnimal.panda,
    this.size = 80,
    this.speechBubble,
    this.pandaState = PandaState.idle,
    this.recordingAmplitude = 0.0,
  });

  @override
  State<AnimalAvatar> createState() => _AnimalAvatarState();
}

class _AnimalAvatarState extends State<AnimalAvatar>
    with TickerProviderStateMixin {
  late AnimationController _breathController;
  late AnimationController _blinkController;
  late AnimationController _swayController;
  late AnimationController _sparkleController;
  late AnimationController _leafController;
  late AnimationController _noteController;
  late AnimationController _wheatController;
  late AnimationController _growController;

  @override
  void initState() {
    super.initState();
    _breathController = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 4000),
    )..repeat(reverse: true);

    _blinkController = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 3500),
    )..repeat();

    _swayController = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1500),
    );

    _sparkleController = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2000),
    );

    // 叶子、音符、麦穗：各自不同频率的摆动
    _leafController = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2800),
    )..repeat();

    _noteController = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1800),
    )..repeat();

    _wheatController = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 3200),
    )..repeat();

    // 生长动画（生成音乐时触发）
    _growController = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200),
    );
  }

  @override
  void didUpdateWidget(covariant AnimalAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pandaState == PandaState.recording && !_swayController.isAnimating) {
      _swayController.repeat(reverse: true);
      _sparkleController.stop();
      _growController.stop();
      _growController.reset();
    } else if (widget.pandaState == PandaState.generating && !_sparkleController.isAnimating) {
      _sparkleController.repeat();
      _swayController.stop();
      _growController.forward(from: 0);
    } else if (widget.pandaState == PandaState.idle) {
      _swayController.stop();
      _swayController.reset();
      _sparkleController.stop();
      _sparkleController.reset();
      _growController.reset();
    }
  }

  @override
  void dispose() {
    _breathController.dispose();
    _blinkController.dispose();
    _swayController.dispose();
    _sparkleController.dispose();
    _leafController.dispose();
    _noteController.dispose();
    _wheatController.dispose();
    _growController.dispose();
    super.dispose();
  }

  /// 眨眼进度：0→1→0 快速完成一次眨眼
  double _blinkProgress(double t) {
    // t 在 0~1 之间循环，眨眼只占 0~0.08 和 0.92~1 区间
    const blinkStart = 0.0;
    const blinkDuration = 0.06;
    if (t < blinkStart + blinkDuration) {
      final bt = (t - blinkStart) / blinkDuration;
      return sin(bt * pi); // 0→1→0
    }
    return 0.0;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 对话气泡
        if (widget.speechBubble != null) ...[
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
              widget.speechBubble!,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textPrimary,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          CustomPaint(
            size: const Size(14, 8),
            painter: _BubbleTrianglePainter(
              color: AppTheme.primaryGreen.withOpacity(0.04),
              strokeColor: AppTheme.greenStroke,
              strokeWidth: 1.5,
            ),
          ),
        ],

        // 熊猫 — 动画层
        AnimatedBuilder(
          animation: Listenable.merge([
            _breathController, _blinkController, _swayController,
            _sparkleController, _leafController, _noteController,
            _wheatController, _growController,
          ]),
          builder: (context, _) {
            final breath = sin(_breathController.value * 2 * pi) * 3.5;
            final blink = _blinkProgress(_blinkController.value);
            final sparklePhase = _sparkleController.value;

            // 叶子、音符、麦穗各自的摆动相位
            final leafPhase = _leafController.value;
            final notePhase = _noteController.value;
            final wheatPhase = _wheatController.value;
            final grow = (_growController.isAnimating || widget.pandaState == PandaState.generating)
                ? _growController.value.clamp(0.0, 1.0)
                : 1.0;

            double swayAngle = 0;
            if (widget.pandaState == PandaState.recording) {
              swayAngle = sin(_swayController.value * 2 * pi) * 0.03 +
                  widget.recordingAmplitude * 0.04;
            }
            double nodAngle = 0;
            if (widget.pandaState == PandaState.generating) {
              nodAngle = sin(_sparkleController.value * 2 * pi) * 0.04;
            }

            return Transform.translate(
              offset: Offset(0, breath),
              child: Transform.rotate(
                angle: swayAngle + nodAngle,
                child: _buildPandaCircle(
                  blink: blink,
                  sparklePhase: sparklePhase,
                  leafSway: leafPhase,
                  noteBounce: notePhase,
                  wheatSway: wheatPhase,
                  growScale: grow,
                ),
              ),
            );
          },
        ),

        const SizedBox(height: 4),
        Text(
          widget.animal.displayName,
          style: const TextStyle(
            fontSize: 11,
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildPandaCircle({
    required double blink,
    required double sparklePhase,
    required double leafSway,
    required double noteBounce,
    required double wheatSway,
    required double growScale,
  }) {
    final showSparkles = widget.pandaState == PandaState.generating;
    final s = widget.size;

    // 足够的空间展示熊猫脸 + 头顶装饰 + 耳朵（避免裁剪）
    return SizedBox(
      width: s + 24,
      height: s + 30,
      child: CustomPaint(
        size: Size(s + 24, s + 30),
        painter: PandaFacePainter(
          blinkProgress: blink,
          sparklePhase: sparklePhase,
          showSparkles: showSparkles,
          leafSway: leafSway,
          noteBounce: noteBounce,
          wheatSway: wheatSway,
          growScale: growScale,
        ),
      ),
    );
  }
}

/// 气泡底部小三角
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
      ..moveTo(size.width / 2, size.height)
      ..lineTo(size.width * 0.3, 0)
      ..lineTo(size.width * 0.7, 0)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawLine(
      Offset(size.width * 0.3, 0),
      Offset(size.width * 0.7, 0),
      Paint()
        ..color = strokeColor
        ..strokeWidth = strokeWidth,
    );
  }

  @override
  bool shouldRepaint(covariant _BubbleTrianglePainter old) => false;
}
