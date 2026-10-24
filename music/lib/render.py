"""MIDI -> WAV (FluidSynth) -> hall reverb + master (numpy) -> OGG/MP3 (ffmpeg)."""
import os
import subprocess
import numpy as np
import soundfile as sf
from scipy.signal import fftconvolve, butter, sosfilt

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FLUID = os.path.join(ROOT, "bin", "fluidsynth", "fluidsynth-v2.6.1-win10-x64-cpp11", "bin", "fluidsynth.exe")
SF2 = os.path.join(ROOT, "soundfonts", "MuseScore_General.sf2")
SR = 48000


def hall_ir(seconds=3.2, predelay=0.025, seed=3):
	"""Stereo synthetic hall: decorrelated noise, exponential decay, darker as it decays."""
	rng = np.random.default_rng(seed)
	n = int(seconds * SR)
	t = np.arange(n) / SR
	ir = np.zeros((n, 2))
	for ch in range(2):
		noise = rng.standard_normal(n)
		# split into bands, decay highs faster (air absorption)
		lo = sosfilt(butter(2, 900, "low", fs=SR, output="sos"), noise)
		mid = sosfilt(butter(2, [900, 4500], "band", fs=SR, output="sos"), noise)
		hi = sosfilt(butter(2, 4500, "high", fs=SR, output="sos"), noise)
		env = lambda rt: np.exp(-6.9 * t / rt)
		ir[:, ch] = lo * env(seconds) + mid * env(seconds * 0.7) * 0.8 + hi * env(seconds * 0.35) * 0.5
	fade_in = np.clip(t / 0.06, 0, 1) ** 1.5
	ir *= fade_in[:, None]
	ir = np.concatenate([np.zeros((int(predelay * SR), 2)), ir])
	return ir / np.sqrt(np.sum(ir ** 2) / 2)


def render(mid_path, out_base, wet=0.32, gain=0.5):
	dry_path = out_base + "_dry.wav"
	subprocess.run([FLUID, "-ni", "-q", "-R", "0", "-C", "0", "-g", str(gain), "-r", str(SR),
		"-F", dry_path, SF2, mid_path], check=True)
	x, sr = sf.read(dry_path)
	assert sr == SR
	if x.ndim == 1:
		x = np.stack([x, x], 1)
	# per-channel reverb send is baked into the MIDI CC91 for FluidSynth's own reverb, which we disabled;
	# here one shared hall on the whole mix (lows trimmed in the send so it stays airy, not muddy)
	send = sosfilt(butter(2, 220, "high", fs=SR, output="sos"), x, axis=0)
	ir = hall_ir()
	tail = int(len(ir))
	wet_sig = np.stack([fftconvolve(send[:, c], ir[:, c]) for c in range(2)], 1)
	y = np.zeros((len(x) + tail, 2))
	y[: len(x)] += x * (1 - wet * 0.5)
	y[: len(wet_sig)] += wet_sig * wet * 0.18
	# gentle air shelf
	air = sosfilt(butter(1, 7000, "high", fs=SR, output="sos"), y, axis=0)
	y += air * 0.12
	# trim trailing silence, normalise to -1 dBFS peak with a soft knee
	env = np.max(np.abs(y), 1)
	last = np.nonzero(env > 1e-4)[0]
	y = y[: last[-1] + SR // 4] if len(last) else y
	y = np.tanh(y / np.max(np.abs(y)) * 1.1) / np.tanh(1.1) * 0.89
	fades = min(len(y), SR)
	y[-fades:] *= np.linspace(1, 0, fades)[:, None] ** 2
	wav = out_base + ".wav"
	sf.write(wav, y, SR, subtype="PCM_24")
	os.remove(dry_path)
	subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", "6", out_base + ".ogg"], check=True)
	subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libmp3lame", "-q:a", "2", out_base + ".mp3"], check=True)
	return wav, len(y) / SR


def fluid_dry(mid_path, gain=0.5):
	"""Render a MIDI file with FluidSynth, no effects -> float array (n, 2)."""
	tmp = mid_path + ".dry.wav"
	subprocess.run([FLUID, "-ni", "-q", "-R", "0", "-C", "0", "-g", str(gain), "-r", str(SR), "-F", tmp, SF2, mid_path], check=True)
	x, sr = sf.read(tmp)
	os.remove(tmp)
	return x if x.ndim == 2 else np.stack([x, x], 1)


def encode(y, out_base):
	"""Write WAV + OGG + MP3."""
	sf.write(out_base + ".wav", y, SR, subtype="PCM_24")
	subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", out_base + ".wav", "-c:a", "libvorbis", "-q:a", "6", out_base + ".ogg"], check=True)
	subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", out_base + ".wav", "-c:a", "libmp3lame", "-q:a", "2", out_base + ".mp3"], check=True)
