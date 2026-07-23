import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/gentle_copy.dart';
import '../painters/sprout_growth_painter.dart';

/// 芽苗生长加载组件
/// 包含 CustomPainter 动画 + 阶段文案 + 15s 超时兜底
class SproutLoadingOverlay extends StatefulWidget {
  /// 超时回调 — 切换轻量化模型
  final VoidCallback? onTimeout;

  /// 生成完成回调
  final VoidCallback? onComplete;

  const SproutLoadingOverlay({
    super.key,
    this.onTimeout,
    this.onComplete,
  });

  @override
  State<SproutLoadingOverlay> createState() => SproutLoadingOverlayState();
}

class SproutLoadingOverlayState extends State<SproutLoadingOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  Timer? _timeoutTimer;
  bool _isTimedOut = false;

  /// 超时时长 12 秒（离线模式限制）
  static const _timeoutSeconds = 12;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat();

    // 15 秒超时
    _timeoutTimer = Timer(const Duration(seconds: _timeoutSeconds), () {
      if (mounted) {
        setState(() => _isTimedOut = true);
        widget.onTimeout?.call();
      }
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    _timeoutTimer?.cancel();
    super.dispose();
  }

  /// 主动完成（外部调用）
  void complete() {
    _timeoutTimer?.cancel();
    _animController.stop();
    widget.onComplete?.call();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animController,
      builder: (context, _) {
        final progress = _animController.value;

        // 确定当前阶段
        String phaseText;
        if (progress < 0.3) {
          phaseText = GentleCopy.sproutPhase1;
        } else if (progress < 0.7) {
          phaseText = GentleCopy.sproutPhase2;
        } else {
          phaseText = GentleCopy.sproutPhase3;
        }

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          decoration: BoxDecoration(
            color: AppTheme.primaryGreen.withOpacity(0.04),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppTheme.greenStroke.withOpacity(0.5),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 芽苗动画
              SizedBox(
                width: 140,
                height: 140,
                child: CustomPaint(
                  painter: SproutGrowthPainter(
                    progress: progress,
                    size: 120,
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // 主文案
              Text(
                _isTimedOut
                    ? GentleCopy.modelFallback
                    : GentleCopy.sprouting,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: _isTimedOut
                      ? AppTheme.chineseGold
                      : AppTheme.primaryGreen,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 4),

              // 阶段文案 / 超时提示
              Text(
                _isTimedOut
                    ? GentleCopy.modelFallbackHint
                    : phaseText,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),

              // 超时后的进度指示
              if (_isTimedOut) ...[
                const SizedBox(height: 12),
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppTheme.chineseGold,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
