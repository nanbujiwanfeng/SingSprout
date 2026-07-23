import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../core/constants/app_config.dart';
import '../services/audio_service.dart';

/// 音频录制与播放状态管理
enum AudioStatus { idle, recording, processing, playing, paused }

class AudioProvider extends ChangeNotifier {
  final AudioService _audioService = AudioService();

  AudioStatus _status = AudioStatus.idle;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  List<double>? _waveformData;

  // ── 录音状态 ──
  double _currentAmplitude = 0.0;
  int _elapsedRecordingSeconds = 0;
  String? _currentRecordingPath;
  StreamSubscription<double>? _amplitudeSub;
  Timer? _recordingTimer;

  // ── 静音/噪音检测 ──
  int _silenceFrames = 0;
  int _noiseFrames = 0;
  static const int _silenceThreshold = 10; // 连续 10 帧低音量视为静音
  static const int _noiseThreshold = 80;   // 连续 80 帧过高音量视为嘈杂
  static const double _silenceAmpLimit = 0.05; // 低于此值视为静音
  static const double _noiseAmpLimit = 0.85;   // 持续高于此值视为嘈杂

  /// 来电中断缓存
  String? _cachedRecordingPath;

  // ── Getters ──
  AudioStatus get status => _status;
  Duration get currentPosition => _currentPosition;
  Duration get totalDuration => _totalDuration;
  List<double>? get waveformData => _waveformData;
  bool get isRecording => _status == AudioStatus.recording;
  double get currentAmplitude => _currentAmplitude;
  int get elapsedRecordingSeconds => _elapsedRecordingSeconds;
  String? get currentRecordingPath => _currentRecordingPath;

  /// 是否全程静音（无有效人声）
  bool get isSilent =>
      _elapsedRecordingSeconds >= 1 && _silenceFrames > _elapsedRecordingSeconds * 8;

  /// 是否环境太嘈杂
  bool get isTooNoisy =>
      _elapsedRecordingSeconds >= 2 && _noiseFrames > _elapsedRecordingSeconds * 6;

  // isTooShort 已在下方定义，此处移除重复

  /// 是否有来电中断缓存
  bool get hasCachedRecording => _cachedRecordingPath != null;
  String? get cachedRecordingPath => _cachedRecordingPath;

  /// 录音时长上限回调（15 秒自动停止）
  VoidCallback? onMaxDurationReached;

  /// 开始录音
  Future<void> startRecording() async {
    // 权限由调用方（页面层）负责申请，此处直接启动录音
    final path = await _audioService.startRecording();
    if (path == null) return;

    _currentRecordingPath = path;
    _status = AudioStatus.recording;
    _currentPosition = Duration.zero;
    _elapsedRecordingSeconds = 0;
    _waveformData = [];
    notifyListeners();

    // 订阅音量幅值流
    _amplitudeSub = _audioService.amplitudeStream.listen((amp) {
      _currentAmplitude = amp;
      _waveformData?.add(amp);

      // 静音检测：连续低音量计数
      if (amp < _silenceAmpLimit) {
        _silenceFrames++;
      } else {
        _silenceFrames = 0;
      }

      // 噪音检测：持续高音量计数
      if (amp > _noiseAmpLimit) {
        _noiseFrames++;
      } else {
        _noiseFrames = (_noiseFrames > 0) ? _noiseFrames - 1 : 0;
      }

      notifyListeners();
    });

    // 启动计时器（最大 15 秒）
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _elapsedRecordingSeconds++;
      _currentPosition = Duration(seconds: _elapsedRecordingSeconds);
      notifyListeners();

      // 15 秒自动停止
      if (_elapsedRecordingSeconds >= 15) {
        _recordingTimer?.cancel();
        onMaxDurationReached?.call();
      }
    });
  }

  /// 停止录音，返回文件路径
  Future<String?> stopRecording() async {
    _amplitudeSub?.cancel();
    _amplitudeSub = null;
    _recordingTimer?.cancel();
    _recordingTimer = null;

    _status = AudioStatus.processing;
    notifyListeners();

    final path = await _audioService.stopRecording();
    _currentRecordingPath = path;
    return path;
  }

  /// 获取录音时长 Duration
  Duration get recordingDuration =>
      Duration(seconds: _elapsedRecordingSeconds);

  /// 录音时长是否不足（< 5 秒）
  bool get isTooShort => _elapsedRecordingSeconds < 5;

  void processingComplete() {
    _status = AudioStatus.idle;
    notifyListeners();
  }

  void startPlaying(Duration totalDuration) {
    _status = AudioStatus.playing;
    _totalDuration = totalDuration;
    _currentPosition = Duration.zero;
    notifyListeners();
  }

  void updatePosition(Duration position) {
    _currentPosition = position;
    notifyListeners();
  }

  void pausePlayback() {
    _status = AudioStatus.paused;
    notifyListeners();
  }

  void resumePlayback() {
    _status = AudioStatus.playing;
    notifyListeners();
  }

  void stopPlayback() {
    _status = AudioStatus.idle;
    _currentPosition = Duration.zero;
    notifyListeners();
  }

  void updateWaveform(List<double> data) {
    _waveformData = data;
    notifyListeners();
  }

  /// 重置所有状态
  /// 来电中断：缓存当前录音路径
  void cacheForInterrupt() {
    _cachedRecordingPath = _currentRecordingPath;
  }

  /// 清除来电中断缓存
  void clearInterruptCache() {
    _cachedRecordingPath = null;
  }

  /// 重置所有状态
  void reset() {
    _amplitudeSub?.cancel();
    _recordingTimer?.cancel();
    _status = AudioStatus.idle;
    _currentPosition = Duration.zero;
    _totalDuration = Duration.zero;
    _waveformData = null;
    _currentAmplitude = 0.0;
    _elapsedRecordingSeconds = 0;
    _currentRecordingPath = null;
    _silenceFrames = 0;
    _noiseFrames = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _amplitudeSub?.cancel();
    _recordingTimer?.cancel();
    super.dispose();
  }
}
