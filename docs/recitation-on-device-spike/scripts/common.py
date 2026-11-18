"""Shared helpers of the spike: the model (Hisnlabs/tajweed-v2, ONNX), its log-mel, CTC decoding.

MODEL_DIR is the folder with the files downloaded from the model's Hugging Face page (config.json, imam.py,
onnx/model-int8.onnx); AUDIO_DIR holds <reciter>/<SSSAAA>.wav at 16 kHz mono. Neither is kept in git.
"""
import json, os, sys, wave
import numpy as np, onnxruntime as ort
from faster_whisper.feature_extractor import FeatureExtractor

MODEL_DIR = os.environ['MODEL_DIR']
AUDIO_DIR = os.environ['AUDIO_DIR']
sys.path.insert(0, MODEL_DIR)
import imam  # noqa: E402  the rule engine shipped with the model
from quran_transcript import Aya  # noqa: E402

META = json.load(open(os.path.join(MODEL_DIR, 'config.json')))
SYMBOLS = META['phonemes']
LEAD = int(16000 * 0.4)  # the training clips start and end with silence
FRAME = 0.02
_mel = FeatureExtractor(feature_size=80)

SURAHS = {1: 7, 103: 3, 108: 3, 112: 4, 113: 5, 114: 6, 2: 5}
CLIPS = [(s, a) for s, n in SURAHS.items() for a in range(1, n + 1)]


def session(model='onnx/model-int8.onnx', threads=2):
    o = ort.SessionOptions()
    o.intra_op_num_threads = threads
    o.inter_op_num_threads = 1
    return ort.InferenceSession(os.path.join(MODEL_DIR, model), o, providers=['CPUExecutionProvider'])


def read_wav(path):
    with wave.open(path) as f:
        assert f.getframerate() == 16000 and f.getsampwidth() == 2
        return np.frombuffer(f.readframes(f.getnframes()), '<i2').astype(np.float32) / 32768


def clip(reciter, surah, ayah):
    return read_wav(os.path.join(AUDIO_DIR, reciter, f'{surah:03d}{ayah:03d}.wav'))


def words(surah, ayah):
    return Aya(surah, ayah).get().uthmani.split(' ')


def logprobs(sess, audio, lead=True):
    """log-probabilities [frames, 43], one frame per 20 ms; with lead, 0.4 s of silence is put on both sides
    (as the model's own inference.py does) and frame t is at t*0.02 - 0.4 s of the audio"""
    if lead:
        audio = np.concatenate([np.zeros(LEAD, np.float32), audio, np.zeros(LEAD, np.float32)])
    mel = _mel(audio, padding=0)
    mel = mel[:, : min(3000, mel.shape[1] // 2 * 2)]
    return sess.run(None, {'mel': mel[None].astype(np.float32), 'riwaya': np.array([0], np.int64)})[0][0]


def decode(lp, offset=-LEAD / 16000):
    """CTC best path → script, per-symbol probability, per-symbol time (+ the end of the last one)"""
    ids = lp.argmax(-1)
    out, probs, times, prev = [], [], [], 0
    for t, i in enumerate(ids):
        if i != prev and i != 0:
            out.append(SYMBOLS[i - 1]); probs.append(float(np.exp(lp[t, i]))); times.append((t + 0.5) * FRAME + offset)
        prev = i
    last = [t for t, i in enumerate(ids) if i != 0]
    times.append(((last[-1] + 1) * FRAME + offset) if last else 0.0)
    return ''.join(out), probs, times


def remarks(ws, heard, probs, times, lang='en'):
    ref = imam.recited(ws, heard, riwaya='hafs')
    return ref, imam.listen(ref, heard, heard_probs=probs, heard_times=times, min_prob=0.3, min_prob_jali=0.7,
                            langs=(lang,))
