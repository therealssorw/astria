extends Node3D
## Headless test for proximity voice chat. Run:
##   godot --headless --path . res://tests/test_voice_chat.tscn
##
## Two pawns offline (OfflineMultiplayerPeer makes this peer the server), so the
## whole listen-server path is real: a packet goes into Net's relay and comes out
## of Voice on the other side without an RPC in between. What is checked is the
## part that matters — WHO GETS TO HEAR IT is measured on the server's own copy
## of both pawns, and a talker cannot flood the relay everybody shares.
##
## Prints VOICETEST RESULT=PASS/FAIL and exits with the matching code. There is
## no audio on a headless run, so this is about routing and the wire format;
## whether it SOUNDS right is not something a test can tell you.

const PLAYER := preload("res://scenes/player.tscn")

var fails := 0

func _ready() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	call_deferred("_run")

# ---------------- helpers ----------------

func ok(cond: bool, label: String, detail := "") -> void:
	if cond:
		print("  PASS  %s %s" % [label, detail])
	else:
		fails += 1
		print("  FAIL  %s %s" % [label, detail])

func _spawn_player(id: int, pos: Vector3) -> Player:
	var p: Player = PLAYER.instantiate()
	p.name = str(id)
	p.peer_id = id
	p.username = "T%d" % id
	$Players.add_child(p)
	p.global_position = pos
	p.net_pos = pos
	p.set_physics_process(false)
	Net.players[id] = {"name": "T%d" % id, "kills": 0, "deaths": 0}
	return p

## A second of speech at `amp`, as the packets it would really be sent as.
func _packets(amp: float, seconds: float) -> Array[PackedByteArray]:
	var per := int(VoiceCodec.RATE * Voice.PACKET_INTERVAL)
	var out: Array[PackedByteArray] = []
	for _i in int(seconds / Voice.PACKET_INTERVAL):
		var block := PackedFloat32Array()
		block.resize(per)
		for s in per:
			block[s] = sin(TAU * 220.0 * float(s) / float(VoiceCodec.RATE)) * amp
		out.append(VoiceCodec.encode(block))
	return out

func _sine(rate: float, seconds: float, hz := 220.0) -> PackedFloat32Array:
	var n := int(rate * seconds)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = sin(TAU * hz * float(i) / rate) * 0.5
	return out

# ---------------- run ----------------

func _run() -> void:
	print("=== format ===")
	_check_format()
	print("=== resampler ===")
	_check_resampler()
	print("=== who can hear you ===")
	await _check_proximity()
	print("=== flood control ===")
	_check_flood()
	print("=== being heard ===")
	await _check_playback()
	print("VOICETEST RESULT=%s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(1 if fails > 0 else 0)

func _check_format() -> void:
	var quiet := PackedFloat32Array([0.0, 0.0, 0.0])
	var quiet_bytes := VoiceCodec.encode(quiet)
	ok(quiet_bytes == PackedByteArray([0, 0, 0]), "silence is a run of zero bytes",
			str(Array(quiet_bytes)))

	var probes := PackedFloat32Array([-1.0, -0.72, -0.25, -0.03, 0.0, 0.03, 0.25, 0.72, 1.0])
	var back := VoiceCodec.decode(VoiceCodec.encode(probes))
	ok(back.size() == probes.size(), "one byte in, one sample out",
			"%d -> %d" % [probes.size(), back.size()])
	var worst := 0.0
	var signs := true
	for i in probes.size():
		worst = maxf(worst, absf(back[i] - probes[i]))
		if signf(probes[i]) != 0.0 and signf(back[i]) != signf(probes[i]):
			signs = false
	ok(worst <= 0.02, "a sample survives the round trip", "worst error %.4f" % worst)
	ok(signs, "the sign survives it too")

	var clipped := VoiceCodec.decode(VoiceCodec.encode(PackedFloat32Array([4.0, -4.0])))
	ok(absf(clipped[0] - 1.0) < 0.01 and absf(clipped[1] + 1.0) < 0.01,
			"anything over full scale clips instead of wrapping",
			"%.3f / %.3f" % [clipped[0], clipped[1]])

	# the two limits the server enforces have to fit what the client really sends
	var per := int(VoiceCodec.RATE * Voice.PACKET_INTERVAL)
	ok(per < VoiceCodec.MAX_PACKET, "a real packet is inside the size limit",
			"%d of %d bytes" % [per, VoiceCodec.MAX_PACKET])
	ok(VoiceCodec.RATE < VoiceCodec.MAX_BYTES_PER_SECOND,
			"a second of talking is inside the budget",
			"%d of %d bytes" % [VoiceCodec.RATE, VoiceCodec.MAX_BYTES_PER_SECOND])

func _check_resampler() -> void:
	# whatever the machine mixes at, the wire gets VoiceCodec.RATE
	for mix in [44100.0, 48000.0, 22050.0]:
		var r := VoiceCodec.Resampler.new()
		var got: int = r.push(_sine(mix, 1.0), mix).size()
		ok(absf(float(got) - float(VoiceCodec.RATE)) <= 8.0,
				"%d Hz in, a second comes out at %d" % [int(mix), VoiceCodec.RATE],
				"%d samples" % got)

	# and fed in blocks, as the capture really hands it over, it neither loses
	# nor invents samples at the seams — a resampler that restarted each block
	# would drift and click
	var blocked := VoiceCodec.Resampler.new()
	var total := 0
	var whole := _sine(44100.0, 1.0)
	var step := 512
	for start in range(0, whole.size(), step):
		total += blocked.push(whole.slice(start, mini(start + step, whole.size())),
				44100.0).size()
	ok(absf(float(total) - float(VoiceCodec.RATE)) <= 8.0,
			"blocks join up without drifting", "%d samples over %d blocks" % [
			total, int(ceil(float(whole.size()) / float(step)))])

	var out := VoiceCodec.Resampler.new().push(_sine(44100.0, 0.5), 44100.0)
	ok(absf(VoiceCodec.rms(out) - 0.354) < 0.05, "and it is still the sound going in",
			"rms %.3f (a 0.5 sine is 0.354)" % VoiceCodec.rms(out))

func _check_proximity() -> void:
	var me := _spawn_player(1, Vector3.ZERO)
	var them := _spawn_player(2, Vector3(5.0, 0.0, 0.0))
	await get_tree().physics_frame

	ok(Net.voice_targets(1) == [2], "somebody 5 m away hears you",
			str(Net.voice_targets(1)))
	ok(not Net.voice_targets(1).has(1), "you never hear yourself")

	them.global_position = Vector3(Net.VOICE_RANGE - 1.0, 0.0, 0.0)
	ok(Net.voice_targets(1) == [2], "and just inside the range")
	them.global_position = Vector3(Net.VOICE_RANGE + 1.0, 0.0, 0.0)
	ok(Net.voice_targets(1).is_empty(), "just outside it, nobody does",
			str(Net.voice_targets(1)))
	them.global_position = Vector3(600.0, 0.0, 0.0)
	ok(Net.voice_targets(1).is_empty(), "and across the island nobody does")

	# height counts: somebody on the roof is not standing next to you
	them.global_position = Vector3(0.0, Net.VOICE_RANGE + 4.0, 0.0)
	ok(Net.voice_targets(1).is_empty(), "nor overhead")

	# the server measures ITS copy of the pawn, not what the client says. A
	# rejected report leaves net_pos where it was, and that is what counts.
	them.global_position = Vector3(5.0, 0.0, 0.0)
	them.net_pos = Vector3(400.0, 0.0, 0.0)
	them._net_has_state = true
	ok(Net.voice_targets(1).is_empty(),
			"a listener is placed by the server's own copy of its pawn")
	them._net_has_state = false

	# registered but not spawned yet: no pawn, no audience, no crash
	Net.players[3] = {"name": "T3", "kills": 0, "deaths": 0}
	ok(not Net.voice_targets(1).has(3), "a player with no pawn in the world is skipped")
	Net.players.erase(3)
	ok(Net.voice_targets(9).is_empty(), "and a speaker with no pawn has no audience")

	them.global_position = Vector3(5.0, 0.0, 0.0)
	ok(me != null and them != null, "both pawns stood up")

func _check_flood() -> void:
	var packet := _packets(0.4, Voice.PACKET_INTERVAL)[0]
	ok(not Net.voice_accepts(1, PackedByteArray()), "an empty packet is refused")
	var huge := PackedByteArray()
	huge.resize(VoiceCodec.MAX_PACKET + 1)
	ok(not Net.voice_accepts(1, huge), "an oversized packet is refused",
			"%d bytes" % huge.size())

	# a second of ordinary talking all gets through...
	Net._voice_spend.clear()
	var carried := 0
	for p: PackedByteArray in _packets(0.4, 1.0):
		if Net.voice_accepts(2, p):
			carried += 1
	ok(carried == int(1.0 / Voice.PACKET_INTERVAL), "a second of talking all gets through",
			"%d packets" % carried)

	# ...and ten times the rate does not, without ever having a free window
	Net._voice_spend.clear()
	var refused := 0
	for i in 200:
		if not Net.voice_accepts(3, packet):
			refused += 1
	ok(refused > 150, "ten times that is cut off for the rest of the second",
			"%d of 200 packets dropped" % refused)
	Net._voice_spend.clear()

func _check_playback() -> void:
	var them: Player = $Players.get_node("2")
	Net.active = true
	var packet := _packets(0.4, Voice.PACKET_INTERVAL)[0]

	# the whole listen-server path, no RPC in the middle: peer 2 talks, the
	# server routes it, and this peer is the one standing next to them
	them.global_position = Vector3(5.0, 0.0, 0.0)
	Voice.reset()
	Net._relay_voice(2, packet)
	ok(Voice.talking(2), "a neighbour talking is heard")

	them.global_position = Vector3(400.0, 0.0, 0.0)
	Voice.reset()
	Net._relay_voice(2, packet)
	ok(not Voice.talking(2), "the same words from across the island are not")

	# nothing routes a voice back to its owner, on either side of the wire
	Voice.reset()
	Voice.on_voice(1, packet)
	ok(not Voice.talking(1), "your own voice is never played back at you")

	Voice.reset()
	Voice.on_voice(2, PackedByteArray())
	var over := PackedByteArray()
	over.resize(VoiceCodec.MAX_PACKET + 1)
	Voice.on_voice(2, over)
	ok(not Voice.talking(2), "an empty or oversized packet is not played either")

	them.global_position = Vector3(5.0, 0.0, 0.0)
	Net._relay_voice(2, packet)
	ok(Voice.talking(2), "a speaker is remembered while they talk")
	Voice.forget(2)
	ok(not Voice.talking(2), "and forgotten when they leave")

	Net._relay_voice(2, packet)
	Voice.reset()
	ok(Voice.talking_peers().is_empty(), "leaving the world forgets everybody")
	Net.active = false
	Net.players.clear()
