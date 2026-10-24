"""Tiny score-as-code toolkit: write notes in eighth-note units, export General MIDI with banks + CC curves.

Time is measured in eighths (6/8: one bar = 6). Pitches are names ("F#5", "Bb3") or MIDI numbers.
"""
import random
import mido

NOTE = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
PPQ = 480
EIGHTH = PPQ // 2


def pitch(p):
	if isinstance(p, int):
		return p
	if p.isdigit():
		return int(p)
	name, rest = p[0].upper(), p[1:]
	acc = 0
	while rest and rest[0] in "#b":
		acc += 1 if rest[0] == "#" else -1
		rest = rest[1:]
	return 12 * (int(rest) + 1) + NOTE[name] + acc


def parse_line(text):
	"""'D5:2 E5:1 r:3 [D4 F#4 A4]:6' -> [(pitches|None, dur)]. Dur in eighths (floats ok)."""
	out = []
	for tok in text.replace("|", " ").split():
		p, d = tok.rsplit(":", 1)
		d = float(d)
		if p == "r":
			out.append((None, d))
		elif p.startswith("["):
			out.append(([pitch(x) for x in p.strip("[]").split()], d))
		else:
			out.append(([pitch(p)], d))
	return out


class Track:
	def __init__(self, score, name, program, bank=0, channel=0, volume=100, pan=64, reverb=40, chorus=0):
		self.score, self.name, self.program, self.bank, self.channel = score, name, program, bank, channel
		self.volume, self.pan, self.reverb, self.chorus = volume, pan, reverb, chorus
		self.notes = []  # (start, dur, pitch, vel)
		self.ccs = []  # (time, cc, value)

	def note(self, start, dur, p, vel=80, legato=1.0):
		self.notes.append((start, dur * legato, pitch(p), vel))

	def line(self, start, text, vel=80, legato=1.0, accent_first=0, contour=0.0, transpose=0):
		"""Melody line. contour > 0 makes higher notes louder (natural phrasing)."""
		t = start
		items = parse_line(text)
		for i, (ps, d) in enumerate(items):
			if ps:
				for p in ps:
					p += transpose
					v = vel + (accent_first if i == 0 else 0) + contour * (p - 72)
					self.note(t, d, p, int(v), legato)
			t += d
		return t

	def dyn(self, points, step=0.5):
		"""Dynamics curve [(time, 0..127)] - written as CC2 for the SoundFont render, CC1 for DAW export."""
		self.ramp("DYN", points, step)

	def cc(self, time, number, value):
		self.ccs.append((time, number, int(max(0, min(127, value)))))

	def ramp(self, number, points, step=0.5):
		"""Linear CC ramp through [(time, value), ...]."""
		for (t0, v0), (t1, v1) in zip(points, points[1:]):
			n = max(1, int((t1 - t0) / step))
			for k in range(n):
				self.cc(t0 + (t1 - t0) * k / n, number, v0 + (v1 - v0) * k / n)
		self.cc(points[-1][0], number, points[-1][1])


class Score:
	def __init__(self, bpm_quarter=96, seed=1, humanize=0.06):
		self.tracks = []
		self.tempos = [(0, bpm_quarter)]
		self.rng = random.Random(seed)
		self.humanize = humanize  # timing jitter in eighths
		self.time_sig = (6, 8)

	def track(self, *a, **k):
		t = Track(self, *a, **k)
		self.tracks.append(t)
		return t

	def tempo(self, time, bpm):
		self.tempos.append((time, bpm))

	def tempo_ramp(self, t0, t1, bpm0, bpm1, steps=12):
		for k in range(steps + 1):
			self.tempo(t0 + (t1 - t0) * k / steps, bpm0 + (bpm1 - bpm0) * k / steps)

	def save(self, path, dyn_cc=2):
		mid = mido.MidiFile(ticks_per_beat=PPQ, type=1)
		meta = mido.MidiTrack()
		meta.append(mido.MetaMessage("time_signature", numerator=self.time_sig[0], denominator=self.time_sig[1], time=0))
		ev = [(int(t * EIGHTH), mido.MetaMessage("set_tempo", tempo=mido.bpm2tempo(b))) for t, b in sorted(self.tempos)]
		self._flush(meta, ev)
		mid.tracks.append(meta)
		for tr in self.tracks:
			mt = mido.MidiTrack()
			mt.append(mido.MetaMessage("track_name", name=tr.name, time=0))
			c = tr.channel
			ev = [
				(0, mido.Message("control_change", channel=c, control=0, value=tr.bank)),
				(0, mido.Message("control_change", channel=c, control=32, value=0)),
				(0, mido.Message("program_change", channel=c, program=tr.program)),
				(0, mido.Message("control_change", channel=c, control=7, value=tr.volume)),
				(0, mido.Message("control_change", channel=c, control=10, value=tr.pan)),
				(0, mido.Message("control_change", channel=c, control=91, value=tr.reverb)),
				(0, mido.Message("control_change", channel=c, control=93, value=tr.chorus)),
			]
			if not any(n == "DYN" and t < 0.1 for t, n, _ in tr.ccs):
				ev.append((0, mido.Message("control_change", channel=c, control=dyn_cc, value=100)))
			for t, n, v in tr.ccs:
				n = dyn_cc if n == "DYN" else n
				ev.append((max(1, int(t * EIGHTH)), mido.Message("control_change", channel=c, control=n, value=v)))
			for s, d, p, v in tr.notes:
				j = self.rng.uniform(-1, 1) * self.humanize
				on = max(2, int((s + j) * EIGHTH))
				off = max(on + 10, int((s + d + j * 0.5) * EIGHTH) - 4)
				v = int(max(1, min(127, v + self.rng.randint(-4, 4))))
				ev.append((on, mido.Message("note_on", channel=c, note=p, velocity=v)))
				ev.append((off, mido.Message("note_off", channel=c, note=p, velocity=0)))
			self._flush(mt, ev)
			mid.tracks.append(mt)
		mid.save(path)

	@staticmethod
	def _flush(mt, ev):
		# note_offs before note_ons at the same tick (repeated notes)
		ev.sort(key=lambda e: (e[0], 0 if e[1].type == "note_off" else (1 if e[1].type != "note_on" else 2)))
		last = 0
		for t, m in ev:
			mt.append(m.copy(time=t - last))
			last = t
