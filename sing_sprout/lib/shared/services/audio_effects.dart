import 'dart:math';
import 'dart:typed_data';
import '../../core/constants/enums.dart';

/// Professional DSP audio effects chain for post-processing synthesized music.
///
/// Pure Dart, no dependencies. All effects are designed to run in an isolate.
/// Processing chain: Saturation → EQ → Compressor → Reverb → Stereo Widener → Limiter
class AudioEffectsProcessor {
  final int sampleRate;
  final bool stereo;

  AudioEffectsProcessor({this.sampleRate = 44100, this.stereo = true});

  // ── Public API ──

  /// Process mono samples through the full effects chain with per-style presets.
  Float64List process(Float64List samples, StyleSeed style) {
    final preset = _EffectPreset.forStyle(style);
    var buf = samples;

    buf = _analogSaturation(buf, drive: preset.drive);
    buf = _threeBandEq(buf, preset.eq);
    buf = _threeBandCompressor(buf, preset.compressor);
    if (preset.chorus.mix > 0.01) {
      buf = _chorusEffect(buf, preset.chorus);
    }
    if (preset.delay.mix > 0.01) {
      buf = _stereoDelay(buf, preset.delay);
    }
    buf = _schroederReverb(buf, preset.reverb);
    if (stereo) {
      buf = _stereoWidener(buf, width: preset.width);
    }
    buf = _lookAheadLimiter(buf, ceiling: -0.3);

    return buf;
  }

  /// Render stereo output from mono input with effects.
  /// Returns interleaved stereo samples: [L0, R0, L1, R1, ...]
  Float64List processToStereo(Float64List samples, StyleSeed style) {
    final preset = _EffectPreset.forStyle(style);
    var buf = Float64List.fromList(samples);

    buf = _analogSaturation(buf, drive: preset.drive);
    buf = _threeBandEq(buf, preset.eq);
    buf = _threeBandCompressor(buf, preset.compressor);
    if (preset.chorus.mix > 0.01) {
      buf = _chorusEffect(buf, preset.chorus);
    }
    final stereoBuf = _schroederReverbStereo(buf, preset.reverb);
    var processed = stereoBuf;
    if (preset.delay.mix > 0.01) {
      processed = _stereoDelayStereo(processed, preset.delay);
    }
    final widened = _stereoWidenerStereo(processed, width: preset.width);
    return _lookAheadLimiterStereo(widened, ceiling: -0.3);
  }

  // ── Analog Saturation ──

  /// Cubic soft-clipping saturation with even harmonics for warmth.
  static Float64List _analogSaturation(Float64List input, {double drive = 1.3}) {
    final out = Float64List(input.length);
    for (var i = 0; i < input.length; i++) {
      double x = input[i] * drive;
      // Cubic saturation: x - x³/3, approximates tube warmth
      // Range-normalized to avoid hard clipping
      if (x > 1.8) x = 1.8;
      if (x < -1.8) x = -1.8;
      out[i] = (x - x * x * x / 10.0) * 0.75;
    }
    return out;
  }

  // ── 3-Band Equalizer ──

  /// Gentle 3-band EQ using biquad-style shelving filters.
  /// bands: [lowGainDb, midGainDb, highGainDb] in dB
  static Float64List _threeBandEq(Float64List input, _EqBands bands) {
    final out = Float64List(input.length);
    // Simplified using 1-pole low-shelf/high-shelf approximations
    // Low shelf: fc ≈ 250Hz, High shelf: fc ≈ 4000Hz
    final lowGain = pow(10, bands.lowDb / 20).toDouble();
    final midGain = pow(10, bands.midDb / 20).toDouble();
    final highGain = pow(10, bands.highDb / 20).toDouble();

    double lowState = 0, highState = 0;
    const lowAlpha = 0.035;  // ~250Hz @ 44100
    const highAlpha = 0.45;  // ~4000Hz @ 44100

    for (var i = 0; i < input.length; i++) {
      // Low shelf
      lowState += lowAlpha * (input[i] - lowState);
      final lowComponent = lowState * (lowGain - 1.0);

      // High shelf (input - lowpass = highpass)
      highState += highAlpha * (input[i] - highState);
      final highComponent = (input[i] - highState) * (highGain - 1.0);

      // Mid = original with mid gain applied to the difference
      final midComponent = (input[i] - lowState - (input[i] - highState)) * (midGain - 1.0);

      out[i] = input[i] + lowComponent + midComponent + highComponent;
    }
    return out;
  }

  // ── 3-Band Compressor ──

  /// Three-band compressor with soft knee, independent per band.
  static Float64List _threeBandCompressor(Float64List input, _CompParams params) {
    if (params.thresholdDb >= 0) return input; // disabled

    final out = Float64List(input.length);

    // Crossover filters (2nd order Linkwitz-Riley approximation)
    const lowFc = 0.035;   // ~250Hz
    const highFc = 0.45;   // ~4000Hz

    // Separate bands
    double lowLP = 0, midBP1 = 0, midBP2 = 0, highHP = 0;
    final lowBand = Float64List(input.length);
    final midBand = Float64List(input.length);
    final highBand = Float64List(input.length);

    for (var i = 0; i < input.length; i++) {
      lowLP += lowFc * (input[i] - lowLP);
      lowBand[i] = lowLP;

      highHP += highFc * (input[i] - highHP);
      highBand[i] = input[i] - highHP;

      midBP1 += lowFc * (input[i] - midBP1);
      midBP2 += highFc * (midBP1 - midBP2);
      midBand[i] = midBP1 - midBP2;
    }

    // Compress each band
    _compressBand(lowBand, params);
    _compressBand(midBand, params);
    _compressBand(highBand, params);

    // Sum bands
    for (var i = 0; i < input.length; i++) {
      out[i] = lowBand[i] + midBand[i] + highBand[i];
    }

    // Makeup gain
    final makeup = pow(10, params.makeupDb / 20).toDouble();
    for (var i = 0; i < out.length; i++) {
      out[i] *= makeup;
    }

    return out;
  }

  /// Soft-knee compressor for a single band.
  static void _compressBand(Float64List band, _CompParams params) {
    final threshold = pow(10, params.thresholdDb / 20).toDouble();
    final ratio = params.ratio;
    final knee = 0.05; // 5% soft knee

    for (var i = 0; i < band.length; i++) {
      final abs = band[i].abs();
      if (abs < 1e-9) continue;

      final db = 20 * log(abs) / ln10;
      if (db < threshold - knee / 2) continue; // below threshold

      double gainReductionDb;
      if (db > threshold + knee / 2) {
        // Above knee: full compression
        gainReductionDb = (db - threshold) * (1.0 - 1.0 / ratio);
      } else {
        // In knee: gradual compression
        final t = (db - threshold + knee / 2) / knee;
        gainReductionDb = (db - threshold) * (1.0 - 1.0 / ratio) * t * t * (3 - 2 * t);
      }

      final gain = pow(10, -gainReductionDb / 20).toDouble();
      band[i] *= gain;
    }
  }

  // ── Schroeder Reverb ──

  /// Mono Schroeder reverb: 4 parallel comb filters → 2 series allpass filters.
  static Float64List _schroederReverb(Float64List input, _ReverbParams params) {
    if (params.wetMix <= 0.01) return input;

    // Comb filter delay lengths in samples (prime numbers for diffusion)
    const combDelays = [1557, 1617, 1691, 1753];
    const allpassDelays = [431, 277];

    // Allocate comb buffers
    final combBufs = List<Float64List>.generate(
      4, (_) => Float64List(combDelays[3] + 1),
    );
    final combPtrs = Int32List(4);

    // Allocate allpass buffers
    final apBufs = List<Float64List>.generate(
      2, (_) => Float64List(allpassDelays[1] + 1),
    );
    final apPtrs = Int32List(2);

    final out = Float64List(input.length);
    final wet = params.wetMix;
    final dry = 1.0 - wet;
    final decay = params.decay;
    final damping = _dampingCoeff(params.damping, allpassDelays[0]);

    for (var i = 0; i < input.length; i++) {
      // 4 parallel comb filters
      double combSum = 0;
      for (var c = 0; c < 4; c++) {
        final delayLen = combDelays[c];
        final ptr = combPtrs[c];
        final delayed = combBufs[c][ptr];
        // Low-pass filter in feedback loop (damping)
        combBufs[c][ptr] = input[i] + (delayed * decay * damping + delayed * decay * (1 - damping));
        combSum += delayed;
        combPtrs[c] = (ptr + 1) % delayLen;
      }

      // 2 series allpass filters
      double apOut = combSum * 0.25;
      for (var a = 0; a < 2; a++) {
        final delayLen = allpassDelays[a];
        final ptr = apPtrs[a];
        final delayed = apBufs[a][ptr];
        apBufs[a][ptr] = apOut + delayed * 0.5;
        apOut = delayed - apOut * 0.5;
        apPtrs[a] = (ptr + 1) % delayLen;
      }

      out[i] = input[i] * dry + apOut * wet;
    }

    return out;
  }

  /// Stereo Schroeder reverb with L/R decorrelation.
  static Float64List _schroederReverbStereo(Float64List monoIn, _ReverbParams params) {
    if (params.wetMix <= 0.01) {
      final stereo = Float64List(monoIn.length * 2);
      for (var i = 0; i < monoIn.length; i++) {
        stereo[i * 2] = monoIn[i];
        stereo[i * 2 + 1] = monoIn[i];
      }
      return stereo;
    }

    // Two independent reverb instances with slightly different comb delays for stereo decorrelation
    const combDelaysL = [1557, 1617, 1691, 1753];
    const combDelaysR = [1499, 1669, 1783, 1823]; // different primes for R channel

    final combBufsL = List<Float64List>.generate(4, (_) => Float64List(1823 + 1));
    final combPtrsL = Int32List(4);
    final combBufsR = List<Float64List>.generate(4, (_) => Float64List(1823 + 1));
    final combPtrsR = Int32List(4);

    // Allpass delays - also slightly different per channel
    const apDelaysL = [431, 277];
    const apDelaysR = [419, 293];
    final maxAp = 431;

    final apBufsL = List<Float64List>.generate(2, (_) => Float64List(maxAp + 1));
    final apPtrsL = Int32List(2);
    final apBufsR = List<Float64List>.generate(2, (_) => Float64List(maxAp + 1));
    final apPtrsR = Int32List(2);

    final out = Float64List(monoIn.length * 2);
    final wet = params.wetMix;
    final dry = 1.0 - wet;
    final decay = params.decay;

    for (var i = 0; i < monoIn.length; i++) {
      final x = monoIn[i];

      // Left channel combs
      double combSumL = 0;
      for (var c = 0; c < 4; c++) {
        final dl = combDelaysL[c];
        final p = combPtrsL[c];
        final d = combBufsL[c][p];
        combBufsL[c][p] = x + d * decay;
        combSumL += d;
        combPtrsL[c] = (p + 1) % dl;
      }

      // Right channel combs
      double combSumR = 0;
      for (var c = 0; c < 4; c++) {
        final dl = combDelaysR[c];
        final p = combPtrsR[c];
        final d = combBufsR[c][p];
        combBufsR[c][p] = x + d * decay;
        combSumR += d;
        combPtrsR[c] = (p + 1) % dl;
      }

      // Left allpass chain
      double apL = combSumL * 0.25;
      for (var a = 0; a < 2; a++) {
        final dl = apDelaysL[a];
        final p = apPtrsL[a];
        final d = apBufsL[a][p];
        apBufsL[a][p] = apL + d * 0.5;
        apL = d - apL * 0.5;
        apPtrsL[a] = (p + 1) % dl;
      }

      // Right allpass chain
      double apR = combSumR * 0.25;
      for (var a = 0; a < 2; a++) {
        final dl = apDelaysR[a];
        final p = apPtrsR[a];
        final d = apBufsR[a][p];
        apBufsR[a][p] = apR + d * 0.5;
        apR = d - apR * 0.5;
        apPtrsR[a] = (p + 1) % dl;
      }

      out[i * 2] = x * dry + apL * wet;
      out[i * 2 + 1] = x * dry + apR * wet;
    }

    return out;
  }

  static double _dampingCoeff(double damping, int samplePeriod) {
    // damping: 0.0 = no damping (bright), 1.0 = full damping (dark)
    return exp(-damping * 0.1 / samplePeriod);
  }

  // ── Stereo Widener (Mono) ──

  /// Creates pseudo-stereo from mono using complementary comb filters.
  static Float64List _stereoWidener(Float64List input, {double width = 0.5}) {
    if (width <= 0.01) return input;
    // For mono output, apply subtle pitch-shifted doubling
    // This is a simplified widener that adds a slightly delayed copy
    final delaySamples = (3 + width * 15).round(); // 3-18 sample delay
    final out = Float64List(input.length);
    final wet = width * 0.3;
    for (var i = 0; i < input.length; i++) {
      final delayed = i >= delaySamples ? input[i - delaySamples] : 0;
      out[i] = input[i] * (1 - wet) + delayed * wet;
    }
    return out;
  }

  /// Stereo widener operating on interleaved stereo samples.
  static Float64List _stereoWidenerStereo(Float64List stereoIn, {double width = 0.5}) {
    if (width <= 0.01) return stereoIn;
    // Mid/side processing: boost side, reduce mid
    final out = Float64List(stereoIn.length);
    final midGain = 1.0 - width * 0.4;   // reduce mid
    final sideGain = 1.0 + width * 0.6;  // boost side

    for (var i = 0; i < stereoIn.length; i += 2) {
      final l = stereoIn[i];
      final r = stereoIn[i + 1];
      final mid = (l + r) * 0.5;
      final side = (l - r) * 0.5;

      out[i] = mid * midGain + side * sideGain;
      out[i + 1] = mid * midGain - side * sideGain;
    }

    return out;
  }

  // ── Look-Ahead Peak Limiter ──

  /// Look-ahead brick-wall limiter to prevent digital clipping.
  static Float64List _lookAheadLimiter(Float64List input, {double ceiling = -0.3}) {
    const lookAhead = 64; // ~1.45ms @ 44100Hz
    const releaseCoeff = 0.9995;

    final ceilingLinear = pow(10, ceiling / 20).toDouble();
    final out = Float64List(input.length);
    double gainReduction = 1.0;

    // Simple envelope follower + look-ahead
    for (var i = 0; i < input.length; i++) {
      // Look ahead for peak
      double peak = 0;
      final lookEnd = min(i + lookAhead, input.length);
      for (var j = i; j < lookEnd; j++) {
        final abs = input[j].abs();
        if (abs > peak) peak = abs;
      }

      // Calculate required gain reduction
      if (peak * gainReduction > ceilingLinear) {
        gainReduction = ceilingLinear / peak;
      } else {
        // Release
        gainReduction = gainReduction * releaseCoeff + (1.0 - releaseCoeff);
        if (gainReduction > 1.0) gainReduction = 1.0;
      }

      out[i] = input[i] * gainReduction;
    }

    return out;
  }

  /// Stereo look-ahead limiter.
  static Float64List _lookAheadLimiterStereo(Float64List stereoIn, {double ceiling = -0.3}) {
    const lookAhead = 64;
    const releaseCoeff = 0.9995;

    final ceilingLinear = pow(10, ceiling / 20).toDouble();
    final out = Float64List(stereoIn.length);
    double gainReduction = 1.0;

    for (var i = 0; i < stereoIn.length; i += 2) {
      double peak = 0;
      final lookEnd = min(i + lookAhead * 2, stereoIn.length);
      for (var j = i; j < lookEnd; j += 2) {
        final abs = stereoIn[j].abs();
        if (abs > peak) peak = abs;
        final absR = stereoIn[j + 1].abs();
        if (absR > peak) peak = absR;
      }

      if (peak * gainReduction > ceilingLinear) {
        gainReduction = ceilingLinear / peak;
      } else {
        gainReduction = gainReduction * releaseCoeff + (1.0 - releaseCoeff);
        if (gainReduction > 1.0) gainReduction = 1.0;
      }

      out[i] = stereoIn[i] * gainReduction;
      out[i + 1] = stereoIn[i + 1] * gainReduction;
    }

    return out;
  }

  // ── Chorus Effect ──

  /// Multi-voice chorus for thickening pads and strings.
  Float64List _chorusEffect(Float64List input, _ChorusParams params) {
    final out = Float64List(input.length);
    final maxDelay = (params.depth * 0.015 * sampleRate).round() + 2;
    final delayBuf = Float64List(maxDelay);
    var delayPos = 0;
    double lfo1 = 0, lfo2 = 0, lfo3 = 0;
    const lfoRate1 = 0.55, lfoRate2 = 0.73, lfoRate3 = 0.41;

    for (var i = 0; i < input.length; i++) {
      lfo1 += lfoRate1 / sampleRate * 2 * pi;
      lfo2 += lfoRate2 / sampleRate * 2 * pi;
      lfo3 += lfoRate3 / sampleRate * 2 * pi;

      final mod1 = (sin(lfo1) * maxDelay * params.depth * 0.33).round();
      final mod2 = (sin(lfo2) * maxDelay * params.depth * 0.33).round();
      final mod3 = (sin(lfo3) * maxDelay * params.depth * 0.33).round();

      final read1 = (delayPos - mod1 + maxDelay) % maxDelay;
      final read2 = (delayPos - mod2 + maxDelay) % maxDelay;
      final read3 = (delayPos - mod3 + maxDelay) % maxDelay;

      final d1 = delayBuf[read1];
      final d2 = delayBuf[read2];
      final d3 = delayBuf[read3];

      delayBuf[delayPos] = input[i];
      delayPos = (delayPos + 1) % maxDelay;

      final wet = (d1 + d2 + d3) / 3.0 * params.mix;
      out[i] = input[i] * (1.0 - params.mix) + wet;
    }

    return out;
  }

  // ── Stereo Delay ──

  /// Ping-pong style stereo delay with feedback and low-pass filtering.
  Float64List _stereoDelay(Float64List input, _DelayParams params) {
    final delaySamples = (params.timeSeconds * sampleRate).round();
    if (delaySamples <= 0) return input;
    final delayBuf = Float64List(delaySamples + 1);
    var delayPos = 0;
    final out = Float64List(input.length);
    double feedbackState = 0;

    for (var i = 0; i < input.length; i++) {
      final readPos = (delayPos - delaySamples + delayBuf.length) % delayBuf.length;
      final delayed = delayBuf[readPos];
      feedbackState += 0.3 * (delayed - feedbackState);
      delayBuf[delayPos] = input[i] + feedbackState * params.feedback;
      delayPos = (delayPos + 1) % delayBuf.length;
      out[i] = input[i] * (1.0 - params.mix * 0.4) + delayed * params.mix;
    }

    return out;
  }

  /// Stereo delay with L/R offset for ping-pong effect.
  Float64List _stereoDelayStereo(Float64List stereoIn, _DelayParams params) {
    final delayL = (params.timeSeconds * sampleRate).round();
    final delayR = ((params.timeSeconds + 0.04) * sampleRate).round();
    final maxDelay = max(delayL, delayR) + 1;
    final delayBuf = Float64List(maxDelay);
    var delayPos = 0;
    final out = Float64List(stereoIn.length);
    double fbL = 0, fbR = 0;

    for (var i = 0; i < stereoIn.length; i += 2) {
      final readL = (delayPos - delayL + maxDelay) % maxDelay;
      final readR = (delayPos - delayR + maxDelay) % maxDelay;

      final dL = delayBuf[readL];
      final dR = delayBuf[readR];

      fbL += 0.3 * (dL - fbL);
      fbR += 0.3 * (dR - fbR);

      final monoIn = (stereoIn[i] + stereoIn[i + 1]) * 0.5;
      delayBuf[delayPos] = monoIn + fbL * params.feedback * 0.7;
      delayPos = (delayPos + 1) % maxDelay;

      out[i] = stereoIn[i] * (1.0 - params.mix * 0.4) + dL * params.mix;
      out[i + 1] = stereoIn[i + 1] * (1.0 - params.mix * 0.4) + dR * params.mix;
    }

    return out;
  }
}

// ── Effect Presets per Style ──

class _EffectPreset {
  final double drive;
  final _EqBands eq;
  final _CompParams compressor;
  final _ChorusParams chorus;
  final _DelayParams delay;
  final _ReverbParams reverb;
  final double width;

  const _EffectPreset({
    required this.drive,
    required this.eq,
    required this.compressor,
    required this.chorus,
    required this.delay,
    required this.reverb,
    required this.width,
  });

  static _EffectPreset forStyle(StyleSeed style) {
    switch (style) {
      case StyleSeed.morningDew:
        return const _EffectPreset(
          drive: 1.15,
          eq: _EqBands(lowDb: 0.5, midDb: 0.0, highDb: -0.5),
          compressor: _CompParams(thresholdDb: -14, ratio: 2.5, makeupDb: 3),
          chorus: _ChorusParams(mix: 0.08, depth: 0.3),
          delay: _DelayParams(mix: 0.0, timeSeconds: 0.0, feedback: 0.0),
          reverb: _ReverbParams(wetMix: 0.22, decay: 0.55, damping: 0.45),
          width: 0.35,
        );
      case StyleSeed.mountainStream:
        return const _EffectPreset(
          drive: 1.1,
          eq: _EqBands(lowDb: 1.0, midDb: 0.0, highDb: -1.0),
          compressor: _CompParams(thresholdDb: -16, ratio: 2.0, makeupDb: 4),
          chorus: _ChorusParams(mix: 0.15, depth: 0.5),
          delay: _DelayParams(mix: 0.0, timeSeconds: 0.0, feedback: 0.0),
          reverb: _ReverbParams(wetMix: 0.35, decay: 0.70, damping: 0.60),
          width: 0.7,
        );
      case StyleSeed.frogDrum:
        return const _EffectPreset(
          drive: 1.3,
          eq: _EqBands(lowDb: 1.5, midDb: -0.5, highDb: 1.0),
          compressor: _CompParams(thresholdDb: -10, ratio: 3.0, makeupDb: 4),
          chorus: _ChorusParams(mix: 0.0, depth: 0.0),
          delay: _DelayParams(mix: 0.12, timeSeconds: 0.18, feedback: 0.25),
          reverb: _ReverbParams(wetMix: 0.15, decay: 0.40, damping: 0.30),
          width: 0.5,
        );
      case StyleSeed.random:
        return forStyle(StyleSeed.morningDew);
    }
  }
}

class _ChorusParams {
  final double mix;
  final double depth;
  const _ChorusParams({this.mix = 0.0, this.depth = 0.3});
}

class _DelayParams {
  final double mix;
  final double timeSeconds;
  final double feedback;
  const _DelayParams({this.mix = 0.0, this.timeSeconds = 0.0, this.feedback = 0.0});
}

class _EqBands {
  final double lowDb, midDb, highDb;
  const _EqBands({this.lowDb = 0, this.midDb = 0, this.highDb = 0});
}

class _CompParams {
  final double thresholdDb; // dB, e.g. -12
  final double ratio;       // e.g. 3.0
  final double makeupDb;    // makeup gain in dB
  const _CompParams({this.thresholdDb = 0, this.ratio = 2, this.makeupDb = 0});
}

class _ReverbParams {
  final double wetMix;   // 0-1
  final double decay;     // 0-1
  final double damping;   // 0-1 (0=bright, 1=dark)
  const _ReverbParams({this.wetMix = 0.2, this.decay = 0.5, this.damping = 0.4});
}
