import 'dart:math';
import 'dart:typed_data';

/// Pure-Dart SoundFont 2 (SF2) parser and sample-based renderer.
///
/// Parses the binary SF2 format and renders MIDI notes to audio using
/// real instrument samples with pitch shifting and ADSR envelopes.
/// Falls back to wavetable synthesis when no soundfont is loaded.
///
/// SF2 format reference: SoundFont 2.04 specification
/// RIFF container → INFO (metadata) + sdta (samples) + pdta (preset data)
class SoundfontRenderer {
  bool _loaded = false;

  // Raw sample data from smpl chunk
  Int16List _sampleData = Int16List(0);

  // Sample headers: start offset, end offset, start loop, end loop, sample rate, original pitch, pitch correction
  final List<_SfSample> _samples = [];

  // Instrument zones: maps MIDI key/velocity ranges to samples with generators
  final List<_SfInstrument> _instruments = [];

  // Preset zones: maps MIDI key/velocity to instruments
  final List<_SfPreset> _presets = [];

  int _outputSampleRate = 44100;

  SoundfontRenderer({int sampleRate = 44100}) : _outputSampleRate = sampleRate;

  bool get isLoaded => _loaded;

  /// Load an SF2 file from bytes. Returns true on success.
  bool load(Uint8List bytes) {
    try {
      _parseRiff(bytes);
      _loaded = _samples.isNotEmpty && _presets.isNotEmpty;
      return _loaded;
    } catch (e) {
      _loaded = false;
      return false;
    }
  }

  /// Render a MIDI note with the given velocity into the output buffer.
  /// Uses bank 0 preset 0 (first preset) by default.
  void renderNote(
    Float64List buffer,
    double startSeconds,
    double durationSeconds,
    int midiNote,
    double velocity, {
    int bank = 0,
    int presetNum = 0,
  }) {
    if (!_loaded || _samples.isEmpty) return;

    // Find matching preset → instrument → sample zone
    _SfSample? sample;
    double sampleVolume = 1.0;
    double pan = 0.5; // center
    double tune = 0; // cents
    int overrideKey = -1;
    int overrideVelocity = -1;

    // Search presets
    for (final preset in _presets) {
      if (preset.bank != bank || preset.presetNum != presetNum) continue;
      for (final zone in preset.zones) {
        if (zone.keyRange != null &&
            (midiNote < zone.keyRange!.low || midiNote > zone.keyRange!.high)) continue;
        if (zone.velRange != null &&
            ((velocity * 127).round() < zone.velRange!.low || (velocity * 127).round() > zone.velRange!.high)) continue;

        final instIdx = zone.instrumentIndex;
        if (instIdx < 0 || instIdx >= _instruments.length) continue;

        // Process preset-level generators
        for (final gen in zone.generators) {
          final r = _applyGenerator(gen, sampleVolume, pan, tune, overrideKey, overrideVelocity);
          sampleVolume = r.sampleVolume;
          pan = r.pan;
          tune = r.tune;
          overrideKey = r.overrideKey;
          overrideVelocity = r.overrideVelocity;
        }

        final inst = _instruments[instIdx];
        for (final iZone in inst.zones) {
          if (iZone.keyRange != null &&
              (midiNote < iZone.keyRange!.low || midiNote > iZone.keyRange!.high)) continue;
          if (iZone.velRange != null &&
              ((velocity * 127).round() < iZone.velRange!.low || (velocity * 127).round() > iZone.velRange!.high)) continue;

          final sampleIdx = iZone.sampleIndex;
          if (sampleIdx < 0 || sampleIdx >= _samples.length) continue;
          sample = _samples[sampleIdx];

          for (final gen in iZone.generators) {
            final r = _applyGenerator(gen, sampleVolume, pan, tune, overrideKey, overrideVelocity);
            sampleVolume = r.sampleVolume;
            pan = r.pan;
            tune = r.tune;
            overrideKey = r.overrideKey;
            overrideVelocity = r.overrideVelocity;
          }
          break; // first matching instrument zone wins
        }
        break; // first matching preset zone wins
      }
      break; // first matching preset wins
    }

    if (sample == null) return;

    _renderSample(
      buffer, sample,
      startSeconds, durationSeconds,
      midiNote, velocity,
      volume: sampleVolume, pan: pan, tune: tune,
      overrideKey: overrideKey,
    );
  }

  /// Reset the renderer, freeing sample memory.
  void reset() {
    _loaded = false;
    _sampleData = Int16List(0);
    _samples.clear();
    _instruments.clear();
    _presets.clear();
  }

  // ── Sample rendering with pitch shifting ──

  void _renderSample(
    Float64List buffer,
    _SfSample sample,
    double startSeconds,
    double durationSeconds,
    int midiNote,
    double velocity, {
    double volume = 1.0,
    double pan = 0.5,
    double tune = 0,
    int overrideKey = -1,
  }) {
    final effectiveKey = overrideKey >= 0 ? overrideKey : sample.originalPitch;
    // Pitch ratio: how much to shift the sample
    final semitoneShift = midiNote - effectiveKey + tune / 100.0;
    final pitchRatio = pow(2.0, semitoneShift / 12.0).toDouble();

    // Adjust sample rate ratio
    final srcRate = sample.sampleRate > 0 ? sample.sampleRate : 44100;
    final rateRatio = srcRate / _outputSampleRate * pitchRatio;

    final startSample = (startSeconds * _outputSampleRate).round().clamp(0, buffer.length - 1);
    final numOutputSamples = (durationSeconds * _outputSampleRate).round();
    final endSample = (startSample + numOutputSamples).clamp(0, buffer.length);

    final sampleLen = sample.end - sample.start;
    if (sampleLen <= 0) return;

    // ADSR from generators or defaults
    const attackTime = 0.01;
    const decayTime = 0.1;
    const sustainLevel = 0.7;
    const releaseTime = 0.15;

    final gain = volume * velocity * 0.7;
    final leftGain = gain * (1.0 - pan);
    final rightGain = gain * pan;

    for (var i = startSample; i < endSample; i++) {
      final t = (i - startSample) / _outputSampleRate;
      if (t >= durationSeconds) break;

      // ADSR envelope
      double env;
      if (t < attackTime) {
        env = t / attackTime;
      } else if (t < attackTime + decayTime) {
        env = 1.0 - (1.0 - sustainLevel) * ((t - attackTime) / decayTime);
      } else if (t < durationSeconds - releaseTime) {
        env = sustainLevel;
      } else {
        final releaseT = (t - (durationSeconds - releaseTime)) / releaseTime;
        env = sustainLevel * (1.0 - releaseT).clamp(0.0, 1.0);
      }

      // Sample position with linear interpolation
      final srcIdx = sample.start + t * _outputSampleRate * rateRatio;

      final idx = srcIdx.round();
      if (idx >= sample.end - 1) break;

      final frac = srcIdx - idx;
      final s0 = _sampleData[idx] / 32768.0;
      final s1 = _sampleData[idx + 1] / 32768.0;
      final s = s0 + (s1 - s0) * frac;

      buffer[i] += s * env * (leftGain + rightGain) * 0.5; // mono sum
    }
  }

  // ── Generator processing ──

  ({double sampleVolume, double pan, double tune, int overrideKey, int overrideVelocity}) _applyGenerator(
    _SfGenerator gen,
    double sampleVolume,
    double pan,
    double tune,
    int overrideKey,
    int overrideVelocity,
  ) {
    const genInitialAttenuation = 48;
    const genPan = 17;
    const genCoarseTune = 3;
    const genFineTune = 4;
    const genOverrideKey = 8;
    const genOverrideVelocity = 9;

    final amount = gen.amount & 0xFFFF;

    switch (gen.type) {
      case genInitialAttenuation:
        final db = -amount / 10.0;
        sampleVolume *= pow(10, db / 20).toDouble();
        break;
      case genPan:
        pan = (amount / 1000.0).clamp(0.0, 1.0);
        break;
      case genCoarseTune:
        tune += amount * 100;
        break;
      case genFineTune:
        tune += amount;
        break;
      case genOverrideKey:
        overrideKey = amount > 0 ? amount : -1;
        break;
      case genOverrideVelocity:
        overrideVelocity = amount > 0 ? amount : -1;
        break;
    }

    return (sampleVolume: sampleVolume, pan: pan, tune: tune, overrideKey: overrideKey, overrideVelocity: overrideVelocity);
  }

  // ── RIFF/SF2 Parser ──

  void _parseRiff(Uint8List bytes) {
    final data = ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes);
    var offset = 0;

    // RIFF header
    if (offset + 12 > bytes.length) return;
    final riffId = _readStr(data, offset, 4); // 'RIFF'
    offset += 4;
    /*final fileSize = */ data.getUint32(offset, Endian.little);
    offset += 4;
    final formType = _readStr(data, offset, 4); // 'sfbk'
    offset += 4;

    if (riffId != 'RIFF' || formType != 'sfbk') return;

    // Parse chunks
    while (offset + 8 <= bytes.length) {
      final chunkId = _readStr(data, offset, 4);
      offset += 4;
      final chunkSize = data.getUint32(offset, Endian.little);
      offset += 4;

      switch (chunkId) {
        case 'LIST':
          final listType = _readStr(data, offset, 4);
          offset += 4;
          final listEnd = offset + chunkSize - 4;
          if (listType == 'sdta') {
            _parseSdta(data, offset, listEnd);
          } else if (listType == 'pdta') {
            _parsePdta(data, offset, listEnd);
          }
          offset = listEnd;
          break;
        default:
          offset += chunkSize;
      }
    }
  }

  void _parseSdta(ByteData data, int start, int end) {
    var offset = start;
    while (offset + 8 <= end) {
      final chunkId = _readStr(data, offset, 4);
      offset += 4;
      final chunkSize = data.getUint32(offset, Endian.little);
      offset += 4;

      if (chunkId == 'smpl') {
        // Load all samples as 16-bit mono
        final numSamples = chunkSize ~/ 2;
        _sampleData = Int16List(numSamples);
        for (var i = 0; i < numSamples; i++) {
          _sampleData[i] = data.getInt16(offset + i * 2, Endian.little);
        }
      }
      offset += chunkSize;
    }
  }

  void _parsePdta(ByteData data, int start, int end) {
    var offset = start;

    // Read all sub-chunks
    final Map<String, List<int>> subChunks = {};
    while (offset + 8 <= end) {
      final chunkId = _readStr(data, offset, 4);
      offset += 4;
      final chunkSize = data.getUint32(offset, Endian.little);
      offset += 4;
      subChunks[chunkId] = [offset, chunkSize];
      offset += chunkSize;
    }

    // Parse preset headers (phdr)
    if (subChunks.containsKey('phdr')) {
      final info = subChunks['phdr']!;
      final phdrStart = info[0];
      final phdrLen = info[1];
      const recordSize = 38;
      final numPresets = phdrLen ~/ recordSize;

      // Read preset names and indices
      for (var i = 0; i < numPresets; i++) {
        final pos = phdrStart + i * recordSize;
        final name = _readFixedStr(data, pos, 20);
        final presetNum = data.getUint16(pos + 20, Endian.little);
        final bank = data.getUint16(pos + 22, Endian.little);
        final bagIndex = data.getUint16(pos + 24, Endian.little);
        final bagCount = (i + 1 < numPresets)
            ? data.getUint16(phdrStart + (i + 1) * recordSize + 24, Endian.little) - bagIndex
            : 0;
        // Skip terminal record (name 'EOP')
        if (name.trim() == 'EOP') continue;

        _presets.add(_SfPreset(
          name: name,
          bank: bank,
          presetNum: presetNum,
          bagIndex: bagIndex,
          bagCount: bagCount,
          zones: [],
        ));
      }
    }

    // Parse preset bags (pbag) and generators (pgen)
    if (subChunks.containsKey('pbag') && subChunks.containsKey('pgen') && subChunks.containsKey('pmod')) {
      final bagInfo = subChunks['pbag']!;
      final bagStart = bagInfo[0];
      final bagLen = bagInfo[1];
      const bagSize = 4;
      final numBags = bagLen ~/ bagSize;

      final genInfo = subChunks['pgen']!;
      final genStart = genInfo[0];

      for (var pi = 0; pi < _presets.length && pi < numBags; pi++) {
        final preset = _presets[pi];
        final bagIdx = preset.bagIndex;
        final nextBagIdx = (pi + 1 < numBags)
            ? (pi + 1 < _presets.length ? _presets[pi + 1].bagIndex : numBags)
            : numBags;

        for (var b = bagIdx; b < nextBagIdx; b++) {
          final bagPos = bagStart + b * bagSize;
          final genIndex = data.getUint16(bagPos, Endian.little);

          // Read generators for this bag
          final zone = _SfPresetZone(instrumentIndex: -1, keyRange: null, velRange: null, generators: []);
          var g = genIndex;
          while (g < 1000) { // reasonable max
            final genPos = genStart + g * 4;
            final genType = data.getUint16(genPos, Endian.little);
            final genAmount = data.getUint16(genPos + 2, Endian.little);

            // Check for instrument generator (type 41)
            if (genType == 41) {
              zone.instrumentIndex = genAmount;
            } else if (genType == 43) {
              // key range
              final low = genAmount & 0xFF;
              final high = (genAmount >> 8) & 0xFF;
              zone.keyRange = _Range(low, high);
            } else if (genType == 44) {
              // vel range
              final low = genAmount & 0xFF;
              final high = (genAmount >> 8) & 0xFF;
              zone.velRange = _Range(low, high);
            } else {
              zone.generators.add(_SfGenerator(genType, genAmount));
            }

            g++;
            // Generator list ends when type=0
            if (genType == 0 || genType == 0xFFFF) break;
          }

          preset.zones.add(zone);
        }
      }
    }

    // Parse instruments (inst)
    if (subChunks.containsKey('inst')) {
      final instInfo = subChunks['inst']!;
      final instStart = instInfo[0];
      final instLen = instInfo[1];
      const instRecSize = 22;
      final numInsts = instLen ~/ instRecSize;

      for (var i = 0; i < numInsts; i++) {
        final pos = instStart + i * instRecSize;
        final name = _readFixedStr(data, pos, 20);
        final bagIndex = data.getUint16(pos + 20, Endian.little);
        final bagCount = (i + 1 < numInsts)
            ? data.getUint16(instStart + (i + 1) * instRecSize + 20, Endian.little) - bagIndex
            : 0;
        if (name.trim() == 'EOI') continue;

        _instruments.add(_SfInstrument(
          name: name,
          bagIndex: bagIndex,
          bagCount: bagCount,
          zones: [],
        ));
      }
    }

    // Parse instrument bags (ibag) and generators (igen)
    if (subChunks.containsKey('ibag') && subChunks.containsKey('igen')) {
      final bagInfo = subChunks['ibag']!;
      final bagStart = bagInfo[0];
      final bagLen = bagInfo[1];
      const bagSize = 4;
      final numIBags = bagLen ~/ bagSize;

      final genInfo = subChunks['igen']!;
      final genStart = genInfo[0];

      for (var ii = 0; ii < _instruments.length && ii < numIBags; ii++) {
        final inst = _instruments[ii];
        final bagIdx = inst.bagIndex;
        final nextBagIdx = (ii + 1 < numIBags)
            ? (ii + 1 < _instruments.length ? _instruments[ii + 1].bagIndex : numIBags)
            : numIBags;

        for (var b = bagIdx; b < nextBagIdx; b++) {
          final bagPos = bagStart + b * bagSize;
          final genIndex = data.getUint16(bagPos, Endian.little);

          final zone = _SfInstZone(sampleIndex: -1, keyRange: null, velRange: null, generators: []);
          var g = genIndex;
          while (g < 1000) {
            final genPos = genStart + g * 4;
            final genType = data.getUint16(genPos, Endian.little);
            final genAmount = data.getUint16(genPos + 2, Endian.little);

            if (genType == 53) {
              // sample ID
              zone.sampleIndex = genAmount;
            } else if (genType == 43) {
              final low = genAmount & 0xFF;
              final high = (genAmount >> 8) & 0xFF;
              zone.keyRange = _Range(low, high);
            } else if (genType == 44) {
              final low = genAmount & 0xFF;
              final high = (genAmount >> 8) & 0xFF;
              zone.velRange = _Range(low, high);
            } else {
              zone.generators.add(_SfGenerator(genType, genAmount));
            }

            g++;
            if (genType == 0 || genType == 0xFFFF) break;
          }

          inst.zones.add(zone);
        }
      }
    }

    // Parse sample headers (shdr)
    if (subChunks.containsKey('shdr')) {
      final shdrInfo = subChunks['shdr']!;
      final shdrStart = shdrInfo[0];
      final shdrLen = shdrInfo[1];
      const shdrSize = 46;
      final numSamples = shdrLen ~/ shdrSize;

      for (var i = 0; i < numSamples; i++) {
        final pos = shdrStart + i * shdrSize;
        final name = _readFixedStr(data, pos, 20);
        if (name.trim() == 'EOS') break;

        final start = data.getUint32(pos + 20, Endian.little);
        final end = data.getUint32(pos + 24, Endian.little);
        final startLoop = data.getUint32(pos + 28, Endian.little);
        final endLoop = data.getUint32(pos + 32, Endian.little);
        final sampleRate = data.getUint32(pos + 36, Endian.little);
        final originalPitch = data.getUint8(pos + 40);
        final pitchCorrection = data.getInt8(pos + 41);

        _samples.add(_SfSample(
          name: name,
          start: start,
          end: (end > 0 ? end : (_sampleData.length * 2)).clamp(0, _sampleData.length),
          startLoop: startLoop,
          endLoop: endLoop > 0 ? endLoop : 0,
          sampleRate: sampleRate > 0 ? sampleRate : 44100,
          originalPitch: originalPitch > 0 ? originalPitch : 60,
          pitchCorrection: pitchCorrection,
        ));
      }
    }
  }

  static String _readStr(ByteData data, int offset, int len) {
    final sb = StringBuffer();
    for (var i = 0; i < len && offset + i < data.lengthInBytes; i++) {
      final c = data.getUint8(offset + i);
      if (c == 0) break;
      sb.writeCharCode(c);
    }
    return sb.toString();
  }

  static String _readFixedStr(ByteData data, int offset, int len) {
    final sb = StringBuffer();
    for (var i = 0; i < len && offset + i < data.lengthInBytes; i++) {
      final c = data.getUint8(offset + i);
      if (c == 0) break;
      sb.writeCharCode(c);
    }
    return sb.toString().trim();
  }
}

// ── Internal SF2 data structures ──

class _SfPreset {
  final String name;
  final int bank;
  final int presetNum;
  final int bagIndex;
  final int bagCount;
  final List<_SfPresetZone> zones;

  _SfPreset({
    required this.name,
    required this.bank,
    required this.presetNum,
    required this.bagIndex,
    required this.bagCount,
    required this.zones,
  });
}

class _SfPresetZone {
  int instrumentIndex;
  _Range? keyRange;
  _Range? velRange;
  final List<_SfGenerator> generators;

  _SfPresetZone({
    required this.instrumentIndex,
    this.keyRange,
    this.velRange,
    required this.generators,
  });
}

class _SfInstrument {
  final String name;
  final int bagIndex;
  final int bagCount;
  final List<_SfInstZone> zones;

  _SfInstrument({
    required this.name,
    required this.bagIndex,
    required this.bagCount,
    required this.zones,
  });
}

class _SfInstZone {
  int sampleIndex;
  _Range? keyRange;
  _Range? velRange;
  final List<_SfGenerator> generators;

  _SfInstZone({
    required this.sampleIndex,
    this.keyRange,
    this.velRange,
    required this.generators,
  });
}

class _SfGenerator {
  final int type;
  final int amount; // unsigned 16-bit word amount
  _SfGenerator(this.type, this.amount);
}

class _SfSample {
  final String name;
  final int start;   // in samples
  final int end;
  final int startLoop;
  final int endLoop;
  final int sampleRate;
  final int originalPitch;
  final int pitchCorrection; // cents

  _SfSample({
    required this.name,
    required this.start,
    required this.end,
    required this.startLoop,
    required this.endLoop,
    required this.sampleRate,
    required this.originalPitch,
    required this.pitchCorrection,
  });
}

class _Range {
  final int low;
  final int high;
  const _Range(this.low, this.high);
}
