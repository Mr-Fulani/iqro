import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'follow_core.dart';

typedef _Status = Pointer<Void>;
typedef _Release = void Function(Pointer<Void>);
typedef _ReleaseC = Void Function(Pointer<Void>);

/// The model of the recitation check, run by ONNX Runtime (the
/// `onnxruntime-android` library of the Android build) through its C API.
///
/// The API is a table of functions in an order that never changes between
/// versions; the places below are those of `onnxruntime_c_api.h` (found
/// with `offsetof(OrtApi, …)`), the same for every version from 1.12 on.
class RecitationModelSession {
  RecitationModelSession._(this._api);

  static const _apiVersion = 12;
  static const _createEnv = 3;
  static const _createSessionFromArray = 8;
  static const _run = 9;
  static const _createSessionOptions = 10;
  static const _setGraphOptimizationLevel = 23;
  static const _setIntraOpNumThreads = 24;
  static const _setInterOpNumThreads = 25;
  static const _createTensorWithData = 49;
  static const _getTensorMutableData = 51;
  static const _createCpuMemoryInfo = 69;
  static const _releaseEnv = 92;
  static const _releaseStatus = 93;
  static const _releaseMemoryInfo = 94;
  static const _releaseSession = 95;
  static const _releaseValue = 96;
  static const _releaseSessionOptions = 100;

  /// Null when the build has no ONNX Runtime or the model does not load.
  static RecitationModelSession? open(
    Uint8List model, {
    required int threads,
    String library = 'libonnxruntime.so',
  }) {
    final Pointer<Void> api;
    try {
      final base = DynamicLibrary.open(library)
          .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
            'OrtGetApiBase',
          )();
      api = base
          .cast<Pointer<NativeFunction<Pointer<Void> Function(Uint32)>>>()
          .value
          .asFunction<Pointer<Void> Function(int)>()(_apiVersion);
    } on Object {
      return null;
    }
    if (api == nullptr) return null;
    final session = RecitationModelSession._(api);
    return session._load(model, threads) ? session : null;
  }

  final Pointer<Void> _api;
  Pointer<Void> _env = nullptr;
  Pointer<Void> _session = nullptr;
  Pointer<Void> _memory = nullptr;

  Pointer<NativeFunction<T>> _at<T extends Function>(int place) =>
      Pointer.fromAddress((_api.cast<IntPtr>() + place).value);

  /// True when the call went well; its error, if any, is let go.
  bool _ok(_Status status) {
    if (status == nullptr) return true;
    _at<_ReleaseC>(_releaseStatus).asFunction<_Release>()(status);
    return false;
  }

  bool _load(Uint8List model, int threads) {
    final out = calloc<Pointer<Void>>();
    final name = 'iqro'.toNativeUtf8();
    final bytes = malloc<Uint8>(model.length);
    Pointer<Void> options = nullptr;
    try {
      bytes.asTypedList(model.length).setAll(0, model);
      // Errors only (3).
      if (!_ok(
        _at<_Status Function(Int32, Pointer<Utf8>, Pointer<Pointer<Void>>)>(
              _createEnv,
            )
            .asFunction<
              _Status Function(int, Pointer<Utf8>, Pointer<Pointer<Void>>)
            >()(3, name, out),
      )) {
        return false;
      }
      _env = out.value;
      if (!_ok(
        _at<_Status Function(Pointer<Pointer<Void>>)>(
          _createSessionOptions,
        ).asFunction<_Status Function(Pointer<Pointer<Void>>)>()(out),
      )) {
        return false;
      }
      options = out.value;
      final set = <(int, int)>[
        (_setIntraOpNumThreads, threads),
        (_setInterOpNumThreads, 1),
        (_setGraphOptimizationLevel, 99), // every optimization
      ];
      for (final (place, value) in set) {
        _ok(
          _at<_Status Function(Pointer<Void>, Int32)>(
            place,
          ).asFunction<_Status Function(Pointer<Void>, int)>()(options, value),
        );
      }
      if (!_ok(
        _at<
              _Status Function(
                Pointer<Void>,
                Pointer<Uint8>,
                Size,
                Pointer<Void>,
                Pointer<Pointer<Void>>,
              )
            >(_createSessionFromArray)
            .asFunction<
              _Status Function(
                Pointer<Void>,
                Pointer<Uint8>,
                int,
                Pointer<Void>,
                Pointer<Pointer<Void>>,
              )
            >()(_env, bytes, model.length, options, out),
      )) {
        return false;
      }
      _session = out.value;
      // The arena allocator (1), default memory (0).
      if (!_ok(
        _at<_Status Function(Int32, Int32, Pointer<Pointer<Void>>)>(
          _createCpuMemoryInfo,
        ).asFunction<_Status Function(int, int, Pointer<Pointer<Void>>)>()(
          1,
          0,
          out,
        ),
      )) {
        return false;
      }
      _memory = out.value;
      return true;
    } finally {
      if (options != nullptr) {
        _at<_ReleaseC>(_releaseSessionOptions).asFunction<_Release>()(options);
      }
      // ONNX Runtime has its own copy of the model by now.
      malloc.free(bytes);
      calloc.free(name);
      calloc.free(out);
      if (_memory == nullptr) close();
    }
  }

  Pointer<Float> _input = nullptr;
  var _capacity = 0;
  late final _shape = calloc<Int64>(3);
  late final _one = calloc<Int64>()..value = 1;
  late final _riwaya = calloc<Int64>(); // 0: Hafs
  late final _values = calloc<Pointer<Void>>(3);
  late final _names = calloc<Pointer<Utf8>>(3)
    ..[0] = 'mel'.toNativeUtf8()
    ..[1] = 'riwaya'.toNativeUtf8()
    ..[2] = 'logprobs'.toNativeUtf8();

  late final _tensor =
      _at<
            _Status Function(
              Pointer<Void>,
              Pointer<Void>,
              Size,
              Pointer<Int64>,
              Size,
              Int32,
              Pointer<Pointer<Void>>,
            )
          >(_createTensorWithData)
          .asFunction<
            _Status Function(
              Pointer<Void>,
              Pointer<Void>,
              int,
              Pointer<Int64>,
              int,
              int,
              Pointer<Pointer<Void>>,
            )
          >();
  late final _runModel =
      _at<
            _Status Function(
              Pointer<Void>,
              Pointer<Void>,
              Pointer<Pointer<Utf8>>,
              Pointer<Pointer<Void>>,
              Size,
              Pointer<Pointer<Utf8>>,
              Size,
              Pointer<Pointer<Void>>,
            )
          >(_run)
          .asFunction<
            _Status Function(
              Pointer<Void>,
              Pointer<Void>,
              Pointer<Pointer<Utf8>>,
              Pointer<Pointer<Void>>,
              int,
              Pointer<Pointer<Utf8>>,
              int,
              Pointer<Pointer<Void>>,
            )
          >();
  late final _release = _at<_ReleaseC>(_releaseValue).asFunction<_Release>();

  /// [mel]: 80 rows of [frames] values. Log-probabilities of frames / 2
  /// frames; null when the model fails.
  Float32List? run(Float32List mel, int frames) {
    if (_session == nullptr) return null;
    if (frames > _capacity) {
      if (_capacity > 0) malloc.free(_input);
      _capacity = frames + 200;
      _input = malloc<Float>(80 * _capacity);
    }
    _input.asTypedList(mel.length).setAll(0, mel);
    _shape[0] = 1;
    _shape[1] = 80;
    _shape[2] = frames;
    _values[0] = nullptr;
    _values[1] = nullptr;
    _values[2] = nullptr;
    try {
      // Float tensors are type 1, 64-bit integers 7.
      if (!_ok(
            _tensor(
              _memory,
              _input.cast(),
              4 * 80 * frames,
              _shape,
              3,
              1,
              _values,
            ),
          ) ||
          !_ok(_tensor(_memory, _riwaya.cast(), 8, _one, 1, 7, _values + 1)) ||
          !_ok(
            _runModel(
              _session,
              nullptr,
              _names,
              _values,
              2,
              _names + 2,
              1,
              _values + 2,
            ),
          )) {
        return null;
      }
      final data = calloc<Pointer<Float>>();
      try {
        if (!_ok(
          _at<_Status Function(Pointer<Void>, Pointer<Pointer<Float>>)>(
                _getTensorMutableData,
              )
              .asFunction<
                _Status Function(Pointer<Void>, Pointer<Pointer<Float>>)
              >()(_values[2], data),
        )) {
          return null;
        }
        // A copy: the model's own memory goes with its answer.
        return Float32List.fromList(
          data.value.asTypedList(frames ~/ 2 * recitationClasses),
        );
      } finally {
        calloc.free(data);
      }
    } finally {
      for (var i = 0; i < 3; i++) {
        if (_values[i] != nullptr) _release(_values[i]);
      }
    }
  }

  /// Lets the model's memory go: it is tens of megabytes, and no garbage
  /// collector knows of it.
  void close() {
    if (_session != nullptr) {
      _at<_ReleaseC>(_releaseSession).asFunction<_Release>()(_session);
      _session = nullptr;
    }
    if (_memory != nullptr) {
      _at<_ReleaseC>(_releaseMemoryInfo).asFunction<_Release>()(_memory);
      _memory = nullptr;
    }
    if (_env != nullptr) {
      _at<_ReleaseC>(_releaseEnv).asFunction<_Release>()(_env);
      _env = nullptr;
    }
    if (_capacity > 0) {
      // What a run needs was made at the first one.
      malloc.free(_input);
      _capacity = 0;
      for (var i = 0; i < 3; i++) {
        calloc.free(_names[i]);
      }
      calloc
        ..free(_names)
        ..free(_values)
        ..free(_shape)
        ..free(_one)
        ..free(_riwaya);
    }
  }
}
