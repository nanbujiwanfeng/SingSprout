import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/gentle_copy.dart';
import '../../core/constants/enums.dart';
import '../../core/constants/app_routes.dart';
import '../../shared/widgets/mood_color_picker.dart';
import '../../shared/widgets/sprout_loading_overlay.dart';
import '../../shared/widgets/style_preview_card.dart';

/// 录音与 AI 生成页面
class RecordingPage extends StatefulWidget {
  final String? recordingPath;

  const RecordingPage({super.key, this.recordingPath});

  @override
  State<RecordingPage> createState() => _RecordingPageState();
}

class _RecordingPageState extends State<RecordingPage> {
  StyleSeed _selectedStyle = StyleSeed.morningDew;
  MoodColor? _selectedMood;

  bool _isGenerating = false;
  bool _isTimedOut = false;
  final GlobalKey<SproutLoadingOverlayState> _sproutKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final hasRecording = widget.recordingPath != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('创作'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 芽苗加载动画 / 录音状态
              if (_isGenerating)
                SproutLoadingOverlay(
                  key: _sproutKey,
                  onTimeout: () {
                    setState(() => _isTimedOut = true);
                    _showGentleSnackBar(GentleCopy.modelFallback);
                  },
                  onComplete: () {
                    _navigateToEditor();
                  },
                )
              else
                _buildRecordingStatus(hasRecording),

              const SizedBox(height: 32),

              // 风格选择
              Text(
                GentleCopy.selectStyle,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                GentleCopy.previewHint,
                style: TextStyle(
                  fontSize: 11,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 12),

              // 横向风格卡片
              SizedBox(
                height: 155,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: StyleSeed.values.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final style = StyleSeed.values[index];
                    return StylePreviewCard(
                      style: style,
                      isSelected: style == _selectedStyle,
                      width: 105,
                      onSelected: () {
                        setState(() => _selectedStyle = style);
                      },
                    );
                  },
                ),
              ),

              const SizedBox(height: 24),

              // 心情贴纸（可跳过）
              const Text(
                '今天的心情（可选）',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              MoodColorPicker(
                selected: _selectedMood,
                onSelected: (mood) => setState(() => _selectedMood = mood),
              ),

              const SizedBox(height: 32),

              // 生成按钮
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isGenerating ? null : _startGeneration,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryGreen,
                    disabledBackgroundColor:
                        AppTheme.primaryGreen.withOpacity(0.4),
                  ),
                  child: Text(
                    _isTimedOut
                        ? '🔄 ${GentleCopy.modelFallback}'
                        : '✨ AI 生成音乐',
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecordingStatus(bool hasRecording) {
    return Container(
      height: 120,
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTheme.primaryGreen.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppTheme.greenStroke.withOpacity(0.5),
          width: 1,
        ),
      ),
      child: Center(
        child: hasRecording
            ? const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    color: AppTheme.primaryGreen,
                    size: 40,
                  ),
                  SizedBox(height: 8),
                  Text(
                    GentleCopy.recordingDone,
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                ],
              )
            : const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.mic,
                    color: AppTheme.primaryGreen,
                    size: 36,
                  ),
                  SizedBox(height: 8),
                  Text(
                    GentleCopy.processing,
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  void _startGeneration() {
    setState(() {
      _isGenerating = true;
      _isTimedOut = false;
    });

    // 模拟 AI 生成流程：2 秒后完成
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && _isGenerating) {
        _sproutKey.currentState?.complete();
      }
    });
  }

  void _navigateToEditor() {
    if (!mounted) return;
    setState(() => _isGenerating = false);
    context.go('${AppRoutes.editor}?id=new');
  }

  void _showGentleSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            color: AppTheme.chineseInk,
            fontSize: 13,
          ),
          textAlign: TextAlign.center,
        ),
        backgroundColor: AppTheme.chineseBeigeAlt,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppTheme.greenStroke, width: 1),
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }
}
