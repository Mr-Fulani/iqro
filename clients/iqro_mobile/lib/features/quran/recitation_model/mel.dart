import 'dart:math' as math;
import 'dart:typed_data';

/// Whisper's log-mel of a microphone's sound as it comes: 80 bands, 100
/// frames a second, each frame worked out once.
class StreamingMel {
  StreamingMel(this._filters) {
    for (var n = 0; n < _size; n++) {
      _hann[n] = .5 - .5 * math.cos(2 * math.pi * n / _size);
    }
    for (var k = 0; k < _bins; k++) {
      for (var n = 0; n < _size; n++) {
        _cos[k * _size + n] = math.cos(2 * math.pi * k * n / _size);
        _sin[k * _size + n] = math.sin(2 * math.pi * k * n / _size);
      }
    }
  }

  static const bands = 80;
  static const _size = 400;
  static const _hop = 160;
  static const _bins = 201;
  static const _silence = -10.0;
  static const _kept = 3200;

  /// 80 × 201, as the model's own feature extractor has them.
  final Float32List _filters;
  final _hann = Float64List(_size);
  final _cos = Float32List(_bins * _size);
  final _sin = Float32List(_bins * _size);

  /// The samples from [_base] on: those the frames to come still need.
  var _sound = Float32List(0);
  var _base = 0;
  var _count = 0;

  /// Frames worked out, the first being frame [_first].
  final _frames = <Float32List>[];
  var _first = 0;

  /// Samples heard so far.
  int get samples => _count;

  void add(Int16List pcm) {
    final grown = Float32List(_count - _base + pcm.length)
      ..setRange(0, _count - _base, _sound);
    for (var i = 0; i < pcm.length; i++) {
      grown[_count - _base + i] = pcm[i] / 32768;
    }
    _sound = grown;
    _count += pcm.length;
    // Frame k has the samples k·160 ± 200.
    while ((_first + _frames.length) * _hop + _size ~/ 2 <= _count) {
      _frames.add(_frame(_first + _frames.length));
    }
    if (_frames.length > _kept) {
      final drop = _frames.length - _kept;
      _frames.removeRange(0, drop);
      _first += drop;
    }
    final needed = math.max(0, (_first + _frames.length) * _hop - _size ~/ 2);
    if (needed > _base) {
      _sound = Float32List.sublistView(_sound, needed - _base);
      _base = needed;
    }
  }

  double _sample(int n) {
    if (n < 0) n = -n; // as the extractor mirrors the start
    if (n >= _count || n < _base) return 0;
    return _sound[n - _base];
  }

  Float32List _frame(int k) {
    final x = Float64List(_size);
    final start = k * _hop - _size ~/ 2;
    for (var n = 0; n < _size; n++) {
      x[n] = _sample(start + n) * _hann[n];
    }
    final power = Float64List(_bins);
    for (var b = 0; b < _bins; b++) {
      var re = 0.0;
      var im = 0.0;
      final row = b * _size;
      for (var n = 0; n < _size; n++) {
        re += x[n] * _cos[row + n];
        im -= x[n] * _sin[row + n];
      }
      power[b] = re * re + im * im;
    }
    final out = Float32List(bands);
    for (var m = 0; m < bands; m++) {
      var sum = 0.0;
      final row = m * _bins;
      for (var b = 0; b < _bins; b++) {
        sum += _filters[row + b] * power[b];
      }
      out[m] = math.log(math.max(sum, 1e-10)) / math.ln10;
    }
    return out;
  }

  /// The frames from [from] up to [to] as the model takes them (80 rows),
  /// with [lead] and [tail] frames of silence around them.
  Float32List window(int from, int to, {int lead = 0, int tail = 0}) {
    final count = lead + to - from + tail;
    final rows = List<Float32List?>.filled(count, null);
    var top = _silence;
    for (var k = from; k < to; k++) {
      final Float32List row;
      if (k < _first) {
        continue;
      } else if (k - _first < _frames.length) {
        row = _frames[k - _first];
      } else {
        // Its last samples have not come yet: silence stands for them.
        row = _frame(k);
      }
      rows[lead + k - from] = row;
      for (final value in row) {
        if (value > top) top = value;
      }
    }
    final out = Float32List(bands * count);
    final quiet = (math.max(_silence, top - 8) + 4) / 4;
    for (var t = 0; t < count; t++) {
      final row = rows[t];
      for (var m = 0; m < bands; m++) {
        out[m * count + t] = row == null
            ? quiet
            : (math.max(row[m], top - 8) + 4) / 4;
      }
    }
    return out;
  }
}
