"""Main theme, second take: "Where the Waystones Sleep" - faster, busier, with real peaks and valleys.

♩=132 (v1: 96). Form: intro - A (theme, now leaping over an octave and a half) - A' (decorated, violin +
cello counter-lines) - B (B minor: violins call, flute answers) - bridge (the valley: solo flute + harp,
slower) - build (rising bass F#-G-A-B, modulating) - A'' in E major (violins carry the theme, flute descant,
choir) - C (light dance variation) - coda (the head once more, a borrowed minor iv, harp roll).
Run: python main_theme_v2.py -> out/main_theme_v2.{mid,wav,ogg,mp3} + out/main_theme_v2_daw.mid
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "lib"))
from score import Score, parse_line
from harmony import chord, halves, bass_note, lead_voices
from render import render

BAR = 6
def bar(i):
	return i * BAR

def run(names, d=0.5):
	return " ".join("%s:%s" % (n, d) for n in names.split())

# ---------------- harmony ----------------
INTRO = ["D", "G", "D", ("Asus4", "A")]
SEC_A = ["D", "C", "G", ("D", "A"), "Bm", "G", ("Em", "A7"), "D"]
SEC_A1 = ["D", "C", "G", "D", "Bm", ("G", "A"), ("F#m", "Bm"), ("Em", "A7")]
SEC_B = ["Bm", "G", "D", ("A", "F#7"), "Bm", ("G", "A"), "D", ("Asus4", "A")]
BRIDGE = ["G", "D", "Em", "Bm", "G", "D", ("Em", "G"), "A"]
BUILD = ["F#m", "G", "A", "B7"]
SEC_A2 = ["E", "D", "A", ("E", "B"), "C#m", "A", ("F#m", "B7"), "E"]
SEC_C = ["E", "A", "E", "B", "C#m", "A", ("F#m", "B7"), "E"]
CODA = ["E", "D", "C#m", ("A", "Am"), "E", "E"]
FORM = INTRO + SEC_A + SEC_A1 + SEC_B + BRIDGE + BUILD + SEC_A2 + SEC_C + CODA
I0, A0, A1, B0, R0, K0, A2, C0, O0 = 0, 4, 12, 20, 28, 36, 40, 48, 56
END = O0 + 6

# ---------------- melodies ----------------
THEME = ("D5:2 E5:1 F#5:1 A5:1 D6:1 | C6:1.5 B5:0.5 G5:1 E5:2 C5:1 | D5:1 G5:1 B5:1 D6:2 B5:1 | "
	"A5:1 F#5:1 D5:1 E5:3 | F#5:1 B5:1 D6:1 F#6:2 D6:1 | E6:1 D6:1 B5:1 G5:2 B5:1 | "
	"G5:1 F#5:1 E5:1 C#5:1 E5:1 G5:1 | F#5:0.5 G5:0.5 F#5:1 E5:1 D5:3")
THEME_DECO = ("A5:0.5 B5:0.5 A5:1 F#5:1 D5:1 F#5:1 A5:1 | G5:1 C6:1 E6:1 D6:1 C6:1 G5:1 | B5:2 D6:1 G6:2 F#6:1 | "
	"E6:0.5 F#6:0.5 E6:1 D6:1 A5:2 F#5:1 | B5:1 F#5:1 B5:1 D6:1 C#6:1 B5:1 | B5:1 G5:1 B5:1 A5:1 C#6:1 E6:1 | "
	"F#6:2 C#6:1 D6:2 B5:1 | G5:1 B5:1 E6:1 C#6:1 A5:1 G5:1")
VLN_COUNTER = "F#5:6 | E5:6 | D5:3 G5:3 | F#5:6 | D5:6 | D5:3 E5:3 | A5:3 F#5:3 | G5:3 E5:3"
CELLO_A1 = "A3:3 D4:3 | E4:4 D4:1 C4:1 | B3:6 | A3:3 F#3:3 | D4:3 F#4:3 | G4:3 E4:3 | C#4:3 D4:3 | B3:3 A3:3"
CELLO_A = "A3:3 D4:3 | E4:4 D4:1 C4:1 | B3:6 | A3:3 C#4:3 | D4:3 F#4:3 | G4:4 F#4:1 E4:1 | E4:3 C#4:3 | D4:6"
B_VLN = ("B4:1 D5:1 F#5:1 B5:2 A5:1 | G5:1 B5:1 D6:1 B5:2 G5:1 | F#5:6 | E5:6 | "
	"D6:2 B5:1 F#5:2 B5:1 | G5:1 B5:1 D6:1 E6:1 C#6:1 A5:1 | A5:1 F#5:1 D5:1 F#5:1 A5:1 D6:1 | D6:1 A5:1 A5:1 E5:3")
B_FLUTE = ("r:12 | A5:0.5 B5:0.5 A5:1 F#5:1 D6:2 A5:1 | C#6:1 A5:1 E5:1 F#5:1 A#5:1 C#6:1 | "
	"r:3 " + run("B5 C#6 D6 E6") + " F#6:1 | r:6 | F#6:1 D6:1 A5:1 D6:1 F#6:1 A6:1 | A6:1 E6:1 D6:1 C#6:3")
BRIDGE_FLUTE = ("B4:3 D5:2 G5:1 | F#5:4 E5:1 D5:1 | E5:3 G5:2 B5:1 | A5:1 F#5:4 r:1 | "
	"B5:3 A5:2 G5:1 | F#5:3 A5:3 | G5:2 E5:1 D5:2 B4:1 | C#5:3 E5:3")
BRIDGE_CELLO = "r:24 | B3:6 | A3:6 | G3:3 B3:3 | E4:6"
BUILD_FLUTE = ("F#5:1 A5:1 C#6:1 F#6:3 | G5:1 B5:1 D6:1 G6:3 | A5:1 C#6:1 E6:1 A6:3 | "
	+ run("B5 C#6 D#6 E6 F#6 G#6 A6 B6") + " A6:1 F#6:1")
BUILD_VLN = "C#5:6 | D5:6 | E5:6 | F#5:3 A5:3"
DESCANT = ("B5:2 E6:1 G#6:2 B6:1 | A6:2 F#6:1 D6:1 F#6:1 A6:1 | E6:1 C#6:1 A5:1 C#6:0.5 E6:0.5 A6:2 | "
	"G#6:2 E6:1 D#6:1 F#6:1 B6:1 | B5:1 E6:1 G#6:1 B6:2 G#6:1 | A6:1 G#6:1 E6:1 C#6:2 E6:1 | "
	"C#6:1 B5:1 A5:1 F#5:0.5 A5:0.5 B5:0.5 D#6:0.5 F#6:1 | B5:0.5 C#6:0.5 B5:1 A5:1 G#5:3")
DANCE = ("E6:1 B5:1 G#5:1 B5:1 E6:1 G#6:1 | A6:1 E6:1 C#6:1 E6:1 A5:1 C#6:1 | B5:0.5 C#6:0.5 B5:1 G#5:1 E5:1 G#5:1 B5:1 | "
	"F#5:1 B5:1 D#6:1 F#6:2 D#6:1 | E6:1 C#6:1 G#5:1 C#6:1 E6:1 G#6:1 | A6:1.5 G#6:0.5 E6:1 C#6:1 A5:1 C#6:1 | "
	"F#6:1 C#6:1 A5:1 " + run("B5 C#6 D#6 F#6") + " A6:1 | G#6:2 E6:1 B5:3")
DANCE_VLN = "r:24 | G#5:6 | A5:3 C#6:3 | A5:3 F#5:3 | E5:6"
CODA_FLUTE = "E5:2 F#5:1 G#5:2 B5:1 | A5:3 F#5:2 D5:1 | E5:2 C#5:1 E5:2 G#5:1 | A5:3 C6:2 A5:1 | G#5:3 F#5:3 | E5:6"
CODA_CELLO = "G#3:6 | F#3:6 | E3:6 | E3:6 | B3:6 | G#3:6"


def chords_in(i0, n):
	for i in range(i0, i0 + n):
		for off, ln, name in halves(FORM[i]):
			yield i, bar(i) + off, ln, name


def compose():
	s = Score(bpm_quarter=132, seed=5, humanize=0.05)
	flute = s.track("Flute", 73, bank=17, channel=0, volume=106, pan=58)
	harp = s.track("Harp", 46, channel=1, volume=94, pan=40)
	vln1 = s.track("Violins I", 49, bank=21, channel=2, volume=124, pan=44)
	vln2 = s.track("Violins II", 49, bank=26, channel=3, volume=104, pan=76)
	pad = s.track("Strings (pad)", 49, bank=17, channel=4, volume=80, pan=64)
	cello = s.track("Cello", 42, bank=17, channel=5, volume=86, pan=86)
	bass = s.track("Contrabass", 43, channel=6, volume=80, pan=80)
	pizz_lo = s.track("Celli pizz", 45, bank=40, channel=7, volume=88, pan=84)
	pizz_hi = s.track("Violins pizz", 45, bank=20, channel=8, volume=86, pan=46)
	perc = s.track("Cymbal", 48, channel=9, volume=80, pan=64)
	choir = s.track("Women's choir", 52, bank=17, channel=10, volume=90, pan=64)
	celesta = s.track("Celesta", 8, channel=11, volume=104, pan=30)
	timp = s.track("Timpani", 47, channel=12, volume=80, pan=70)
	curves = {}

	def mel(tr, start, text, level, follow=1.3, center=76, legato=0.97, transpose=0, vel=84, bloom=True):
		"""Melody whose dynamics follow its shape: higher = louder, long notes bloom a little."""
		t = start
		pts = curves.setdefault(tr, [])
		for ps, d in parse_line(text):
			if ps:
				p = ps[0] + transpose
				tr.note(t, d, p, int(vel + (p - center) * 0.5), legato)
				pts.append((t, level + (p - center) * follow))
				if d >= 3 and bloom:
					pts.append((t + d * 0.55, level + (p - center) * follow + 9))
					pts.append((t + d - 0.3, level + (p - center) * follow - 6))
			t += d
		return t

	# ---------------- harp ----------------
	PATS = [[0, 1, 2, 3, 4, 3], [0, 2, 3, 4, 3, 2], [0, 1, 3, 2, 4, 5]]
	for i, t, ln, name in chords_in(0, END - 1):
		root, iv, _ = chord(name)
		b = bass_note(name, 43)
		stack = [b, b + 7, b + 12, b + 12 + iv[1], b + 19, b + 24]
		if R0 <= i < R0 + 8:  # bridge: three slow notes per bar
			pat, step, loud = ([0, 2, 4] if ln == 6 else [0, 3]), (2 if ln == 6 else 1.5), 56
		elif ln == 3:
			pat, step, loud = ([0, 1, 2] if t % 6 == 0 else [0, 2, 3]), 1, 66
		else:
			pat, step, loud = PATS[i % 3], 1, 66
		if i < A0 or i >= O0:
			loud = 58
		elif A2 <= i < C0:
			loud = 80
		elif K0 <= i < A2:
			loud = 62 + (i - K0) * 5
		for k, idx in enumerate(pat):
			harp.note(t + k * step, 4 if k else 5, stack[idx], loud + (8 if k == 0 else 0) - (3 if k % 2 else 0))
	for k, p in enumerate(["E3", "B3", "E4", "F#4", "G#4", "B4", "E5", "F#5", "G#5", "B5", "F#6"]):
		harp.note(bar(END - 1) + k * 0.4, 12, p, 64 - k)

	# ---------------- flute ----------------
	mel(flute, bar(A0) - 1.5, run("A4 B4 C#5"), 66)
	mel(flute, bar(A0), THEME, 78)
	mel(flute, bar(A1), THEME_DECO, 84)
	mel(flute, bar(B0), B_FLUTE, 86)
	mel(flute, bar(R0), BRIDGE_FLUTE, 62, follow=1.0, center=72)
	mel(flute, bar(K0), BUILD_FLUTE, 80, follow=1.6)
	mel(flute, bar(A2), DESCANT, 70, follow=1.0, center=80)
	mel(flute, bar(C0), DANCE, 80, legato=0.9)
	mel(flute, bar(O0), CODA_FLUTE, 62, follow=1.0, center=72, bloom=False)
	curves[flute] += [(bar(O0 + 5) + 2, 58), (bar(END) - 0.5, 12)]

	# ---------------- violins ----------------
	mel(vln1, bar(A1), VLN_COUNTER, 62, transpose=-12, center=64, legato=1.0)
	mel(vln1, bar(B0), B_VLN, 100, legato=1.0)
	mel(vln1, bar(K0), BUILD_VLN, 58, center=73, follow=3.0, legato=1.0, bloom=False)
	mel(vln1, bar(A2), THEME, 112, transpose=2, legato=1.0)
	mel(vln2, bar(A2), THEME, 88, transpose=-10, center=66, legato=1.0)
	mel(vln1, bar(C0), DANCE_VLN, 70, legato=1.0)
	curves[vln1] += [(bar(A2) - 0.5, 112), (bar(C0 + 8) - 0.5, 40)]

	# ---------------- cello ----------------
	mel(cello, bar(A1), CELLO_A1, 74, center=57, legato=1.0)
	mel(cello, bar(R0), BRIDGE_CELLO, 52, center=57, follow=0.8, legato=1.0)
	mel(cello, bar(A2), CELLO_A, 66, center=59, transpose=2, legato=1.0)
	mel(cello, bar(O0), CODA_CELLO, 56, center=55, follow=0.6, legato=1.0, bloom=False)
	curves[cello] += [(bar(O0 + 5) + 2, 46), (bar(END) - 0.5, 10)]

	# ---------------- pad, bass, choir ----------------
	voices = [62, 66, 69, 74]
	for i, t, ln, name in chords_in(1, END - 1):
		voices = lead_voices(voices, name, 55, 76)
		if (R0 <= i < R0 + 4) or (C0 <= i < C0 + 4):
			continue
		for v in voices:
			pad.note(t, ln, v, 70)
		if i >= A1:
			b = bass_note(name, 36)
			bass.note(t, ln, b if b <= 47 else b - 12, 66 if i < A2 or i >= C0 else 78)
	pad.dyn([(bar(1), 18), (bar(A0), 44), (bar(A1), 54), (bar(B0), 62), (bar(B0 + 6), 80), (bar(R0), 30), (bar(R0 + 4), 26),
		(bar(K0), 44), (bar(A2) - 0.5, 104), (bar(A2), 82), (bar(C0), 60), (bar(C0 + 4), 40), (bar(C0 + 7), 84),
		(bar(O0), 56), (bar(END) - 0.5, 8)])
	cv = [66, 71, 74]
	for i, t, ln, name in chords_in(B0 + 4, 4):
		cv = lead_voices(cv, name, 64, 79)
		for v in cv:
			choir.note(t, ln, v, 70)
	for i, t, ln, name in chords_in(K0, 4 + 8):
		cv = lead_voices(cv, name, 64, 80)
		for v in cv:
			choir.note(t, ln, v, 76)
	for i, t, ln, name in chords_in(O0, 5):
		cv = lead_voices(cv, name, 64, 79)
		for v in cv:
			choir.note(t, ln, v, 66)
	choir.dyn([(bar(B0 + 4), 10), (bar(B0 + 7), 66), (bar(B0 + 8) - 0.5, 30), (bar(K0), 20), (bar(A2) - 0.5, 104),
		(bar(A2), 84), (bar(A2 + 4), 96), (bar(C0) - 0.5, 60), (bar(O0), 44), (bar(O0 + 3), 40), (bar(END) - 1, 0)])

	# ---------------- pizzicato (A' walking, C dancing) ----------------
	vv = [66, 69, 74]
	for i, t, ln, name in chords_in(A1, 8):
		pizz_lo.note(t, 2, bass_note(name, 43), 74)
		vv = lead_voices(vv, name, 64, 79)
		if ln == 6:
			pizz_hi.note(t + 3, 1, vv[0], 60)
			pizz_hi.note(t + 3, 1, vv[1], 56)
			pizz_hi.note(t + 5, 1, vv[2], 52)
	for i, t, ln, name in chords_in(C0, 8):
		vv = lead_voices(vv, name, 64, 80)
		for o in ([0, 3] if ln == 6 else [0]):
			pizz_lo.note(t + o, 1, bass_note(name, 43) + (7 if o == 3 else 0), 80 if o == 0 else 70)
			for k in (1, 2):
				pizz_hi.note(t + o + k, 1, vv[k % 2], 58 + (i - C0) * 2)
				pizz_hi.note(t + o + k, 1, vv[2], 52 + (i - C0) * 2)

	# ---------------- sparkle, timpani, cymbal ----------------
	celesta.line(bar(I0 + 2), "A6:1 F#6:1 E6:1 D6:1 A5:2 | r:3 E6:1 D6:1 C#6:1", vel=54)
	celesta.line(bar(A0 + 3), "r:3 A6:1 E6:1 C#6:1", vel=48)
	celesta.line(bar(R0 + 3), "r:2 B6:1 F#6:1 D6:1 B5:1", vel=46)
	celesta.line(bar(R0 + 7), "r:3 E6:1 C#6:1 A5:1", vel=46)
	celesta.line(bar(C0), "E6:1 r:2 B6:1 r:2 | A6:1 r:2 E6:1 r:2 | B6:1 r:2 G#6:1 r:2 | F#6:1 r:2 B6:1 r:2", vel=50)
	celesta.line(bar(O0 + 1), "r:2 A6:1 F#6:1 D6:1 A5:1", vel=44)
	celesta.line(bar(O0 + 3), "r:3 C7:1 A6:1 E6:1", vel=40)
	for k in range(36):
		timp.note(bar(K0 + 2) + 3 + k * 0.25, 0.25, "B1", 34 + k * 2)
	timp.note(bar(A2), 6, "E2", 100)
	timp.note(bar(A2 + 4), 4, "C#2", 80)
	timp.note(bar(A2 + 7), 4, "E2", 84)
	perc.note(bar(A2), 6, 49, 84)

	# ---------------- tempo: valley in the bridge, push through the build, breadth at the top ----------------
	s.tempo_ramp(bar(R0) - 4, bar(R0), 132, 108, 6)
	s.tempo_ramp(bar(K0), bar(K0 + 3), 112, 134, 8)
	s.tempo_ramp(bar(K0 + 3) + 3, bar(A2), 134, 112, 4)
	s.tempo(bar(A2), 126)
	s.tempo(bar(C0), 138)
	s.tempo_ramp(bar(O0) - 3, bar(O0), 138, 120, 4)
	s.tempo_ramp(bar(O0 + 2), bar(END), 120, 78, 14)

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
	return s


if __name__ == "__main__":
	here = os.path.dirname(os.path.abspath(__file__))
	out = os.path.join(here, "out")
	os.makedirs(out, exist_ok=True)
	s = compose()
	s.save(os.path.join(out, "main_theme_v2.mid"), dyn_cc=2)
	s.save(os.path.join(out, "main_theme_v2_daw.mid"), dyn_cc=1)
	wav, secs = render(os.path.join(out, "main_theme_v2.mid"), os.path.join(out, "main_theme_v2"), wet=0.3)
	print("rendered %.1f s -> %s" % (secs, wav))
