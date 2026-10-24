"""Small numpy synth + break-chopping toolkit for the electronic pieces (48 kHz, stereo buses)."""
import numpy as np
from scipy.signal import butter, sosfilt, fftconvolve, resample_poly

SR = 48000


def hz(p):
	return 440.0 * 2 ** ((p - 69) / 12)


def lp(x, fc, order=2):
	return sosfilt(butter(order, fc, "low", fs=SR, output="sos"), x, axis=0)


def hp(x, fc, order=2):
	return sosfilt(butter(order, fc, "high", fs=SR, output="sos"), x, axis=0)


def saw(f, n, phase=0.0):
	"""Band-limited (polyBLEP) sawtooth; f = Hz, scalar or per-sample array."""
	dt = (np.full(n, float(f)) if np.isscalar(f) else f) / SR
	ph = (phase + np.cumsum(dt)) % 1.0
	y = 2 * ph - 1
	m = ph < dt
	t = ph[m] / dt[m]
	y[m] -= t + t - t * t - 1
	m = ph > 1 - dt
	t = (ph[m] - 1) / dt[m]
	y[m] -= t * t + t + t + 1
	return y


def pulse(f, n, width=0.5, phase=0.0):
	return saw(f, n, phase) - saw(f, n, phase + width)


def env(n_hold, a=0.005, d=0.1, s=0.7, r=0.1):
	"""ADSR; returns n_hold + release samples."""
	nr = max(8, int(r * SR))
	n = n_hold + nr
	t = np.arange(n) / SR
	e = np.where(t < a, t / max(a, 1e-5), s + (1 - s) * np.exp(-(t - a) / max(d, 1e-4)))
	e[n_hold:] *= np.linspace(1, 0, nr) ** 2
	return e


class Bus:
	"""A stereo track to add sounds to."""
	def __init__(self, seconds):
		self.b = np.zeros((int(seconds * SR), 2))

	def add(self, t, sig, gain=1.0, pan=0.0):
		i = int(round(t * SR))
		if i >= len(self.b) or i < 0:
			return
		sig = sig[: len(self.b) - i]
		if sig.ndim == 1:
			a = (pan + 1) * np.pi / 4
			self.b[i : i + len(sig), 0] += sig * gain * np.cos(a) * 1.414
			self.b[i : i + len(sig), 1] += sig * gain * np.sin(a) * 1.414
		else:
			self.b[i : i + len(sig)] += sig * gain

	def rms(self):
		m = np.abs(self.b).max(1) > 1e-4
		return float(np.sqrt(np.mean(self.b[m] ** 2))) if m.any() else 0.0

	def level(self, target_db):
		"""Scale so the active parts sit at target_db RMS."""
		r = self.rms()
		if r > 0:
			self.b *= 10 ** (target_db / 20) / r
		return self


def ping_pong(x, time_s, fb=0.45, mix=0.3, taps=6):
	"""Stereo delay bouncing between the channels."""
	out = x.copy()
	d = int(time_s * SR)
	mono = x.mean(1)
	for k in range(1, taps + 1):
		g = mix * fb ** (k - 1)
		if k * d >= len(x):
			break
		out[k * d :, k % 2] += mono[: len(x) - k * d] * g
	return out


def reverb(x, ir, wet=0.25):
	w = np.stack([fftconvolve(x[:, c], ir[:, c])[: len(x)] for c in range(2)], 1)
	return x + w * wet * 0.18


def crush(x, hold=4, bits=6):
	"""Sample-rate + bit reduction."""
	y = np.repeat(x[::hold], hold, axis=0)[: len(x)]
	q = 2 ** bits
	return np.round(y * q) / q


def sidechain(n, times, depth=0.7, rel=0.14):
	"""Gain curve ducking after each time (seconds)."""
	g = np.ones(n)
	L = int(rel * 4 * SR)
	shape = depth * np.exp(-np.arange(L) / (rel * SR))
	for t in times:
		i = int(t * SR)
		if i < n:
			seg = g[i : i + L]
			np.minimum(seg, 1 - shape[: len(seg)], out=seg)
	return g


# ---------------- instruments (mono unless noted) ----------------
def lead(p, dur, bright=1.0):
	"""Detuned saw/pulse lead with delayed vibrato and an FM bell on the attack."""
	n_hold = int(dur * SR)
	e = env(n_hold, 0.004, 0.18, 0.72, 0.12)
	n = len(e)
	t = np.arange(n) / SR
	vib = 1 + 0.004 * np.sin(2 * np.pi * 5.6 * t) * np.clip((t - 0.12) / 0.2, 0, 1)
	f = hz(p) * vib
	y = saw(f, n) * 0.5 + saw(f * 1.006, n, 0.3) * 0.35 + saw(f * 0.994, n, 0.7) * 0.35 + pulse(f * 0.5, n, 0.3) * 0.25
	bell = np.sin(2 * np.pi * hz(p) * t + 2.2 * np.exp(-t / 0.07) * np.sin(2 * np.pi * hz(p) * 3 * t)) * np.exp(-t / 0.22)
	return (lp(y, 5200 * bright) + bell * 0.6) * e


def bell(p, dur):
	n = int((dur + 0.6) * SR)
	t = np.arange(n) / SR
	f = hz(p)
	y = np.sin(2 * np.pi * f * t + 1.8 * np.exp(-t / 0.15) * np.sin(2 * np.pi * f * 3.5 * t))
	return y * np.exp(-t / 0.35) * np.clip(t / 0.002, 0, 1)


def pluck(p, dur=0.12):
	n = int((dur + 0.25) * SR)
	t = np.arange(n) / SR
	f = hz(p)
	y = saw(f, n) * np.exp(-t / 0.035) + pulse(f, n, 0.4) * 0.5 * np.exp(-t / 0.09) + np.sin(2 * np.pi * f * t) * 0.6 * np.exp(-t / 0.16)
	return y * np.clip(t / 0.001, 0, 1)


def supersaw(p, dur, rng, voices=5, spread=16.0, a=0.06, r=0.25):
	"""Stereo: detuned saws, different phases left and right."""
	n_hold = int(dur * SR)
	e = env(n_hold, a, 0.3, 0.85, r)
	n = len(e)
	out = np.zeros((n, 2))
	for v in range(voices):
		det = 2 ** ((v - (voices - 1) / 2) * spread / (voices - 1) * 2 / 1200)
		for c in range(2):
			out[:, c] += saw(hz(p) * det, n, rng.random())
	return out * e[:, None] / voices


def reese(p, dur, drive=3.0, cutoff=700.0, wobble_hz=0.0):
	"""Detuned-saw bass + sine sub, driven. wobble_hz opens/closes the filter rhythmically."""
	n_hold = int(dur * SR)
	e = env(n_hold, 0.004, 0.2, 0.9, 0.03)
	n = len(e)
	t = np.arange(n) / SR
	f = hz(p)
	raw = saw(f * 1.008, n) + saw(f * 0.992, n, 0.5) + saw(f * 2.004, n, 0.2) * 0.35
	dark = lp(raw, cutoff)
	if wobble_hz > 0:
		w = 0.5 - 0.5 * np.cos(2 * np.pi * wobble_hz * t)
		y = dark * (1 - w) + lp(raw, cutoff * 5) * w
	else:
		y = dark
	sub = np.sin(2 * np.pi * f * t)
	return (np.tanh(y * drive) * 0.7 + sub * 0.9) * e


def kick(punch=1.0):
	n = int(0.32 * SR)
	t = np.arange(n) / SR
	f = 46 + 190 * np.exp(-t / 0.028)
	y = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.13)
	click = np.random.default_rng(1).standard_normal(n) * np.exp(-t / 0.003) * 0.4
	return np.tanh((y + click) * 2.2 * punch)


def snare(rng, pitch=0.0, length=0.16):
	n = int((length + 0.08) * SR)
	t = np.arange(n) / SR
	noise = hp(rng.standard_normal(n), 1400) * np.exp(-t / (length * 0.45))
	f = 195 * 2 ** (pitch / 12)
	tone = np.sin(2 * np.pi * (f + 90 * np.exp(-t / 0.02)) * t) * np.exp(-t / 0.07)
	return np.tanh((noise * 0.9 + tone * 0.9) * 2.0)


def riser(dur, rng):
	"""Noise sweeping up, stereo."""
	n = int(dur * SR)
	x = np.linspace(0, 1, n)
	out = np.zeros((n, 2))
	for c in range(2):
		nz = rng.standard_normal(n)
		out[:, c] = lp(nz, 700) * (1 - x) + hp(nz, 3500) * x
	return out * (x ** 2)[:, None]


def impact(rng):
	"""Sub drop + noise burst, stereo."""
	n = int(1.6 * SR)
	t = np.arange(n) / SR
	sub = np.sin(2 * np.pi * np.cumsum(34 + 70 * np.exp(-t / 0.12)) / SR) * np.exp(-t / 0.45)
	out = np.zeros((n, 2))
	for c in range(2):
		out[:, c] = sub + lp(rng.standard_normal(n), 6000) * np.exp(-t / 0.35) * 0.5
	return np.tanh(out * 1.5)


def tape_stop(x, start, dur):
	"""Slow the audio from `start` (s) to a halt over `dur` seconds; returns the shortened buffer."""
	i = int(start * SR)
	n = int(dur * SR)
	speed = np.linspace(1, 0, n) ** 1.2
	pos = i + np.cumsum(speed)
	pos = pos[pos < len(x) - 1]
	seg = np.stack([np.interp(pos, np.arange(len(x)), x[:, c]) for c in range(2)], 1)
	seg *= np.linspace(1, 0, len(seg))[:, None] ** 0.5
	return np.concatenate([x[:i], seg])


def stutter(x, start, piece, repeats):
	"""Repeat the `piece` seconds at `start` `repeats` times in place (overwrites what follows)."""
	i, n = int(start * SR), int(piece * SR)
	chunk = x[i : i + n].copy()
	f = min(96, n // 4)
	chunk[:f] *= np.linspace(0, 1, f)[:, None]
	chunk[-f:] *= np.linspace(1, 0, f)[:, None]
	for r in range(repeats):
		a = i + r * n
		if a + n <= len(x):
			x[a : a + n] = chunk
	return x


# ---------------- break chopping ----------------
def fit_break(raw_mono, bpm_from, bpm_to, slot):
	"""Speed a rendered break up (pitch rises, like a sped-up sample) so one sixteenth = `slot` samples."""
	from fractions import Fraction
	fr = Fraction(bpm_from, bpm_to).limit_denominator(200)
	y = resample_poly(raw_mono, fr.numerator, fr.denominator)
	return y


def chop(seq, src, slot):
	"""seq: per bar a list of 16 steps (None or (slice, retrig, pitch_semitones, reverse, gain)) -> mono."""
	out = np.zeros(len(seq) * 16 * slot + slot)
	nslices = len(src) // slot
	for b, steps in enumerate(seq):
		if not steps:
			continue
		for k, st in enumerate(steps):
			if st is None:
				continue
			idx, retrig, pitch, rev, g = st
			sl = src[(idx % nslices) * slot : (idx % nslices + 1) * slot]
			if pitch:
				sl = np.interp(np.arange(slot) * 2 ** (pitch / 12), np.arange(slot), sl, right=0.0)
			if rev:
				sl = sl[::-1]
			sub = slot // retrig
			piece = sl[:sub].copy()
			f = min(72, sub // 4)
			piece[:f] *= np.linspace(0, 1, f)
			piece[-2 * f :] *= np.linspace(1, 0, 2 * f)
			pos = (b * 16 + k) * slot
			for r in range(retrig):
				out[pos + r * sub : pos + r * sub + sub] += piece * g * (1.0 if retrig == 1 else 0.75 + 0.25 * r / retrig)
	return out
