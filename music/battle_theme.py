"""Battle theme sketch: "Grimoires Drawn" - flute + drums.

A fast 6/8 jig in D Dorian (♩=180, one bar per second): the main theme's head (D E F A | G E C) turned into a
restless flute line with runs, cuts, hemiolas and a cascade, over taiko, toms, congas, snare, tambourine
and shaker. Flute dynamics follow the line (higher = louder, accents on the beats) so it keeps surging.
Run: python battle_theme.py -> out/battle_theme.{mid,wav,ogg,mp3} + out/battle_theme_daw.mid
(The earlier full-orchestra version is battle_theme_orchestral.py.)
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

# ---------------- flute ----------------
A = ("D5:1 E5:1 F5:1 A5:2 F5:1 | G5:1 A5:1 G5:1 E5:1 D5:1 C5:1 | D5:1 F5:1 A5:1 D6:2 A5:1 | "
	"C6:0.5 D6:0.5 C6:1 A5:1 G5:1 E5:1 C5:1 | D5:1 E5:1 F5:1 A5:2 F5:1 | G5:1 B5:1 D6:1 G6:2 D6:1 | "
	"E6:1 D6:1 C6:1 A5:1 G5:1 E5:1 | F5:1 E5:1 C#5:1 D5:3")
A2 = ("A5:0.5 B5:0.5 C6:0.5 D6:0.5 E6:1 F6:1 E6:0.5 D6:0.5 C6:1 | D6:1 A5:1 F5:1 G5:0.5 A5:0.5 G5:1 E5:1 | "
	"D5:1 F5:1 A5:1 D6:1 F6:1 A6:1 | G6:1.5 F6:0.5 E6:1 D6:1 C6:1 A5:1 | "
	"B5:0.5 C6:0.5 D6:1 B5:1 G5:1 A5:0.5 B5:0.5 G5:1 | C6:1 E6:1 G6:1 E6:1 C6:1 G5:1 | "
	"A5:0.5 B5:0.5 C6:0.5 B5:0.5 A5:1 G5:1 E5:1 C#5:1 | D5:3 r:1 A4:1 C5:1")
B_LOW = "D5:2 D5:2 F5:2 | E5:2 C5:2 A4:2 | F5:2 F5:2 A5:2 | G5:2 E5:2 C5:2"
B_HIGH = "D6:2 D6:2 F6:2 | E6:2 C6:2 A5:2 | F6:2 F6:2 A6:2 | G6:2 E6:2 C6:2"
B_SEQ = ("A5:1 Bb5:1 A5:1 G5:1 F5:1 E5:1 | Bb5:1 C6:1 Bb5:1 A5:1 G5:1 F5:1 | C6:1 D6:1 C6:1 Bb5:1 A5:1 G5:1 | "
	+ run("A5 Bb5 C6 C#6 D6 E6") + " F6:1 E6:1 C#6:1")
C = ("D6:6 | C6:3 A5:3 | Bb5:6 | A5:2 C#6:2 E6:2 | " + run("F6 G6 " * 6) + " | "
	+ run("E6 D6 C6 Bb5 A5 G5 F5 E5 D5 C#5 D5 E5") + " | " + run("F5 G5 A5 Bb5 C6 D6 E6 F6 G6 A6 G6 E6") + " | "
	"A6:2 G6:0.5 E6:0.5 C#6:1 A5:1 C#6:1")
A3 = ("D5:1 E5:1 F5:1 B5:0.25 A5:1.75 F5:1 | G5:1 A5:1 G5:1 E5:1 D5:1 C5:1 | D5:1 F5:1 A5:1 E6:0.25 D6:1.75 A5:1 | "
	"C6:0.5 D6:0.5 C6:1 A5:1 G5:1 E5:1 C5:1 | " + A2.split(" | ", 4)[4])
CODA = (run("D5 E5 F5 G5 A5 B5 C6 D6 E6 F6 G6 A6") + " | A6:1 F6:1 D6:1 A5:1 F5:1 E5:1 | "
	"A5:1 r:1 A5:1 C#6:1 r:1 E6:1 | D6:2 r:4")

INTRO, S_A, S_A2, S_B, S_C, S_A3, S_B2, S_CODA = 0, 4, 12, 20, 28, 36, 44, 52


def compose():
	s = Score(bpm_quarter=180, seed=21, humanize=0.03)
	fl = s.track("Flute", 73, bank=17, channel=0, volume=112, pan=60)
	kit = s.track("Drums", 0, channel=9, volume=118, pan=64)
	taiko = s.track("Taiko", 116, channel=1, volume=118, pan=60)
	dyn = []

	def flute(start, text, level, legato=0.9):
		"""Write a flute passage; dynamics follow pitch (higher = louder) with accents on the beats."""
		t = start
		for ps, d in parse_line(text):
			if ps:
				p = ps[0]
				on_beat = abs((t - start) % 3) < 0.01
				v = 84 + (14 if on_beat else 0) + (p - 76) * 0.8
				fl.note(t, d, p, int(v), legato if d < 3 else 0.97)
				dyn.append((t, level + (p - 76) * 1.6 + (8 if on_beat else 0) + (6 if d >= 2 else 0)))
			t += d
		return t

	# pickup into A at the end of the intro
	flute(bar(S_A) - 2, run("A4 C5 D5 E5"), 84)
	flute(bar(S_A), A, 88)
	flute(bar(S_A2), A2, 94)
	flute(bar(S_B), B_LOW, 82)
	flute(bar(S_B + 4), B_SEQ, 92)
	flute(bar(S_C), C, 90)
	flute(bar(S_A3), A3, 100)
	flute(bar(S_B2), B_HIGH, 98)
	flute(bar(S_B2 + 4), B_SEQ, 104)
	flute(bar(S_CODA), CODA, 106)
	# long notes in the breakdown swell instead of sitting still
	dyn += [(bar(S_C), 70), (bar(S_C) + 5, 110), (bar(S_C + 1), 84), (bar(S_C + 2), 66), (bar(S_C + 2) + 5, 108),
		(bar(S_C + 3), 86), (bar(S_C + 4), 96)]
	dyn.sort()
	clean = []
	for t, v in dyn:
		if clean and t - clean[-1][0] < 0.2:
			clean[-1] = (t, max(0, min(127, v)))
		else:
			clean.append((t, max(0, min(127, v))))
	fl.dyn(clean, step=0.25)

	# ---------------- drums ----------------
	BD, SN, CRASH, CRASH2, TAMB, SHAKER = 36, 38, 49, 57, 54, 70
	TOMS = [41, 43, 45, 47, 48, 50]  # low -> high
	CG_MUTE, CG_OPEN, CG_LOW = 62, 63, 64

	def boom(t, v=112):
		taiko.note(t, 3, "D2", v)

	def ka(t, v=84):
		taiko.note(t, 1, "A2", v)

	def congas(t, v=0):
		for k, (n, vel) in enumerate([(CG_OPEN, 92), (CG_MUTE, 62), (CG_MUTE, 70), (CG_LOW, 88), (CG_MUTE, 62), (CG_OPEN, 74)]):
			kit.note(t + k, 1, n, vel + v)

	def tom_run(t, n, up=True, v0=70, dv=6, d=0.5):
		for k in range(n):
			idx = min(5, k * 6 // n)
			kit.note(t + k * d, d, TOMS[idx if up else 5 - idx], min(127, v0 + k * dv))

	def jig(i, level):
		"""level 0..3: busier and louder."""
		t = bar(i)
		boom(t, 108 + level * 5)
		boom(t + 3, 96 + level * 5)
		ka(t + 5, 76 + level * 8)
		if level >= 1:
			ka(t + 2, 66 + level * 6)
		congas(t, level * 4)
		kit.note(t + 3, 1, SN, 70 + level * 12)
		kit.note(t, 1, TAMB, 70)
		kit.note(t + 3, 1, TAMB, 64)
		if level >= 2:
			for k in range(12):
				kit.note(t + k * 0.5, 0.5, SHAKER, 50 + (14 if k % 6 == 0 else 0))
			kit.note(t + 1, 0.5, SN, 34)
			kit.note(t + 4.5, 0.5, SN, 40)
		if level >= 3:
			kit.note(t, 1, BD, 104)
			kit.note(t + 3, 1, BD, 96)
			ka(t + 1, 70)
			ka(t + 4, 74)
		if i % 4 == 3:  # fill in the back half of every 4th bar
			tom_run(t + 3, 6, up=False, v0=76 + level * 8, dv=5)
		if i % 8 == 4:
			kit.note(t, 3, CRASH if i % 16 == 4 else CRASH2, 100 + level * 6)

	def hemiola(i, level):
		t = bar(i)
		for k, o in enumerate((0, 2, 4)):
			boom(t + o, 110 if k == 0 else 98)
			kit.note(t + o, 1, SN, 84 + level * 8)
			kit.note(t + o + 1, 1, CG_MUTE, 60)
		kit.note(t, 1, TAMB, 76)
		if level >= 2:
			for k in range(12):
				kit.note(t + k * 0.5, 0.5, SHAKER, 48 + (12 if k % 4 == 0 else 0))

	# intro: taiko alone, congas join, a groove bar, then a tom fill into A
	boom(bar(0), 116)
	boom(bar(0) + 3, 100)
	ka(bar(0) + 5)
	boom(bar(1), 116)
	boom(bar(1) + 3, 100)
	congas(bar(1), -10)
	jig(2, 0)
	boom(bar(3), 116)
	tom_run(bar(3), 8, up=True, v0=60, dv=6)
	kit.note(bar(3), 1, SN, 80)

	for i in range(S_A, S_A + 8):
		jig(i, 0)
	for i in range(S_A2, S_A2 + 8):
		jig(i, 1)
	for i in range(S_B, S_B + 4):
		hemiola(i, 1)
	for i in range(S_B + 4, S_B + 8):
		jig(i, 2)
	kit.note(bar(S_B), 3, CRASH2, 100)
	# breakdown: half time, then a build of snare sixteenths, taiko and a tom run
	for i in range(S_C, S_C + 4):
		boom(bar(i), 104)
		kit.note(bar(i) + 3, 1, TAMB, 60)
		if i % 2 == 1:
			ka(bar(i) + 4, 70)
			ka(bar(i) + 5, 76)
	kit.note(bar(S_C), 6, CRASH, 96)
	for k in range(42):
		kit.note(bar(S_C + 4) + k * 0.5, 0.5, SN, 36 + k * 1.9)
	for i in range(S_C + 4, S_C + 8):
		boom(bar(i), 100 + (i - S_C - 4) * 6)
		boom(bar(i) + 3, 92 + (i - S_C - 4) * 6)
	tom_run(bar(S_C + 7) + 3, 6, up=True, v0=90, dv=6)
	for i in range(S_A3, S_A3 + 8):
		jig(i, 3)
	for i in range(S_B2, S_B2 + 4):
		hemiola(i, 3)
	for i in range(S_B2 + 4, S_B2 + 8):
		jig(i, 3)
	kit.note(bar(S_B2), 3, CRASH, 110)
	# coda: two driving bars, then hits in unison with the flute
	jig(S_CODA, 3)
	jig(S_CODA + 1, 3)
	t = bar(S_CODA + 2)
	for o in (0, 2, 3, 5):
		boom(t + o, 120)
		kit.note(t + o, 1, SN, 110)
		kit.note(t + o, 1, BD, 110)
	f = bar(S_CODA + 3)
	taiko.note(f, 6, "D2", 127)
	kit.note(f, 6, CRASH, 124)
	kit.note(f, 6, CRASH2, 118)
	kit.note(f, 1, BD, 127)
	kit.note(f, 1, SN, 120)
	return s


if __name__ == "__main__":
	here = os.path.dirname(os.path.abspath(__file__))
	out = os.path.join(here, "out")
	os.makedirs(out, exist_ok=True)
	s = compose()
	s.save(os.path.join(out, "battle_theme.mid"), dyn_cc=2)
	s.save(os.path.join(out, "battle_theme_daw.mid"), dyn_cc=1)
	wav, secs = render(os.path.join(out, "battle_theme.mid"), os.path.join(out, "battle_theme"), wet=0.2)
	print("rendered %.1f s -> %s" % (secs, wav))
