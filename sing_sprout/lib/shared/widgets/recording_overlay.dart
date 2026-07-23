import 'package:flutter/material.dart';
import '../painters/particle_wave_painter.dart';

/// 录音粒子覆盖层 — 在录音按钮周围显示动态粒子波形
class RecordingOverlay extends StatefulWidget {
  final double amplitude;   // 当前音量 0~1
  final bool isRecording;   // 是否正在录音
  final double buttonRadius;

  const RecordingOverlay({
    super.key,
    required this.amplitude,
    required this.isRecording,
    this.buttonRadius = 60,
  });

  @override
  State<RecordingOverlay> createState() => _RecordingOverlayState();
}

class _RecordingOverlayState extends State<RecordingOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );

    if (widget.isRecording) {
      _animController.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant RecordingOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRecording && !_animController.isAnimating) {
      _animController.repeat();
    } else if (!widget.isRecording && _animController.isAnimating) {
      _animController.stop();
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final overlaySize = (widget.buttonRadius + 60) * 2;

    return AnimatedOpacity(
      opacity: widget.isRecording ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 300),
      child: IgnorePointer(
        child: SizedBox(
          width: overlaySize,
          height: overlaySize,
          child: AnimatedBuilder(
            animation: _animController,
            builder: (context, _) {
              return CustomPaint(
                painter: ParticleWavePainter(
                  animationValue: _animController.value,
                  amplitude: widget.amplitude,
                  buttonRadius: widget.buttonRadius,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
