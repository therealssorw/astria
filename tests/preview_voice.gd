extends Node3D
## Look-at aid, not a pass/fail test: draws the REAL voice HUD in each of its
## states over a stand-in world, so the mic glyph, the level meter and the marker
## over a talker's head can be judged without a second machine and a microphone.
##   godot --path . res://tests/preview_voice.tscn
## It needs a real window — do NOT pass --headless, there is nothing to draw
## into, and _draw() is never called. Shots land in user://voice_preview.
##
## It also serves as the only check that the overlay's drawing code runs at all:
## test_voice_chat covers the routing and the wire format, and neither of those
## touches a polygon.

const OUT_DIR := "user://voice_preview"
const PLAYER := preload("res://scenes/player.tscn")
const OVERLAY := preload("res://scripts/ui/voice/voice_overlay.gd")

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()

	# a body to hang a voice on, stood in front of the camera
	var them: Node3D = PLAYER.instantiate()
	them.name = "2"
	them.peer_id = 2
	them.username = "Neighbour"
	$Players.add_child(them)
	them.global_position = Vector3(0.0, 0.0, -5.0)
	them.set_physics_process(false)
	Net.players[2] = {"name": "Neighbour", "kills": 0, "deaths": 0}

	var layer := CanvasLayer.new()
	add_child(layer)
	var overlay: Control = OVERLAY.new()
	layer.add_child(overlay)
	await get_tree().process_frame

	# The one part of PLAYBACK a single machine can check: a voice really grows a
	# generator on the speaker's own body and takes the samples, at the wire's
	# rate rather than the mixer's. Whether it sounds right needs two machines
	# and two microphones, which no test here can stand in for.
	Voice.on_voice(2, VoiceCodec.encode(_speech()))
	for _i in 4:
		await get_tree().process_frame
	var sp: AudioStreamPlayer3D = them.get_node_or_null("Voice")
	print("PREVIEW playback: node=%s playing=%s rate=%s" % [
			"yes" if sp else "NONE", str(sp.playing) if sp else "-",
			str(sp.stream.mix_rate) if sp else "-"])
	Voice.forget(2)

	# Voice is running for real in a windowed run — it has opened this machine's
	# microphone — and its own tick would overwrite every state posed below with
	# what the mic is actually doing (nothing, since there is no session). So it
	# is stopped, and the shots are poses.
	Voice.set_process(false)

	# 1. push-to-talk, held: gold mic and a moving level meter
	Voice.set_mode(Voice.Mode.PUSH_TO_TALK)
	Voice.mic_ready = true
	Voice.transmitting = true
	Voice.input_level = 0.22
	await _shot("push_to_talk")

	# 2. an open mic nobody is using — dim, but always drawn, which is the point
	Voice.set_mode(Voice.Mode.OPEN_MIC)
	Voice.transmitting = false
	Voice.input_level = 0.02
	await _shot("open_mic_quiet")

	# 3. somebody near you is talking (and your own open mic is live)
	Voice.transmitting = true
	Voice.input_level = 0.3
	Voice.on_voice(2, VoiceCodec.encode(_speech()))
	await _shot("someone_talking")

	# 4. the mic that isn't there. Push-to-talk draws nothing until the button is
	# down, so the button has to be put down — this state only exists while
	# somebody is trying to talk.
	Voice.forget(2)
	Voice.set_mode(Voice.Mode.PUSH_TO_TALK)
	Voice.mic_ready = false
	Voice.transmitting = false
	Input.action_press("voice_talk")
	await _shot("no_microphone")
	Input.action_release("voice_talk")

	print("PREVIEW saved=", ProjectSettings.globalize_path(OUT_DIR))
	get_tree().quit()

func _speech() -> PackedFloat32Array:
	var n := int(VoiceCodec.RATE * Voice.PACKET_INTERVAL)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = sin(TAU * 220.0 * float(i) / float(VoiceCodec.RATE)) * 0.4
	return out

func _shot(shot_name: String) -> void:
	# the glyph pulses, so a few frames in is more representative than frame one
	for _i in 20:
		await get_tree().process_frame
		# the marker fades a moment after the last packet; keep this one talking
		if shot_name == "someone_talking":
			Voice.on_voice(2, VoiceCodec.encode(_speech()))
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [OUT_DIR, shot_name])
