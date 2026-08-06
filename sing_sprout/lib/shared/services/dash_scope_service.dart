import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

/// Alibaba Cloud DashScope (百炼) API service.
///
/// Three capabilities:
/// 1. Full-score generation — AI writes per-bar bass, chords, rhythm,
///    percussion, and optionally melody (speech mode). No templates.
/// 2. Speech transcription — file-based ASR via DashScope's native API.
/// 3. Legacy recipe mode — kept for compatibility.
class DashScopeService {
  static final DashScopeService _instance = DashScopeService._();
  factory DashScopeService() => _instance;
  DashScopeService._();

  static const _baseUrl = 'https://dashscope.aliyuncs.com/compatible-mode/v1';
  static const _asrBase = 'https://dashscope.aliyuncs.com/api/v1/services/audio/asr';

  /// ASR model chain: tried in order. paraformer-mtl-v1 supports
  /// Southwestern Mandarin, Cantonese, and Hakka dialects natively.
  static const _asrModelChain = [
    'paraformer-mtl-v1',
    'paraformer-realtime-v2',
    'sensevoice-v1',
  ];

  static const _model = 'qwen-plus';
  static const _keyStorageKey = 'dashscope_api_key';

  final _storage = const FlutterSecureStorage();
  final _client = http.Client();

  String? _cachedKey;
  bool _keyChecked = false;

  /// Whether an API key has been configured.
  Future<bool> get isConfigured async {
    if (_cachedKey != null) return true;
    if (_keyChecked) return false;
    try {
      _cachedKey = await _storage.read(key: _keyStorageKey);
    } catch (e) {
      debugPrint('[DashScope] Failed to read API key from storage: $e');
      _cachedKey = null;
    }
    _keyChecked = true;
    return _cachedKey != null && _cachedKey!.isNotEmpty;
  }

  /// Store the API key securely.
  Future<void> setApiKey(String key) async {
    _cachedKey = key.trim();
    _keyChecked = true;
    await _storage.write(key: _keyStorageKey, value: _cachedKey);
  }

  /// Remove the stored API key.
  Future<void> clearApiKey() async {
    _cachedKey = null;
    _keyChecked = true;
    await _storage.delete(key: _keyStorageKey);
  }

  /// Get the stored key (or null).
  Future<String?> _getKey() async {
    if (_cachedKey != null) return _cachedKey;
    try {
      _cachedKey = await _storage.read(key: _keyStorageKey);
    } catch (e) {
      debugPrint('[DashScope] Failed to read API key from storage: $e');
      _cachedKey = null;
    }
    _keyChecked = true;
    return _cachedKey;
  }

  /// Test whether a given API key is valid.
  Future<String?> testConnection({String? keyOverride}) async {
    final key = keyOverride ?? await _getKey();
    if (key == null || key.isEmpty) return '未设置 API Key';
    try {
      final response = await _client
          .post(
            Uri.parse('$_baseUrl/chat/completions'),
            headers: {
              'Authorization': 'Bearer $key',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': _model,
              'messages': [{'role': 'user', 'content': 'hi'}],
              'max_tokens': 5,
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) return null;
      try {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final err = body['error'] as Map<String, dynamic>?;
        return (err?['message'] as String?) ?? 'API 返回错误 (${response.statusCode})';
      } catch (_) {
        return 'API 返回错误 (${response.statusCode})';
      }
    } on Exception catch (e) {
      if (e.toString().contains('TimeoutException')) return '连接超时，请检查网络';
      final s = e.toString();
      return '连接失败: ${s.length > 60 ? s.substring(0, 60) : s}';
    }
  }

  /// 发送通用聊天请求。
  ///
  /// [systemPrompt] — 系统提示词
  /// [userMessage] — 用户消息
  /// [temperature] — 创造性温度 (0.0-1.0)
  /// [maxTokens] — 最大返回 token 数
  ///
  /// 返回 AI 回复文本，或 null（失败时）
  Future<String?> chatCompletion({
    required String systemPrompt,
    required String userMessage,
    double temperature = 0.8,
    int maxTokens = 500,
  }) async {
    final key = await _getKey();
    if (key == null || key.isEmpty) return null;

    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/chat/completions'),
        headers: {
          'Authorization': 'Bearer $key',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': _model,
          'messages': [
            {'role': 'system', 'content': systemPrompt},
            {'role': 'user', 'content': userMessage},
          ],
          'temperature': temperature,
          'max_tokens': maxTokens,
        }),
      ).timeout(const Duration(seconds: 60));

      if (response.statusCode != 200) {
        debugPrint('[DashScope] chatCompletion error ${response.statusCode}');
        if (response.statusCode == 429 || response.statusCode >= 500) {
          return null; // caller will retry
        }
        return null;
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = body['choices'] as List<dynamic>?;
      if (choices == null || choices.isEmpty) return null;

      return choices[0]['message']['content'] as String?;
    } catch (e) {
      debugPrint('[DashScope] chatCompletion exception: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════
  // Speech transcription (file-based, no mic conflict)
  // ═══════════════════════════════════════════

  /// Transcribe a WAV file using DashScope's ASR APIs.
  ///
  /// Tries models in chain order: paraformer-mtl-v1 (multi-dialect),
  /// paraformer-realtime-v2, then sensevoice-v1.
  Future<String?> transcribeFile(String wavFilePath) async {
    final key = await _getKey();
    if (key == null || key.isEmpty) return null;

    final file = File(wavFilePath);
    if (!await file.exists()) {
      debugPrint('[DashScope] ASR: file not found');
      return null;
    }

    final rawBytes = await file.readAsBytes();
    final pcm16k = _wavToPcm16k(rawBytes);
    if (pcm16k == null) {
      debugPrint('[DashScope] ASR: failed to parse WAV');
      return null;
    }

    for (final model in _asrModelChain) {
      final url = '$_asrBase/$model';
      final result = await _tryAsrCall(url, model, pcm16k, key);
      if (result != null) return result;
      debugPrint('[DashScope] ASR: $model failed, trying next...');
    }
    return null;
  }

  Future<String?> _tryAsrCall(
    String url, String model, Uint8List pcm16k, String key,
  ) async {
    try {
      final response = await _client
          .post(
            Uri.parse(url),
            headers: {
              'Authorization': 'Bearer $key',
              'Content-Type': 'application/json',
              'X-DashScope-DataInspection': 'enable',
            },
            body: jsonEncode({
              'model': model,
              'input': {'audio': base64Encode(pcm16k)},
              'parameters': {
                'format': 'pcm',
                'sample_rate': 16000,
              },
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        debugPrint('[DashScope] ASR $model error ${response.statusCode}');
        return null;
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final output = body['output'] as Map<String, dynamic>?;
      if (output == null) return null;

      final sentences = output['sentences'] as List<dynamic>?;
      if (sentences != null && sentences.isNotEmpty) {
        final text = sentences.map((s) => (s['text'] as String?) ?? '').join('');
        if (text.isNotEmpty) return text;
      }

      final text = output['text'] as String?;
      if (text != null && text.isNotEmpty) return text;

      return null;
    } catch (e) {
      debugPrint('[DashScope] ASR $model exception: $e');
      return null;
    }
  }

  /// Parse a WAV file and convert to 16kHz mono PCM.
  /// Returns raw PCM bytes or null if the WAV is invalid.
  Uint8List? _wavToPcm16k(Uint8List wavBytes) {
    try {
      if (wavBytes.length < 44) return null;

      final data = ByteData.view(wavBytes.buffer, wavBytes.offsetInBytes, wavBytes.length);

      // WAV header
      final riff = String.fromCharCodes(wavBytes.sublist(0, 4));
      if (riff != 'RIFF') return null;

      final sourceRate = data.getUint32(24, Endian.little);
      final numChannels = data.getUint16(22, Endian.little);
      final bitsPerSample = data.getUint16(34, Endian.little);

      if (bitsPerSample != 16) {
        debugPrint('[DashScope] ASR: only 16-bit WAV supported, got $bitsPerSample-bit');
        return null;
      }

      // Find data chunk
      var offset = 36;
      while (offset + 8 <= wavBytes.length) {
        final chunkId = String.fromCharCodes(wavBytes.sublist(offset, offset + 4));
        final chunkSize = data.getUint32(offset + 4, Endian.little);
        if (chunkId == 'data') {
          final dataStart = offset + 8;
          final dataEnd = (dataStart + chunkSize).clamp(0, wavBytes.length);
          final rawSamples = wavBytes.sublist(dataStart, dataEnd);

          // Convert to mono if stereo (average channels)
          Uint8List monoSamples;
          if (numChannels == 2) {
            monoSamples = _stereoToMono(rawSamples);
          } else {
            monoSamples = rawSamples;
          }

          // Resample to 16kHz
          if (sourceRate == 16000) {
            return monoSamples;
          }
          return _resamplePcm(monoSamples, sourceRate, 16000);
        }
        offset += 8 + chunkSize;
      }

      return null;
    } catch (e) {
      debugPrint('[DashScope] WAV parse error: $e');
      return null;
    }
  }

  /// Convert stereo 16-bit PCM to mono by averaging channels.
  Uint8List _stereoToMono(Uint8List stereo) {
    final result = Uint8List(stereo.length ~/ 2);
    final inData = ByteData.view(stereo.buffer, stereo.offsetInBytes, stereo.length);
    final outData = ByteData.view(result.buffer, result.offsetInBytes, result.length);
    for (var i = 0; i < stereo.length; i += 4) {
      final left = inData.getInt16(i, Endian.little);
      final right = inData.getInt16(i + 2, Endian.little);
      outData.setInt16(i ~/ 2, ((left + right) ~/ 2).clamp(-32768, 32767), Endian.little);
    }
    return result;
  }

  /// Simple linear-interpolation resampling.
  Uint8List _resamplePcm(Uint8List input, int sourceRate, int targetRate) {
    final ratio = sourceRate / targetRate;
    final inputSamples = input.length ~/ 2;
    final outputSamples = (inputSamples / ratio).ceil();
    final result = Uint8List(outputSamples * 2);
    final inData = ByteData.view(input.buffer, input.offsetInBytes, input.length);
    final outData = ByteData.view(result.buffer, result.offsetInBytes, result.length);

    for (var i = 0; i < outputSamples; i++) {
      final srcIdx = (i * ratio);
      final srcFloor = srcIdx.floor();
      final srcCeil = (srcFloor + 1).clamp(0, inputSamples - 1);
      final frac = srcIdx - srcFloor;

      final s1 = inData.getInt16(srcFloor.clamp(0, inputSamples - 1) * 2, Endian.little);
      final s2 = inData.getInt16(srcCeil * 2, Endian.little);
      final interpolated = (s1 + (s2 - s1) * frac).round().clamp(-32768, 32767);
      outData.setInt16(i * 2, interpolated, Endian.little);
    }
    return result;
  }

  // ═══════════════════════════════════════════
  // Audio event detection (SenseVoice)
  // ═══════════════════════════════════════════

  /// Result of audio event / sound classification.
  AudioEventResult? _lastEventCache;

  /// Detect sound events in a short audio clip using SenseVoice.
  ///
  /// Returns structured event data — sound type, confidence, and
  /// whether speech/music/environmental sounds are present.
  /// Useful for "Field Sound Lab" auto-classification.
  Future<AudioEventResult?> detectAudioEvents(String wavFilePath) async {
    final key = await _getKey();
    if (key == null || key.isEmpty) return null;

    final file = File(wavFilePath);
    if (!await file.exists()) return null;

    final rawBytes = await file.readAsBytes();
    final pcm16k = _wavToPcm16k(rawBytes);
    if (pcm16k == null) return null;

    try {
      final response = await _client
          .post(
            Uri.parse('$_asrBase/sensevoice-v1'),
            headers: {
              'Authorization': 'Bearer $key',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': 'sensevoice-v1',
              'input': {'audio': base64Encode(pcm16k)},
              'parameters': {
                'format': 'pcm',
                'sample_rate': 16000,
                'audio_event_detection': true,
              },
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return null;

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final output = body['output'] as Map<String, dynamic>?;
      if (output == null) return null;

      final events = (output['events'] as List<dynamic>?)
          ?.map((e) => AudioEvent(
                label: (e['label'] as String?) ?? '',
                confidence: (e['confidence'] as num?)?.toDouble() ?? 0.0,
              ),)
          .toList();

      if (events != null && events.isNotEmpty) {
        final result = AudioEventResult(
          events: events,
          hasSpeech: events.any((e) => e.label.contains('Speech')),
          hasMusic: events.any((e) => e.label.contains('Music')),
          hasEnvironmental: events.any((e) =>
              e.label.contains('Nature') || e.label.contains('Animal'),),
        );
        _lastEventCache = result;
        return result;
      }

      return null;
    } catch (e) {
      debugPrint('[DashScope] Audio event detection failed: $e');
      return null;
    }
  }

  /// Get the last cached event result (avoids re-calling API).
  AudioEventResult? get lastEventResult => _lastEventCache;

  // ═══════════════════════════════════════════
  // Full-score generation
  // ═══════════════════════════════════════════

  static const _fullScoreSystemPrompt = '''
你是一位专业的儿童音乐编曲家，专为中国乡村儿童创作温暖、纯真、高品质的音乐伴奏。

给定一段哼唱旋律的MIDI音符序列（可能附带语音文本和环境声音描述），
为这段旋律创作完整的、有层次感的伴奏乐谱。你需要逐小节决定和弦、贝斯、节奏和打击乐，
让最终的伴奏听起来像一首真正的歌——有呼吸、有起伏、有记忆点。

返回纯JSON（不要markdown包裹）。格式如下：

{
  "tempo_bpm": 88,
  "mood": "活泼跳跃",
  "key_tonality": "C大调",
  "bars": [
    {
      "bar": 1,
      "chord": [60, 64, 67],
      "bass": [36, 36, 43, 36],
      "bass_rhythm": [1, 1, 1, 1],
      "chord_rhythm": [0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5],
      "percussion": ["kick", null, "snare", null, "kick", null, "snare+hh", null],
      "dynamic": 0.7
    }
  ]
}

── 和弦（chord）──
- 每小节3-4个MIDI音。使用五声音阶友好进行：I-IV-V-I、I-vi-IV-V、I-V-vi-IV。
- ★声部引导★：相邻小节的和弦连接时，每个声部移动不超过3个半音。
  使用和弦转位使声部平滑连接。例如C(60,64,67)→F(60,65,69)而非(53,65,69)。
- 前奏用I和弦(根音位置)，终止式用V-I(原位)，中间段落多用转位保持流动感。
- 避免V-IV进行（古典和声禁忌）。II-V-I和IV-V-I是好的终止准备。
- 每8小节可插入一次色彩和弦（如ii7或vii°）增加惊喜感，但不滥用。

── 贝斯（bass）──
- 每拍一个音为基础框架。MIDI范围：28-55。
- ★反向进行★：旋律上行时贝斯下行，旋律下行时贝斯上行，形成张力。
- ★经过音★：在两个和弦根音之间插入半音或全音经过音，使贝斯线条歌唱化。
  例如C→F之间：36(C), 38(D), 40(E), 41(F)。
- ★切分重音★：在第2拍后半拍或第4拍后半拍加入八分音符切分，制造推动感。
- 高潮段落可用八度跳跃(如36→48→36)增加能量。

── 和弦节奏（chord_rhythm）──
- 每小节至少4个值(四分音符级)，表示和弦音的分解节奏。
- 每2小节变换一次节奏型，轮换使用：
  · 柱式铺垫[4.0] — 抒情/前奏段落
  · 上行琶音[0.5×8] — 渐强段落
  · 下行琶音[0.5×8] — 渐弱段落
  · 附点推进[0.75,0.25,0.5,0.5,0.75,0.25,0.5,0.5] — 活泼段落
  · 三连音涌动[0.33×12] — 高潮段落（加速感）
- 同一节奏型不超过连续2小节，保持新鲜感。

── 打击乐（percussion）──
- 每半拍一个标记。可选: "kick","snare","hh","kick+hh","snare+hh","clap",null。
- ★基础框架★: kick在1,3拍 | snare在2,4拍 | hh填充所有八分音符空隙。
- ★段落标记★: 每4小节末尾做1拍的fill:
  欢快型: ["kick","snare","kick+hh","snare+hh","kick","kick","snare+hh","hh"]
  抒情型: [null,null,"kick","snare",null,null,null,null]  (渐疏)
- 欢快风格(>90BPM): hh密集几乎每格都有，clap在第2,4拍加强。
- 抒情风格(<75BPM): 取消hihat，仅保留kick+snare骨架，让空间感出来。
- ★渐强fill★: 高潮前1小节，打击乐密度逐渐增加(kick→kick+hh→snare+hh→fill)。

── 力度弧线（dynamic）──
- 整曲必须有清晰的情绪弧线，避免所有小节同样力度:
  前奏(0.45-0.55) → 主题进入(0.65-0.72) → 发展(0.72-0.78) →
  高潮(0.82-0.92，在60%-80%位置) → 回落(0.65-0.55) → 尾声(0.45-0.35)
- 高潮位置 = 总小节数 × 0.7 附近，前后各1-2小节奏铺垫/释放。

── 速度与情绪（tempo_bpm / mood）──
- 欢快/跳跃: 95-115 BPM
- 温暖/抒情: 65-80 BPM
- 活泼/游戏: 85-100 BPM
- mood: 6字以内的诗意描述。例如"晨露轻舞"、"雨后蛙鸣"、"阳光洒落"。

── 创作核心原则 ──
1. ★问答结构★：每4小节一个乐句对。前2小节用V或IV制造"上行问句"(旋律走高，和弦不稳定)，
   后2小节用I制造"下行答句"(旋律回落，和弦解决)。这创造自然的"呼吸感"。
2. ★记忆点★：找出旋律中出现最多的音高，在伴奏中通过和弦最高音或贝斯重音强调它。
3. ★留白美学★：不是每拍都要有音。在旋律长音处，伴奏适当稀疏(减少和弦音数量或打击乐)，
   让旋律有呼吸空间。留白的对比让后面的饱满更有冲击力。
4. ★层次递进★：前奏只有和弦+贝斯(无打击乐)，主题加入轻柔打击乐，高潮打击乐全开。
   像搭积木一样一层层加，而不是一开始就把所有东西堆上去。
5. ★童趣优先★：和弦避免减三和弦和过度半音化。和声要"明亮、安全、温暖"。
   五声音阶(do-re-mi-sol-la)是最安全的选择。
6. ★自然融合★：如有环境声音描述(鸟鸣→高音区分解和弦模仿，水声→流畅的琶音，
   风声→pad式长音)，在编曲中巧妙呼应而非简单模仿。
7. 小节数 = ceil(总时长×tempo_bpm/60/4)，范围4-16小节。''';

  /// Generate a full accompaniment score from melody data.
  ///
  /// [melodyNotes] — detected MIDI notes from humming.
  /// [totalDuration] — recording duration in seconds.
  /// [tonicMidi] — estimated tonic MIDI number.
  /// [speechText] — optional speech-to-text result.
  /// [needsMelody] — if true, AI should compose the melody too (speech mode).
  /// [audioEvents] — optional description of detected sounds in the recording.
  Future<AiFullScore?> generateFullScore({
    required List<Map<String, dynamic>> melodyNotes,
    required double totalDuration,
    required int tonicMidi,
    String? speechText,
    bool needsMelody = false,
    String? audioEvents,
  }) async {
    final key = await _getKey();
    if (key == null || key.isEmpty) return null;

    final melodySummary = _formatMelody(melodyNotes, totalDuration);
    final barCount = ((totalDuration * 80 / 60 / 4).ceil()).clamp(4, 16);

    final userPrompt = StringBuffer();
    userPrompt.writeln('主音: MIDI $tonicMidi');
    userPrompt.writeln('时长: ${totalDuration.toStringAsFixed(1)}秒');
    userPrompt.writeln('预计小节数: $barCount');
    userPrompt.writeln('旋律音符: $melodySummary');

    if (audioEvents != null && audioEvents.isNotEmpty) {
      userPrompt.writeln('环境声音: $audioEvents');
      userPrompt.writeln('请将这些自然声音的感觉融入编曲风格中。');
    }

    final systemPrompt = StringBuffer(_fullScoreSystemPrompt);

    if (speechText != null && speechText.isNotEmpty) {
      userPrompt.writeln('用户说的话: "$speechText"');
      userPrompt.writeln('请根据说话内容和情绪来设计伴奏风格。');
    } else {
      userPrompt.writeln('请根据旋律特点设计伴奏。');
    }

    if (needsMelody) {
      userPrompt.writeln('注意：这段录音是说话而非哼唱，没有检测到有效的旋律。'
          '请同时创作一段完整的旋律（melody和melody_rhythm字段），'
          '与伴奏一起返回。旋律应该贴合说话内容的情绪。');
      systemPrompt.writeln('\n如果用户要求同时创作旋律，请添加以下字段：');
      systemPrompt.writeln('"melody": [64, 64, 65, 67, ...]  // MIDI音高序列，每音一个数');
      systemPrompt.writeln('"melody_rhythm": [1, 1, 1, 2, ...]  // 每个音的时值（拍），与melody一一对应');
    }

    try {
      final response = await _client
          .post(
            Uri.parse('$_baseUrl/chat/completions'),
            headers: {
              'Authorization': 'Bearer $key',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': _model,
              'messages': [
                {'role': 'system', 'content': systemPrompt.toString()},
                {'role': 'user', 'content': userPrompt.toString()},
              ],
              'temperature': 0.8,
              'max_tokens': needsMelody ? 4000 : 3000,
            }),
          )
          .timeout(const Duration(seconds: 35));

      if (response.statusCode != 200) {
        debugPrint('[DashScope] Full-score API error ${response.statusCode}: ${response.body}');
        return null;
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = body['choices'] as List<dynamic>?;
      if (choices == null || choices.isEmpty) return null;

      final content = choices[0]['message']['content'] as String?;
      if (content == null) return null;

      return _parseFullScore(content);
    } catch (e) {
      debugPrint('[DashScope] Full-score request failed: $e');
      return null;
    }
  }

  AiFullScore? _parseFullScore(String raw) {
    try {
      var jsonStr = raw.trim();
      if (jsonStr.startsWith('```')) {
        jsonStr = jsonStr.replaceFirst(RegExp(r'```\w*\n?'), '');
        jsonStr = jsonStr.replaceFirst(RegExp(r'\n?```$'), '');
      }

      final obj = jsonDecode(jsonStr) as Map<String, dynamic>;
      final tempo = (obj['tempo_bpm'] as num?)?.toDouble();
      final mood = obj['mood'] as String?;
      final barsRaw = obj['bars'] as List<dynamic>?;

      final melodyRaw = (obj['melody'] as List<dynamic>?)
          ?.map((e) => (e as num).toInt())
          .toList();
      final melodyRhythmRaw = (obj['melody_rhythm'] as List<dynamic>?)
          ?.map((e) => (e as num).toDouble())
          .toList();

      if (tempo == null || barsRaw == null || barsRaw.isEmpty) {
        debugPrint('[DashScope] Full-score missing required fields');
        return null;
      }

      final bars = <AiBarScore>[];
      for (final b in barsRaw) {
        final barMap = b as Map<String, dynamic>;
        final chord = (barMap['chord'] as List<dynamic>?)
            ?.map((e) => (e as num).toInt())
            .toList();
        final bass = (barMap['bass'] as List<dynamic>?)
            ?.map((e) => (e as num).toInt())
            .toList();
        final bassRhythm = (barMap['bass_rhythm'] as List<dynamic>?)
            ?.map((e) => (e as num).toDouble())
            .toList();
        final chordRhythm = (barMap['chord_rhythm'] as List<dynamic>?)
            ?.map((e) => (e as num).toDouble())
            .toList();
        final percussion = (barMap['percussion'] as List<dynamic>?)
            ?.map((e) => e as String?)
            .toList();
        final dynamicVal = (barMap['dynamic'] as num?)?.toDouble() ?? 0.7;

        if (chord == null || chord.isEmpty) {
          debugPrint('[DashScope] Bar missing chord');
          return null;
        }

        bars.add(AiBarScore(
          barIndex: (barMap['bar'] as num?)?.toInt() ?? bars.length + 1,
          chord: chord,
          bass: bass ?? [],
          bassRhythm: bassRhythm ?? [],
          chordRhythm: chordRhythm ?? [],
          percussion: percussion ?? [],
          dynamic_: dynamicVal.clamp(0.2, 1.0),
        ),);
      }

      return AiFullScore(
        tempoBpm: tempo.clamp(50, 130),
        mood: mood ?? '',
        bars: bars,
        melody: melodyRaw,
        melodyRhythm: melodyRhythmRaw,
      );
    } catch (e) {
      debugPrint('[DashScope] Failed to parse full score: $e');
      return null;
    }
  }

  /// Format melody notes as a brief text summary for the AI prompt.
  String _formatMelody(List<Map<String, dynamic>> notes, double totalDuration) {
    if (notes.isEmpty) return '无旋律音符';
    final midiNums = notes.map((n) => n['noteNumber'].toString()).join(', ');
    final uniqueNotes = notes.map((n) => n['noteNumber'] as int).toSet();
    final avgMidi = uniqueNotes.reduce((a, b) => a + b) ~/ uniqueNotes.length;
    const noteNames = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
    final noteName = '${noteNames[avgMidi % 12]}${avgMidi ~/ 12 - 1}';
    return '${notes.length}个音符, '
        '音高: $midiNums, '
        '平均: $noteName (MIDI $avgMidi), '
        '时长: ${totalDuration.toStringAsFixed(1)}秒';
  }

  // ── 语音合成 (CosyVoice TTS) ──

  static const _ttsBase = 'https://dashscope.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation';

  /// 使用 CosyVoice 将文字合成为语音，返回本地文件路径。
  /// [voice] 默认使用童声 longhuhu_v3。
  Future<String?> synthesizeSpeech({
    required String text,
    String voice = 'longhuhu_v3',
    double rate = 1.0,
    int volume = 50,
    String format = 'mp3',
  }) async {
    final key = await _getKey();
    if (key == null || key.isEmpty) return null;

    try {
      final response = await _client
          .post(
            Uri.parse(_ttsBase),
            headers: {
              'Authorization': 'Bearer $key',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': 'cosyvoice-v3-flash',
              'input': {'text': text},
              'parameters': {
                'voice': voice,
                'format': format,
                'volume': volume,
                'rate': rate,
              },
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        debugPrint('[DashScope] TTS failed: ${response.statusCode} ${response.body}');
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final output = data['output'] as Map<String, dynamic>?;
      final audio = output?['audio'] as Map<String, dynamic>?;
      final audioUrl = audio?['url'] as String?;
      if (audioUrl == null) return null;

      // Download audio to local file
      final audioResp = await _client.get(Uri.parse(audioUrl)).timeout(const Duration(seconds: 30));
      if (audioResp.statusCode != 200) return null;

      final docsDir = await getApplicationDocumentsDirectory();
      final greetingsDir = Directory('${docsDir.path}/greetings');
      if (!await greetingsDir.exists()) {
        await greetingsDir.create(recursive: true);
      }
      final filename = 'greeting_${DateTime.now().millisecondsSinceEpoch}.$format';
      final file = File('${greetingsDir.path}/$filename');
      await file.writeAsBytes(audioResp.bodyBytes);

      debugPrint('[DashScope] TTS saved: ${file.path}');
      return file.path;
    } catch (e) {
      debugPrint('[DashScope] TTS error: $e');
      return null;
    }
  }

  void dispose() => _client.close();
}

// ═══════════════════════════════════════════
// Data models
// ═══════════════════════════════════════════

/// Full per-bar accompaniment score written by AI.
class AiFullScore {
  final double tempoBpm;
  final String mood;
  final List<AiBarScore> bars;

  /// AI-composed melody (only when needsMelody=true).
  final List<int>? melody;
  final List<double>? melodyRhythm;

  const AiFullScore({
    required this.tempoBpm,
    required this.mood,
    required this.bars,
    this.melody,
    this.melodyRhythm,
  });
}

/// One bar of AI-written accompaniment.
class AiBarScore {
  final int barIndex;
  final List<int> chord;
  final List<int> bass;
  final List<double> bassRhythm;
  final List<double> chordRhythm;
  final List<String?> percussion;
  final double dynamic_;

  const AiBarScore({
    required this.barIndex,
    required this.chord,
    required this.bass,
    required this.bassRhythm,
    required this.chordRhythm,
    required this.percussion,
    required this.dynamic_,
  });
}

/// A single sound event detected by SenseVoice.
class AudioEvent {
  final String label;
  final double confidence;

  const AudioEvent({required this.label, required this.confidence});

  @override
  String toString() => '$label (${(confidence * 100).toStringAsFixed(0)}%)';
}

/// Aggregated audio event detection result.
class AudioEventResult {
  final List<AudioEvent> events;
  final bool hasSpeech;
  final bool hasMusic;
  final bool hasEnvironmental;

  const AudioEventResult({
    required this.events,
    this.hasSpeech = false,
    this.hasMusic = false,
    this.hasEnvironmental = false,
  });

  /// Human-readable summary for use in prompts.
  String get summary {
    if (events.isEmpty) return '';
    final labels = events.take(3).map((e) => e.toString()).join(', ');
    final categories = <String>[];
    if (hasSpeech) categories.add('人声');
    if (hasMusic) categories.add('音乐');
    if (hasEnvironmental) categories.add('自然环境声');
    final catStr = categories.isNotEmpty ? ' (${categories.join('/')})' : '';
    return '$labels$catStr';
  }

  @override
  String toString() => summary;
}
