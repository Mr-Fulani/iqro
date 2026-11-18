// The model of the trial recitation follower behind three plain functions, so the app's Dart code needs no
// knowledge of ONNX Runtime's API. Built by prepare.sh for the trial build only; not part of a normal build.
#include <stdlib.h>
#include <string.h>
#include "onnxruntime_c_api.h"

static const OrtApi *g;
static OrtEnv *env;
static OrtSession *session;
static OrtMemoryInfo *mem;

void *iqro_alloc(size_t bytes) { return malloc(bytes); }
void iqro_free(void *p) { free(p); }

// 0 when the model is ready.
int iqro_open(const void *model, size_t bytes, int threads) {
  g = OrtGetApiBase()->GetApi(ORT_API_VERSION);
  if (!g) return 1;
  OrtSessionOptions *o;
  if (g->CreateEnv(ORT_LOGGING_LEVEL_ERROR, "iqro", &env)) return 2;
  if (g->CreateSessionOptions(&o)) return 3;
  g->SetIntraOpNumThreads(o, threads);
  g->SetInterOpNumThreads(o, 1);
  g->SetSessionGraphOptimizationLevel(o, ORT_ENABLE_ALL);
  if (g->CreateSessionFromArray(env, model, bytes, o, &session)) return 4;
  g->ReleaseSessionOptions(o);
  if (g->CreateCpuMemoryInfo(OrtArenaAllocator, OrtMemTypeDefault, &mem)) return 5;
  return 0;
}

// mel: 80 rows of `frames` values (frames even). out: frames / 2 rows of 43 log-probabilities.
// Returns the rows written, or a negative number.
int iqro_run(const float *mel, int frames, float *out) {
  const char *in[] = {"mel", "riwaya"}, *names[] = {"logprobs"};
  int64_t shape[] = {1, 80, frames}, one[] = {1}, riwaya = 0;
  OrtValue *v[2] = {0, 0}, *r = 0;
  if (g->CreateTensorWithDataAsOrtValue(mem, (void *)mel, sizeof(float) * 80 * frames, shape, 3,
                                        ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, &v[0])) return -1;
  if (g->CreateTensorWithDataAsOrtValue(mem, &riwaya, sizeof riwaya, one, 1,
                                        ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64, &v[1])) return -2;
  OrtStatus *s = g->Run(session, 0, in, (const OrtValue *const *)v, 2, names, 1, &r);
  g->ReleaseValue(v[0]);
  g->ReleaseValue(v[1]);
  if (s) { g->ReleaseStatus(s); return -3; }
  float *data;
  g->GetTensorMutableData(r, (void **)&data);
  memcpy(out, data, sizeof(float) * (frames / 2) * 43);
  g->ReleaseValue(r);
  return frames / 2;
}

void iqro_close(void) {
  if (session) g->ReleaseSession(session);
  if (env) g->ReleaseEnv(env);
  session = 0;
  env = 0;
}
