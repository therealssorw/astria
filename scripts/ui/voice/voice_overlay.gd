extends Control
## Everything voice chat draws: a microphone in the corner for your own mic, and
## the same microphone over the head of anybody being heard right now. One glyph
## in two places on purpose — it means "a mic is open", wherever it appears.
##
## Vector-drawn and camera-projected like every other in-world marker (the
## enemy wind-up star, the NPC bubble), so there is no glyph texture. Gold is
## the game's "pay attention", which is what somebody talking is.

const ACCENT := Color(1.0, 0.85, 0.25) # the same gold as the telegraph star
const QUIET := Color(1.0, 1.0, 1.0, 0.35) # an open mic that nobody is using
const ALARM := Color(1.0, 0.4, 0.3) # there is no microphone to talk into
const HINT := Color(1.0, 1.0, 1.0, 0.4) # matches hud.gd's own corner hint

const MARGIN := Vector2(34.0, 62.0) # up from the bottom-left, over the P hint
const GLYPH_W := 9.0
const GLYPH_H := 14.0
const METER_W := 46.0
const METER_H := 4.0
## Loudness that fills the meter. Speech sits well under 1.0 — an rms of 0.3 is
## already shouting — so a meter scaled 0..1 would never move.
const METER_FULL := 0.35
const ARC_SEGMENTS := 7
const HEAD_HEIGHT := 2.95 # above the nametag, which sits at 2.3
const PULSE_SPEED := 5.0

var _t := 0.0

func _ready() -> void:
	# by hand, NOT set_anchors_preset: that keeps the control's current rect,
	# which for a code-built Control is 0x0, and the corner indicator is placed
	# off the bottom of `size`. The projected markers would have survived it —
	# a _draw() is not clipped to the rect — which is exactly why it is the kind
	# of bug that only shows up in a screenshot.
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _draw() -> void:
	_draw_own_mic()
	_draw_talkers()

# ---------------- your own microphone ----------------

func _draw_own_mic() -> void:
	var trying := Voice.transmitting or (not Voice.mic_ready and Input.is_action_pressed("voice_talk"))
	# push-to-talk shows nothing until it is pressed; an open mic is always drawn,
	# because a hot mic the player has forgotten about is the thing to avoid
	if not trying and not Voice.is_open_mic():
		return
	var at := Vector2(MARGIN.x, size.y - MARGIN.y)
	if not Voice.mic_ready:
		_draw_mic(at, 1.0, ALARM)
		_draw_slash(at, 1.0, ALARM)
		_label(at, "no microphone", ALARM)
		return
	var live := Voice.transmitting
	var pulse: float = 1.0 + (0.06 * sin(_t * PULSE_SPEED) if live else 0.0)
	_draw_mic(at, pulse, ACCENT if live else QUIET)
	_draw_meter(at, live)
	if Voice.is_open_mic():
		_label(at, "open mic", ACCENT if live else HINT)

func _draw_meter(at: Vector2, live: bool) -> void:
	var x := at.x + GLYPH_W * 0.9 + 6.0
	var y := at.y - METER_H * 0.5
	var back := Rect2(x, y, METER_W, METER_H)
	draw_rect(back, Color(1, 1, 1, 0.12))
	var fill: float = clampf(Voice.input_level / METER_FULL, 0.0, 1.0)
	if fill > 0.0:
		draw_rect(Rect2(x, y, METER_W * fill, METER_H), ACCENT if live else QUIET)

func _label(at: Vector2, text: String, color: Color) -> void:
	var font := get_theme_default_font()
	draw_string(font, Vector2(at.x + GLYPH_W * 0.9 + 6.0, at.y + 16.0), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, color)

# ---------------- whoever is talking out there ----------------

func _draw_talkers() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	for id in Voice.talking_peers():
		var pawn := Net.pawn_of(id)
		if pawn == null or not is_instance_valid(pawn):
			continue
		if pawn.is_local:
			continue # your own mic is the corner indicator, not a marker on you
		var head: Vector3 = pawn.global_position + Vector3(0.0, HEAD_HEIGHT, 0.0)
		if cam.is_position_behind(head):
			continue
		var at := cam.unproject_position(head)
		var s: float = 1.0 + 0.08 * sin(_t * PULSE_SPEED)
		_draw_mic(at, s, ACCENT)
		_draw_waves(at, s, ACCENT)

# ---------------- the glyph ----------------

## A microphone: a capsule for the head, a cradle under it, and a stem. `s`
## scales the whole thing about `c`.
func _draw_mic(c: Vector2, s: float, color: Color) -> void:
	var w := GLYPH_W * s
	var h := GLYPH_H * s
	var head := Vector2(c.x, c.y - h * 0.18)
	draw_colored_polygon(_capsule(head, w, h * 0.8), color)
	var cradle_r := w * 0.78
	var cradle_c := Vector2(c.x, c.y - h * 0.06)
	var cradle := PackedVector2Array()
	_arc(cradle, cradle_c, cradle_r, 0.0, PI)
	draw_polyline(cradle, color, maxf(1.6 * s, 1.0), true)
	var foot := cradle_c.y + cradle_r
	draw_line(Vector2(c.x, foot), Vector2(c.x, foot + h * 0.24), color,
			maxf(1.6 * s, 1.0), true)

## Closed outline of a vertical capsule centred on `c`: a semicircle over the
## top, another under the bottom, joined down the sides.
func _capsule(c: Vector2, w: float, h: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var r := w * 0.5
	var span: float = maxf(h * 0.5 - r, 0.0)
	_arc(pts, Vector2(c.x, c.y - span), r, PI, TAU)  # over the top
	_arc(pts, Vector2(c.x, c.y + span), r, 0.0, PI)  # under the bottom
	return pts

## Two arcs off the mic's right shoulder — sound coming out of it.
func _draw_waves(c: Vector2, s: float, color: Color) -> void:
	var from := Vector2(c.x + GLYPH_W * 0.75 * s, c.y - GLYPH_H * 0.18 * s)
	for i in 2:
		var pts := PackedVector2Array()
		_arc(pts, from, (4.0 + 4.0 * float(i)) * s, -PI * 0.42, PI * 0.42)
		var faded := color
		faded.a *= 0.85 - 0.3 * float(i)
		draw_polyline(pts, faded, maxf(1.5 * s, 1.0), true)

## A stroke through the glyph: this mic does not exist.
func _draw_slash(c: Vector2, s: float, color: Color) -> void:
	var r := GLYPH_H * 0.62 * s
	draw_line(c + Vector2(-r, r) * 0.7, c + Vector2(r, -r) * 0.7, color,
			maxf(1.8 * s, 1.0), true)

static func _arc(into: PackedVector2Array, c: Vector2, r: float,
		from: float, to: float) -> void:
	for i in ARC_SEGMENTS + 1:
		var a: float = lerpf(from, to, float(i) / float(ARC_SEGMENTS))
		into.append(c + Vector2(cos(a), sin(a)) * r)
