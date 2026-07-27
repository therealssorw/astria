class_name FighterAudio
extends RefCounted
## Every noise a fighter makes, and the rules about which one plays. Shared by
## the player and the bandits, because both built the same five
## AudioStreamPlayer3Ds from the same six lines each — and both wrote out "does
## a block sound like a block" in the middle of their own damage code, with the
## two copies already slightly different.
##
## The streams themselves stay as `@export`s on the fighter: they are
## per-character art, and a character is what the editor tunes. This owns only
## the PLAYERS built from them, so a stream left unassigned is a normal state
## and simply makes no sound.

## Where on the body each noise comes from. A grunt is a voice, so it sits at
## head height; everything else is a body impact at chest height, and footsteps
## come off the floor.
const VOICE_Y := 1.4
const BODY_Y := 1.2
const FOOT_Y := 0.15
## A parry is a block landing perfectly, so it is the same thud pitched up.
const PARRY_PITCH := 1.25
## How far a footstep carries. Deliberately shorter than a voice: hearing
## something enormous walking is the point, hearing it across the island is not.
const STEP_RANGE := 22.0

## The bus a deep voice is sent down, built on demand (see `ensure_voice_bus`).
## A big character is not just a pitched-down small one — the room answers it —
## and reverb is a bus effect, so there has to be a bus to put it on.
const VOICE_BUS := "BigVoice"
const VOICE_ROOM_SIZE := 0.85
const VOICE_WET := 0.42
const VOICE_DAMPING := 0.35

var grunt: AudioStreamPlayer3D    # one random grunt per unblocked hit
var impact: AudioStreamPlayer3D   # a punch getting through
var block: AudioStreamPlayer3D    # the guard eating one
var death: AudioStreamPlayer3D
var woosh: AudioStreamPlayer3D    # any swing starting, hit or miss
## A shout, for a fighter big enough to make one: not a reaction to anything, but
## something it does on purpose (the juggernaut's entrance, and each of its big
## moves). Nothing else in the game has one, and a fighter without the stream
## simply never yells.
var yell: AudioStreamPlayer3D
## Footfalls while it is moving — a LOOP, ticked with the ground speed rather
## than fired per step: nothing in this project knows when a foot lands, and a
## clip that stops when the character stops reads correctly anyway.
var steps: AudioStreamPlayer3D

## `streams` is name -> AudioStream, straight off the fighter's exports. `opts`
## is the shape of the VOICE, which is a per-character thing rather than a
## per-clip one: "voice_pitch" slows everything it says down (0.55 is the
## juggernaut, which is the ordinary bandit grunts made enormous), and
## "voice_reverb" puts them in a room.
func _init(host: Node, streams: Dictionary, opts := {}) -> void:
	grunt = _build(host, streams.get("grunt"), VOICE_Y)
	impact = _build(host, streams.get("impact"), BODY_Y)
	block = _build(host, streams.get("block"), BODY_Y)
	death = _build(host, streams.get("death"), BODY_Y)
	woosh = _build(host, streams.get("woosh"), BODY_Y)
	yell = _build(host, streams.get("yell"), VOICE_Y)
	steps = _build(host, streams.get("steps"), FOOT_Y)
	if steps:
		steps.max_distance = STEP_RANGE
		# an imported mp3 does not loop by default, and a walk cycle has to
		_loop(steps.stream)
	_shape_voice(opts)

## The voice players — and ONLY those. An impact is the world hitting a body and
## a footstep is the floor; neither belongs to whoever is making them, so neither
## gets pitched or sent to the room.
func _shape_voice(opts: Dictionary) -> void:
	var pitch := float(opts.get("voice_pitch", 1.0))
	var bus := VOICE_BUS if bool(opts.get("voice_reverb", false)) else ""
	if is_equal_approx(pitch, 1.0) and bus == "":
		return
	if bus != "":
		ensure_voice_bus()
	for p: AudioStreamPlayer3D in [grunt, death, yell]:
		if p == null:
			continue
		p.pitch_scale = pitch
		if bus != "":
			p.bus = bus

## Builds the reverb bus the first time anything asks for it, and leaves it alone
## afterwards. Made here rather than in a saved bus layout on purpose: a layout
## file is a thing to keep in step by hand, and this is the only effect the game
## has ever needed.
static func ensure_voice_bus() -> void:
	if AudioServer.get_bus_index(VOICE_BUS) >= 0:
		return
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, VOICE_BUS)
	AudioServer.set_bus_send(idx, "Master")
	var verb := AudioEffectReverb.new()
	verb.room_size = VOICE_ROOM_SIZE
	verb.wet = VOICE_WET
	verb.damping = VOICE_DAMPING
	AudioServer.add_bus_effect(idx, verb)

static func _loop(stream: AudioStream) -> void:
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD

static func _build(host: Node, stream: AudioStream, y: float) -> AudioStreamPlayer3D:
	if stream == null:
		return null
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.position.y = y
	host.add_child(p)
	return p

static func _play(p: AudioStreamPlayer3D) -> void:
	if p:
		p.play()

func play_swing() -> void:
	_play(woosh)

func play_death() -> void:
	stop_steps()
	_play(death)

## Something big announcing itself. Deliberately not queued behind anything: a
## shout that lands late has missed the thing it was announcing.
func play_yell() -> void:
	if yell and not yell.playing:
		yell.play()

## Feet, driven by how fast the body is actually moving — the same "measure it
## rather than be told" the NPC walk cycle uses, so anything that MOVES this
## fighter gets footsteps with no code at the other end. `ratio` is ground speed
## over the character's own walk speed.
func tick_steps(ratio: float, moving_above := 0.15) -> void:
	if steps == null:
		return
	if ratio <= moving_above:
		stop_steps()
		return
	# stride rate follows the real speed, within a band: below it a walk sounds
	# like a stagger, above it like a sprint the animation never plays
	steps.pitch_scale = clampf(ratio, 0.7, 1.6)
	if not steps.playing:
		steps.play()

func stop_steps() -> void:
	if steps and steps.playing:
		steps.stop()

## Only a hit that got THROUGH voices the character, and a lethal one voices the
## death sound instead — so the two never overlap.
func play_grunt(alive: bool) -> void:
	if alive:
		_play(grunt)

## A hit the guard ate thuds off the block; only one that got through sounds
## like flesh. A parry is that same thud pitched up — it IS a block, just a
## perfect one, and the gold flash and the banner carry the rest of the read.
func play_impact(result: int) -> void:
	if result == Player.Guard.BLOCKED or result == Player.Guard.PARRIED:
		if block:
			block.pitch_scale = PARRY_PITCH if result == Player.Guard.PARRIED else 1.0
			block.play()
	else:
		_play(impact)
