import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/gentle_copy.dart';
import '../../core/constants/app_routes.dart';
import '../../shared/models/music_work.dart';
import '../../shared/widgets/record_button.dart';
import '../../shared/widgets/animal_avatar.dart';
import '../../shared/widgets/grain_background.dart';
import '../../shared/widgets/recording_overlay.dart';
import '../../shared/models/user_profile.dart';
import '../../shared/providers/audio_provider.dart';
import 'humming_garden_provider.dart';

/// 哼唱花园 — 首页 & MVP 核心创作入口
class HummingGardenPage extends StatefulWidget {
  const HummingGardenPage({super.key});

  @override
  State<HummingGardenPage> createState() => _HummingGardenPageState();
}

class _HummingGardenPageState extends State<HummingGardenPage> {
  bool _isRecording = false;

  @override
  void initState() {
    super.initState();
    // 绑定 AudioProvider 的最大时长回调
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final audioProvider = context.read<AudioProvider>();
      audioProvider.onMaxDurationReached = _onMaxDurationReached;
    });
  }

  void _onMaxDurationReached() {
    _handleRecordingStop(autoStopped: true);
  }

  Future<void> _handleRecordingStart() async {
    final audioProvider = context.read<AudioProvider>();

    await audioProvider.startRecording();

    if (mounted && audioProvider.isRecording) {
      setState(() => _isRecording = true);
    } else if (mounted) {
      // 权限未授予 → 温柔引导
      _showGentleSnackBar(GentleCopy.micPermissionHint);
    }
  }

  Future<void> _handleRecordingStop({bool autoStopped = false}) async {
    if (!_isRecording && !autoStopped) return;

    final audioProvider = context.read<AudioProvider>();

    if (!audioProvider.isRecording) return;

    final path = await audioProvider.stopRecording();

    if (!mounted) return;

    setState(() => _isRecording = false);

    // 检查录音时长
    if (audioProvider.isTooShort) {
      // 时长不足 → 温柔提示
      _showGentleDialog(
        GentleCopy.tooShort,
        GentleCopy.tooShortHint,
      );
      audioProvider.reset();
      return;
    }

    if (autoStopped) {
      _showGentleSnackBar(GentleCopy.maxTimeReached);
    }

    // 跳转录音详情页
    if (mounted) {
      context.pushNamed(
        'recording',
        queryParameters: path != null ? {'path': path} : {},
      );
      audioProvider.processingComplete();
    }
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
            fontSize: 14,
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
        elevation: 2,
      ),
    );
  }

  void _showGentleDialog(String title, String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppTheme.greenStroke, width: 1),
        ),
        title: Text(
          title,
          style: GoogleFonts.maShanZheng(
            fontSize: 22,
            color: AppTheme.primaryGreen,
          ),
          textAlign: TextAlign.center,
        ),
        content: Text(
          message,
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 14,
          ),
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.primaryGreen,
            ),
            child: const Text('好的～'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GrainBackground(
        child: SafeArea(
          child: Stack(
            children: [
              // 主内容区域
              _buildMainContent(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    const buttonSize = 120.0;

    return Column(
      children: [
        const SizedBox(height: 28),

        // 书法标题
        _buildTitle(),

        const SizedBox(height: 32),

        // 熊猫头像问候
        const AnimalAvatar(
          animal: GuardianAnimal.panda,
          size: 80,
          speechBubble: GentleCopy.pandaGreeting,
        ),

        const SizedBox(height: 48),

        const Spacer(),

        // 录音按钮 + 粒子覆盖层
        SizedBox(
          width: buttonSize + 120,
          height: buttonSize + 120,
          child: Consumer<AudioProvider>(
            builder: (context, audio, _) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  // 粒子覆盖层
                  RecordingOverlay(
                    amplitude: audio.currentAmplitude,
                    isRecording: _isRecording,
                    buttonRadius: buttonSize / 2,
                  ),

                  // 录音按钮
                  RecordButton(
                    size: buttonSize,
                    onRecordingStart: _handleRecordingStart,
                    onRecordingStop: () => _handleRecordingStop(),
                  ),
                ],
              );
            },
          ),
        ),

        const SizedBox(height: 12),

        // 提示文字
        const Text(
          GentleCopy.hintLongPress,
          style: TextStyle(
            fontSize: 14,
            color: AppTheme.textSecondary,
            letterSpacing: 1.0,
          ),
        ),

        const Spacer(),

        // 最近作品
        const _RecentWorksSection(),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildTitle() {
    return Text(
      GentleCopy.pageTitle,
      style: GoogleFonts.maShanZheng(
        textStyle: AppTheme.calligraphyTitle,
      ),
    );
  }
}

/// 最近作品区
class _RecentWorksSection extends StatelessWidget {
  const _RecentWorksSection();

  @override
  Widget build(BuildContext context) {
    return Consumer<HummingGardenProvider>(
      builder: (context, provider, _) {
        final works = provider.works;

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    GentleCopy.recentWorksTitle,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  if (works.isNotEmpty)
                    TextButton(
                      onPressed: () {
                        // 跳转作品集（音乐树页面）
                        context.go(AppRoutes.musicTree);
                      },
                      child: const Text(
                        GentleCopy.viewAll,
                        style: TextStyle(color: AppTheme.primaryGreen),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),

              // 空态
              if (works.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  decoration: BoxDecoration(
                    color: AppTheme.bgCard,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppTheme.divider,
                      width: 1,
                    ),
                  ),
                  child: const Text(
                    GentleCopy.emptyWorks,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                )
              else
                SizedBox(
                  height: 110,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: works.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (context, index) {
                      final work = works[index];
                      return _WorkCard(work: work);
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// 单个作品卡片 — 统一圆角 16 + 阴影 + 国风配色
class _WorkCard extends StatelessWidget {
  final MusicWork work;
  const _WorkCard({required this.work});

  @override
  Widget build(BuildContext context) {
    // 格式化时长
    final d = work.duration;
    final min = d.inMinutes;
    final sec = d.inSeconds % 60;
    final durationText = '$min:${sec.toString().padLeft(2, '0')}';

    return Container(
      width: 110,
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.divider,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryGreen.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            // 跳转编辑器
            context.push('${AppRoutes.editor}?id=${work.id}');
          },
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 风格图标
              Text(
                work.styleSeed.icon,
                style: const TextStyle(fontSize: 28),
              ),
              const SizedBox(height: 6),
              Text(
                work.title,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                durationText,
                style: const TextStyle(
                  fontSize: 10,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
