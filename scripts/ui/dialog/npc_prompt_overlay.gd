extends Control
## HUD marker for anything you can press interact at — the same trick as the
## enemy wind-up star in hud.gd (project a point in the world with the camera and
## draw a 2D shape there), but it draws a speech bubble carrying the interact
## button instead. Which button is inside follows the last device used: "E" on
## keyboard, "Y" on an Xbox pad, a drawn triangle on a PlayStation pad.
##
## It does not know what it is drawing over. Anything in `PromptTarget.GROUP`
## that answers `prompt_alpha` and `prompt_anchor()` gets one — a talkable NPC,
## the door into the catacombs, and whatever is added next. See PromptTarget.

const BUBBLE_W := 48.0
const BUBBLE_H := 38.0
const CORNER := 11.0
const TAIL_W := 13.0
const TAIL_H := 12.0
const BORDER := 2.0
const ARC_SEGMENTS := 5
const PULSE_SPEED := 3.2
const PULSE_AMOUNT := 0.05

## Drawn, not a panel — but it is still a UI surface, so it takes the palette's
## darkest shade rather than a black of its own.
const BG := Color(UiTheme.INK.r, UiTheme.INK.g, UiTheme.INK.b, 0.72)
const ACCENT := Color(1.0, 0.85, 0.25) # same gold as the enemy telegraph star

var _t := 0.0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _draw() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	for target in get_tree().get_nodes_in_group(PromptTarget.GROUP):
		if not is_instance_valid(target) or not target.has_method("prompt_anchor"):
			continue
		var a := float(target.get("prompt_alpha"))
		if a <= 0.001:
			continue
		var anchor: Vector3 = target.call("prompt_anchor")
		if cam.is_position_behind(anchor):
			continue
		_draw_bubble(cam.unproject_position(anchor), a)

## `tip` is where the tail points — the projected spot above the NPC's head.
func _draw_bubble(tip: Vector2, alpha: float) -> void:
	var fade := alpha * alpha * (3.0 - 2.0 * alpha) # smoothstep the fade in/out
	var s: float = (0.86 + 0.14 * fade) * (1.0 + PULSE_AMOUNT * sin(_t * PULSE_SPEED))
	var w := BUBBLE_W * s
	var h := BUBBLE_H * s
	var tail_h := TAIL_H * s
	var tail_w := TAIL_W * s
	var body := Rect2(tip.x - w * 0.5, tip.y - tail_h - h, w, h)

	var bg := BG
	bg.a *= fade
	var line := ACCENT
	line.a *= fade * 0.9

	# body and tail are one closed path, so the outline runs round the whole
	# silhouette instead of cutting a seam where the tail meets the box
	var path := _bubble_path(body, CORNER * s, tip, tail_w)
	var tris := Geometry2D.triangulate_polygon(path)
	for i in range(0, tris.size(), 3):
		draw_colored_polygon(PackedVector2Array([
				path[tris[i]], path[tris[i + 1]], path[tris[i + 2]]]), bg)
	var outline := path.duplicate()
	outline.append(path[0])
	draw_polyline(outline, line, BORDER * s, true)

	var glyph := ACCENT
	glyph.a = fade
	if InputDevice.uses_shape_glyph():
		_draw_triangle(body.get_center(), h * 0.30, glyph, maxf(2.0 * s, 1.0))
	else:
		_draw_letter(body, InputDevice.interact_letter(), glyph, s)

## Closed clockwise outline of the speech bubble: a rounded box whose bottom
## edge dips down into a tail that points at `tip`.
func _bubble_path(body: Rect2, r: float, tip: Vector2, tail_w: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var x1 := body.position.x
	var y1 := body.position.y
	var x2 := body.end.x
	var y2 := body.end.y
	_arc(pts, Vector2(x1 + r, y1 + r), r, PI, PI * 1.5)         # top-left
	_arc(pts, Vector2(x2 - r, y1 + r), r, PI * 1.5, TAU)        # top-right
	_arc(pts, Vector2(x2 - r, y2 - r), r, 0.0, PI * 0.5)        # bottom-right
	pts.append(Vector2(tip.x + tail_w * 0.5, y2))
	pts.append(tip)
	pts.append(Vector2(tip.x - tail_w * 0.5, y2))
	_arc(pts, Vector2(x1 + r, y2 - r), r, PI * 0.5, PI)         # bottom-left
	return pts

static func _arc(into: PackedVector2Array, c: Vector2, r: float, from: float, to: float) -> void:
	for i in ARC_SEGMENTS + 1:
		var a: float = lerpf(from, to, float(i) / ARC_SEGMENTS)
		into.append(c + Vector2(cos(a), sin(a)) * r)

func _draw_letter(body: Rect2, text: String, color: Color, s: float) -> void:
	var font := get_theme_default_font()
	var size := int(round(21.0 * s))
	var metrics := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, size)
	# get_string_size gives the advance box; centre on the ascent for optical fit
	var origin := Vector2(body.position.x,
			body.get_center().y + (font.get_ascent(size) - metrics.y * 0.5))
	draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_CENTER, body.size.x, size, color)

## PlayStation's triangle face button, pointing up and centred on `c`.
func _draw_triangle(c: Vector2, r: float, color: Color, width: float) -> void:
	var pts := PackedVector2Array()
	for i in 3:
		var ang := -PI / 2.0 + TAU * i / 3.0
		pts.append(c + Vector2(cos(ang), sin(ang)) * r)
	pts.append(pts[0])
	draw_polyline(pts, color, width, true)
