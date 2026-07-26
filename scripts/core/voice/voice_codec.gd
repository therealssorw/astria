class_name VoiceCodec
extends RefCounted
## The wire format for speech: mono samples at RATE, one byte each, plus the
## rate conversion that gets the microphone's blocks into it.
##
## There is no Opus encoder reachable from GDScript, so this is logarithmic
## companding — µ-law's curve, computed in floats rather than through G.711's
## tables. Both ends of the wire are this file, so being bit-compatible with a
## telephone buys nothing, and the float form is the one that can be read.
##
## EVERY PACKET STANDS ALONE, and that is the whole reason a predictive codec
## (ADPCM, or anything with a running predictor) is not used here despite being
## half the bandwidth. Voice goes over an unreliable channel: one dropped packet
## would poison a predictor's state for everything after it, and the stream
## would degrade for as long as somebody kept talking. One byte in, one sample
## out, no history — a lost packet is a 50 ms hole and nothing more.

## Samples a second the format is defined at. Telephone-ish: plainly
## intelligible, and a clean quarter of Godot's usual 44100 mix rate. It is also
## THE BANDWIDTH DIAL — one byte a sample means RATE bytes a second per talker,
## so halving it halves what the relay carries.
const RATE := 11025

## Biggest packet the server will carry. A packet is one PACKET_INTERVAL of
## speech (~550 bytes at the rate above), so anything approaching this is
## already a broken or a patched client.
const MAX_PACKET := 1024

## Bytes a second one talker may push through the relay: the format's own rate
## plus headroom for packet timing. Past this the server drops the rest of that
## second (see Net.voice_accepts), so a patched client cannot flood the relay it
## shares with everybody else.
const MAX_BYTES_PER_SECOND := 14000

## Companding strength. 255 is µ-law's, and what the curve was tuned on.
const MU := 255.0

## log(1 + MU): the divisor that lands the curve on 0..1. A static var rather
## than a const because a const initialiser cannot call log().
static var _log_1p_mu := log(1.0 + MU)

## Samples (-1..1) -> one byte each. The top bit is the sign, the low seven the
## companded magnitude, so silence is a run of zero bytes.
static func encode(samples: PackedFloat32Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(samples.size())
	for i in samples.size():
		var x := clampf(samples[i], -1.0, 1.0)
		var q := int(round(log(1.0 + MU * absf(x)) / _log_1p_mu * 127.0))
		out[i] = (q | 0x80) if x < 0.0 else q
	return out

static func decode(bytes: PackedByteArray) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(bytes.size())
	for i in bytes.size():
		var b := bytes[i]
		var mag := (exp(float(b & 0x7F) / 127.0 * _log_1p_mu) - 1.0) / MU
		out[i] = -mag if (b & 0x80) != 0 else mag
	return out

## Loudness of a block, which is what open-mic mode opens on.
static func rms(samples: PackedFloat32Array) -> float:
	if samples.is_empty():
		return 0.0
	var sum := 0.0
	for s in samples:
		sum += s * s
	return sqrt(sum / float(samples.size()))

## Rate conversion with the phase kept ACROSS calls. The microphone hands over
## blocks at whatever the audio server mixes at (44100 here, 48000 on plenty of
## machines, and not something the game gets to choose), and a resampler that
## restarted at each block boundary would click on every seam.
class Resampler extends RefCounted:
	var _buf := PackedFloat32Array()
	var _phase := 0.0 # where we are in _buf, in input samples

	## Feed a block of mono input, get back however many output samples it
	## completed — which is not a fixed number, hence the leftovers in _buf.
	func push(mono: PackedFloat32Array, from_rate: float) -> PackedFloat32Array:
		var out := PackedFloat32Array()
		_buf.append_array(mono)
		if from_rate <= 0.0 or _buf.size() < 2:
			return out
		var step := from_rate / float(RATE)
		while _phase + 1.0 < float(_buf.size()):
			var i := int(_phase)
			out.append(lerpf(_buf[i], _buf[i + 1], _phase - float(i)))
			_phase += step
		var drop := int(_phase)
		if drop > 0:
			_buf = _buf.slice(drop)
			_phase -= float(drop)
		return out

	func reset() -> void:
		_buf = PackedFloat32Array()
		_phase = 0.0
