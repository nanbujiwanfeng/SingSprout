import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// 录音按钮 — 径向渐变绿色，长按缩放动效，松开弹簧回弹
class RecordButton extends StatefulWidget {
  final VoidCallback onRecordingStart;
  final VoidCallback onRecordingStop;
  final double size;
  final bool enabled;

  const RecordButton({
    super.key,
    required this.onRecordingStart,
    required this.onRecordingStop,
    this.size = 120,
    this.enabled = true,
  });

  /// 按钮内圈（不含阴影）的半径，供外部粒子动画定位
  double get innerRadius => size / 2;

  @override
  State<RecordButton> createState() => _RecordButtonState();
}

class _RecordButtonState extends State<RecordButton>
    with SingleTickerProviderStateMixin {
  bool _isPressed = false;

  /// 按压缩放控制器
  late AnimationController _pressScaleController;
  late Animation<double> _pressScaleAnimation;

  /// 空闲阴影呼吸控制器
  late AnimationController _shadowBreathController;
  late Animation<double> _shadowBreathAnimation;

  @override
  void initState() {
    super.initState();

    // 按压缩放：150ms ease-out 缩到 0.88
    _pressScaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _pressScaleAnimation = Tween<double>(begin: 1.0, end: 0.88).animate(
      CurvedAnimation(
        parent: _pressScaleController,
        curve: Curves.easeOut,
      ),
    );
    _pressScaleController.addListener(() => setState(() {}));

    // 空闲阴影呼吸：2s 循环
    _shadowBreathController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _shadowBreathAnimation = Tween<double>(begin: 0.12, end: 0.25).animate(
      CurvedAnimation(
        parent: _shadowBreathController,
        curve: Curves.easeInOut,
      ),
    );
    _shadowBreathController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _pressScaleController.dispose();
    _shadowBreathController.dispose();
    super.dispose();
  }

  void _onPressStart(_) {
    if (!widget.enabled) return;
    setState(() => _isPressed = true);
    _shadowBreathController.stop();
    _pressScaleController.forward();
    widget.onRecordingStart();
  }

  void _onPressEnd(_) {
    if (!widget.enabled || !_isPressed) return;
    setState(() => _isPressed = false);
    _pressScaleController.reverse().then((_) {
      // 弹簧回弹完成后恢复呼吸阴影
      if (!_isPressed) {
        _shadowBreathController.repeat(reverse: true);
      }
    });
    widget.onRecordingStop();
  }

  @override
  Widget build(BuildContext context) {
    final currentScale = _isPressed
        ? _pressScaleAnimation.value
        : _pressScaleAnimation.value;

    // 阴影透明度：按压时略深，空闲时呼吸
    final shadowOpacity = _isPressed
        ? 0.3
        : _shadowBreathAnimation.value;

    return GestureDetector(
      onLongPressStart: _onPressStart,
      onLongPressEnd: _onPressEnd,
      child: Transform.scale(
        scale: currentScale,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const RadialGradient(
              center: Alignment(-0.1, -0.1),
              colors: [
                AppTheme.chineseGreenLight,  // 中心：淡亮
                AppTheme.primaryGreen,       // 中间：品牌绿
                AppTheme.chineseGreenDark,   // 边缘：深绿
              ],
              stops: [0.0, 0.5, 1.0],
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryGreen.withOpacity(shadowOpacity),
                blurRadius: _isPressed ? 20 : 14,
                spreadRadius: _isPressed ? 2 : 0,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 麦克风图标
              Icon(
                _isPressed ? Icons.mic : Icons.mic_none_rounded,
                color: Colors.white,
                size: widget.size * 0.38,
              ),

              // 录音指示小圆点（录音时显示）
              if (_isPressed)
                Positioned(
                  top: widget.size * 0.22,
                  child: _RecordingDot(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 录音状态指示小圆点 — 脉冲动画
class _RecordingDot extends StatefulWidget {
  @override
  State<_RecordingDot> createState() => _RecordingDotState();
}

class _RecordingDotState extends State<_RecordingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _dotController;

  @override
  void initState() {
    super.initState();
    _dotController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _dotController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _dotController,
      builder: (context, _) {
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.chineseGold.withOpacity(
              0.6 + _dotController.value * 0.4,
            ),
          ),
        );
      },
    );
  }
}
