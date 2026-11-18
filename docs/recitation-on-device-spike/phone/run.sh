#!/bin/sh
# Times the model on an Android phone over adb. Nothing is installed: three files go to /data/local/tmp/iqro-bench,
# the program runs from there and the folder is removed afterwards. No app or setting of the phone is touched.
#   ORT=<folder of the unpacked onnxruntime-android AAR> MODEL=<model-int8.onnx> SERIAL=91aedea7 sh run.sh
set -e
NDK=${NDK:-$HOME/Library/Android/sdk/ndk/28.2.13676358}
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${TMPDIR:-/tmp}/iqro-bench
"$NDK"/toolchains/llvm/prebuilt/darwin-x86_64/bin/aarch64-linux-android24-clang -O2 -I "$ORT/headers" \
  -o "$OUT" "$HERE/bench.c" -L "$ORT/jni/arm64-v8a" -lonnxruntime -lm
adb -s "$SERIAL" shell mkdir -p /data/local/tmp/iqro-bench
adb -s "$SERIAL" push "$OUT" /data/local/tmp/iqro-bench/bench
adb -s "$SERIAL" push "$ORT/jni/arm64-v8a/libonnxruntime.so" "$MODEL" /data/local/tmp/iqro-bench/
adb -s "$SERIAL" shell "cd /data/local/tmp/iqro-bench && chmod +x bench && LD_LIBRARY_PATH=. ./bench $(basename "$MODEL")"
adb -s "$SERIAL" shell rm -r /data/local/tmp/iqro-bench
