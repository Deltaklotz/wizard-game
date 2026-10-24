"""Battle theme, second take: "Grimoires Drawn" - flute(s) + drums, faster and wilder.

♩=200 (v1: 180), 6/8, D Dorian -> E Dorian. Form: drum intro - A (angular theme) - A' (sixteenth runs) -
drum break - B (octave-jumping hemiolas, climbing sequence) - Q (sudden quiet: stalking low flute over
shaker/rim) - R (build, modulating up a step) - A'' in E (two flutes in counterpoint) - C "storm" (flute
cascades answered by tom fills, then continuous arpeggios) - drum break - F (theme in octaves, full kit) -
coda (run up, unison hits).
Run: python battle_theme_v2.py -> out/battle_theme_v2.{mid,wav,ogg,mp3} + out/battle_theme_v2_daw.mid
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "lib"))
from score import Score, parse_line
from render import render

BAR = 6
def bar(i):
	return i * BAR

def run(names, d=0.5):
	return " ".join("%s:%s" % (n, d) for n in names.split())

def bars(text, a, b):
	return " | ".join(x.strip() for x in text.split("|")[a:b])

# ---------------- flute lines ----------------
A = ("D5:1 A5:1 D6:1 C6:0.5 B5:0.5 A5:1 F5:1 | G5:1 E5:1 C5:1 E5:1 G5:1 C6:1 | A5:0.5 B5:0.5 C6:1 A5:1 F5:1 D5:1 F5:1 | "
	"E5:1 A5:1 C#6:1 E6:2 C#6:1 | D6:1 A5:1 F5:1 D5:1 F5:1 A5:1 | B5:1 G5:1 D5:1 G5:1 B5:1 D6:1 | "
	"C6:0.5 D6:0.5 E6:1 C6:1 A5:1 G5:1 E5:1 | F5:1 E5:1 C#5:1 D5:2 r:1")
A2 = (run("D5 E5 F5 G5 A5 B5") + " C6:1 D6:1 A5:1 | G6:1 E6:1 C6:1 G5:1 C6:1 E6:1 | F6:0.5 E6:0.5 D6:1 A5:1 D6:1 F6:1 A6:1 | "
	"G6:1.5 E6:0.5 C#6:1 A5:1 " + run("C#6 E6") + " A6:1 | " + run("A6 G6 F6 E6 D6 C6") + " B5:1 G5:1 B5:1 | "
	"D6:1 B5:1 G5:1 " + run("A5 B5 C6 D6") + " E6:1 | F6:1 C6:1 A5:1 E6:1 C6:1 G5:1 | "
	+ run("A5 G5 F5 E5") + " C#5:1 D5:2 r:1")
B = ("D5:1 D6:1 A5:1 A4:1 F5:1 F6:1 | E6:1 E5:1 C6:1 C5:1 A5:1 A4:1 | F5:1 F6:1 D6:1 D5:1 A5:1 A6:1 | "
	"G6:1 G5:1 E6:1 E5:1 C#6:1 A5:1 | A5:1 Bb5:1 A5:1 G5:1 F5:1 E5:1 | Bb5:1 C6:1 Bb5:1 A5:1 G5:1 F5:1 | "
	"C6:1 D6:1 C6:1 Bb5:1 A5:1 G5:1 | " + run("A5 Bb5 C6 C#6 D6 E6") + " F6:1 E6:1 C#6:1")
Q = ("D5:1 r:1 D5:1 F5:1 r:1 E5:1 | D5:1 r:2 A4:1 C5:1 r:1 | D5:1 r:1 D5:1 F5:1 r:1 G5:1 | A5:1 r:2 G5:1 F5:1 E5:1 | "
	"D5:1 F5:1 D5:1 F5:1 A5:1 F5:1 | G5:1 Bb5:1 G5:1 Bb5:1 D6:1 Bb5:1")
R = ("A5:1 C#6:1 A5:1 C#6:1 E6:1 C#6:1 | " + run("A5 B5 C#6 D6 E6 F#6") + " G6:1 E6:1 C#6:1 | "
	"B5:1 D#6:1 B5:1 D#6:1 F#6:1 D#6:1 | " + run("B5 C#6 D#6 E6 F#6 G#6 A6 B6") + " A6:1 F#6:1")
C = (run("E6 B5 G5 E5 G5 B5") + " E6:1 r:2 | " + run("D6 A5 F#5 D5 F#5 A5") + " D6:1 r:2 | "
	+ run("C6 G5 E5 C5 E5 G5") + " C6:1 r:2 | " + run("B5 D#6 F#6 B6 F#6 D#6") + " B5:1 r:2 | "
	+ run("E6 G6 B6 G6 E6 B5 G5 B5 E6 B5 G5 E5") + " | " + run("F#5 A5 D6 A5 F#5 D5 F#5 A5 D6 F#6 A6 F#6") + " | "
	+ run("G6 E6 C6 G5 C6 E6 G6 E6 C6 E6 G6 C7") + " | B6:2 r:1 B5:1 D#6:1 F#6:1")
CODA = (run("E5 F#5 G5 A5 B5 C#6 D6 E6 F#6 G6 A6 B6") + " | B6:1 G6:1 E6:1 B5:1 G5:1 F#5:1 | "
	"B5:1 r:1 B5:1 D#6:1 r:1 F#6:1 | E6:2 r:4")

S_A, S_A2, S_D1, S_B, S_Q, S_R, S_A3, S_C, S_D2, S_F, S_CODA = 4, 12, 20, 22, 30, 36, 40, 48, 56, 58, 66
END = S_CODA + 4


def compose():
	s = Score(bpm_quarter=200, seed=33, humanize=0.025)
	fl = s.track("Flute", 73, bank=17, channel=0, volume=114, pan=52)
	fl2 = s.track("Flute 2", 73, bank=17, channel=2, volume=100, pan=78)
	kit = s.track("Drums", 0, channel=9, volume=108, pan=64)
	taiko = s.track("Taiko", 116, channel=1, volume=108, pan=60)
	curves = {fl: [], fl2: []}

	def flute(tr, start, text, level, transpose=0, legato=0.88):
		"""Dynamics follow the line: higher = louder, accents on the beats, long notes pushed."""
		t = start
		for ps, d in parse_line(text):
			if ps:
				p = ps[0] + transpose
				on_beat = abs((t - start) % 3) < 0.01
				tr.note(t, d, p, int(86 + (14 if on_beat else 0) + (p - 76) * 0.8), legato if d < 2 else 0.95)
				curves[tr].append((t, level + (p - 78) * 1.7 + (9 if on_beat else 0) + (6 if d >= 2 else 0)))
			t += d

	flute(fl, bar(S_A) - 2, run("A4 B4 C5 C#5"), 84)
	flute(fl, bar(S_A), A, 90)
	flute(fl, bar(S_A2), A2, 96)
	flute(fl, bar(S_B) - 1, run("A4 C#5"), 80)
	flute(fl, bar(S_B), B, 94)
	flute(fl, bar(S_Q), bars(Q, 0, 2), 54, legato=0.6)
	flute(fl, bar(S_Q + 2), bars(Q, 2, 4), 60, legato=0.6)
	flute(fl, bar(S_Q + 4), bars(Q, 4, 5), 70, legato=0.7)
	flute(fl, bar(S_Q + 5), bars(Q, 5, 6), 76, legato=0.7)
	flute(fl, bar(S_R), bars(R, 0, 2), 84)
	flute(fl, bar(S_R + 2), bars(R, 2, 4), 96)
	flute(fl, bar(S_A3), A2, 100, transpose=2)
	flute(fl2, bar(S_A3), A, 84, transpose=2)
	flute(fl, bar(S_C), C, 100)
	flute(fl, bar(S_F) - 1, run("B4 D#5"), 90)
	flute(fl, bar(S_F), bars(A, 0, 4), 106, transpose=2)
	flute(fl2, bar(S_F), bars(A, 0, 4), 96, transpose=-10)
	flute(fl, bar(S_F + 4), bars(A2, 4, 8), 108, transpose=2)
	flute(fl2, bar(S_F + 4), bars(A, 4, 8), 94, transpose=2)
	flute(fl, bar(S_CODA), CODA, 108)
	flute(fl2, bar(S_CODA), bars(CODA, 0, 1), 92, transpose=-12)
	flute(fl2, bar(S_CODA + 2), "G5:1 r:1 G5:1 B5:1 r:1 D#6:1 | B5:2 r:4", 100)
	for tr, pts in curves.items():
		pts.sort()
		clean = []
		for t, v in pts:
			v = max(0, min(127, v))
			if clean and t - clean[-1][0] < 0.2:
				clean[-1] = (clean[-1][0], v)
			else:
				clean.append((t, v))
		tr.dyn(clean, step=0.25)

	# ---------------- drums ----------------
	BD, RIM, SN, CRASH, CRASH2, TAMB, SHAKER = 36, 37, 38, 49, 57, 54, 70
	TOMS = [41, 43, 45, 47, 48, 50]
	CG_MUTE, CG_OPEN, CG_LOW = 62, 63, 64

	def boom(t, v=112, d=3):
		taiko.note(t, d, "D2", min(127, v))

	def ka(t, v=84):
		taiko.note(t, 1, "A2", min(127, v))

	def congas(t, v=0):
		for k, (n, vel) in enumerate([(CG_OPEN, 92), (CG_MUTE, 62), (CG_MUTE, 70), (CG_LOW, 88), (CG_MUTE, 62), (CG_OPEN, 74)]):
			kit.note(t + k, 1, n, vel + v)

	def tom_run(t, n, up=True, v0=70, dv=6, d=0.5):
		for k in range(n):
			idx = min(5, k * 6 // n)
			kit.note(t + k * d, d, TOMS[idx if up else 5 - idx], min(127, v0 + k * dv))

	def shaker(t, v=50, accent=6):
		for k in range(12):
			kit.note(t + k * 0.5, 0.5, SHAKER, v + (14 if k % accent == 0 else 0))

	def jig(i, level, fill=True, rel=None):
		t = bar(i)
		r = i if rel is None else rel
		boom(t, 108 + level * 5)
		boom(t + 3, 96 + level * 5)
		ka(t + 5, 76 + level * 8)
		ka(t + 2, 64 + level * 6)
		congas(t, level * 4)
		kit.note(t + 3, 1, SN, 74 + level * 12)
		kit.note(t, 1, TAMB, 70)
		kit.note(t + 3, 1, TAMB, 64)
		if level >= 1:
			shaker(t, 46 + level * 3)
			kit.note(t + 1, 0.5, SN, 34)
			kit.note(t + 4.5, 0.5, SN, 42)
		if level >= 2:
			kit.note(t, 1, BD, 104)
			kit.note(t + 3, 1, BD, 96)
			kit.note(t + 2.5, 0.5, SN, 48)
			ka(t + 1, 70)
			ka(t + 4, 74)
		if level >= 3:
			kit.note(t + 1.5, 0.5, BD, 84)
			kit.note(t + 5.5, 0.5, SN, 60)
			kit.note(t + 5, 0.5, SN, 52)
		if fill and r % 4 == 3:
			tom_run(t + 3, 6, up=(r % 8 == 3), v0=80 + level * 8, dv=5)
		if r % 4 == 0:
			kit.note(t, 3, CRASH if r % 8 == 0 else CRASH2, 98 + level * 7)

	def hemiola(i, level):
		t = bar(i)
		for k, o in enumerate((0, 2, 4)):
			boom(t + o, 114 if k == 0 else 102, 2)
			kit.note(t + o, 1, SN, 88 + level * 8)
			kit.note(t + o, 1, BD, 100)
			kit.note(t + o + 1, 1, CG_OPEN, 72)
			ka(t + o + 1, 66)
		kit.note(t, 1, TAMB, 78)
		shaker(t, 48 + level * 3, accent=4)

	def drum_break(i):
		"""Two bars of drums alone."""
		t = bar(i)
		kit.note(t, 3, CRASH, 110)
		for o, n, v in [(0, 5, 112), (1, 5, 80), (1.5, 4, 84), (2, 3, 96), (3, 2, 108), (4, 1, 90), (4.5, 1, 94), (5, 0, 104), (5.5, 0, 108)]:
			kit.note(t + o, 0.5, TOMS[n], v)
		for o in (0, 3, 5):
			boom(t + o, 118, 2)
			kit.note(t + o, 1, BD, 110)
		t += 6
		for o in (0, 1.5, 3, 4.5):  # dotted-quarter cross rhythm on taiko against snare sixteenths
			boom(t + o, 120, 1.5)
			kit.note(t + o, 1, BD, 108)
		for k in range(12):
			kit.note(t + k * 0.5, 0.5, SN, 58 + k * 5)
		tom_run(t + 4, 4, up=True, v0=100, dv=6)

	# intro
	boom(bar(0), 118)
	boom(bar(0) + 3, 104)
	ka(bar(0) + 5)
	boom(bar(1), 118)
	ka(bar(1) + 2, 78)
	boom(bar(1) + 3, 104)
	ka(bar(1) + 4, 78)
	ka(bar(1) + 5, 88)
	congas(bar(1), -6)
	jig(2, 1, fill=False)
	boom(bar(3), 118)
	kit.note(bar(3), 1, SN, 90)
	tom_run(bar(3) + 1, 6, up=True, v0=64, dv=7)

	for i in range(S_A, S_A + 8):
		jig(i, 1)
	for i in range(S_A2, S_A2 + 8):
		jig(i, 2)
	drum_break(S_D1)
	for i in range(S_B, S_B + 4):
		hemiola(i, 1)
	kit.note(bar(S_B), 3, CRASH2, 104)
	for i in range(S_B + 4, S_B + 8):
		jig(i, 2, fill=False)
	for k in range(6):
		kit.note(bar(S_B + 7) + 3 + k * 0.5, 0.5, SN, 70 + k * 9)
	# Q: sudden quiet - shaker, rim clicks, a soft taiko heartbeat; congas creep back
	kit.note(bar(S_Q), 6, CRASH, 112)
	boom(bar(S_Q), 124)
	for i in range(S_Q, S_Q + 6):
		t = bar(i)
		q = i - S_Q
		shaker(t, 34 + q * 3)
		kit.note(t + 3, 1, RIM, 62 + q * 4)
		kit.note(t + 5, 1, RIM, 50 + q * 4)
		if q:
			boom(t, 70 + q * 6)
		if q >= 2:
			boom(t + 3, 60 + q * 6)
		if q >= 4:
			congas(t, -22 + (q - 4) * 10)
	# R: build - snare roll, taiko on every beat, toms climbing
	for k in range(48):
		kit.note(bar(S_R) + k * 0.5, 0.5, SN, 40 + k * 1.75)
	for i in range(S_R, S_R + 4):
		q = i - S_R
		boom(bar(i), 100 + q * 7)
		boom(bar(i) + 3, 96 + q * 7)
		if q >= 2:
			ka(bar(i) + 2, 80)
			ka(bar(i) + 5, 86)
	tom_run(bar(S_R + 3) + 2, 8, up=True, v0=84, dv=5)
	for i in range(S_A3, S_A3 + 8):
		jig(i, 3)
	# C: storm - flute cascades answered by tom fills, then everything
	for q in range(4):
		t = bar(S_C + q)
		kit.note(t, 3, CRASH if q % 2 == 0 else CRASH2, 112)
		boom(t, 122)
		kit.note(t, 1, BD, 116)
		shaker(t, 44)
		kit.note(t + 3, 1, SN, 104)
		boom(t + 3, 108, 1)
		tom_run(t + 4, 4, up=(q % 2 == 1), v0=92, dv=7)
	for i in range(S_C + 4, S_C + 7):
		jig(i, 3, fill=False)
	t = bar(S_C + 7)
	boom(t, 124)
	kit.note(t, 2, CRASH, 116)
	kit.note(t, 1, SN, 112)
	kit.note(t, 1, BD, 116)
	drum_break(S_D2)
	for i in range(S_F, S_F + 8):
		jig(i, 3, rel=i - S_F)
		kit.note(bar(i) + 4, 0.5, BD, 80)
	jig(S_CODA, 3, fill=False)
	jig(S_CODA + 1, 3, fill=False)
	tom_run(bar(S_CODA + 1) + 3, 6, up=False, v0=96, dv=5)
	t = bar(S_CODA + 2)
	for o in (0, 2, 3, 5):
		boom(t + o, 122, 1)
		kit.note(t + o, 1, SN, 112)
		kit.note(t + o, 1, BD, 112)
		kit.note(t + o, 1, CRASH2, 90)
	f = bar(S_CODA + 3)
	taiko.note(f, 6, "D2", 127)
	taiko.note(f, 6, "A2", 120)
	kit.note(f, 6, CRASH, 126)
	kit.note(f, 6, CRASH2, 120)
	kit.note(f, 1, BD, 127)
	kit.note(f, 1, SN, 122)

	s.tempo(bar(S_F), 208)
	return s


if __name__ == "__main__":
	here = os.path.dirname(os.path.abspath(__file__))
	out = os.path.join(here, "out")
	os.makedirs(out, exist_ok=True)
	s = compose()
	s.save(os.path.join(out, "battle_theme_v2.mid"), dyn_cc=2)
	s.save(os.path.join(out, "battle_theme_v2_daw.mid"), dyn_cc=1)
	wav, secs = render(os.path.join(out, "battle_theme_v2.mid"), os.path.join(out, "battle_theme_v2"), wet=0.2)
	print("rendered %.1f s -> %s" % (secs, wav))
