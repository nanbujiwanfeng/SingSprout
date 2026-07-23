import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
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
import '../../shared/services/audio_service.dart';
import 'humming_garden_provider.dart';

/// 哼唱花园 — 首页 & MVP 核心创作入口
class HummingGardenPage extends StatefulWidget {
  const HummingGardenPage({super.key});

  @override
  State<HummingGardenPage> createState() => _HummingGardenPageState();
}

class _HummingGardenPageState extends State<HummingGardenPage>
    with WidgetsBindingObserver {
  bool _isRecording = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final audioProvider = context.read<AudioProvider>();
      audioProvider.onMaxDurationReached = _onMaxDurationReached;
      context.read<HummingGardenProvider>().loadWorks();
      _checkCallInterrupt();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 检测 App 从后台恢复（可能是来电中断）
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _isRecording) {
      // 录音中恢复：可能是来电中断，缓存录音并停止
      final audioProvider = context.read<AudioProvider>();
      audioProvider.cacheForInterrupt();
      _handleRecordingStop(autoStopped: true);
    }
  }

  /// 检查是否有来电中断缓存的录音
  void _checkCallInterrupt() {
    final audioProvider = context.read<AudioProvider>();
    if (audioProvider.hasCachedRecording) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showResumeDialog();
      });
    }
  }

  void _showResumeDialog() {
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
          GentleCopy.callInterruptedTitle,
          style: GoogleFonts.maShanZheng(
            fontSize: 20,
            color: AppTheme.primaryGreen,
          ),
          textAlign: TextAlign.center,
        ),
        content: const Text(
          GentleCopy.callInterruptedContent,
          style: TextStyle(color: AppTheme.textPrimary, fontSize: 14),
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () {
              context.read<AudioProvider>().clearInterruptCache();
              Navigator.of(ctx).pop();
            },
            child: const Text(GentleCopy.callInterruptedDiscard,
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              // 跳转到创作页面继续
              final path =
                  context.read<AudioProvider>().cachedRecordingPath;
              if (path != null) {
                context.push(
                    '${AppRoutes.recording}?path=${Uri.encodeComponent(path)}');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryGreen,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
            ),
            child: const Text(GentleCopy.callInterruptedResume),
          ),
        ],
      ),
    );
  }

  void _onMaxDurationReached() {
    _handleRecordingStop(autoStopped: true);
  }

  Future<void> _handleRecordingStart() async {
    if (!mounted) return;

    // 麦克风权限校验（录音文件保存到应用私有目录，不需要存储权限）
    final micOk = await _checkAndRequestPermission(
      permission: Permission.microphone,
      title: '需要麦克风权限',
      reason: GentleCopy.micPermissionHint,
    );
    if (!mounted) return;
    if (!micOk) return;

    // 权限通过 → 开始录音
    final audioProvider = context.read<AudioProvider>();
    await audioProvider.startRecording();

    if (!mounted) return;
    if (audioProvider.isRecording) {
      setState(() => _isRecording = true);
    }
  }

  /// 检查并请求权限，处理永久拒绝引导
  Future<bool> _checkAndRequestPermission({
    required Permission permission,
    required String title,
    required String reason,
  }) async {
    // 1. 先检查当前状态
    final status = await permission.status;
    if (status.isGranted) return true;

    // 2. 已永久拒绝 → 弹窗引导去系统设置
    if (status.isPermanentlyDenied) {
      _showSettingsDialog(permissionName: title);
      return false;
    }

    // 3. 显示正在检查权限（用户可见反馈）
    _showGentleSnackBar('正在检查$title...');

    // 4. 初次请求 → 弹系统授权窗口
    final result = await permission.request();
    if (result.isGranted) {
      _showGentleSnackBar('$title 已授权 ✓');
      return true;
    }

    // 5. 用户拒绝 → 永久拒绝引导 or 温柔提示
    if (result.isPermanentlyDenied) {
      _showSettingsDialog(permissionName: title);
    } else {
      _showGentleSnackBar(reason);
    }
    return false;
  }

  /// 永久拒绝 → 弹窗带「去设置」按钮
  void _showSettingsDialog({required String permissionName}) {
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
          permissionName,
          style: GoogleFonts.maShanZheng(
            fontSize: 20,
            color: AppTheme.primaryGreen,
          ),
          textAlign: TextAlign.center,
        ),
        content: const Text(
          '你之前拒绝了该权限，现在去设置里打开吧～',
          style: TextStyle(color: AppTheme.textPrimary, fontSize: 14),
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('先不用',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              openAppSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryGreen,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
            ),
            child: const Text('去设置'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleRecordingStop({bool autoStopped = false}) async {
    if (!_isRecording && !autoStopped) return;

    final audioProvider = context.read<AudioProvider>();
    if (!audioProvider.isRecording) return;

    final path = await audioProvider.stopRecording();
    if (!mounted) return;

    setState(() => _isRecording = false);

    // ── 边界异常检测 ──

    // 1. 全程静音
    if (audioProvider.isSilent) {
      _showGentleDialog(
        GentleCopy.noSoundTitle,
        GentleCopy.noSoundContent,
        actionLabel: GentleCopy.noSoundRetry,
      );
      audioProvider.reset();
      return;
    }

    // 2. 环境嘈杂
    if (audioProvider.isTooNoisy) {
      _showGentleDialog(
        GentleCopy.tooNoisyTitle,
        GentleCopy.tooNoisyContent,
        actionLabel: GentleCopy.tooNoisyRetry,
      );
      audioProvider.reset();
      return;
    }

    // 3. 录音太短 < 5s
    if (audioProvider.isTooShort) {
      _showGentleDialog(
        GentleCopy.tooShortTitle,
        GentleCopy.tooShortContent,
        actionLabel: GentleCopy.tooShortRetry,
      );
      audioProvider.reset();
      return;
    }

    // 4. 达到最大时长
    if (autoStopped) {
      _showGentleSnackBar(GentleCopy.maxTimeReached);
    }

    // ── 正常流程：跳转录音详情页 ──
    if (mounted) {
      await context.push(
        '${AppRoutes.recording}${path != null ? '?path=${Uri.encodeComponent(path)}' : ''}',
      );
      audioProvider.processingComplete();
      if (mounted) {
        context.read<HummingGardenProvider>().loadWorks();
      }
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

  void _showGentleDialog(String title, String message, {String actionLabel = '好的～'}) {
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
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryGreen,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: Text(actionLabel),
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
          child: CustomScrollView(
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: _buildMainContent(),
              ),
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
        const SizedBox(height: 24),

        // 熊猫头像问候（动画状态跟随录音）
        Consumer<AudioProvider>(
          builder: (context, audio, _) {
            PandaState state;
            if (audio.isRecording) {
              state = PandaState.recording;
            } else if (audio.status == AudioStatus.processing) {
              state = PandaState.generating;
            } else {
              state = PandaState.idle;
            }
            return AnimalAvatar(
              animal: GuardianAnimal.panda,
              size: 80,
              speechBubble: GentleCopy.pandaGreeting,
              pandaState: state,
              recordingAmplitude: audio.currentAmplitude,
            );
          },
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
        Text(
          GentleCopy.hintLongPress,
          style: const TextStyle(
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
