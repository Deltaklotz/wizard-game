"""Battle theme sketch: "Grimoires Drawn".

The main theme's head turned to D minor over a 6/8 gallop: spiccato strings, taiko + timpani, horns, flute
and piccolo flying on top, choir stabs. B = tension (violins soar, brass/choir stabs, whirling flutes),
C = the main theme itself in F major as a heroic turn, a drum build, the climax, a hard ending.
Run: python battle_theme.py -> out/battle_theme.{mid,wav,ogg,mp3} + out/battle_theme_daw.mid
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "lib"))
from score import Score, pitch
from harmony import chord, halves, bass_note, lead_voices, arch, scale_run
from render import render

BAR = 6
def bar(i):
	return i * BAR

D_MINOR = [2, 4, 5, 7, 9, 10, 0]
D_HARM = [2, 4, 5, 7, 9, 10, 1]  # over A: C#

INTRO = ["Dm", "Dm", "Bb", "A"]
SEC_A = ["Dm", "C", "Bb", "A", "Dm", "Bb", ("Gm", "A7"), "Dm"]
SEC_B = ["Gm", "Bb", "C", "A", "Gm", "Bb", "C", ("Asus4", "A")]
SEC_C = ["F", "Eb", "Bb", "F", "Dm", "Bb", ("Gm", "C7"), "A"]
BUILD = ["Dm", "Dm", "Bb", "A"]
ENDING = ["Bb", ("Gm", "A"), "Dm"]
FORM = INTRO + SEC_A + SEC_A + SEC_B + SEC_C + BUILD + SEC_A + ENDING
I0, A0, A1, B0, C0, K0, A2, E0 = 0, 4, 12, 20, 28, 36, 40, 48

THEME = ("D5:2 E5:1 F5:2 A5:1 | G5:3 E5:2 C5:1 | D5:2 Bb4:1 D5:2 F5:1 | E5:5 r:1 | "
	"A5:2 G5:1 F5:2 D5:1 | F5:2 G5:1 A5:2 Bb5:1 | Bb5:2 A5:1 G5:2 E5:1 | D5:3 r:1 A4:1 C5:1")
THEME2 = THEME.replace("E5:5 r:1", "E5:3 F5:1 E5:1 C#5:1")
B_VLN = ("Bb5:3 A5:2 G5:1 | F5:3 D6:3 | E6:2 D6:1 C6:2 G5:1 | A5:6 | "
	"Bb5:3 C6:2 D6:1 | F6:3 D6:3 | E6:2 D6:1 C6:2 E6:1 | D6:3 C#6:3")
# the main theme (D major) quoted in F major, last bar turned towards D minor
C_THEME = ("F5:2 G5:1 A5:2 C6:1 | Bb5:3 G5:2 Eb5:1 | F5:2 D5:1 F5:2 Bb5:1 | A5:5 r:1 | "
	"D6:2 C6:1 A5:2 F5:1 | Bb5:2 A5:1 G5:2 F5:1 | G5:2 A5:1 Bb5:2 G5:1 | A5:3 E5:2 C#5:1")


def chords_in(i0, n):
	for i in range(i0, i0 + n):
		for off, ln, name in halves(FORM[i]):
			yield i, bar(i) + off, ln, name


def compose():
	s = Score(bpm_quarter=156, seed=11, humanize=0.04)
	flute = s.track("Flute", 73, bank=17, channel=0, volume=100, pan=56)
	picc = s.track("Piccolo", 72, channel=1, volume=74, pan=52)
	vln = s.track("Violins I (legato)", 49, bank=21, channel=2, volume=104, pan=42)
	spic = s.track("Violins II (spiccato)", 48, bank=26, channel=3, volume=120, pan=76)
	low = s.track("Celli + violas (spiccato)", 48, bank=17, channel=4, volume=110, pan=84)
	cb = s.track("Contrabass", 43, channel=5, volume=92, pan=88)
	horns = s.track("Horns", 60, bank=17, channel=6, volume=104, pan=36)
	brass = s.track("Brass stabs", 61, bank=17, channel=7, volume=84, pan=60)
	tpt = s.track("Trumpet", 56, bank=17, channel=8, volume=90, pan=54)
	drums = s.track("Orchestral percussion", 48, channel=9, volume=110, pan=64)
	choir = s.track("Choir", 52, bank=17, channel=10, volume=96, pan=64)
	timp = s.track("Timpani", 47, channel=11, volume=110, pan=70)
	taiko = s.track("Taiko", 116, channel=12, volume=112, pan=58)
	tbn = s.track("Trombones", 57, bank=17, channel=13, volume=70, pan=74)
	trem = s.track("Violins tremolo", 44, bank=21, channel=14, volume=108, pan=50)
	harp = s.track("Harp", 46, channel=15, volume=90, pan=30)
	BD, SN, CRASH, CRASH2 = 36, 38, 49, 57

	# ---------------- intro: tremolo + taiko, horn call, choir swell ----------------
	trem.note(0, bar(4), "D4", 80)
	trem.note(0, bar(4), "A4", 80)
	trem.dyn([(0, 10), (bar(4) - 0.5, 100)])
	for i in range(4):
		taiko.note(bar(i), 3, "D2", 112)
		taiko.note(bar(i) + 3, 3, "D2", 96)
		if i >= 2:
			for k in range(6):
				taiko.note(bar(i) + 3 + k * 0.5, 0.5, "A2", 60 + k * 9 + (i - 2) * 8)
	timp.note(0, 2, "D2", 100)
	for k in range(24):  # timpani roll into A
		timp.note(bar(3) + k * 0.25, 0.25, "A1", 40 + k * 3)
	horns.line(bar(1), "D4:2 E4:1 F4:2 A4:1 | G4:3 E4:3 | E4:6", vel=96)
	horns.dyn([(bar(1), 70), (bar(2), 100), (bar(3), 80), (bar(4) - 0.5, 110)])
	cv = [62, 65, 69]
	for i, t, ln, name in chords_in(I0, 4):
		cv = lead_voices(cv, name, 60, 76)
		for v in cv:
			choir.note(t, ln, v, 80)
	choir.dyn([(0, 0), (bar(2), 60), (bar(4) - 0.5, 100)])
	flute.line(bar(3) + 2, "r:1 " + " ".join("%s:0.5" % p for p in ["D5", "E5", "F5", "G5", "A5", "Bb5", "C#6", "D6"]), vel=90)

	# ---------------- driving layers for A, A', B, build, A'' ----------------
	drive = [(A0, 8), (A1, 8), (B0, 8), (K0, 4), (A2, 8), (E0, 2)]
	vv = [62, 65, 69]
	for s0, n in drive:
		for i, t, ln, name in chords_in(s0, n):
			r = bass_note(name, 38)
			# low strings: 6/8 gallop, octave kick on the 6th eighth
			pat = [(0, 2, 0, 112), (2, 1, 0, 84), (3, 2, 0, 104), (5, 1, 12, 92)] if ln == 6 else [(0, 2, 0, 110), (2, 1, 12, 90)]
			for o, d, up, v in pat:
				low.note(t + o, d, r + up, v, legato=0.7)
			cb.note(t, min(ln, 3), r - 12 if r - 12 >= 28 else r, 100, legato=0.9)
			if ln == 6:
				cb.note(t + 3, 3, r - 12 if r - 12 >= 28 else r, 88, legato=0.9)
			# upper strings: spiccato chord-tone figure
			vv = lead_voices(vv, name, 62, 77)
			fig = [vv[0], vv[1], vv[2], vv[1], vv[2], vv[0] + 12 if vv[0] + 12 <= 81 else vv[2]]
			for k in range(int(ln)):
				spic.note(t + k, 1, fig[k], 100 if k % 3 == 0 else 74, legato=0.55)
	low.dyn([(bar(A0), 92), (bar(B0), 100), (bar(C0), 70), (bar(K0), 60), (bar(A2) - 0.5, 118), (bar(E0), 120)])
	spic.dyn([(bar(A0), 80), (bar(A1), 90), (bar(B0), 100), (bar(C0), 60), (bar(K0), 50), (bar(A2) - 0.5, 115),
		(bar(A2), 104)])

	# percussion grooves
	def groove(i, intensity):
		t = bar(i)
		drums.note(t, 1, BD, 104 + intensity * 6)
		drums.note(t + 3, 1, BD, 90 + intensity * 6)
		drums.note(t + 3, 1, SN, 70 + intensity * 10)
		for k in (1, 2, 4, 5):
			drums.note(t + k, 0.5, SN, 30 + intensity * 6)
		taiko.note(t, 2, "D2", 110)
		taiko.note(t + 2, 1, "A2", 66 + intensity * 8)
		taiko.note(t + 3, 2, "D2", 100)
		taiko.note(t + 5, 1, "A2", 74 + intensity * 8)
		if intensity >= 2:
			taiko.note(t + 1, 1, "A2", 60)
			taiko.note(t + 4, 1, "A2", 64)
		if i % 4 == 3:  # fill
			for k in range(4):
				taiko.note(t + 4 + k * 0.5, 0.5, "A2", 80 + k * 10)
	for s0, n, inten in [(A0, 8, 0), (A1, 8, 1), (B0, 8, 2), (A2, 8, 2)]:
		drums.note(bar(s0), 4, CRASH, 110)
		for i in range(s0, s0 + n):
			groove(i, inten)
		drums.note(bar(s0 + 4), 3, CRASH2, 92)
	for s0, n in [(A0, 8), (A1, 8), (B0, 8), (A2, 8)]:
		for i, t, ln, name in chords_in(s0, n):
			timp.note(t, 2, bass_note(name, 33) if bass_note(name, 33) <= 45 else bass_note(name, 33) - 12, 108)

	# ---------------- A: horns state the theme, flute runs + trills ----------------
	horns.line(bar(A0), THEME, vel=104, transpose=-12, contour=0.3)
	horns.dyn(arch(bar(A0), 24, 90, 118) + arch(bar(A0 + 4), 24, 96, 122))
	for b in (A0 + 3, A0 + 7):
		run = scale_run(pitch("A5"), pitch("D6") + 12, D_HARM)
		flute.line(bar(b) + 3, " ".join("%d:0.5" % p for p in run[:6]), vel=86)
	flute.line(bar(A0) , "r:24 " + " ".join(["A6:0.5", "Bb6:0.5"] * 6) + " | r:6 " + " ".join(["F6:0.5", "G6:0.5"] * 6), vel=70)
	flute.dyn([(bar(A0), 80), (bar(A1) - 0.5, 96)])

	# ---------------- A': violins + flute on the theme, horn counter, choir ----------------
	vln.line(bar(A1), THEME2, vel=96, contour=0.4)
	vln.dyn(arch(bar(A1), 24, 84, 110) + arch(bar(A1 + 4), 24, 92, 118))
	flute.line(bar(A1), THEME2, vel=92, transpose=12, legato=0.95)
	flute.dyn(arch(bar(A1), 24, 82, 104) + arch(bar(A1 + 4), 24, 88, 110))
	hv = [53, 57]
	for i, t, ln, name in chords_in(A1, 8):
		hv = lead_voices(hv, name, 50, 64)
		for v in hv:
			horns.note(t, ln, v, 90)
	horns.dyn([(bar(A1), 70), (bar(A1 + 7), 92)])
	cv = [65, 69, 74]
	for i, t, ln, name in chords_in(A1, 8):
		cv = lead_voices(cv, name, 62, 77)
		for v in cv:
			choir.note(t, ln, v, 82)
	choir.dyn(arch(bar(A1), 24, 50, 86) + arch(bar(A1 + 4), 24, 60, 96))

	# ---------------- B: tension. violins soar, stabs, whirling flutes ----------------
	vln.line(bar(B0), B_VLN, vel=100, contour=0.3)
	vln.dyn(arch(bar(B0), 24, 92, 118, 0.7) + arch(bar(B0 + 4), 24, 100, 124, 0.7))
	bv, cv, tv = [55, 58, 62, 65], [67, 70, 74], [43, 50]
	for i, t, ln, name in chords_in(B0, 8):
		bv = lead_voices(bv, name, 50, 67)
		cv = lead_voices(cv, name, 64, 79)
		hits = [0, 3] if ln == 6 else [0]
		if ln == 6 and i % 2 == 1:
			hits = [0, 2, 3, 5]
		for h in hits:
			for v in bv:
				brass.note(t + h, 1, v, 110 if h in (0, 3) else 92, legato=0.8)
			for v in cv:
				choir.note(t + h, 1.4, v, 100)
		tv = lead_voices(tv, name, 38, 55)
		for v in tv:
			tbn.note(t, ln, v, 96)
		# whirling flute + piccolo: chord tones up and down in sixteenths
		root, iv, tones = chord(name)
		ups = [p for p in range(pitch("D5"), pitch("D7")) if p % 12 in tones]
		wh = ups[:6] + ups[6:0:-1]
		for k in range(int(ln * 2)):
			p = wh[k % len(wh)]
			flute.note(t + k * 0.5, 0.5, p, 80 + (12 if k % 6 == 0 else 0), legato=0.9)
			if p + 12 <= pitch("C8"):
				picc.note(t + k * 0.5, 0.5, p + 12 if p < pitch("G6") else p, 64, legato=0.9)
	brass.dyn([(bar(B0), 100), (bar(C0) - 0.5, 120)])
	choir.dyn([(bar(B0), 92), (bar(C0) - 0.5, 118)])
	tbn.dyn([(bar(B0), 70), (bar(C0) - 0.5, 110)])
	flute.dyn([(bar(B0), 76), (bar(C0) - 0.5, 104)])

	# ---------------- C: the main theme, heroic, in F major (half-time feel) ----------------
	tpt.line(bar(C0), C_THEME, vel=100, contour=0.2)
	tpt.dyn(arch(bar(C0), 24, 86, 112) + arch(bar(C0 + 4), 24, 92, 120))
	horns.line(bar(C0), C_THEME, vel=100, transpose=-12)
	horns.dyn(arch(bar(C0), 48, 92, 118))
	vln.line(bar(C0), C_THEME, vel=96, transpose=0)
	vln.dyn(arch(bar(C0), 48, 86, 116))
	cv, tv = [65, 69, 72], [41, 48, 53]
	for i, t, ln, name in chords_in(C0, 8):
		cv = lead_voices(cv, name, 62, 79)
		tv = lead_voices(tv, name, 36, 57)
		for v in cv:
			choir.note(t, ln, v, 90)
		for v in tv:
			tbn.note(t, ln, v, 90)
		r = bass_note(name, 38)
		low.note(t, ln, r, 100)
		cb.note(t, ln, r - 12 if r - 12 >= 28 else r, 100)
		trem.note(t, ln, cv[-1] + 12, 70)
		# harp sweeps
		root, iv, tones = chord(name)
		ups = [p for p in range(pitch("F3"), pitch("C7")) if p % 12 in tones]
		for k in range(min(len(ups), int(ln * 2))):
			harp.note(t + k * 0.5 * (6 / ln) * (ln / 6), 2, ups[k * len(ups) // int(ln * 2)], 74)
		timp.note(t, 3, bass_note(name, 33) if bass_note(name, 33) <= 45 else bass_note(name, 33) - 12, 100)
		if ln == 6:
			drums.note(t, 1, BD, 110)
			taiko.note(t, 3, "D2", 112)
			taiko.note(t + 3, 2, "A2", 84)
	drums.note(bar(C0), 6, CRASH, 112)
	drums.note(bar(C0 + 4), 6, CRASH2, 104)
	choir.dyn(arch(bar(C0), 48, 86, 120))
	trem.dyn([(bar(C0), 60), (bar(C0 + 8) - 0.5, 90), (bar(K0), 30), (bar(A2) - 0.5, 120)])
	tbn.dyn([(bar(C0), 80), (bar(C0 + 6), 104), (bar(C0 + 8) - 0.5, 90)])
	flute.line(bar(C0), "r:6 " + " ".join(["C7:0.5", "Bb6:0.5"] * 6) + " r:12 " + " ".join(["F6:0.5", "G6:0.5"] * 6)
		+ " r:6 " + " ".join(["A6:0.5", "Bb6:0.5"] * 6), vel=66)
	flute.dyn([(bar(C0), 70), (bar(K0) - 0.5, 84)])

	# ---------------- build: drums + ostinato + rising tremolo and choir ----------------
	for k in range(48):  # snare roll
		drums.note(bar(K0) + k * 0.5, 0.5, SN, 34 + k * 1.8)
	for i in range(K0, K0 + 4):
		taiko.note(bar(i), 2, "D2", 96 + (i - K0) * 8)
		taiko.note(bar(i) + 3, 2, "D2", 90 + (i - K0) * 8)
	for k in range(24):
		timp.note(bar(K0 + 2) + k * 0.5, 0.5, "A1", 50 + k * 3)
	for i, t, ln, name in chords_in(K0, 4):
		trem.note(t, ln, pitch("A4") + (i - K0) * 2, 80)
		trem.note(t, ln, pitch("D5") + (i - K0) * 2 + (1 if i == K0 + 3 else 0), 80)
	cv = [62, 65, 69]
	for i, t, ln, name in chords_in(K0, 4):
		cv = lead_voices([v + 2 for v in cv], name, 60, 79)
		for v in cv:
			choir.note(t, ln, v, 90)
	choir.dyn([(bar(K0), 40), (bar(A2) - 0.5, 122)])
	horns.line(bar(K0 + 2), "D4:2 E4:1 F4:2 A4:1 | G4:2 A4:1 Bb4:2 C#5:1", vel=104)
	horns.dyn([(bar(K0 + 2), 90), (bar(A2) - 0.5, 124)])
	flute.line(bar(K0 + 3) + 2, "r:1 " + " ".join("%s:0.5" % p for p in ["D6", "E6", "F6", "G6", "A6", "Bb6", "C#7", "D7"]), vel=92)

	# ---------------- A'': everything ----------------
	vln.line(bar(A2), THEME2, vel=104, contour=0.3)
	vln.dyn(arch(bar(A2), 24, 104, 124) + arch(bar(A2 + 4), 24, 108, 127))
	flute.line(bar(A2), THEME2, vel=100, transpose=12)
	flute.dyn(arch(bar(A2), 24, 96, 116) + arch(bar(A2 + 4), 24, 100, 124))
	picc.line(bar(A2 + 4), THEME2.split("| ", 4)[4], vel=70, transpose=12)
	horns.line(bar(A2), THEME2, vel=110, transpose=-12)
	horns.dyn([(bar(A2), 118), (bar(E0), 126)])
	tpt.line(bar(A2 + 4), THEME2.split("| ", 4)[4], vel=104)
	tpt.dyn([(bar(A2 + 4), 100), (bar(E0), 120)])
	cv, tv, bv = [65, 69, 74], [38, 45, 50], [57, 62, 65]
	for i, t, ln, name in chords_in(A2, 8):
		cv = lead_voices(cv, name, 62, 79)
		tv = lead_voices(tv, name, 36, 55)
		bv = lead_voices(bv, name, 53, 67)
		for v in cv:
			choir.note(t, ln, v, 96)
		for v in tv:
			tbn.note(t, ln, v, 100)
		for v in bv:
			brass.note(t, 1, v, 104, legato=0.8)
			if ln == 6:
				brass.note(t + 3, 1, v, 96, legato=0.8)
	choir.dyn(arch(bar(A2), 48, 100, 124))
	tbn.dyn([(bar(A2), 96), (bar(E0), 116)])
	brass.dyn([(bar(A2), 100), (bar(E0), 120)])

	# ---------------- ending: two hits, then the last chord ----------------
	e = bar(E0)
	vln.line(e, "D6:2 F6:1 D6:2 Bb5:1 | Bb5:2 A5:1 A5:2 C#6:1", vel=110)
	flute.line(e, "D6:2 F6:1 D6:2 Bb5:1 | Bb5:2 A5:1 A5:2 C#6:1", vel=104, transpose=12)
	horns.line(e, "F4:3 D4:3 | D4:3 E4:3", vel=114)
	cv = [65, 70, 74]
	for i, t, ln, name in chords_in(E0, 2):
		cv = lead_voices(cv, name, 62, 79)
		for v in cv:
			choir.note(t, ln, v, 104)
		for v in lead_voices([50, 57, 62], name, 45, 67):
			brass.note(t, 1, v, 112, legato=0.8)
			brass.note(t + ln - 1, 1, v, 104, legato=0.8)
	for k in range(24):  # timpani roll into the last chord
		timp.note(e + 6 + k * 0.25, 0.25, "A1", 60 + k * 2.5)
	drums.note(e, 4, CRASH, 112)
	for k in range(12):
		drums.note(e + 6 + k * 0.5, 0.5, SN, 50 + k * 6)
	# final D minor chord, everyone
	f = bar(E0 + 2)
	FINAL = {vln: ["D5", "A5", "D6"], flute: ["D6"], picc: ["A6"], horns: ["D4", "F4", "A4"], tpt: ["D5"],
		brass: ["D3", "A3", "D4", "F4"], tbn: ["D2", "A2", "D3"], choir: ["D4", "F4", "A4", "D5"],
		low: ["D2", "D3"], cb: ["D2"], trem: ["F5", "A5"]}
	for tr, ps in FINAL.items():
		for p in ps:
			tr.note(f, 9, p, 116, legato=1.0)
		tr.dyn([(f, 120), (f + 6, 110), (f + 8.5, 0)])
	drums.note(f, 9, CRASH, 124)
	drums.note(f, 9, CRASH2, 116)
	drums.note(f, 3, BD, 127)
	taiko.note(f, 6, "D2", 127)
	timp.note(f, 9, "D2", 127)
	harp.line(f, " ".join("%s:0.25" % p for p in ["D3", "A3", "D4", "F4", "A4", "D5", "F5", "A5", "D6", "F6", "A6", "D7"]), vel=90)
	s.tempo_ramp(f - 6, f, 156, 140, 6)
	s.tempo(f, 120)
	return s


if __name__ == "__main__":
	here = os.path.dirname(os.path.abspath(__file__))
	out = os.path.join(here, "out")
	os.makedirs(out, exist_ok=True)
	s = compose()
	s.save(os.path.join(out, "battle_theme_orchestral.mid"), dyn_cc=2)
	s.save(os.path.join(out, "battle_theme_orchestral_daw.mid"), dyn_cc=1)
	wav, secs = render(os.path.join(out, "battle_theme_orchestral.mid"), os.path.join(out, "battle_theme_orchestral"), wet=0.24)
	print("rendered %.1f s -> %s" % (secs, wav))
