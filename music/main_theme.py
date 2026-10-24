"""Main theme sketch: "Where the Waystones Sleep".

D major with a folk bVII (C), 6/8, light: harp bed, flute lead, cello counter, violins + women's choir
in the B section for weight, then everyone together, flute alone to close. No piano.
Run: python main_theme.py  -> out/main_theme.{mid,wav,ogg,mp3} + out/main_theme_daw.mid (CC1 dynamics)
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "lib"))
from score import Score
from render import render

BAR = 6
def bar(i):
	return i * BAR

# --- harmony --------------------------------------------------------------------------------------
CHORDS = {
	"D": (2, [0, 4, 7]), "C": (0, [0, 4, 7]), "G": (7, [0, 4, 7]), "Bm": (11, [0, 3, 7]),
	"Em": (4, [0, 3, 7]), "A": (9, [0, 4, 7]), "A7": (9, [0, 4, 7, 10]), "Asus4": (9, [0, 5, 7]),
}
INTRO = ["D", "G", "D", ("Asus4", "A")]
SEC_A = ["D", "C", "G", "D", "Bm", "G", ("Em", "A7"), "D"]
SEC_A2 = ["D", "C", "G", "D", "Bm", "G", "A7", "D"]
SEC_B = ["Bm", "G", "D", "A", "Bm", "G", "C", ("Asus4", "A")]
OUTRO = ["D", "C", "Bm", "G", "D", "D"]
FORM = INTRO + SEC_A + SEC_A2 + SEC_B + SEC_A2 + OUTRO
# bar indices
I0, A0, A2, B0, A3, O0 = 0, 4, 12, 20, 28, 36


def halves(c):
	"""Bar chord -> [(start offset, length, name)]."""
	if isinstance(c, tuple):
		return [(0, 3, c[0]), (3, 3, c[1])]
	return [(0, 6, c)]


def pcs(name):
	root, iv = CHORDS[name]
	return root, [(root + i) % 12 for i in iv], iv


def lead_voices(prev, name, lo, hi):
	"""Greedy voice leading: each voice moves to the nearest free chord tone in [lo, hi]."""
	_, tones, _ = pcs(name)
	cands = [p for p in range(lo, hi + 1) if p % 12 in tones]
	out = []
	for v in prev:
		best = min((p for p in cands if p not in out), key=lambda p: abs(p - v))
		out.append(best)
	# make sure root and third are present when possible
	return sorted(out)


# --- melody ---------------------------------------------------------------------------------------
A_HEAD = "D5:2 E5:1 F#5:2 A5:1 | G5:3 E5:2 C5:1 | D5:2 B4:1 D5:2 G5:1 | F#5:5 r:1"
A_TAIL = "B5:2 A5:1 F#5:2 D5:1 | G5:2 F#5:1 E5:2 D5:1 | E5:2 F#5:1 G5:2 E5:1 | D5:6"
A2_HEAD = "D5:2 E5:1 F#5:2 A5:1 | G5:3 E5:2 C5:1 | D5:2 B4:1 D5:2 G5:1 | F#5:3 G5:0.5 F#5:0.5 E5:1 D5:1"
A2_TAIL = "B5:2 A5:1 F#5:2 A5:1 | D6:3 B5:2 G5:1 | A5:2 G5:1 F#5:2 E5:1 | D5:6"
B_MEL = "D5:1 F#5:2 B5:3 | B5:2 A5:1 G5:3 | A5:2 F#5:1 D5:3 | E5:6 | D5:1 F#5:2 B5:2 C#6:1 | D6:3 B5:3 | C6:2 B5:1 G5:2 E5:1 | A5:6"
B_HARM = "B4:1 D5:2 F#5:3 | G5:2 F#5:1 D5:3 | F#5:2 D5:1 A4:3 | C#5:6 | B4:1 D5:2 F#5:2 A5:1 | B5:3 G5:3 | G5:2 G5:1 E5:2 C5:1 | D5:3 C#5:3"
CELLO_COUNTER = "A3:3 D4:3 | E4:4 D4:1 C4:1 | B3:6 | A3:3 F#3:3 | D4:3 F#4:3 | G4:4 F#4:1 E4:1 | E4:3 C#4:3 | D4:6"


def arch(t0, bars, lo, hi, peak=0.6):
	"""Phrase-shaped dynamics: lo -> hi at `peak` of the phrase -> slightly under lo."""
	L = bars * BAR
	return [(t0, lo), (t0 + L * peak, hi), (t0 + L - 0.5, lo * 0.85)]


def compose():
	s = Score(bpm_quarter=96, seed=7)

	flute = s.track("Flute", 73, bank=17, channel=0, volume=104, pan=58)
	harp = s.track("Harp", 46, channel=1, volume=92, pan=40)
	vln1 = s.track("Violins I", 49, bank=21, channel=2, volume=100, pan=44)
	vln2 = s.track("Violins II", 49, bank=26, channel=3, volume=92, pan=76)
	pad = s.track("Strings (pad)", 49, bank=17, channel=4, volume=84, pan=64)
	cello = s.track("Cello", 42, bank=17, channel=5, volume=86, pan=86)
	bass = s.track("Contrabass", 43, channel=6, volume=78, pan=80)
	pizz_lo = s.track("Celli pizz", 45, bank=40, channel=7, volume=84, pan=84)
	pizz_hi = s.track("Violins pizz", 45, bank=20, channel=8, volume=86, pan=46)
	choir = s.track("Women's choir", 52, bank=17, channel=10, volume=88, pan=64)
	celesta = s.track("Celesta", 8, channel=11, volume=104, pan=30)

	# --- harp: rolling 6/8 arpeggios through everything ---
	for i, c in enumerate(FORM):
		if i >= O0 + 5:
			break
		for off, ln, name in halves(c):
			root, _, iv = pcs(name)
			b = 36 + root
			b += 12 if b < 43 else 0
			third = iv[1]
			stack = [b, b + 7, b + 12, b + 12 + third, b + 19, b + 24]
			if ln == 3:
				pat = [0, 1, 2] if off == 0 else [0, 2, 3]
			else:
				pat = [0, 1, 2, 3, 4, 5] if i % 4 == 3 else [0, 1, 2, 3, 4, 3]
			loud = 62 if i < A2 else (70 if i < A3 else 74)
			if i >= O0:
				loud = 60
			for k, idx in enumerate(pat):
				harp.note(bar(i) + off + k, 5 if k == 0 else 4, stack[idx], loud + (8 if k == 0 else 0) - (3 if k % 2 else 0))
	# final roll: D add9 up to E6
	for k, p in enumerate(["D3", "A3", "D4", "E4", "F#4", "A4", "D5", "E5", "F#5", "A5", "E6"]):
		harp.note(bar(O0 + 5) + k * 0.33, 10, p, 66 - k)

	# --- flute ---
	flute.line(bar(A0), A_HEAD + " | " + A_TAIL, vel=82, legato=0.98, contour=0.3)
	flute.dyn(arch(bar(A0), 4, 62, 88) + arch(bar(A0 + 4), 4, 68, 92))
	flute.line(bar(A2), A2_HEAD + " | " + A2_TAIL, vel=84, legato=0.98, contour=0.3)
	flute.dyn(arch(bar(A2), 4, 66, 92) + arch(bar(A2 + 4), 4, 72, 100))
	# answers in the B section
	flute.line(bar(B0 + 3), "r:3 A5:1 B5:1 C#6:1", vel=74)
	flute.line(bar(B0 + 7), "r:4 C#5:1 E5:1", vel=78)
	flute.dyn([(bar(B0), 70), (bar(B0 + 8) - 0.5, 80)])
	flute.line(bar(A3), A2_HEAD + " | " + A2_TAIL, vel=88, legato=0.98, contour=0.3)
	flute.dyn(arch(bar(A3), 4, 78, 100) + arch(bar(A3 + 4), 4, 82, 108))
	flute.line(bar(O0), "D5:2 E5:1 F#5:2 A5:1 | G5:6 | F#5:3 E5:2 D5:1 | E5:6 | D5:12", vel=74, contour=0.2)
	flute.dyn([(bar(O0), 72), (bar(O0 + 1) + 3, 80), (bar(O0 + 3), 60), (bar(O0 + 4), 58), (bar(O0 + 6), 18)])

	# --- cello counter-melody (A' and A'') + bass ---
	cello.line(bar(A2), CELLO_COUNTER, vel=78, legato=1.0)
	cello.dyn(arch(bar(A2), 4, 55, 82) + arch(bar(A2 + 4), 4, 60, 86))
	cello.line(bar(A3), CELLO_COUNTER, vel=84, legato=1.0)
	cello.dyn(arch(bar(A3), 4, 66, 92) + arch(bar(A3 + 4), 4, 70, 96))
	for i, c in enumerate(FORM):
		if i < A0:
			continue
		for off, ln, name in halves(c):
			root, _, _ = pcs(name)
			p = 36 + root
			p += 12 if p < 36 else 0
			if p > 47:
				p -= 12
			bass.note(bar(i) + off, ln, p, 64 if i < B0 else 72)

	# --- string pad (voice-led), swelling through the piece ---
	voices = [62, 66, 69, 74]
	for i, c in enumerate(FORM):
		if i == 0:
			continue
		for off, ln, name in halves(c):
			voices = lead_voices(voices, name, 55, 76)
			for v in voices:
				pad.note(bar(i) + off, ln, v, 70)
	pad.dyn([(bar(1), 20), (bar(4), 50), (bar(A2), 52), (bar(B0), 58), (bar(B0 + 6), 88), (bar(A3), 70),
		(bar(O0), 64), (bar(O0 + 6), 10)])

	# --- pizzicato in A' (light walking feel under the counter-melody) ---
	vv = [66, 69, 74]
	for i in range(A2, B0):
		for off, ln, name in halves(FORM[i]):
			root, _, _ = pcs(name)
			b = 36 + root
			b += 12 if b < 43 else 0
			pizz_lo.note(bar(i) + off, 2, b, 72)
			vv = lead_voices(vv, name, 64, 79)
			if ln == 6:
				pizz_hi.note(bar(i) + 3, 1, vv[0], 58)
				pizz_hi.note(bar(i) + 3, 1, vv[1], 54)
				pizz_hi.note(bar(i) + 5, 1, vv[2], 50)

	# --- violins: B melody + harmony, then doubling the theme in A'' ---
	vln1.line(bar(B0), B_MEL, vel=84, legato=1.0, contour=0.4)
	vln1.dyn(arch(bar(B0), 4, 62, 96, 0.7) + arch(bar(B0 + 4), 4, 76, 110, 0.55))
	vln2.line(bar(B0), B_HARM, vel=76, legato=1.0)
	vln2.dyn(arch(bar(B0), 4, 52, 84, 0.7) + arch(bar(B0 + 4), 4, 66, 98, 0.55))
	vln1.line(bar(A3), A2_HEAD + " | " + A2_TAIL, vel=78, legato=1.0, contour=0.3)
	vln1.dyn(arch(bar(A3), 4, 56, 80) + arch(bar(A3 + 4), 4, 60, 88) + [(bar(O0), 40), (bar(O0) + 1, 0)])
	vln2.line(bar(A3), A2_HEAD + " | " + A2_TAIL, vel=70, transpose=-12)
	vln2.dyn(arch(bar(A3), 8, 50, 76) + [(bar(O0), 30), (bar(O0) + 1, 0)])

	# --- women's choir: weight in B and A'', fading out in the outro ---
	cv = [66, 69, 74]
	for i in list(range(B0, O0 + 6)):
		for off, ln, name in halves(FORM[i]):
			cv = lead_voices(cv, name, 64, 79)
			for v in cv:
				choir.note(bar(i) + off, ln, v, 72)
	choir.dyn([(bar(B0), 8), (bar(B0 + 2), 50), (bar(B0 + 5), 82), (bar(B0 + 7), 96), (bar(A3), 60),
		(bar(A3 + 6), 72), (bar(O0), 46), (bar(O0 + 3), 30), (bar(O0 + 6), 0)])

	# --- celesta sparkles ---
	celesta.line(bar(I0 + 2), "A6:1 F#6:1 E6:1 D6:1 A5:2 | r:3 E6:1 D6:1 C#6:1", vel=56)
	celesta.line(bar(A0 + 3), "r:3 A6:1 F#6:1 D6:1", vel=50)
	celesta.line(bar(A2 + 3), "r:3 A6:1 F#6:1 D6:1", vel=50)
	celesta.line(bar(O0 + 1), "r:2 G6:1 E6:1 C6:1 G5:1", vel=46)
	celesta.line(bar(O0 + 5), "r:2 D6:1 E6:1 F#6:1 A6:3", vel=42)

	# --- tempo: breath before A'', ritardando at the end ---
	s.tempo_ramp(bar(A3) - 4, bar(A3) - 0.5, 96, 84, 6)
	s.tempo(bar(A3), 96)
	s.tempo_ramp(bar(O0 + 3), bar(O0 + 6), 96, 72, 12)
	return s


if __name__ == "__main__":
	here = os.path.dirname(os.path.abspath(__file__))
	out = os.path.join(here, "out")
	os.makedirs(out, exist_ok=True)
	s = compose()
	s.save(os.path.join(out, "main_theme.mid"), dyn_cc=2)
	s.save(os.path.join(out, "main_theme_daw.mid"), dyn_cc=1)
	wav, secs = render(os.path.join(out, "main_theme.mid"), os.path.join(out, "main_theme"))
	print("rendered %.1f s -> %s" % (secs, wav))
