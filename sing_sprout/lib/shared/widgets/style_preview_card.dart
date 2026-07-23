import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/gentle_copy.dart';
import '../../core/constants/enums.dart';

/// 风格预览卡片 — 横向排列，长按 3 秒试听
class StylePreviewCard extends StatefulWidget {
  final StyleSeed style;
  final bool isSelected;
  final VoidCallback onSelected;
  final double width;

  const StylePreviewCard({
    super.key,
    required this.style,
    required this.isSelected,
    required this.onSelected,
    this.width = 100,
  });

  @override
  State<StylePreviewCard> createState() => _StylePreviewCardState();
}

class _StylePreviewCardState extends State<StylePreviewCard>
    with SingleTickerProviderStateMixin {
  bool _isPreviewing = false;
  Timer? _previewTimer;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
  }

  @override
  void dispose() {
    _previewTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _startPreview() {
    if (_isPreviewing) return;
    setState(() => _isPreviewing = true);
    _pulseController.repeat(reverse: true);

    // 3 秒后自动停止
    _previewTimer?.cancel();
    _previewTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _isPreviewing = false);
        _pulseController.stop();
        _pulseController.reset();
      }
    });
  }

  void _stopPreview() {
    _previewTimer?.cancel();
    if (mounted) {
      setState(() => _isPreviewing = false);
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isActive = widget.isSelected || _isPreviewing;

    return GestureDetector(
      onTap: widget.onSelected,
      onLongPressStart: (_) => _startPreview(),
      onLongPressEnd: (_) => _stopPreview(),
      onLongPressCancel: _stopPreview,
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, _) {
          final pulseScale =
              _isPreviewing ? 1.0 + _pulseController.value * 0.03 : 1.0;

          return Transform.scale(
            scale: pulseScale,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: widget.width,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
              decoration: BoxDecoration(
                color: isActive
                    ? AppTheme.primaryGreen.withOpacity(0.08)
                    : AppTheme.bgCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _isPreviewing
                      ? AppTheme.chineseGold
                      : isActive
                          ? AppTheme.primaryGreen
                          : AppTheme.divider,
                  width: isActive ? 2 : 1,
                ),
                boxShadow: isActive
                    ? [
                        BoxShadow(
                          color: (_isPreviewing
                                  ? AppTheme.chineseGold
                                  : AppTheme.primaryGreen)
                              .withOpacity(0.15),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 风格图标
                  Text(
                    widget.style.icon,
                    style: TextStyle(
                      fontSize: 28,
                    ),
                  ),
                  const SizedBox(height: 6),

                  // 风格名称
                  Text(
                    widget.style.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          widget.isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isActive
                          ? AppTheme.primaryGreen
                          : AppTheme.textPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 2),

                  // 风格描述
                  Text(
                    widget.style.description,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppTheme.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),

                  const SizedBox(height: 6),

                  // 预览状态指示
                  _isPreviewing
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            SizedBox(
                              width: 10,
                              height: 10,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: AppTheme.chineseGold,
                              ),
                            ),
                            SizedBox(width: 4),
                            Text(
                              GentleCopy.previewPlaying,
                              style: TextStyle(
                                fontSize: 9,
                                color: AppTheme.chineseGold,
                              ),
                            ),
                          ],
                        )
                      : const Text(
                          GentleCopy.previewHint,
                          style: TextStyle(
                            fontSize: 9,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
