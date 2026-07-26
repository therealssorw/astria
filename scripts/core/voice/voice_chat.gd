extends Node
## Autoload "Voice": proximity voice chat — your microphone, the people standing
## near enough to hear it, and their voices coming out of their bodies.
##
## WHO HEARS YOU IS THE SERVER'S DECISION, never the speaker's. A packet is sent
## to the server and nowhere else; the server measures the distance on its OWN
## copy of both pawns and relays only to the peers in range (Net.voice_targets).
## So a patched client can shout, but it cannot pick an audience, and it cannot
## listen in on a conversation it is not standing next to — those packets are
## never sent to it in the first place. Nothing here is trusted with anything.
##
## Everything on THIS side of that decision is cosmetic and local, in the sense
## the project's server-authority rules mean: which mode the mic is in, how loud
## it thinks you are, where in the world the audio comes out. Faking any of it
## gains a cheat nothing.
##
## Two modes, kept in user://settings.cfg beside the username:
##   PUSH_TO_TALK  the mic is shut unless "voice_talk" is held (V / L3)
##   OPEN_MIC      it opens by itself above OPEN_MIC_LEVEL, with a hangover so
##                 it does not chop the ends off words
## "voice_mode" (M) switches between them in game. That one is keyboard-only for
## now, like sprint and the scoreboard — it has no pad button yet.

enum Mode { PUSH_TO_TALK, OPEN_MIC }

const SETTINGS_PATH := "user://settings.cfg"

## A packet is this much speech: 20 a second. Shorter means more overhead per
## byte of voice, longer means the pause between pressing and being heard grows.
const PACKET_INTERVAL := 0.05

## Loudness that opens an open mic, and how long it stays open after dropping
## back under. Without the hangover every gap between words closes the mic and
## speech arrives as chopped fragments.
const OPEN_MIC_LEVEL := 0.045
const OPEN_MIC_HANGOVER := 0.45

## How long after somebody's last packet they still count as talking. It is the
## HUD's dial, not the audio's: a marker that vanished between packets would
## strobe at 20 Hz.
const SPEAKING_FADE := 0.4

## Seconds of a speaker's audio kept waiting to be played. Over this the oldest
## is thrown away rather than queued: a burst that arrives late is better heard
## as a gap than as everyone talking half a second behind the world.
const JITTER_CAP := 0.35

## Where a voice comes out of a body, and how the distance is scaled. The player
## fades to nothing exactly at Net.VOICE_RANGE, which is where the server stops
## relaying — so the cut-off is never audible as a pop.
const MOUTH_HEIGHT := 1.6
const UNIT_SIZE := 8.0

## Name of the bus the microphone is captured on.
const MIC_BUS := "Mic"

signal mode_changed(mode: Mode)

var mode: Mode = Mode.PUSH_TO_TALK
## False when this run has no microphone to capture (or no audio at all, which
## is every headless run and the dedicated server). Not an error state: the rest
## of voice chat still works, you just cannot talk.
var mic_ready := false
## Whether the mic is open and packets are going out right now — what the HUD
## indicator draws.
var transmitting := false
## Loudness of the last block captured, 0..1. Drives the HUD's level meter and,
## in open-mic mode, the decision to transmit at all.
var input_level := 0.0

var _capture: AudioEffectCapture
var _mic_player: AudioStreamPlayer
var _resampler := VoiceCodec.Resampler.new()
var _out := PackedFloat32Array() # captured, resampled, not yet packetised
var _hangover := 0.0
## peer -> {"queue": PackedFloat32Array, "last": msec, "player", "playback"}
var _speakers := {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_settings()
	if not _audio_available():
		return
	_setup_bus()
	_setup_mic()

func _process(delta: float) -> void:
	_hangover = maxf(0.0, _hangover - delta)
	_pump_mic()
	_pump_speakers()

## The mode switch. Deliberately read as an EVENT rather than polled, so a
## LineEdit with focus (the menu's username box) eats the key instead of
## silently flipping the mic mode while somebody types their name.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("voice_mode"):
		set_mode(Mode.PUSH_TO_TALK if mode == Mode.OPEN_MIC else Mode.OPEN_MIC)
		get_viewport().set_input_as_handled()

# ---------------- capture ----------------

## No audio at all on a headless run or the dedicated server, and nothing to
## capture there either — the server relays voice without ever decoding it.
func _audio_available() -> bool:
	if Net.should_run_dedicated():
		return false
	return DisplayServer.get_name() != "headless"

## A bus of its own for the microphone, because a capture effect has to live on
## one. Turned down to silence rather than MUTED: an inaudible bus certainly
## still runs its effects, and the capture we depend on IS an effect.
func _setup_bus() -> void:
	var idx := AudioServer.get_bus_index(MIC_BUS)
	if idx == -1:
		idx = AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, MIC_BUS)
	AudioServer.set_bus_volume_db(idx, -80.0)
	for i in AudioServer.get_bus_effect_count(idx):
		if AudioServer.get_bus_effect(idx, i) is AudioEffectCapture:
			_capture = AudioServer.get_bus_effect(idx, i)
			return
	var cap := AudioEffectCapture.new()
	cap.buffer_length = 0.5
	AudioServer.add_bus_effect(idx, cap)
	_capture = cap

func _setup_mic() -> void:
	if _capture == null:
		return
	if not ProjectSettings.get_setting("audio/driver/enable_input", false):
		# the setting is read once at startup, so this cannot be fixed from here
		push_warning("[Voice] audio/driver/enable_input is off — no microphone.")
		return
	_mic_player = AudioStreamPlayer.new()
	_mic_player.stream = AudioStreamMicrophone.new()
	_mic_player.bus = MIC_BUS
	add_child(_mic_player)
	_mic_player.play()
	mic_ready = true

## Drain the capture, packetise it, and send the packets the player meant to
## send. The drain happens whether or not the mic is open, and that is not
## wasted work: a capture buffer left to fill up hands back the room's noise
## from a minute ago the moment the button goes down, and then overflows.
func _pump_mic() -> void:
	if _capture == null:
		transmitting = false
		return
	var frames := _capture.get_frames_available()
	if frames > 0:
		var block := _capture.get_buffer(frames)
		var mono := PackedFloat32Array()
		mono.resize(block.size())
		for i in block.size():
			mono[i] = (block[i].x + block[i].y) * 0.5
		_out.append_array(_resampler.push(mono, AudioServer.get_mix_rate()))
	var per_packet := int(VoiceCodec.RATE * PACKET_INTERVAL)
	while _out.size() >= per_packet:
		var packet := _out.slice(0, per_packet)
		_out = _out.slice(per_packet)
		input_level = VoiceCodec.rms(packet)
		if mode == Mode.OPEN_MIC and input_level >= OPEN_MIC_LEVEL:
			_hangover = OPEN_MIC_HANGOVER
		if _mic_open() and _can_talk():
			Net.send_voice(VoiceCodec.encode(packet))
	transmitting = mic_ready and _mic_open() and _can_talk()

func _mic_open() -> bool:
	if mode == Mode.OPEN_MIC:
		return _hangover > 0.0
	return Input.is_action_pressed("voice_talk")

## Nothing to say until there is a world with this player standing in it — the
## server routes voice by where the speaker's pawn is, so a packet sent before
## there is one has no audience to be measured against.
func _can_talk() -> bool:
	return Net.active and Net.pawn_of(multiplayer.get_unique_id()) != null

# ---------------- playback ----------------

## A packet arrived for `from_id` — from the server's relay on a client, or
## handed straight over in-process on a listen server. The queueing happens
## whether or not this run can make a sound, so a headless test can still see
## who is being heard.
func on_voice(from_id: int, packet: PackedByteArray) -> void:
	if from_id == multiplayer.get_unique_id():
		return # you never hear yourself; the server does not send it either
	if packet.is_empty() or packet.size() > VoiceCodec.MAX_PACKET:
		return
	var row: Dictionary = _speakers.get(from_id, {"queue": PackedFloat32Array()})
	var queue: PackedFloat32Array = row["queue"]
	queue.append_array(VoiceCodec.decode(packet))
	var cap := int(VoiceCodec.RATE * JITTER_CAP)
	if queue.size() > cap:
		queue = queue.slice(queue.size() - cap)
	row["queue"] = queue
	row["last"] = Time.get_ticks_msec()
	_speakers[from_id] = row

## Feed each speaker's queue into a generator parented to their pawn, so the
## voice is a sound in the world at their body and the 3D mix does the proximity
## falloff for free.
func _pump_speakers() -> void:
	var now := Time.get_ticks_msec()
	for id: int in _speakers.keys():
		var row: Dictionary = _speakers[id]
		var queue: PackedFloat32Array = row["queue"]
		if queue.is_empty() and now - int(row["last"]) > int(SPEAKING_FADE * 1000.0):
			_drop_speaker(id)
			continue
		if queue.is_empty() or not _audio_available():
			continue
		var pb := _playback(id, row)
		if pb == null:
			row["queue"] = PackedFloat32Array() # nowhere to play it: let it go
			continue
		var n: int = mini(pb.get_frames_available(), queue.size())
		for i in n:
			pb.push_frame(Vector2(queue[i], queue[i]))
		row["queue"] = queue.slice(n)

## The generator playing at `id`'s body, built on demand. Rebuilt when the pawn
## it hung on is gone (a respawn, a reconnect) — the audio node was that pawn's
## child and went with it.
func _playback(id: int, row: Dictionary) -> AudioStreamGeneratorPlayback:
	var sp: AudioStreamPlayer3D = row.get("player")
	if is_instance_valid(sp):
		return row.get("playback") as AudioStreamGeneratorPlayback
	var pawn := Net.pawn_of(id)
	if pawn == null:
		return null
	sp = AudioStreamPlayer3D.new()
	sp.name = "Voice" # named so it is findable in the tree; an added node with
	                  # no name of its own gets an unusable "@Class@id" instead
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = float(VoiceCodec.RATE)
	gen.buffer_length = JITTER_CAP
	sp.stream = gen
	sp.position = Vector3(0.0, MOUTH_HEIGHT, 0.0)
	sp.unit_size = UNIT_SIZE
	sp.max_distance = Net.VOICE_RANGE
	sp.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	pawn.add_child(sp)
	sp.play()
	row["player"] = sp
	row["playback"] = sp.get_stream_playback()
	return row.get("playback") as AudioStreamGeneratorPlayback

func _drop_speaker(id: int) -> void:
	var row: Dictionary = _speakers.get(id, {})
	var sp: AudioStreamPlayer3D = row.get("player")
	if is_instance_valid(sp):
		sp.queue_free()
	_speakers.erase(id)

## They left, or we did. Called by Net when a peer goes and when the session
## ends; a lingering entry would otherwise keep a name on the HUD forever.
func forget(id: int) -> void:
	_drop_speaker(id)

func reset() -> void:
	for id: int in _speakers.keys():
		_drop_speaker(id)
	_resampler.reset()
	_out = PackedFloat32Array()
	_hangover = 0.0
	transmitting = false
	input_level = 0.0

# ---------------- what the HUD asks ----------------

## Is this peer being heard right now?
func talking(id: int) -> bool:
	if not _speakers.has(id):
		return false
	return Time.get_ticks_msec() - int(_speakers[id]["last"]) <= int(SPEAKING_FADE * 1000.0)

## Everybody being heard right now, for the markers over their heads.
func talking_peers() -> Array[int]:
	var out: Array[int] = []
	for id: int in _speakers:
		if talking(id):
			out.append(id)
	return out

# ---------------- mode ----------------

func set_mode(next: Mode) -> void:
	if next == mode:
		return
	mode = next
	_hangover = 0.0
	_save_settings()
	mode_changed.emit(mode)

func is_open_mic() -> bool:
	return mode == Mode.OPEN_MIC

## What to call the current mode on screen.
func mode_label() -> String:
	return "OPEN MIC" if is_open_mic() else "PUSH TO TALK"

## Shares settings.cfg with the menu's username, so a load-then-write keeps
## whatever the other section had.
func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK and bool(cfg.get_value("voice", "open_mic", false)):
		mode = Mode.OPEN_MIC

func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("voice", "open_mic", is_open_mic())
	cfg.save(SETTINGS_PATH)
