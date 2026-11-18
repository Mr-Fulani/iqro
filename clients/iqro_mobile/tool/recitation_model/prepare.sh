#!/bin/sh
# Puts into this checkout what the trial build of the recitation check with a model on the phone needs and git
# does not keep (docs/recitation-on-device-spike):
#   assets/recitation_model/model-int8.onnx   the model, from its Hugging Face page (Apache-2.0)
#   assets/recitation_model/expected.json     the table of expected sounds of every ayah, and mel_filters.bin
#   android/app/src/main/jniLibs/arm64-v8a/   ONNX Runtime and the small library over it (iqro_recite.c)
# Needs: curl, unzip, uv (for Python 3.11), the Android NDK. Then build with --dart-define=RECITATION_MODEL=true
# and --target-platform android-arm64. To undo: tool/recitation_model/prepare.sh clean
set -e
cd "$(dirname "$0")/../.."
ASSETS=assets/recitation_model
LIBS=android/app/src/main/jniLibs/arm64-v8a
if [ "$1" = clean ]; then
  rm -f "$ASSETS/model-int8.onnx" "$ASSETS/expected.json" "$ASSETS/mel_filters.bin"
  rm -f "$LIBS/libonnxruntime.so" "$LIBS/libiqro_recite.so"
  exit 0
fi
WORK=${WORK:-build/recitation_model}
NDK=${NDK:-$HOME/Library/Android/sdk/ndk/28.2.13676358}
ORT_VERSION=1.32.0
MODEL=https://huggingface.co/Hisnlabs/tajweed-v2/resolve/main
mkdir -p "$WORK/model/onnx" "$WORK/ort" "$LIBS"
for f in config.json imam.py onnx/model-int8.onnx; do
  [ -s "$WORK/model/$f" ] || curl -sSL -o "$WORK/model/$f" "$MODEL/$f"
done
# The files this trial was measured with.
echo "79cca1a2fc7ef81e325a3071a5f26cfec69203ef2c63177549065cdc1022c373  $WORK/model/onnx/model-int8.onnx" | shasum -a 256 -c -
echo "b6914b40296226eb7cb9e906958bbe332981e86797821775d3f813dd0730911e  $WORK/model/imam.py" | shasum -a 256 -c -
cp "$WORK/model/onnx/model-int8.onnx" "$ASSETS/"
[ -s "$WORK/ort/ort.aar" ] || curl -sSL -o "$WORK/ort/ort.aar" \
  "https://repo1.maven.org/maven2/com/microsoft/onnxruntime/onnxruntime-android/$ORT_VERSION/onnxruntime-android-$ORT_VERSION.aar"
unzip -q -o "$WORK/ort/ort.aar" 'jni/arm64-v8a/libonnxruntime.so' 'headers/*' -d "$WORK/ort"
cp "$WORK/ort/jni/arm64-v8a/libonnxruntime.so" "$LIBS/"
"$NDK"/toolchains/llvm/prebuilt/darwin-x86_64/bin/aarch64-linux-android24-clang -O2 -shared -fPIC \
  -I "$WORK/ort/headers" -o "$LIBS/libiqro_recite.so" tool/recitation_model/iqro_recite.c -L "$LIBS" -lonnxruntime
if [ ! -s "$ASSETS/expected.json" ]; then
  [ -d "$WORK/venv" ] || uv venv -q -p 3.11 "$WORK/venv"
  uv pip install -q -p "$WORK/venv/bin/python" numpy faster-whisper quran-transcript levenshtein
  "$WORK/venv/bin/python" tool/recitation_model/build_table.py "$WORK/model" "$ASSETS"
fi
ls -l "$ASSETS" "$LIBS"
