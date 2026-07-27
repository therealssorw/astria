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
## head height; everything else is a body impact at chest height.
const VOICE_Y := 1.4
const BODY_Y := 1.2
## A parry is a block landing perfectly, so it is the same thud pitched up.
const PARRY_PITCH := 1.25

var grunt: AudioStreamPlayer3D    # one random grunt per unblocked hit
var impact: AudioStreamPlayer3D   # a punch getting through
var block: AudioStreamPlayer3D    # the guard eating one
var death: AudioStreamPlayer3D
var woosh: AudioStreamPlayer3D    # any swing starting, hit or miss

## `streams` is name -> AudioStream, straight off the fighter's exports.
func _init(host: Node, streams: Dictionary) -> void:
	grunt = _build(host, streams.get("grunt"), VOICE_Y)
	impact = _build(host, streams.get("impact"), BODY_Y)
	block = _build(host, streams.get("block"), BODY_Y)
	death = _build(host, streams.get("death"), BODY_Y)
	woosh = _build(host, streams.get("woosh"), BODY_Y)

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
	_play(death)

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
