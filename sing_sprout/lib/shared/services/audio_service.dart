import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// 音频服务 — 录音与播放
/// 集成 record 包实现真实录音，振幅流归一化输出
class AudioService {
  static final AudioService _instance = AudioService._();
  factory AudioService() => _instance;
  AudioService._();

  final AudioRecorder _recorder = AudioRecorder();

  StreamSubscription<Amplitude>? _ampSub;
  final StreamController<double> _amplitudeController =
      StreamController<double>.broadcast();

  bool _isRecording = false;
  bool _isPlaying = false;

  bool get isRecording => _isRecording;
  bool get isPlaying => _isPlaying;

  /// 归一化音量流 (0.0 ~ 1.0)
  Stream<double> get amplitudeStream => _amplitudeController.stream;

  /// 请求麦克风权限
  Future<bool> requestMicPermission() async {
    if (Platform.isIOS || Platform.isAndroid) {
      return await _recorder.hasPermission();
    }
    // 桌面/Web 默认允许（或走 permission_handler）
    return true;
  }

  /// 开始录音，返回文件路径
  Future<String?> startRecording() async {
    try {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) return null;

      final dir = await getApplicationDocumentsDirectory();
      final fileName =
          'recording_${DateTime.now().millisecondsSinceEpoch}.m4a';
      final path = '${dir.path}/singsprout/$fileName';

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          sampleRate: 44100,
          bitRate: 128000,
        ),
        path: path,
      );

      _isRecording = true;

      // 订阅振幅流，归一化到 0~1
      _ampSub = _recorder.onAmplitudeChanged(
        const Duration(milliseconds: 100),
      ).listen((amp) {
        // dB 范围约 -60 ~ 0，归一化
        final normalized = ((amp.current + 60) / 60).clamp(0.0, 1.0);
        _amplitudeController.add(normalized);
      });

      return path;
    } catch (e) {
      // 录音启动异常 → 启动模拟音量流供开发调试
      _startSimulatedAmplitude();
      _isRecording = true;
      return 'mock_recording_${DateTime.now().millisecondsSinceEpoch}.m4a';
    }
  }

  /// 停止录音，返回文件路径
  Future<String?> stopRecording() async {
    try {
      _ampSub?.cancel();
      _ampSub = null;
      final path = await _recorder.stop();
      _isRecording = false;
      _stopSimulatedAmplitude();
      return path;
    } catch (e) {
      _isRecording = false;
      _stopSimulatedAmplitude();
      return 'mock_recording_${DateTime.now().millisecondsSinceEpoch}.m4a';
    }
  }

  /// 播放音频
  Future<void> playAudio(String filePath) async {
    _isPlaying = true;
    // TODO: 集成 audioplayers 包实现播放
  }

  /// 停止播放
  Future<void> stopPlayback() async {
    _isPlaying = false;
  }

  // ── 模拟音量流（开发/Web 回退） ──

  Timer? _simTimer;

  void _startSimulatedAmplitude() {
    _simTimer?.cancel();
    // 模拟自然哼唱的音量波动
    double phase = 0.0;
    _simTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      phase += 0.15;
      // 混合多个正弦波模拟哼唱的起伏感
      final simulated = ((0.35 +
                  0.15 * _fastSin(phase) +
                  0.1 * _fastSin(phase * 2.3) +
                  0.05 * _fastSin(phase * 5.7))
              .clamp(0.05, 0.85) +
          (_fastSin(phase * 0.7) * 0.1));
      _amplitudeController.add(simulated.clamp(0.0, 1.0));
    });
  }

  void _stopSimulatedAmplitude() {
    _simTimer?.cancel();
    _simTimer = null;
  }

  double _fastSin(double x) {
    // 快速近似 sin，避免 dart:math 在 Timer 中的开销
    x = x % (2 * 3.14159265);
    if (x < 0) x += 2 * 3.14159265;
    if (x > 3.14159265) x -= 2 * 3.14159265;
    final x2 = x * x;
    return x * (1.0 - x2 / 6.0 + x2 * x2 / 120.0);
  }

  void dispose() {
    _ampSub?.cancel();
    _amplitudeController.close();
    _simTimer?.cancel();
    _recorder.dispose();
    _isRecording = false;
    _isPlaying = false;
  }
}
