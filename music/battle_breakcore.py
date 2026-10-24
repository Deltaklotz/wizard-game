"""Battle theme, breakcore: "Overcast" - 180 BPM, 4/4, F# minor. New material, nothing medieval.

Chopped breakbeats (a drum break rendered from the SoundFont at 136 BPM, sped up to 180 so it pitches up like
a sampled break, sliced into sixteenths and resequenced with retriggers / reverses / pitch jumps / gaps) +
synthesized kick & snare for weight, reese bass, supersaw pad, pluck arp, saw lead - all numpy (lib/synth.py).
A flute carries the breakdown and doubles the lead in the last drop (the game's voice).
Form (bars): intro 0-7, drop A 8-23, B half-time 24-31, breakdown 32-39, drop C 40-55, outro 56-59.
Run: python battle_breakcore.py -> out/battle_breakcore.{wav,ogg,mp3} + out/battle_breakcore_daw.mid (melodic parts)
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "lib"))
from score import Score
import synth as sy
from synth import SR, Bus
from render import fluid_dry, encode, hall_ir

BPM = 180
E8 = 60 / BPM / 2  # one eighth in seconds
SLOT = 4000  # one sixteenth in samples (exact at 180 BPM / 48 kHz)
BAR_S = 16 * SLOT / SR
BARS = 60
INTRO, DROP_A, SEC_B, BREAK, DROP_C, OUTRO = 0, 8, 24, 32, 40, 56
SRC_BPM = 136

def tb(b, e=0.0):
	"""Seconds at bar b + e eighths."""
	return b * BAR_S + e * E8

# ---------------- harmony ----------------
CH = {"D": (50, 4), "E": (52, 4), "F#m": (54, 3), "C#m": (49, 3), "Bm": (47, 3), "A": (45, 4), "C#": (49, 4)}
LOOP = ["D", "E", "F#m", "C#m"]
FORM = LOOP * 2 + LOOP * 4 + ["Bm", "C#m", "D", "E"] * 2 + ["D", "A", "Bm", "C#"] * 2 + LOOP * 4 + ["D", "E", "F#m", "F#m"]
assert len(FORM) == BARS

# ---------------- melodies (eighths, 8 per bar) ----------------
P1 = ("F#5:3 A5:3 C#6:2 | B5:3 G#5:3 E5:2 | F#5:2 A5:1 C#6:3 B5:1 A5:1 | G#5:4 E5:2 G#5:2 | "
	"A5:3 C#6:3 F#6:2 | E6:3 B5:3 G#5:2 | A5:2 C#6:1 F#6:3 E6:1 C#6:1 | C#6:4 r:1 C#5:1 E5:1 G#5:1")
P2 = ("F#6:3 E6:3 D6:2 | E6:2 B5:1 G#5:2 B5:1 E6:2 | C#6:1 F#6:2 A6:3 G#6:1 F#6:1 | E6:4 G#6:2 E6:2 | "
	"F#6:3 A6:3 F#6:2 | G#6:3 B6:3 G#6:2 | A6:2 G#6:1 F#6:2 E6:1 C#6:2 | C#6:6 r:2")
RIFF = ("B5:1 r:1 B5:1 D6:1 r:1 F#6:1 r:2 | C#6:1 r:1 C#6:1 E6:1 r:1 G#6:1 r:2 | D6:1 r:1 D6:1 F#6:1 r:1 A6:2 F#6:1 | "
	"G#6:3 E6:3 B5:2 | B5:1 r:1 B5:1 D6:1 r:1 F#6:1 r:2 | C#6:1 r:1 C#6:1 E6:1 r:1 G#6:1 r:2 | "
	"D6:1 F#6:1 A6:1 D6:1 F#6:1 A6:1 F#6:1 A6:1 | B6:4 G#6:2 E6:2")
CALM = ("F#5:4 A5:2 C#6:2 | E6:6 C#6:2 | D6:4 B5:2 F#5:2 | G#5:6 r:2 | F#5:4 A5:2 C#6:2 | E6:4 A6:4 | "
	"F#6:4 D6:2 B5:2 | C#6:8")
LAST = "F#6:8 | E6:8 | C#6:8 | F#5:8"

# ---------------- break source + chopping ----------------
T = {
	0: list(range(16)),
	1: list(range(16, 32)),
	2: [0, 1, 2, 3, 4, 5, 2, 3, 4, 5, 10, 11, 12, 13, 4, 5],
	3: [0, 1, 4, 5, 4, 5, 2, 3, 10, 11, 10, 11, 12, 13, 14, 15],
	4: [10, 11, 4, 5, 0, 1, 4, 5, 10, 11, 12, 13, 4, 4, 4, 4],
	5: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 12, 12, 12],
	6: [16, 17, 18, 19, 20, 21, 18, 19, 26, 27, 20, 21, 28, 29, 30, 31],
}


def break_source():
	"""Two bars in the Amen mould, played by the SoundFont's room kit, squashed and sped up."""
	s = Score(bpm_quarter=SRC_BPM, humanize=0.0)
	s.time_sig = (4, 4)
	k = s.track("break", 8, channel=9, volume=127)
	K, S, HH, RIDE, CRASH, OH = 36, 38, 42, 51, 49, 46
	def hit(bar_, step, note, vel, late=0.0):
		k.note(bar_ * 8 + step * 0.5 + late, 0.5, note, vel)
	for b, (kicks, snares) in enumerate([
			([(0, 120), (2, 104), (10, 116), (11, 98)], [(4, 124), (7, 60), (9, 68), (12, 124), (15, 72)]),
			([(0, 120), (2, 104), (10, 116)], [(4, 124), (7, 62), (9, 70), (14, 122), (15, 66)])]):
		for st, v in kicks:
			hit(b, st, K, v)
		for st, v in snares:
			hit(b, st, S, v, 0.03 if v < 80 else 0.0)
		for st in range(0, 16, 2):
			hit(b, st, RIDE, 92 if st % 4 == 0 else 74)
			hit(b, st, HH, 70 if st % 4 == 0 else 54)
	hit(1, 10, CRASH, 100)
	hit(1, 6, OH, 70)
	tmp = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out", "_break.mid")
	s.save(tmp)
	raw = fluid_dry(tmp, gain=0.8).mean(1)
	os.remove(tmp)
	n_src = int(round(32 * SR * 60 / SRC_BPM / 4))
	raw = raw[: n_src + SR // 4]
	# glue it like a record: a little room, hard compression, saturation
	rng = np.random.default_rng(5)
	t = np.arange(int(0.22 * SR)) / SR
	room = rng.standard_normal(len(t)) * np.exp(-t / 0.05)
	raw = raw + sy.fftconvolve(raw, room)[: len(raw)] * 0.012
	raw = raw / np.abs(raw).max()
	raw = np.tanh(raw * 3.2)
	raw = sy.hp(raw, 45)
	fast = sy.fit_break(raw, SRC_BPM, BPM, SLOT)
	return fast[: 32 * SLOT] / np.abs(fast).max()


def st(i, retrig=1, pitch=0, rev=False, g=1.0):
	return (i, retrig, pitch, rev, g)


def mutate(steps, inten, rng, beats=(0, 1, 2, 3)):
	steps = list(steps)
	for beat in beats:
		if rng.random() > inten:
			continue
		k = beat * 4
		c = int(rng.integers(0, 6))
		if c == 0:  # snare burst
			n = int(rng.choice([2, 2, 3, 4]))
			steps[k + 2] = st(4, n)
			steps[k + 3] = st(4, 4, 2)
		elif c == 1:  # stutter the beat's first slice
			i = steps[k][0] if steps[k] else 0
			for j in range(4):
				steps[k + j] = st(i, 1, 0, False, 1.0 - j * 0.05)
		elif c == 2:  # reverse one slice
			j = k + int(rng.integers(0, 4))
			if steps[j]:
				steps[j] = st(steps[j][0], 1, 0, True)
		elif c == 3:  # octave-up tail
			for j in (k + 2, k + 3):
				if steps[j]:
					steps[j] = st(steps[j][0], steps[j][1], 12, False, 0.9)
		elif c == 4:  # choke
			steps[k + 3] = None
		else:  # kick roll
			steps[k] = st(0, 2)
			steps[k + 1] = st(0, 2, -2)
	return steps


def fill(steps, kind):
	steps = list(steps)
	if kind == 0:
		steps[12:16] = [st(4), st(4, 2), st(4, 2, 2), st(4, 4, 4)]
	elif kind == 1:
		steps[12:16] = [st(12, 2), st(12, 2, 3), st(12, 4, 5), st(12, 4, 8)]
	else:  # two beats, accelerating and rising
		steps[8:16] = [st(4), st(4), st(4, 2), st(4, 2, 1), st(4, 2, 2), st(4, 4, 4), st(4, 4, 6), st(4, 8, 9)]
	return steps


def break_sequence(rng):
	seq = [None] * BARS
	plain = lambda t, g=1.0: [st(i, 1, 0, False, g) for i in T[t]]
	for b, t in zip(range(0, 8), [0, 0, 1, 0, 0, 2, 1, 0]):
		seq[b] = plain(t)
	seq[7] = fill(seq[7], 2)
	seq[7][14] = seq[7][15] = None
	cyc_a = [0, 2, 1, 3, 0, 2, 6, 4]
	for b in range(DROP_A, SEC_B):
		r = b - DROP_A
		seq[b] = mutate(plain(cyc_a[r % 8]), 0.18 if r < 8 else 0.34, rng)
		if r % 4 == 3:
			seq[b] = fill(seq[b], 2 if b == SEC_B - 1 else (r // 4) % 2)
	for b in range(SEC_B, BREAK):  # half-time: thinner break, frantic second halves on odd bars
		r = b - SEC_B
		seq[b] = mutate(plain(0 if r % 2 == 0 else 6, 0.62), 0.2, rng, beats=(0, 1))
		seq[b] = mutate(seq[b], 0.95 if r % 2 else 0.3, rng, beats=(2, 3))
	seq[BREAK - 1] = fill(seq[BREAK - 1], 2)
	seq[38] = plain(0, 0.5)
	seq[39] = plain(1, 0.75)
	seq[39][14] = seq[39][15] = None
	cyc_c = [0, 3, 2, 4, 1, 2, 6, 5]
	for b in range(DROP_C, OUTRO):
		r = b - DROP_C
		seq[b] = mutate(plain(cyc_c[r % 8]), 0.42 if r < 8 else 0.58, rng)
		if r % 4 == 3:
			seq[b] = fill(seq[b], 2 if b == OUTRO - 1 else 1 - (r // 4) % 2)
		if r % 2 == 1 and r % 4 != 3:
			seq[b] = fill(seq[b], (r // 2) % 2)
	for b, t in zip(range(OUTRO, OUTRO + 3), [0, 2, 0]):
		seq[b] = plain(t)
	return seq


def compose():
	rng = np.random.default_rng(42)
	total = tb(BARS) + 3.0
	ir = hall_ir(seconds=1.6, predelay=0.012, seed=9)
	n = int(total * SR)

	# MIDI of the melodic parts (flute rendering + DAW export)
	sc = Score(bpm_quarter=BPM, humanize=0.0)
	sc.time_sig = (4, 4)
	m_lead = sc.track("Lead", 81, channel=0)
	m_arp = sc.track("Arp", 8, channel=1)
	m_pad = sc.track("Pad", 89, channel=2)
	m_bass = sc.track("Bass", 38, channel=3)
	m_flute = sc.track("Flute", 73, bank=17, channel=4)
	fl = Score(bpm_quarter=BPM, humanize=0.01)
	f_only = fl.track("Flute", 73, bank=17, channel=0, volume=120)

	# ---------------- drums: chopped break ----------------
	src = break_source()
	seq = break_sequence(rng)
	brk = sy.chop(seq, src, SLOT)[:n]
	brk = np.pad(brk, (0, n - len(brk)))
	def region(b0, b1):
		return slice(int(b0 * 16 * SLOT), int(b1 * 16 * SLOT))
	r = region(0, 8)  # intro: filter opening
	x = np.linspace(0, 1, r.stop - r.start) ** 2.5
	brk[r] = (sy.lp(brk[r], 420) * (1 - x) + brk[r] * x) * (0.35 + 0.5 * x)
	r = region(SEC_B, BREAK)
	brk[r] = sy.hp(brk[r], 260)
	r = region(38, 40)  # build out of the breakdown
	x = np.linspace(0, 1, r.stop - r.start)
	brk[r] = sy.hp(brk[r], 900) * (0.4 + 0.6 * x)
	r = region(OUTRO, OUTRO + 3)  # outro: closing down, crushed
	x = np.linspace(0, 1, r.stop - r.start)
	seg = brk[r]
	seg = seg * (1 - x) + sy.lp(sy.crush(seg, 6, 5), 900) * x
	brk[r] = seg * (1 - 0.5 * x)
	breaks = Bus(total)
	breaks.add(0, np.tanh(brk * 1.6))
	breaks.b = sy.reverb(breaks.b, ir[: SR // 2], 0.10)

	# ---------------- drums: synthesized kick + snare underneath ----------------
	drums = Bus(total)
	kick_times = []
	K = sy.kick()
	def kk(b, step, g=1.0):
		t = b * BAR_S + step * SLOT / SR
		drums.add(t, K, g)
		kick_times.append(t)
	def sn(b, step, g=1.0, pitch=0.0, length=0.16):
		drums.add(b * BAR_S + step * SLOT / SR, sy.snare(rng, pitch, length), g)
	for b in range(4, 8):  # intro, half-time
		kk(b, 0, 0.8)
		if b < 7:
			sn(b, 8, 0.7)
	def roll(b, gap=True):
		hits = [0, 2, 4, 6, 8, 9, 10, 11] + [12 + k * 0.5 for k in range(4 if gap else 8)]
		for i, s_ in enumerate(hits):
			sn(b, s_, 0.45 + 0.5 * i / len(hits), pitch=i * 0.45, length=0.09)
	for s_ in [8, 9, 10, 11, 12, 12.5, 13, 13.5]:
		sn(7, s_, 0.5 + (s_ - 8) * 0.07, pitch=(s_ - 8) * 0.8, length=0.08)
	for b in list(range(DROP_A, SEC_B)) + list(range(DROP_C, OUTRO)) + [OUTRO, OUTRO + 1, OUTRO + 2]:
		rr = b % 4
		for s_ in ([0, 3, 10] if rr == 1 else [0, 10, 11] if rr == 3 else [0, 10]):
			kk(b, s_, 1.0 if s_ in (0, 10) else 0.8)
		if b >= DROP_C + 8 and b < OUTRO:
			kk(b, 6, 0.75)
		sn(b, 4)
		sn(b, 12)
	for b in range(SEC_B, BREAK):  # half-time weight
		kk(b, 0, 1.1)
		kk(b, 6 if b % 2 else 3, 0.8)
		kk(b, 10, 0.7)
		sn(b, 8, 1.25, pitch=-3, length=0.26)
	roll(39)
	drums.b = np.tanh(drums.b * 1.3)

	# ---------------- bass ----------------
	bass = Bus(total)
	PA = [(0, 3, 0), (3, 3, 0), (6, 2, 0)]
	PA_END = [(0, 3, 0), (3, 1, 0), (5, 1, 12), (6, 1, 0), (7, 1, 7)]
	PB = [(0, 1, 0), (1, 0.5, 0), (1.5, 0.5, 0), (3, 0.5, 12), (3.5, 0.5, 0), (4, 1, 0), (5.5, 0.5, 0), (6, 1, 7), (7, 1, 0)]
	PC = [(0, 1.5, 0), (1.5, 1.5, 0), (3, 1.5, 0), (4.5, 1.5, 0), (6, 1, 12), (7, 1, 0)]
	LONG = [(0, 8, 0)]
	for b in range(4, BARS):
		root = CH[FORM[b]][0] - 12
		kw, g = dict(drive=3.0, cutoff=700.0), 1.0
		if b < DROP_A:
			pat, kw, g = LONG, dict(drive=1.6, cutoff=260.0), 0.6
		elif b < SEC_B:
			pat = PA_END if b % 4 == 3 else PA
		elif b < BREAK:
			pat, kw, g = PB, dict(drive=4.5, cutoff=420.0, wobble_hz=6.0), 1.1
		elif b < DROP_C:
			pat, kw, g = LONG, dict(drive=1.4, cutoff=220.0), 0.5 + 0.06 * (b - BREAK)
		elif b < OUTRO:
			pat = PA_END if b % 4 == 3 else (PC if b % 2 else PA)
			kw = dict(drive=3.6, cutoff=900.0)
		else:
			pat, kw, g = LONG, dict(drive=2.0, cutoff=400.0 - 80 * (b - OUTRO)), 0.8
		for off, d, semi in pat:
			bass.add(tb(b, off), sy.reese(root + semi, d * E8 * 0.96, **kw), g)
			m_bass.note(b * 8 + off, d, root + semi, 100)

	# ---------------- pad + arp ----------------
	pad, arp = Bus(total), Bus(total)
	ARP_PAT = [0, 1, 2, 3, 4, 3, 2, 1, 0, 1, 2, 3, 4, 3, 2, 4]
	for b in range(BARS):
		root, third = CH[FORM[b]]
		g = 0.8 if b < DROP_A else 0.7 if b < SEC_B else 0.5 if b < BREAK else 0.75 if b < DROP_C else 0.75 if b < OUTRO else 0.9
		dur = BAR_S * (2.0 if b == BARS - 1 else 1.0)
		for p in [root, root + 7, root + 12 + third, root + 14, root + 19]:
			pad.add(tb(b), sy.supersaw(p, dur, rng), g)
			m_pad.note(b * 8, 8, p, 70)
		tones = [root + 12, root + 19, root + 26, root + 24 + third, root + 31]
		if 2 <= b < DROP_A or DROP_A <= b < SEC_B or BREAK <= b < OUTRO + 2:
			up = 12 if b >= DROP_C else 0
			ag = min(1.0, (b - 1) / 5) if b < DROP_A else 1.0
			for k, idx in enumerate(ARP_PAT):
				p = tones[idx] + up + (12 if (b >= DROP_C and k % 4 == 3) else 0)
				arp.add(tb(b) + k * SLOT / SR, sy.pluck(p), ag * (1.0 if k % 4 == 0 else 0.72), pan=0.5 if k % 2 else -0.5)
				m_arp.note(b * 8 + k * 0.5, 0.5, p, 80)
	x = np.linspace(0, 1, int(tb(8) * SR)) ** 2  # intro: pad opens up
	pad.b[: len(x)] = sy.lp(pad.b[: len(x)], 500) * (1 - x)[:, None] + sy.lp(pad.b[: len(x)], 3200) * x[:, None]
	pad.b[len(x) :] = sy.lp(pad.b[len(x) :], 3600)
	arp.b = sy.reverb(sy.ping_pong(sy.lp(arp.b, 7000), E8 * 1.5, 0.4, 0.3), ir, 0.3)
	pad.b = sy.reverb(pad.b, ir, 0.4)

	# ---------------- lead + flute ----------------
	lead, bells = Bus(total), Bus(total)
	def play_lead(bar0, text, gain=1.0, bright=1.0, octave_layer=False):
		start = len(m_lead.notes)
		m_lead.line(bar0 * 8, text, vel=100)
		for s_, d, p, v in m_lead.notes[start:]:
			sig = sy.lead(p, d * E8 * 0.94, bright)
			lead.add(s_ * E8, sig, gain)
			if octave_layer:
				lead.add(s_ * E8, sy.lead(p - 12, d * E8 * 0.94, 0.7), gain * 0.45)
	tmp = sc.track("_tmp", 0, channel=15)
	tmp.line(4 * 8, " | ".join(P1.split(" | ")[:4]))
	for s_, d, p, v in tmp.notes:
		bells.add(s_ * E8, sy.bell(p, d * E8), 1.0)
	sc.tracks.remove(tmp)
	play_lead(DROP_A, P1)
	play_lead(DROP_A + 8, P2)
	play_lead(SEC_B, RIFF, 0.95, 1.3)
	play_lead(DROP_C, P1, 1.0, 1.15, True)
	play_lead(DROP_C + 8, P2, 1.05, 1.2, True)
	play_lead(OUTRO, LAST, 0.8)
	lead.b = sy.reverb(sy.ping_pong(lead.b, E8 * 3, 0.35, 0.22), ir, 0.3)
	bells.b = sy.reverb(sy.ping_pong(bells.b, E8 * 3, 0.5, 0.4), ir, 0.5)

	for tr in (m_flute, f_only):
		tr.line(BREAK * 8, CALM, vel=92, legato=0.98)
		tr.line(DROP_C * 8, P1, vel=104, legato=0.95)
		tr.line((DROP_C + 8) * 8, P2, vel=106, legato=0.95)
		tr.dyn([(BREAK * 8, 74), (BREAK * 8 + 28, 96), (BREAK * 8 + 56, 84), (BREAK * 8 + 63, 112), (DROP_C * 8, 118), (OUTRO * 8, 118)])
	fl.time_sig = (4, 4)
	fpath = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out", "_flute.mid")
	fl.save(fpath)
	fa = fluid_dry(fpath, gain=0.8)
	os.remove(fpath)
	flute = Bus(total)
	flute.add(0, fa[: n])
	calm_end = int(tb(DROP_C) * SR)
	flute.b[calm_end:] *= 0.62  # in the drop it only colours the synth lead
	flute.b = sy.reverb(sy.ping_pong(flute.b, E8 * 3, 0.35, 0.2), ir, 0.45)

	# ---------------- fx ----------------
	fx = Bus(total)
	for b in (DROP_A, SEC_B, DROP_C, OUTRO, BARS - 1):
		fx.add(tb(b), sy.impact(rng), 1.0)
	fx.add(tb(6), sy.riser(2 * BAR_S - 2 * E8, rng), 0.7)
	fx.add(tb(36), sy.riser(4 * BAR_S - 2 * E8, rng), 1.0)
	fx.add(tb(SEC_B - 1), sy.riser(BAR_S, rng), 0.5)

	# ---------------- mix ----------------
	duck = sy.sidechain(n, kick_times, 0.62, 0.11)[:, None]
	breaks.level(-17.0)
	drums.level(-17.5)
	bass.level(-16.5)
	lead.level(-18.5)
	bells.level(-24.0)
	pad.level(-23.0)
	arp.level(-25.0)
	flute.level(-21.0)
	fx.level(-20.0)
	stems = {"breaks": breaks.b, "drums": drums.b, "bass": bass.b * (0.45 + 0.55 * duck), "lead": lead.b, "bells": bells.b,
		"pad": pad.b * duck, "arp": arp.b * (0.4 + 0.6 * duck), "flute": flute.b, "fx": fx.b}
	mix = sum(stems.values())
	# glitches on the whole mix: a stutter into the second half of the last drop, a 32nd buzz before the outro
	sy.stutter(mix, tb(DROP_C + 7, 6), E8 / 2, 4)
	sy.stutter(mix, tb(OUTRO - 1, 7), E8 / 4, 4)
	mix = sy.tape_stop(mix, tb(BARS - 1) + 0.25, 1.3)
	ref = np.percentile(np.abs(mix), 99.9)
	y = np.tanh(mix / ref * 1.25)
	y = y / np.abs(y).max() * 0.93
	return y, stems, sc


if __name__ == "__main__":
	here = os.path.dirname(os.path.abspath(__file__))
	out = os.path.join(here, "out")
	os.makedirs(out, exist_ok=True)
	y, stems, sc = compose()
	encode(y, os.path.join(out, "battle_breakcore"))
	sc.save(os.path.join(out, "battle_breakcore_daw.mid"), dyn_cc=1)
	print("rendered %.1f s" % (len(y) / SR))
	sec = [("intro", 0), ("drop A", 8), ("B", 24), ("breakdown", 32), ("drop C", 40), ("outro", 56), ("end", 60)]
	print("%-10s" % "" + " ".join("%7s" % k for k in list(stems) + ["MIX"]))
	for (nm, b0), (_, b1) in zip(sec, sec[1:]):
		a, e = int(tb(b0) * SR), int(tb(b1) * SR)
		row = []
		for v in list(stems.values()) + [y]:
			r = np.sqrt(np.mean(v[a:e] ** 2)) if a < len(v) else 0
			row.append("%7.0f" % (20 * np.log10(r)) if r > 1e-5 else "      .")
		print("%-10s" % nm + " ".join(row))
