// Step 3: how long the model takes on a phone. A plain command-line program (no app is installed or touched):
// it loads the ONNX model and times it on windows of 2, 4, 6 and 8 s of (random) log-mel with 1, 2 and 4 threads.
//   bench model-int8.onnx
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include "onnxruntime_c_api.h"

static const OrtApi *g;
#define OK(x) do { OrtStatus *st_ = (x); if (st_) { fprintf(stderr, "%s\n", g->GetErrorMessage(st_)); exit(1); } } while (0)

static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec * 1e3 + t.tv_nsec / 1e6; }
static int cmp(const void *a, const void *b) { double d = *(double *)a - *(double *)b; return d < 0 ? -1 : d > 0; }

int main(int argc, char **argv) {
  g = OrtGetApiBase()->GetApi(ORT_API_VERSION);
  OrtEnv *env; OK(g->CreateEnv(ORT_LOGGING_LEVEL_WARNING, "bench", &env));
  OrtMemoryInfo *mem; OK(g->CreateCpuMemoryInfo(OrtArenaAllocator, OrtMemTypeDefault, &mem));
  const char *in[] = {"mel", "riwaya"}, *out[] = {"logprobs"};
  int threads[] = {1, 2, 4}, secs[] = {2, 4, 6, 8};
  for (int ti = 0; ti < 3; ti++) {
    OrtSessionOptions *o; OK(g->CreateSessionOptions(&o));
    OK(g->SetIntraOpNumThreads(o, threads[ti])); OK(g->SetInterOpNumThreads(o, 1));
    OK(g->SetSessionGraphOptimizationLevel(o, ORT_ENABLE_ALL));
    double t0 = now();
    OrtSession *s; OK(g->CreateSession(env, argv[1], o, &s));
    printf("threads=%d  model loaded in %.0f ms\n", threads[ti], now() - t0);
    for (int si = 0; si < 4; si++) {
      int frames = secs[si] * 100;
      float *mel = malloc(sizeof(float) * 80 * frames);
      for (int i = 0; i < 80 * frames; i++) mel[i] = (rand() % 2000) / 1000.0f - 1.0f;
      int64_t shape[] = {1, 80, frames}, rshape[] = {1}, riwaya = 0;
      OrtValue *v[2] = {0, 0}, *r = 0;
      OK(g->CreateTensorWithDataAsOrtValue(mem, mel, sizeof(float) * 80 * frames, shape, 3, ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, &v[0]));
      OK(g->CreateTensorWithDataAsOrtValue(mem, &riwaya, sizeof riwaya, rshape, 1, ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64, &v[1]));
      double ts[8];
      for (int k = 0; k < 8; k++) {
        double t = now();
        OK(g->Run(s, 0, in, (const OrtValue *const *)v, 2, out, 1, &r));
        ts[k] = now() - t; g->ReleaseValue(r); r = 0;
      }
      qsort(ts + 1, 7, sizeof(double), cmp);  // the first run warms up
      printf("  threads=%d window=%d s: median %.0f ms, slowest %.0f ms  (%.0f ms per second of audio)\n", threads[ti], secs[si], ts[4], ts[7], ts[4] / secs[si]);
      fflush(stdout);
      g->ReleaseValue(v[0]); g->ReleaseValue(v[1]); free(mel);
    }
    g->ReleaseSession(s); g->ReleaseSessionOptions(o);
  }
  return 0;
}
