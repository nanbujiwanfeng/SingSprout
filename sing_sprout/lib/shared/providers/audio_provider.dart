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

  // ── Getters ──
  AudioStatus get status => _status;
  Duration get currentPosition => _currentPosition;
  Duration get totalDuration => _totalDuration;
  List<double>? get waveformData => _waveformData;
  bool get isRecording => _status == AudioStatus.recording;
  double get currentAmplitude => _currentAmplitude;
  int get elapsedRecordingSeconds => _elapsedRecordingSeconds;
  String? get currentRecordingPath => _currentRecordingPath;

  /// 录音时长上限回调（30 秒自动停止）
  VoidCallback? onMaxDurationReached;

  /// 开始录音
  Future<void> startRecording() async {
    // 请求权限
    final hasPermission = await _audioService.requestMicPermission();
    if (!hasPermission) {
      return;
    }

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
      notifyListeners();
    });

    // 启动计时器
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _elapsedRecordingSeconds++;
      _currentPosition = Duration(seconds: _elapsedRecordingSeconds);
      notifyListeners();

      // 达到最大时长自动停止
      if (_elapsedRecordingSeconds >= AppConfig.maxRecordingDurationSec) {
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

  /// 录音时长是否不足（< 3 秒）
  bool get isTooShort =>
      _elapsedRecordingSeconds < AppConfig.hummingMinDurationSec;

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
    notifyListeners();
  }

  @override
  void dispose() {
    _amplitudeSub?.cancel();
    _recordingTimer?.cancel();
    super.dispose();
  }
}
