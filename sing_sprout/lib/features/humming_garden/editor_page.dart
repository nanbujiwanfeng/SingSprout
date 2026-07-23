import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/gentle_copy.dart';
import '../../core/constants/app_routes.dart';
import '../../core/constants/enums.dart';
import '../../shared/models/music_work.dart';
import '../../shared/services/work_repository.dart';
import 'humming_garden_provider.dart';

/// 作品编辑器 — 播放预览、滑杆调节、双音轨、保存/分享
class EditorPage extends StatefulWidget {
  final String workId;
  final String recordingPath;
  final String styleName;
  final String moodName;

  const EditorPage({
    super.key,
    required this.workId,
    this.recordingPath = '',
    this.styleName = '',
    this.moodName = '',
  });

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

  // 录音数据（从构造器参数）
  String _recordingPath = '';
  StyleSeed _styleSeed = StyleSeed.morningDew;
  MoodColor? _moodColor;

  // 默认值
  static const _defaultTemperature = 0.5;
  static const _defaultSpeed = 1.0;
  static const _defaultInstrumentMix = 0.5;

  @override
  void initState() {
    super.initState();
    _recordingPath = widget.recordingPath;
    if (widget.styleName.isNotEmpty) {
      try {
        _styleSeed = StyleSeed.values.byName(widget.styleName);
      } catch (_) {}
    }
    if (widget.moodName.isNotEmpty) {
      try {
        _moodColor = MoodColor.values.byName(widget.moodName);
      } catch (_) {}
    }
  }

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

              // 底部操作按钮 — 2×2 网格
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.save_outlined,
                      label: GentleCopy.save,
                      isPrimary: true,
                      onTap: _saveWork,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.mail_outline,
                      label: GentleCopy.sendToParents,
                      isPrimary: false,
                      onTap: _saveAndJumpToPostOffice,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.park,
                      label: GentleCopy.shareToTree,
                      isPrimary: false,
                      onTap: _shareToTree,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.add_circle_outline,
                      label: GentleCopy.continueCreating,
                      isPrimary: false,
                      onTap: _continueCreating,
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

  /// 创建并持久化 MusicWork
  MusicWork _createWork() {
    final now = DateTime.now();
    return MusicWork(
      id: now.millisecondsSinceEpoch.toString(),
      title: '${_styleSeed.label} · ${now.month}/${now.day}',
      audioPath: _recordingPath,
      styleSeed: _styleSeed,
      moodSticker: _moodColor,
      duration: const Duration(seconds: 30),
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<void> _persistWork(MusicWork work) async {
    // 1. 添加到 Provider（内存）
    if (mounted) {
      context.read<HummingGardenProvider>().addWork(work);
    }
    // 2. 持久化到文件
    await WorkRepository().addWork(work);
  }

  Future<void> _saveWork() async {
    final work = _createWork();
    await _persistWork(work);
    if (!mounted) return;
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

  Future<void> _saveAndJumpToPostOffice() async {
    final work = _createWork();
    await _persistWork(work);
    if (!mounted) return;
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

    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) {
        context.push(AppRoutes.composeCard);
      }
    });
  }

  /// 种到音乐树
  void _shareToTree() {
    final work = _createWork();
    _persistWork(work);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(GentleCopy.shareToTreeHint,
            style: TextStyle(color: AppTheme.chineseInk, fontSize: 13),
            textAlign: TextAlign.center),
        backgroundColor: AppTheme.chineseBeigeAlt,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppTheme.greenStroke, width: 1)),
        duration: const Duration(seconds: 2),
      ),
    );
    context.pop();
  }

  /// 继续创作
  void _continueCreating() {
    final work = _createWork();
    _persistWork(work);
    context.pop();
  }
}

/// 操作按钮（编辑器底部 2×2 网格复用）
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isPrimary;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.isPrimary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (isPrimary) {
      return ElevatedButton.icon(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primaryGreen,
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
        icon: Icon(icon, size: 18),
        label: Text(label, style: const TextStyle(fontSize: 12)),
      );
    }
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.primaryGreen,
        side: const BorderSide(color: AppTheme.primaryGreen),
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontSize: 12)),
    );
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
