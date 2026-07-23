import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/gentle_copy.dart';
import '../../core/constants/app_routes.dart';

/// 作品编辑器 — 播放预览、滑杆调节、双音轨、保存/分享
class EditorPage extends StatefulWidget {
  final String workId;
  const EditorPage({super.key, required this.workId});

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  // 当前参数
  double _temperature = 0.5;
  double _speed = 1.0;
  double _instrumentMix = 0.5;
  bool _isPlaying = false;

  // 上一次保存的参数（用于撤销）
  double? _prevTemperature;
  double? _prevSpeed;
  double? _prevInstrumentMix;

  // 第二段哼唱
  bool _hasSecondTrack = false;

  // 默认值
  static const _defaultTemperature = 0.5;
  static const _defaultSpeed = 1.0;
  static const _defaultInstrumentMix = 0.5;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('编辑作品'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          // 重置按钮
          IconButton(
            icon: const Icon(Icons.restart_alt_rounded),
            tooltip: GentleCopy.reset,
            onPressed: _showResetDialog,
          ),
          // 撤销按钮
          IconButton(
            icon: const Icon(Icons.undo_rounded),
            tooltip: GentleCopy.undo,
            onPressed: _canUndo ? _undo : null,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              // 播放预览区域
              _buildPlaybackPreview(),

              const SizedBox(height: 28),

              // 三个滑杆
              Expanded(
                child: ListView(
                  children: [
                    _SliderControl(
                      label: GentleCopy.musicTemp,
                      leftLabel: GentleCopy.softWarm,
                      rightLabel: GentleCopy.intense,
                      value: _temperature,
                      onChanged: (v) {
                        _savePrevious();
                        setState(() => _temperature = v);
                      },
                    ),
                    const SizedBox(height: 20),
                    _SliderControl(
                      label: GentleCopy.musicSpeed,
                      leftLabel: GentleCopy.slow,
                      rightLabel: GentleCopy.fast,
                      value: _speed,
                      onChanged: (v) {
                        _savePrevious();
                        setState(() => _speed = v);
                      },
                    ),
                    const SizedBox(height: 20),
                    _SliderControl(
                      label: GentleCopy.instrumentMix,
                      leftLabel: GentleCopy.pureVocal,
                      rightLabel: GentleCopy.richInstrument,
                      value: _instrumentMix,
                      onChanged: (v) {
                        _savePrevious();
                        setState(() => _instrumentMix = v);
                      },
                    ),

                    const SizedBox(height: 24),

                    // 第二段哼唱按钮
                    _SecondTrackButton(
                      hasTrack: _hasSecondTrack,
                      onRecord: () => _startSecondRecording(),
                    ),
                  ],
                ),
              ),

              // 底部操作按钮
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _saveAndJumpToPostOffice,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primaryGreen,
                        side: const BorderSide(color: AppTheme.primaryGreen),
                        minimumSize: const Size(0, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                      icon: const Icon(Icons.mail_outline, size: 18),
                      label: const Text(
                        GentleCopy.jumpToPostOffice,
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _saveWork,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryGreen,
                        minimumSize: const Size(0, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                      icon: const Icon(Icons.save_outlined, size: 18),
                      label: const Text(
                        '保存',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaybackPreview() {
    return Container(
      height: 150,
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTheme.primaryGreen.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppTheme.greenStroke.withOpacity(0.5),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 播放按钮
          IconButton(
            icon: Icon(
              _isPlaying ? Icons.pause_circle : Icons.play_circle,
              size: 56,
              color: AppTheme.primaryGreen,
            ),
            onPressed: () {
              setState(() => _isPlaying = !_isPlaying);
            },
          ),
          const Text(
            '00:00 / 00:30',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),

          // 双音轨指示
          if (_hasSecondTrack)
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.chineseGreenLight.withOpacity(0.3),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.layers, size: 14, color: AppTheme.primaryGreen),
                  SizedBox(width: 4),
                  Text(
                    '双音轨',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.primaryGreen,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── 撤销逻辑 ──

  bool get _canUndo =>
      _prevTemperature != null ||
      _prevSpeed != null ||
      _prevInstrumentMix != null;

  void _savePrevious() {
    if (_prevTemperature == null) {
      _prevTemperature = _temperature;
      _prevSpeed = _speed;
      _prevInstrumentMix = _instrumentMix;
    }
  }

  void _undo() {
    if (!_canUndo) return;
    setState(() {
      if (_prevTemperature != null) {
        _temperature = _prevTemperature!;
        _speed = _prevSpeed!;
        _instrumentMix = _prevInstrumentMix!;
        _prevTemperature = null;
        _prevSpeed = null;
        _prevInstrumentMix = null;
      }
    });
  }

  // ── 重置 ──

  void _showResetDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppTheme.greenStroke, width: 1),
        ),
        title: const Text(
          GentleCopy.resetConfirm,
          style: TextStyle(fontSize: 16, color: AppTheme.textPrimary),
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              GentleCopy.notNow,
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _temperature = _defaultTemperature;
                _speed = _defaultSpeed;
                _instrumentMix = _defaultInstrumentMix;
                _prevTemperature = null;
                _prevSpeed = null;
                _prevInstrumentMix = null;
              });
              Navigator.of(ctx).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryGreen,
            ),
            child: const Text(GentleCopy.reset),
          ),
        ],
      ),
    );
  }

  // ── 第二段哼唱 ──

  void _startSecondRecording() {
    // TODO: 集成真实第二段录音流程
    setState(() => _hasSecondTrack = true);
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          GentleCopy.secondTrackHint,
          style: TextStyle(color: AppTheme.chineseInk, fontSize: 13),
          textAlign: TextAlign.center,
        ),
        backgroundColor: AppTheme.chineseBeigeAlt,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppTheme.greenStroke, width: 1),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ── 保存 & 跳转 ──

  void _saveWork() {
    // TODO: 真实持久化到 WorkRepository
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          GentleCopy.savedSuccess,
          style: TextStyle(color: AppTheme.chineseInk, fontSize: 13),
          textAlign: TextAlign.center,
        ),
        backgroundColor: AppTheme.chineseBeigeAlt,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppTheme.greenStroke, width: 1),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
    context.pop();
  }

  void _saveAndJumpToPostOffice() {
    // 保存后跳转声音邮局
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          GentleCopy.savedSuccess,
          style: TextStyle(color: AppTheme.chineseInk, fontSize: 13),
          textAlign: TextAlign.center,
        ),
        backgroundColor: AppTheme.chineseBeigeAlt,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppTheme.greenStroke, width: 1),
        ),
        duration: const Duration(seconds: 1),
      ),
    );

    // 延迟跳转，让用户看到保存成功提示
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) {
        context.push(AppRoutes.composeCard);
      }
    });
  }
}

/// 滑杆控件（编辑器内复用）
class _SliderControl extends StatelessWidget {
  final String label;
  final String leftLabel;
  final String rightLabel;
  final double value;
  final ValueChanged<double> onChanged;

  const _SliderControl({
    required this.label,
    required this.leftLabel,
    required this.rightLabel,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Text(
              leftLabel,
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme.textSecondary,
              ),
            ),
            Expanded(
              child: Slider(
                value: value,
                onChanged: onChanged,
                activeColor: AppTheme.primaryGreen,
                inactiveColor: AppTheme.divider,
              ),
            ),
            Text(
              rightLabel,
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 第二段哼唱按钮
class _SecondTrackButton extends StatelessWidget {
  final bool hasTrack;
  final VoidCallback onRecord;

  const _SecondTrackButton({
    required this.hasTrack,
    required this.onRecord,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: hasTrack
            ? AppTheme.primaryGreen.withOpacity(0.06)
            : AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasTrack ? AppTheme.primaryGreen : AppTheme.divider,
          width: hasTrack ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: [
          Icon(
            hasTrack ? Icons.check_circle : Icons.mic,
            color: hasTrack
                ? AppTheme.primaryGreen
                : AppTheme.textSecondary,
            size: 28,
          ),
          const SizedBox(height: 8),
          Text(
            hasTrack ? '已添加第二段哼唱 ✅' : GentleCopy.secondTrack,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: hasTrack
                  ? AppTheme.primaryGreen
                  : AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            GentleCopy.secondTrackHint,
            style: const TextStyle(
              fontSize: 11,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onRecord,
            style: OutlinedButton.styleFrom(
              foregroundColor: hasTrack
                  ? AppTheme.primaryGreen
                  : AppTheme.textSecondary,
              side: BorderSide(
                color: hasTrack
                    ? AppTheme.primaryGreen
                    : AppTheme.divider,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            icon: Icon(
              hasTrack ? Icons.refresh : Icons.fiber_manual_record,
              size: 16,
            ),
            label: Text(hasTrack ? '重新录制' : '开始录制'),
          ),
        ],
      ),
    );
  }
}
