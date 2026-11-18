"""Step 2: following a known text instead of recognising it. The audio of a surah is fed in small pieces as a
microphone would give it; at each piece the last WINDOW seconds go through the model and its per-frame sound
probabilities are aligned (CTC, Viterbi) with the expected sounds of the passage; the place is where the best path ends.
A path may jump over words (at a price), which is how a left-out word or ayah is noticed.

Truth for the timing: the same model on each whole ayah (both sides of context), aligned to the same text.
The delay reported is audio time: add the computing time of one step (see the speed tables) to get the real delay.

  MODEL_DIR=… AUDIO_DIR=… python 03_follow.py grid > out/03_follow_grid.txt     # settings compared on part of the audio
  MODEL_DIR=… AUDIO_DIR=… python 03_follow.py 0.2 6 0 0 > out/03_follow.txt      # one setting (step, window, guard, added silence) on all of it
"""
import collections, os, sys, time
from common import *

NEG = -1e9
SYM = {c: i + 1 for i, c in enumerate(SYMBOLS)}
SKIP_PRICE = 12.0   # log-probability paid for jumping over words
MAX_SKIP = 12       # words that may be jumped over at once (an ayah of the short surahs)


class Passage:
    def __init__(self, surah, ayat):
        self.ids, self.spans, self.ayah_of, self.words = [], [], [], []
        for a in ayat:
            ws = words(surah, a)
            ref = imam.expected(ws)  # each ayah read to its end and stopped on
            o = len(self.ids)
            self.ids += [SYM[c] for c in ref.phonemes]
            self.spans += [(s + o, e + o) for s, e in ref.spans]
            self.ayah_of += [a] * len(ws); self.words += ws
        self.ids = np.array(self.ids)
        self.word_of = np.zeros(len(self.ids), int)
        for w, (s, e) in enumerate(self.spans): self.word_of[s:e] = w
        self.starts = {s: w for w, (s, e) in enumerate(self.spans) if e > s}  # symbol index → word that begins there


def align(lp, p, lo, hi, first=None):
    """Best CTC path of the frames lp over the symbols p.ids[lo:hi] with a free end.
    first: (a, b) the path must begin with between a and b symbols of the passage already said (else: at lo).
    → per frame: how many symbols of the passage have been said (path), and the words jumped over [(frame, from, to)]"""
    ids = p.ids[lo:hi]; L = len(ids); S = 2 * L + 1
    em = np.full((lp.shape[0], S), 0.0, np.float32)
    em[:, 0::2] = lp[:, [0]]; em[:, 1::2] = lp[:, ids]
    can2 = np.zeros(S, bool); can2[3::2] = ids[1:] != ids[:-1]
    # jumps: into the first symbol of word w from the end of word v (its last symbol or the blank after it), v < w - 1
    jumps = []
    for k in range(L):
        w = p.starts.get(lo + k)
        if w is None: continue
        for v in range(max(0, w - 1 - MAX_SKIP), w - 1):
            e = p.spans[v][1] - lo  # symbols said when word v is done
            if 1 <= e <= L and p.spans[v][1] > p.spans[v][0]: jumps.append((2 * k + 1, 2 * e - 1, 2 * e, v, w))
    if jumps:
        jj = np.array([j[0] for j in jumps]); j1 = np.array([j[1] for j in jumps]); j2 = np.array([j[2] for j in jumps])
    al = np.full(S, NEG)
    if first is None: al[0] = em[0, 0]; al[1] = em[0, 1]
    else:
        a, b = max(0, first[0] - lo), min(L, first[1] - lo)
        al[2 * a:2 * b + 2] = em[0, 2 * a:2 * b + 2]
    T = lp.shape[0]
    bp = np.zeros((T, S), np.int32); bp[0] = np.arange(S)
    for t in range(1, T):
        c1 = np.concatenate([[NEG], al[:-1]]); c2 = np.where(can2, np.concatenate([[NEG, NEG], al[:-2]]), NEG)
        st = np.stack([al, c1, c2]); ch = st.argmax(0); new = st.max(0); src = np.arange(S) - ch
        if jumps:
            x = np.maximum(al[j1], al[j2]) - SKIP_PRICE
            best = np.full(S, NEG); np.maximum.at(best, jj, x)
            for i in np.nonzero((x > new[jj]) & (x == best[jj]))[0]:
                new[jj[i]] = x[i]; src[jj[i]] = j1[i] if al[j1[i]] >= al[j2[i]] else j2[i]
        al = new + em[t]; bp[t] = src
    s = int(al.argmax()); path = np.zeros(T, int); skipped = []
    for t in range(T - 1, -1, -1):
        path[t] = s
        q = int(bp[t, s])
        if s - q > 2: skipped.append((t, int(p.word_of[lo + (q - 1) // 2 if q % 2 else lo + q // 2 - 1]), int(p.word_of[lo + (s - 1) // 2])))
        s = q
    return lo + (path + 1) // 2, skipped[::-1]


def truth(sess, p, clips):
    """per word: (start, end) seconds in the stream, from each whole ayah aligned on its own"""
    out, t0, w0, s0 = [], 0.0, 0, 0
    for a, x in clips:
        n = sum(1 for q in p.ayah_of if q == a)
        hi = p.spans[w0 + n - 1][1]
        lp = logprobs(sess, x)
        said, _ = align(lp, p, s0, hi)
        for w in range(w0, w0 + n):
            s, e = p.spans[w]
            fs = int(np.argmax(said > s)); fe = len(said) - int(np.argmax(said[::-1] <= e - 1)) if said[-1] >= e else len(said)
            # the word ends when its last symbol stops being the one on the path
            last = np.nonzero(said == e)[0]
            fe = (last[0] + 1) if len(last) else len(said)
            out.append((t0 + fs * FRAME - 0.4, t0 + fe * FRAME - 0.4))
        t0 += len(x) / 16000; w0 += n; s0 = hi
    return out


def follow(sess, p, audio, hop, window, guard=0.0, tail=0.0):
    """→ per step: (time of the audio heard so far, symbols said, [jumps])"""
    steps, hist = [], [(0.0, 0)]
    n_hop = int(hop * 16000); pos = 0; cost = []
    for end in range(n_hop, len(audio) + n_hop, n_hop):
        end = min(end, len(audio)); now = end / 16000
        beg = max(0, end - int(window * 16000)); beg -= beg % 320
        x = audio[beg:end]
        if tail: x = np.concatenate([x, np.zeros(int(tail * 16000), np.float32)])
        if len(x) < 3200: continue
        t = time.perf_counter()
        lp = logprobs(sess, x, lead=False)
        nreal = min(lp.shape[0], int(((end - beg) / 16000 - guard) / FRAME))
        if nreal < 2: continue
        lp = lp[:nreal]
        t_beg = beg / 16000
        e0 = max((e for (tt, e) in hist if tt <= t_beg + 1e-6), default=0)
        lo = max(0, e0 - 10); hi = min(len(p.ids), max(pos, e0) + 70)
        said, jumps = align(lp, p, lo, hi, first=(max(lo, e0 - 6), min(hi, e0 + 3)) if beg else None)
        cost.append(time.perf_counter() - t)
        # the place at every frame of this window: kept as the history the next windows start from
        for f in range(0, nreal, 5): hist.append((t_beg + f * FRAME, int(said[f])))
        hist = [h for h in hist if h[0] > now - window - 1] ; hist.sort()
        pos = int(said[-1])
        steps.append((now, pos, [(t_beg + f * FRAME, v, w) for f, v, w in jumps]))
    return steps, cost


def measure(p, tr, steps):
    """delays against the truth: when the place first reached each word / first had each word said in full"""
    reach, done = {}, {}
    for now, pos, _ in steps:
        for w, (s, e) in enumerate(p.spans):
            if e <= s: continue
            if w not in reach and pos > s: reach[w] = now
            if w not in done and pos >= e: done[w] = now
    d_start = [reach[w] - tr[w][0] for w in reach]
    d_end = [done[w] - tr[w][1] for w in done]
    back = sum(1 for a, b in zip(steps, steps[1:]) if p.word_of[max(0, b[1] - 1)] < p.word_of[max(0, a[1] - 1)])
    early = sum(1 for d in d_start if d < -0.1)
    never = sum(1 for w, (s, e) in enumerate(p.spans) if e > s and w not in reach)
    return d_start, d_end, back, early, never


def pct(v, q): return float(np.percentile(v, q)) if len(v) else float('nan')


if __name__ == '__main__':
    reciters = sorted(os.listdir(AUDIO_DIR))
    sess = session(threads=4)
    surahs = [(1, 7), (112, 4), (113, 5), (114, 6), (103, 3)]
    grid = [(0.1, 6, 0.0, 0.0), (0.2, 6, 0.0, 0.0), (0.3, 6, 0.0, 0.0), (0.5, 6, 0.0, 0.0),
            (0.2, 3, 0.0, 0.0), (0.2, 10, 0.0, 0.0), (0.2, 6, 0.1, 0.0), (0.2, 6, 0.2, 0.0), (0.2, 6, 0.0, 0.4)]
    quick = len(sys.argv) > 1 and sys.argv[1] == 'grid'  # the grid on half of the reciters and three surahs
    if quick: reciters, surahs = reciters[::2], surahs[:3]
    else: grid = [tuple(float(v) for v in sys.argv[1:5])] if len(sys.argv) > 4 else grid[1:2]
    data = []
    for r in reciters:
        for s, n in surahs:
            p = Passage(s, range(1, n + 1))
            clips = [(a, clip(r, s, a)) for a in range(1, n + 1)]
            data.append((r, s, p, clips, truth(sess, p, clips)))
    print(f'{len(data)} recitations ({len(reciters)} reciters × {len(surahs)} surahs), {sum(len(d[4]) for d in data)} words, '
          f'{sum(len(x) for d in data for _, x in d[3]) / 16000:.0f} s of audio\n')
    print('step s | window s | guard s | silence added s | word begins → place on it: median / 90 % / worst, s | '
          'word ends → word heard in full: median / 90 % | place moved before the word began | place went back | words never reached | false "left out" | computing per step on this Mac (4 threads), ms')
    for hop, window, guard, tail in grid:
        ds, de, back, early, never, false_skip, cost = [], [], 0, 0, 0, 0, []
        for r, s, p, clips, tr in data:
            steps, c = follow(sess, p, np.concatenate([x for _, x in clips]), hop, window, guard, tail)
            a, b, k, e, nv = measure(p, tr, steps)
            ds += a; de += b; back += k; early += e; never += nv; cost += c
            false_skip += len({(v, w) for st in steps[-1:] for _, v, w in st[2]} | {(v, w) for st in steps for _, v, w in st[2] if st[0] - _ > 1.0})
        print(f'{hop} | {window} | {guard} | {tail} | {pct(ds, 50):.2f} / {pct(ds, 90):.2f} / {max(ds):.2f} | '
              f'{pct(de, 50):.2f} / {pct(de, 90):.2f} | {early} | {back} | {never} | {false_skip} | {1000 * np.median(cost):.0f}', flush=True)
