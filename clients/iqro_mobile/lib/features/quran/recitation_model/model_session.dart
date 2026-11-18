import 'dart:ffi';
import 'dart:typed_data';

import 'follow_core.dart';

typedef _OpenC = Int32 Function(Pointer<Void>, IntPtr, Int32);
typedef _OpenDart = int Function(Pointer<Void>, int, int);
typedef _RunC = Int32 Function(Pointer<Float>, Int32, Pointer<Float>);
typedef _RunDart = int Function(Pointer<Float>, int, Pointer<Float>);

/// The model, through the small library the trial build carries
/// (tool/recitation_model/iqro_recite.c over ONNX Runtime).
class RecitationModelSession {
  RecitationModelSession._(this._library);

  /// Null when the build has no model library or the model does not load.
  static RecitationModelSession? open(
    Uint8List model, {
    required int threads,
    String library = 'libiqro_recite.so',
  }) {
    final DynamicLibrary loaded;
    try {
      loaded = DynamicLibrary.open(library);
    } on Object {
      return null;
    }
    final session = RecitationModelSession._(loaded);
    final bytes = session._alloc(model.length);
    bytes.cast<Uint8>().asTypedList(model.length).setAll(0, model);
    final result = loaded.lookupFunction<_OpenC, _OpenDart>('iqro_open')(
      bytes,
      model.length,
      threads,
    );
    // ONNX Runtime copies what it needs of the model's bytes.
    session._free(bytes);
    return result == 0 ? session : null;
  }

  final DynamicLibrary _library;
  late final _alloc = _library
      .lookupFunction<
        Pointer<Void> Function(IntPtr),
        Pointer<Void> Function(int)
      >('iqro_alloc');
  late final _free = _library
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('iqro_free');
  late final _run = _library.lookupFunction<_RunC, _RunDart>('iqro_run');

  Pointer<Float> _input = nullptr;
  Pointer<Float> _output = nullptr;
  var _capacity = 0;

  /// [mel]: 80 rows of [frames] values. Log-probabilities of frames / 2
  /// frames, valid until the next call; null when the model fails.
  Float32List? run(Float32List mel, int frames) {
    if (frames > _capacity) {
      if (_capacity > 0) {
        _free(_input.cast());
        _free(_output.cast());
      }
      _capacity = frames + 200;
      _input = _alloc(4 * 80 * _capacity).cast();
      _output = _alloc(4 * (_capacity ~/ 2) * recitationClasses).cast();
    }
    _input.asTypedList(mel.length).setAll(0, mel);
    final rows = _run(_input, frames, _output);
    if (rows < 0) return null;
    return _output.asTypedList(rows * recitationClasses);
  }

  void close() {
    _library.lookupFunction<Void Function(), void Function()>('iqro_close')();
  }
}
