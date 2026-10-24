"""Chord symbols, voice leading and phrase dynamics shared by the pieces."""
from score import NOTE

QUALITY = {"": [0, 4, 7], "m": [0, 3, 7], "7": [0, 4, 7, 10], "m7": [0, 3, 7, 10], "sus4": [0, 5, 7],
	"maj7": [0, 4, 7, 11], "add9": [0, 4, 7, 14], "5": [0, 7]}


def chord(name):
	"""'Bb' / 'F#m' / 'A7' / 'Asus4' -> (root pitch class, intervals, pitch classes)."""
	root = NOTE[name[0]]
	rest = name[1:]
	while rest and rest[0] in "#b" and not rest.startswith("b5"):
		root += 1 if rest[0] == "#" else -1
		rest = rest[1:]
	iv = QUALITY[rest]
	return root % 12, iv, [(root + i) % 12 for i in iv]


def halves(c, bar_len=6):
	"""A bar's chord ('Dm' or ('Gm', 'A7')) -> [(offset, length, name)]."""
	if isinstance(c, tuple):
		n = len(c)
		return [(k * bar_len / n, bar_len / n, x) for k, x in enumerate(c)]
	return [(0, bar_len, c)]


def bass_note(name, lo=36):
	root = chord(name)[0]
	p = lo - lo % 12 + root
	return p + 12 if p < lo else p


def lead_voices(prev, name, lo, hi):
	"""Greedy voice leading: each voice moves to the nearest free chord tone in [lo, hi]."""
	tones = chord(name)[2]
	cands = [p for p in range(lo, hi + 1) if p % 12 in tones]
	out = []
	for v in prev:
		free = [p for p in cands if p not in out] or cands
		out.append(min(free, key=lambda p: abs(p - v)))
	return sorted(out)


def arch(t0, length, lo, hi, peak=0.6):
	"""Phrase-shaped dynamics over `length` eighths: lo -> hi at `peak` -> slightly under lo."""
	return [(t0, lo), (t0 + length * peak, hi), (t0 + length - 0.5, lo * 0.85)]


def scale_run(start_p, end_p, key_pcs, step=0.5):
	"""Scale pitches from start to end (inclusive-ish) within the given pitch classes."""
	d = 1 if end_p >= start_p else -1
	return [p for p in range(start_p, end_p + d, d) if p % 12 in key_pcs]
