import 'dart:typed_data';
import '../../core/constants/enums.dart';
import 'arrangement_engine.dart';
import 'audio_effects.dart';
import 'audio_processor.dart';
import 'soundfont_renderer.dart';
import 'wavetable_engine.dart';

/// Real-time modulation parameters for the editor controls.
class ModulationParams {
  final double temperature;
  final double speed;
  final double instrumentMix;

  const ModulationParams({
    this.temperature = 0.5,
    this.speed = 1.0,
    this.instrumentMix = 0.5,
  });

  static const neutral = ModulationParams();
}

/// Enhanced multi-track MIDI-to-WAV renderer with wavetable synthesis and DSP effects.
///
/// Replaces the old sine-wave-only synthesis with:
/// - Per-instrument harmonic profiles (piano, strings, pluck, etc.)
/// - Multi-layer percussion (kick, snare, hi-hat, clap, rim, crash)
/// - Professional DSP effects chain (saturation, EQ, compression, reverb, stereo, limiter)
/// - 44100Hz stereo output for CD-quality audio
class WavSynthesizer {
  /// CD-quality sample rate.
  static const sampleRate = 44100;

  /// Whether to output stereo (interleaved L/R) instead of mono.
  static const stereoOutput = true;

  static final _engine = WavetableEngine(sampleRate: sampleRate, oversample2x: true);
  static final _effects = AudioEffectsProcessor(sampleRate: sampleRate, stereo: true);
  static final _sfRenderer = SoundfontRenderer(sampleRate: sampleRate);

  // ── Public API ──

  /// Try to load a SoundFont 2 file for sample-based rendering.
  /// Returns true if the soundfont was loaded successfully.
  /// When loaded, melodic tracks will use real instrument samples
  /// instead of wavetable synthesis.
  static bool loadSoundfont(Uint8List sf2Bytes) {
    return _sfRenderer.load(sf2Bytes);
  }

  /// Whether a soundfont is currently loaded for sample-based rendering.
  static bool get hasSoundfont => _sfRenderer.isLoaded;

  /// Free the loaded soundfont and return to wavetable synthesis.
  static void unloadSoundfont() => _sfRenderer.reset();

  /// Render modulated samples with per-instrument profiles and DSP effects.
  static Float64List renderModulatedSamples({
    required Arrangement baseArrangement,
    required List<MidiNoteEvent> melody,
    required StyleSeed style,
    required ModulationParams params,
  }) {
    List<MidiNoteEvent> chords, bass, percussion;
    double totalDuration;
    final speedFactor = 1.0 / params.speed;
    if ((params.speed - 1.0).abs() > 0.01) {
      chords = _scaleTiming(baseArrangement.chords, speedFactor);
      bass = _scaleTiming(baseArrangement.bass, speedFactor);
      percussion = _scaleTiming(baseArrangement.percussion, speedFactor);
      totalDuration = baseArrangement.totalDurationSeconds * speedFactor;
    } else {
      chords = baseArrangement.chords;
      bass = baseArrangement.bass;
      percussion = baseArrangement.percussion;
      totalDuration = baseArrangement.totalDurationSeconds;
    }

    final warmth = params.temperature;
    final melodyAdsr = AdsrParams.interpolate(AdsrParams.melody, warmth);
    final chordStyle = style == StyleSeed.mountainStream
        ? AdsrParams.pad
        : (style == StyleSeed.frogDrum ? AdsrParams.pluck : AdsrParams.pad);
    final chordAdsr = AdsrParams.interpolate(chordStyle, warmth);
    final bassAdsr = AdsrParams.interpolate(AdsrParams.bass, warmth);

    final mix = params.instrumentMix;
    final melodyGain = 0.72 - (mix - 0.5) * 0.12;
    final chordGain = (style == StyleSeed.mountainStream ? 0.2 : 0.38) * (mix * 2).clamp(0.1, 1.0);
    final bassGain = 0.5 * (mix * 2).clamp(0.1, 1.0);
    final percGain = mix.clamp(0.0, 1.0);

    final melodyProfile = InstrumentProfile.forMelody(style);
    final chordProfile = InstrumentProfile.forChords(style);
    final bassProfile = InstrumentProfile.forBass();

    final numSamples = (sampleRate * totalDuration).ceil();
    final buffer = Float64List(numSamples);

    // Enable humanization for natural feel
    _engine.resetHumanization(totalDuration: totalDuration);

    // Render tracks with instrument profiles
    _renderMelodicTrack(buffer, bass, bassAdsr, bassProfile, gain: bassGain, totalDuration: totalDuration);
    _renderMelodicTrack(buffer, chords, chordAdsr, chordProfile, gain: chordGain, totalDuration: totalDuration);
    if (percussion.isNotEmpty && percGain > 0.05) {
      _renderPercussionTrack(buffer, percussion);
    }
    _renderMelodicTrack(buffer, melody, melodyAdsr, melodyProfile, gain: melodyGain, totalDuration: totalDuration);

    // Apply DSP effects chain
    final processed = _effects.process(buffer, style);

    return processed;
  }

  /// Render with modulation params and write to file (stereo WAV).
  static Future<String> renderModulated({
    required Arrangement baseArrangement,
    required List<MidiNoteEvent> melody,
    required StyleSeed style,
    required ModulationParams params,
    required String outputPath,
  }) async {
    final mono = renderModulatedSamples(
      baseArrangement: baseArrangement,
      melody: melody,
      style: style,
      params: params,
    );

    final stereo = stereoOutput
        ? _effects.processToStereo(mono, style)
        : mono;

    if (stereoOutput) {
      await AudioProcessor.writeStereoWav(outputPath, stereo, sampleRate);
    } else {
      await AudioProcessor.writeWav(outputPath, mono, sampleRate);
    }
    return outputPath;
  }

  /// Standard render without modulation (used by isolate).
  static Float64List render({
    required List<MidiNoteEvent> melody,
    required List<MidiNoteEvent> chords,
    required List<MidiNoteEvent> bass,
    required List<MidiNoteEvent> percussion,
    required StyleSeed style,
    required double totalDuration,
  }) {
    final melodyProfile = InstrumentProfile.forMelody(style);
    final chordProfile = InstrumentProfile.forChords(style);
    final bassProfile = InstrumentProfile.forBass();

    final chordAdsr = style == StyleSeed.mountainStream ? AdsrParams.pad : AdsrParams.pad;
    final chordGain = style == StyleSeed.mountainStream ? 0.2 : 0.38;

    final numSamples = (sampleRate * totalDuration).ceil();
    final buffer = Float64List(numSamples);

    _engine.resetHumanization(totalDuration: totalDuration);

    _renderMelodicTrack(buffer, bass, AdsrParams.bass, bassProfile, gain: 0.5, totalDuration: totalDuration);
    _renderMelodicTrack(buffer, chords, chordAdsr, chordProfile, gain: chordGain, totalDuration: totalDuration);
    if (percussion.isNotEmpty) {
      _renderPercussionTrack(buffer, percussion);
    }
    _renderMelodicTrack(buffer, melody, AdsrParams.melody, melodyProfile, gain: 0.72, totalDuration: totalDuration);

    return _effects.process(buffer, style);
  }

  /// Render to WAV file (no modulation), with effects.
  static Future<String> renderToFile({
    required dynamic arrangementOrNotes,
    required StyleSeed style,
    required String outputPath,
    double? totalDuration,
  }) async {
    Float64List samples;
    if (arrangementOrNotes is Arrangement) {
      samples = render(
        melody: arrangementOrNotes.melody,
        chords: arrangementOrNotes.chords,
        bass: arrangementOrNotes.bass,
        percussion: arrangementOrNotes.percussion,
        style: style,
        totalDuration: totalDuration ?? arrangementOrNotes.totalDurationSeconds,
      );
    } else {
      final notes = <MidiNoteEvent>[];
      final dur = totalDuration ?? 3.0;
      final noteLen = dur / 3;
      for (var i = 0; i < 3; i++) {
        notes.add(MidiNoteEvent(noteNumber: 60 + i * 2, startSeconds: i * noteLen, durationSeconds: noteLen * 0.85));
      }
      final arr = Arrangement(melody: notes, chords: [], bass: [], percussion: [], tempoBpm: 80, tonicMidi: 60, totalDurationSeconds: dur);
      samples = render(melody: arr.melody, chords: arr.chords, bass: arr.bass, percussion: arr.percussion, style: style, totalDuration: dur);
    }

    final stereo = stereoOutput
        ? _effects.processToStereo(samples, style)
        : samples;

    if (stereoOutput) {
      await AudioProcessor.writeStereoWav(outputPath, stereo, sampleRate);
    } else {
      await AudioProcessor.writeWav(outputPath, samples, sampleRate);
    }
    return outputPath;
  }

  // ── Speed scaling ──

  static List<MidiNoteEvent> _scaleTiming(List<MidiNoteEvent> notes, double factor) {
    return notes.map((n) => MidiNoteEvent(
      noteNumber: n.noteNumber,
      startSeconds: n.startSeconds * factor,
      durationSeconds: n.durationSeconds * factor,
      velocity: n.velocity,
    ),).toList();
  }

  // ── Track Rendering with WavetableEngine ──

  static void _renderMelodicTrack(
    Float64List buffer,
    List<MidiNoteEvent> notes,
    AdsrParams adsr,
    InstrumentProfile profile,
    {double gain = 0.5, double totalDuration = 0}
  ) {
    final useSf = _sfRenderer.isLoaded;
    for (final note in notes) {
      if (note.noteNumber < 0 || note.noteNumber > 127) continue;
      if (useSf) {
        _sfRenderer.renderNote(
          buffer,
          note.startSeconds,
          note.durationSeconds,
          note.noteNumber,
          note.velocity,
        );
      } else {
        _engine.renderNote(
          buffer,
          note.startSeconds,
          note.durationSeconds,
          note.noteNumber,
          note.velocity,
          profile,
          adsr,
          gain,
          humanize: true,
          totalDuration: totalDuration,
        );
      }
    }
  }

  static void _renderPercussionTrack(Float64List buffer, List<MidiNoteEvent> notes) {
    var kickCount = 0, snareCount = 0, hihatCount = 0;
    for (final note in notes) {
      final startSample = (note.startSeconds * sampleRate).round().clamp(0, buffer.length - 1);
      final endSample = (startSample + (note.durationSeconds * sampleRate).round()).clamp(0, buffer.length);

      PercussionType type;
      int seed;
      switch (note.noteNumber) {
        case 36:
          type = PercussionType.kick;
          seed = kickCount++ * 127 + 42;
          break;
        case 38:
          type = PercussionType.snare;
          seed = snareCount++ * 127 + 99;
          break;
        case 42:
          type = PercussionType.hihat;
          seed = hihatCount++ * 127 + 13;
          break;
        case 39:
          type = PercussionType.clap;
          seed = kickCount++ * 127 + 77;
          break;
        case 37:
          type = PercussionType.rim;
          seed = snareCount++ * 127 + 55;
          break;
        case 49:
          type = PercussionType.crash;
          seed = hihatCount++ * 127 + 31;
          break;
        default:
          continue;
      }

      _engine.renderPercussion(buffer, startSample, endSample, type, note.velocity, seed: seed);
    }
  }
}
