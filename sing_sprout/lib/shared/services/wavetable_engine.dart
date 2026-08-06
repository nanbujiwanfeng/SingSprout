import 'dart:math';
import 'dart:typed_data';
import '../../core/constants/enums.dart';

/// Enhanced wavetable synthesizer with harmonic layering, humanization, and per-instrument timbre.
class WavetableEngine {
  final int sampleRate;
  final bool oversample2x;
  final Random _rng = Random();

  WavetableEngine({this.sampleRate = 44100, this.oversample2x = true});

  static const int oversampleFactor = 2;

  /// Humanization state — tracks last note for legato detection and dynamic tempo.
  double _lastNoteEndTime = 0;
  int _lastNoteMidi = -1;

  /// Reset humanization state for a new rendering pass.
  void resetHumanization({double totalDuration = 0}) {
    _lastNoteEndTime = 0;
    _lastNoteMidi = -1;
  }

  // ── Public API ──

  /// Render a melodic note with humanization.
  /// [humanize] enables micro-timing (±5ms), velocity variation (±8%), and legato detection.
  /// [ritardandoEnd] fraction of total duration where ritardando begins (e.g., 0.85).
  void renderNote(
    Float64List buffer,
    double startSeconds,
    double durationSeconds,
    int midiNote,
    double velocity,
    InstrumentProfile profile,
    AdsrParams adsr,
    double gain, {
    bool humanize = true,
    double totalDuration = 0,
    double ritardandoEnd = 0.88,
  }) {
    final freq = _midiToFreq(midiNote);

    // ── Humanization ──
    double effStart = startSeconds;
    double effDuration = durationSeconds;
    double effVelocity = velocity;

    if (humanize) {
      // Micro-timing: ±8ms random offset
      effStart += (_rng.nextDouble() - 0.5) * 0.016;
      if (effStart < 0) effStart = 0;

      // Velocity variation: ±10%
      effVelocity = velocity * (0.9 + _rng.nextDouble() * 0.2);
      effVelocity = effVelocity.clamp(0.1, 1.0);

      // Ritardando: stretch timing near the end
      if (totalDuration > 0 && startSeconds > totalDuration * ritardandoEnd) {
        final positionInEnding = (startSeconds - totalDuration * ritardandoEnd) / (totalDuration * (1.0 - ritardandoEnd));
        final stretch = 1.0 + positionInEnding.clamp(0.0, 1.0) * 0.25; // up to 25% slower
        effDuration *= stretch;
      }

      // Legato detection: adjacent notes get reduced attack for smooth transition
      final timeSinceLast = effStart - _lastNoteEndTime;
      if (timeSinceLast < 0.03 && _lastNoteMidi >= 0) {
        // Overlapping/adjacent notes → legato: reduce attack
        adsr = AdsrParams(
          adsr.attack * 0.3,
          adsr.decay * 0.7,
          adsr.sustain.clamp(0.3, 0.85),
          adsr.release * 0.7,
        );
      }
      _lastNoteEndTime = effStart + effDuration;
      _lastNoteMidi = midiNote;
    }

    // Apply band-limiting for high notes
    final harmonicCutoff = midiNote > 72
        ? (3 - (midiNote - 72).clamp(0, 2).toDouble())
        : 3.0;

    final rate = oversample2x ? sampleRate * oversampleFactor : sampleRate;
    final startSample = (effStart * sampleRate).round().clamp(0, buffer.length - 1);
    final durationSamples = (effDuration * sampleRate).round();
    final endSample = (startSample + durationSamples).clamp(0, buffer.length);

    // Attack transient (hammer/pick/bow noise)
    final transientLen = (profile._transientMs / 1000.0 * sampleRate).round();

    for (var i = startSample; i < endSample; i++) {
      final t = (i - startSample) / sampleRate;
      final env = _adsrEnvelope(t, effDuration, adsr);
      if (env <= 1e-6) continue;

      double sample = 0;

      // Attack transient
      final transientSample = i - startSample;
      if (transientSample < transientLen && transientLen > 0) {
        final tFrac = transientSample / transientLen;
        final tEnv = exp(-tFrac * 4.0) * profile._transientGain;
        sample += (_rng.nextDouble() * 2 - 1) * tEnv * effVelocity;
      }

      // Harmonic synthesis
      for (var h = 0; h < profile._harmonics.length && h < harmonicCutoff.floor(); h++) {
        final harmNum = h + 1;
        final harmFreq = freq * harmNum;
        if (harmFreq > sampleRate * 0.45) break;

        double harmSample;
        if (oversample2x && harmNum <= 2) {
          harmSample = _oversampledWave(harmFreq, t, rate, profile._waveform);
        } else {
          harmSample = _waveSample(harmFreq, t, profile._waveform);
        }
        sample += harmSample * profile._harmonics[h] * effVelocity;
      }

      buffer[i] += sample * env * gain;
    }
  }

  /// Render a percussion hit to the buffer.
  /// Returns the number of samples written.
  void renderPercussion(
    Float64List buffer,
    int startSample,
    int endSample,
    PercussionType type,
    double velocity,
    {int seed = 42}
  ) {
    final rng = Random(seed);

    switch (type) {
      case PercussionType.kick:
        _renderLayeredKick(buffer, startSample, endSample, velocity);
        break;
      case PercussionType.snare:
        _renderLayeredSnare(buffer, startSample, endSample, velocity, rng);
        break;
      case PercussionType.hihat:
        _renderLayeredHihat(buffer, startSample, endSample, velocity, rng);
        break;
      case PercussionType.clap:
        _renderClap(buffer, startSample, endSample, velocity, rng);
        break;
      case PercussionType.rim:
        _renderRimShot(buffer, startSample, endSample, velocity, rng);
        break;
      case PercussionType.crash:
        _renderCrash(buffer, startSample, endSample, velocity, rng);
        break;
    }
  }

  // ── Oversampled Waveform ──

  /// Generate anti-aliased waveform using 2x oversampling + linear interpolation.
  static double _oversampledWave(double freq, double t, int rate, _WaveformType type) {
    final phase = freq * t;
    final frac = phase - phase.floor();
    // Compute two samples at half-offset for anti-aliasing
    final s1 = _waveformValue(frac, type);
    final s2 = _waveformValue((frac + 0.5) % 1.0, type);
    return (s1 + s2) * 0.5;
  }

  // ── Basic Waveform ──

  static double _waveSample(double freq, double t, _WaveformType type) {
    final phase = freq * t;
    final frac = phase - phase.floor();
    return _waveformValue(frac, type);
  }

  static double _waveformValue(double phase, _WaveformType type) {
    // phase is 0-1 fractional phase
    switch (type) {
      case _WaveformType.sine:
        return sin(2 * pi * phase);

      case _WaveformType.triangle:
        if (phase < 0.25) return 4 * phase;
        if (phase < 0.75) return 2 - 4 * phase;
        return 4 * phase - 4;

      case _WaveformType.saw:
        // Band-limited approximation: sawtooth with soft edge
        final saw = 2 * phase - 1;
        // Apply polynomial softening near the discontinuity
        final edge = phase - phase.round();
        final softening = 1.0 - edge.abs() * edge.abs() * 0.3;
        return saw * softening;

      case _WaveformType.piano:
        // Piano-like: sine fundamental + soft attack characteristic
        final fundamental = sin(2 * pi * phase);
        // Add percussive attack transient via exponential
        final attack = phase < 0.05 ? exp(-phase * 80) * 0.6 : 0;
        // Add metallic string component
        final metallic = sin(2 * pi * phase * 3.0) * 0.15 * exp(-phase * 0.5);
        return (fundamental + metallic + attack).clamp(-1.0, 1.0);

      case _WaveformType.strings:
        // Bowed string: rich harmonics with slow attack
        final fundamental = sin(2 * pi * phase);
        final h2 = sin(2 * pi * phase * 2.0) * 0.5;
        final h3 = sin(2 * pi * phase * 3.0) * 0.25;
        final h4 = sin(2 * pi * phase * 4.0) * 0.12;
        return (fundamental + h2 + h3 + h4) * 0.7;

      case _WaveformType.bell:
        // Bell-like: sparse harmonics, fast attack, long decay quality
        final fundamental = sin(2 * pi * phase);
        final h2 = sin(2 * pi * phase * 2.4) * 0.7; // Inharmonic overtones
        final h3 = sin(2 * pi * phase * 5.3) * 0.3;
        return (fundamental + h2 + h3) * 0.65;

      case _WaveformType.pluck:
        // Plucked string (guitar-like): fast attack transient + decay
        final fundamental = sin(2 * pi * phase);
        final body = sin(2 * pi * phase * 2.0) * 0.4 * exp(-phase * 1.5);
        final brightness = sin(2 * pi * phase * 4.0) * 0.15 * exp(-phase * 3.0);
        return (fundamental * exp(-phase * 0.8) + body + brightness).clamp(-1.0, 1.0);

      case _WaveformType.flute:
        // Flute-like: pure fundamental + soft breath noise, gentle attack
        final fundamental = sin(2 * pi * phase);
        final h2 = sin(2 * pi * phase * 2.0) * 0.3 * exp(-phase * 0.3);
        final breath = sin(2 * pi * phase * 1.01) * 0.08; // slight detune for breathiness
        return (fundamental + h2 + breath) * 0.75;

      case _WaveformType.organ:
        // Hammond-like: stacked harmonics with drawbar character
        final fundamental = sin(2 * pi * phase);
        final h2 = sin(2 * pi * phase * 2.0) * 0.6;
        final h3 = sin(2 * pi * phase * 3.0) * 0.45;
        final h4 = sin(2 * pi * phase * 4.0) * 0.2;
        final h5 = sin(2 * pi * phase * 5.0) * 0.08;
        // Percussive click on attack
        final click = phase < 0.03 ? exp(-phase * 100) * 0.2 : 0;
        return (fundamental + h2 + h3 + h4 + h5 + click) * 0.55;

      case _WaveformType.celesta:
        // Celesta-like: metallic bell with soft mallet attack
        final fundamental = sin(2 * pi * phase);
        final h2 = sin(2 * pi * phase * 2.8) * 0.65; // Inharmonic for metallic quality
        final h3 = sin(2 * pi * phase * 5.5) * 0.3;
        final h4 = sin(2 * pi * phase * 9.0) * 0.1;
        // Soft mallet attack envelope
        final attack = phase < 0.01 ? exp(-phase * 200) * 0.4 : 0;
        return (fundamental * 0.8 + h2 + h3 + h4 + attack).clamp(-1.0, 1.0);
    }
  }

  // ── Layered Percussion Synthesis ──

  /// Multi-layer kick drum: sub bass + click transient + body resonance.
  static void _renderLayeredKick(Float64List buffer, int start, int end, double velocity) {
    final sr = buffer.length > 0 ? 44100 : 44100; // safe default
    for (var i = start; i < end; i++) {
      final t = (i - start) / sr;

      // Sub layer: deep frequency sweep (150Hz → 40Hz)
      final subFreq = 150.0 - t * 800.0;
      final subEnv = exp(-t * 22);
      final sub = sin(2 * pi * (subFreq > 35 ? subFreq : 35) * t) * subEnv * 0.7;

      // Click layer: sharp transient for attack definition
      final clickEnv = exp(-t * 200);
      final click = sin(2 * pi * 800 * t) * clickEnv * 0.3;

      // Body resonance: low frequency ring
      final bodyEnv = exp(-t * 12);
      final body = sin(2 * pi * 55 * t) * bodyEnv * 0.25;

      buffer[i] += ((sub + click + body) * 0.85 * velocity).clamp(-1.0, 1.0);
    }
  }

  /// Multi-layer snare: body tone + noise component + wire rattle.
  static void _renderLayeredSnare(Float64List buffer, int start, int end, double velocity, Random rng) {
    final sr = 44100;
    for (var i = start; i < end; i++) {
      final t = (i - start) / sr;
      final env = exp(-t * 30);

      // Body: tuned component
      final body = sin(2 * pi * 200 * t) * env * 0.35;

      // Noise: broadband noise for snare rattle
      final noise = (rng.nextDouble() * 2 - 1) * env * 0.45;

      // Wire: high-frequency ringing
      final wireEnv = exp(-t * 50);
      final wire = (rng.nextDouble() * 2 - 1) * wireEnv * 0.3;

      buffer[i] += ((body + noise + wire) * 0.75 * velocity).clamp(-1.0, 1.0);
    }
  }

  /// Multi-layer hi-hat: metal resonance + noise bands.
  static void _renderLayeredHihat(Float64List buffer, int start, int end, double velocity, Random rng) {
    final sr = 44100;
    var prev = 0.0;
    for (var i = start; i < end; i++) {
      final t = (i - start) / sr;
      final env = exp(-t * 55);

      // Differentiated noise (HP filter effect) for metallic quality
      final raw = (rng.nextDouble() * 2 - 1);
      final diff = (raw - prev) * 0.5;
      prev = raw;

      // Add high-frequency ring
      final ring = sin(2 * pi * 8000 * t) * env * 0.08;

      // Add mid-freq body
      final bodyNoise = (rng.nextDouble() * 2 - 1) * exp(-t * 80) * 0.12;

      buffer[i] += ((diff * env * 0.5 + ring + bodyNoise) * velocity).clamp(-1.0, 1.0);
    }
  }

  /// Hand clap: multiple noise bursts with short delays.
  static void _renderClap(Float64List buffer, int start, int end, double velocity, Random rng) {
    final sr = 44100;
    for (var i = start; i < end; i++) {
      final t = (i - start) / sr;
      final env = exp(-t * 40);

      // Main noise burst
      double sample = (rng.nextDouble() * 2 - 1) * env;

      // Secondary "slap" bursts at ~3ms intervals
      for (var burst = 1; burst <= 3; burst++) {
        final burstDelay = burst * 0.003; // 3ms spacing
        final burstEnv = t > burstDelay ? exp(-(t - burstDelay) * 30) * 0.4 : 0;
        sample += (rng.nextDouble() * 2 - 1) * burstEnv;
      }

      buffer[i] += (sample * 0.6 * velocity).clamp(-1.0, 1.0);
    }
  }

  /// Rim shot: short sharp click with wood resonance.
  static void _renderRimShot(Float64List buffer, int start, int end, double velocity, Random rng) {
    final sr = 44100;
    for (var i = start; i < end; i++) {
      final t = (i - start) / sr;
      // Sharp click
      final click = sin(2 * pi * 1200 * t) * exp(-t * 120) * 0.5;
      // Wood resonance
      final wood = sin(2 * pi * 350 * t) * exp(-t * 25) * 0.35;
      // Ring
      final ring = (rng.nextDouble() * 2 - 1) * exp(-t * 80) * 0.15;

      buffer[i] += ((click + wood + ring) * 0.7 * velocity).clamp(-1.0, 1.0);
    }
  }

  /// Crash cymbal: metallic noise with long decay.
  static void _renderCrash(Float64List buffer, int start, int end, double velocity, Random rng) {
    final sr = 44100;
    var prev = 0.0;
    for (var i = start; i < end; i++) {
      final t = (i - start) / sr;
      final env = exp(-t * 5); // Long decay

      final raw = (rng.nextDouble() * 2 - 1);
      final diff = (raw - prev) * 0.7;
      prev = raw;

      // Multiple metal resonance frequencies
      final res1 = sin(2 * pi * 6000 * t) * env * 0.1;
      final res2 = sin(2 * pi * 4500 * t) * env * 0.08;
      final res3 = sin(2 * pi * 3200 * t) * env * 0.06;

      buffer[i] += ((diff * env * 0.4 + res1 + res2 + res3) * velocity).clamp(-1.0, 1.0);
    }
  }

  // ── ADSR Envelope ──

  static double _adsrEnvelope(double t, double noteDuration, AdsrParams preset) {
    if (t < 0) return 0;
    if (t < preset.attack) return t / preset.attack;
    final aEnd = preset.attack + preset.decay;
    if (t < aEnd) return 1.0 - (1.0 - preset.sustain) * ((t - preset.attack) / preset.decay);
    final releaseStart = noteDuration - preset.release;
    if (t < releaseStart) return preset.sustain;
    if (t < noteDuration) return preset.sustain * (1.0 - (t - releaseStart) / preset.release);
    return 0;
  }

  // ── Utility ──

  static double _midiToFreq(int midi) => 440.0 * pow(2.0, (midi - 69) / 12.0);
}

// ── Types ──

enum _WaveformType { sine, triangle, saw, piano, strings, bell, pluck, flute, organ, celesta }

/// Harmonic profile for an instrument.
/// harmonics[i] = amplitude of the (i+1)th harmonic relative to fundamental.
class InstrumentProfile {
  final _WaveformType _waveform;
  final List<double> _harmonics;
  final double _transientMs;
  final double _transientGain;

  const InstrumentProfile._({
    required _WaveformType waveform,
    required List<double> harmonics,
    double transientMs = 0,
    double transientGain = 0,
  }) : _waveform = waveform,
       _harmonics = harmonics,
       _transientMs = transientMs,
       _transientGain = transientGain;

  // ── Preset Profiles ──

  static const piano = InstrumentProfile._(waveform: _WaveformType.piano, harmonics: [1.0, 0.55, 0.3, 0.0, 0.0], transientMs: 4, transientGain: 0.35);
  static const strings = InstrumentProfile._(waveform: _WaveformType.strings, harmonics: [1.0, 0.5, 0.25, 0.12, 0.0], transientMs: 12, transientGain: 0.15);
  static const bell = InstrumentProfile._(waveform: _WaveformType.bell, harmonics: [1.0, 0.7, 0.3, 0.0, 0.0], transientMs: 2, transientGain: 0.5);
  static const pluck = InstrumentProfile._(waveform: _WaveformType.pluck, harmonics: [1.0, 0.4, 0.18, 0.0, 0.0], transientMs: 3, transientGain: 0.55);
  static const sine = InstrumentProfile._(waveform: _WaveformType.sine, harmonics: [1.0, 0.0, 0.0, 0.0, 0.0]);
  static const pad = InstrumentProfile._(waveform: _WaveformType.triangle, harmonics: [1.0, 0.15, 0.0, 0.0, 0.0]);
  static const flute = InstrumentProfile._(waveform: _WaveformType.flute, harmonics: [1.0, 0.35, 0.08, 0.0, 0.0], transientMs: 8, transientGain: 0.08);
  static const organ = InstrumentProfile._(waveform: _WaveformType.organ, harmonics: [1.0, 0.6, 0.45, 0.2, 0.08], transientMs: 2, transientGain: 0.25);
  static const celesta = InstrumentProfile._(waveform: _WaveformType.celesta, harmonics: [1.0, 0.8, 0.35, 0.12, 0.0], transientMs: 1.5, transientGain: 0.6);

  static InstrumentProfile forMelody(StyleSeed style) {
    switch (style) {
      case StyleSeed.morningDew: return flute;
      case StyleSeed.mountainStream: return celesta;
      case StyleSeed.frogDrum: return pluck;
      case StyleSeed.random: return piano;
    }
  }

  static InstrumentProfile forChords(StyleSeed style) {
    switch (style) {
      case StyleSeed.morningDew: return organ;
      case StyleSeed.mountainStream: return pad;
      case StyleSeed.frogDrum: return pluck;
      case StyleSeed.random: return piano;
    }
  }

  static InstrumentProfile forBass() => sine;
}

class AdsrParams {
  final double attack, decay, sustain, release;
  const AdsrParams(this.attack, this.decay, this.sustain, this.release);

  static const melody = AdsrParams(0.025, 0.06, 0.70, 0.18);
  static const pad = AdsrParams(0.12, 0.18, 0.55, 0.65);
  static const bass = AdsrParams(0.015, 0.04, 0.72, 0.12);
  static const pluck = AdsrParams(0.005, 0.08, 0.40, 0.25);

  static AdsrParams interpolate(AdsrParams base, double warmth) {
    return AdsrParams(
      base.attack + warmth * 0.04,
      base.decay + warmth * 0.03,
      (base.sustain + warmth * 0.1).clamp(0.2, 0.85),
      base.release + warmth * 0.25,
    );
  }
}

enum PercussionType { kick, snare, hihat, clap, rim, crash }
