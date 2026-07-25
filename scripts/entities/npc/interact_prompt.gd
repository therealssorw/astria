extends Node3D
class_name InteractPrompt
## Floating "press this button" badge that hovers in front of an NPC.
## The badge art is generated procedurally (rounded translucent plate, plus a
## drawn triangle for PlayStation pads) so no texture assets are needed, and it
## swaps automatically when the player switches between keyboard and gamepad.

const TEX_SIZE := 128
const CORNER_RADIUS := 26.0
const BORDER := 6.0
const PIXEL_SIZE := 0.0032
const FADE_SPEED := 7.0
const BOB_HEIGHT := 0.05
const BOB_SPEED := 2.2

static var _tex_cache := {}

var badge: Sprite3D
var letter: Label3D
var caption: Label3D

var _shown := false
var _alpha := 0.0
var _t := 0.0
var _base_y := 0.0

func _init(action_text := "") -> void:
	badge = Sprite3D.new()
	badge.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	badge.shaded = false
	badge.pixel_size = PIXEL_SIZE
	badge.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	badge.render_priority = 1
	add_child(badge)

	letter = Label3D.new()
	letter.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	letter.font_size = 110
	letter.pixel_size = PIXEL_SIZE
	letter.outline_size = 0
	letter.render_priority = 2
	letter.modulate = Color(1, 1, 1)
	add_child(letter)

	caption = Label3D.new()
	caption.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	caption.font_size = 48
	caption.pixel_size = PIXEL_SIZE
	caption.outline_size = 14
	caption.outline_modulate = Color(0, 0, 0, 0.85)
	caption.position.y = -0.29
	caption.render_priority = 2
	caption.text = action_text
	caption.visible = action_text != ""
	add_child(caption)

func _ready() -> void:
	_base_y = position.y
	InputDevice.kind_changed.connect(_refresh_glyph)
	_refresh_glyph(InputDevice.kind)
	_apply_alpha(0.0)
	visible = false
	set_process(true)

func _process(delta: float) -> void:
	var target := 1.0 if _shown else 0.0
	_alpha = move_toward(_alpha, target, FADE_SPEED * delta)
	if _alpha <= 0.0:
		visible = false
		return
	visible = true
	_t += delta
	position.y = _base_y + sin(_t * BOB_SPEED) * BOB_HEIGHT
	_apply_alpha(_alpha)

## Fade the badge in/out instead of popping it.
func show_prompt(on: bool) -> void:
	if _shown == on:
		return
	_shown = on
	if on:
		_t = 0.0

func set_caption(text: String) -> void:
	caption.text = text
	caption.visible = text != ""

func _apply_alpha(a: float) -> void:
	var eased := a * a * (3.0 - 2.0 * a) # smoothstep, so the fade reads softer
	badge.modulate = Color(1, 1, 1, eased)
	letter.modulate = Color(1, 1, 1, eased)
	caption.modulate = Color(1, 1, 1, eased * 0.85)
	var s := 0.85 + 0.15 * eased
	badge.scale = Vector3(s, s, s)
	letter.scale = badge.scale
	caption.scale = badge.scale

func _refresh_glyph(kind: InputDeviceTracker.Kind) -> void:
	badge.texture = _badge_texture(kind)
	letter.text = InputDevice.interact_letter()
	letter.visible = letter.text != ""

# ---------------- procedural badge art ----------------

static func _badge_texture(kind: InputDeviceTracker.Kind) -> Texture2D:
	if _tex_cache.has(kind):
		return _tex_cache[kind]
	var img := Image.create_empty(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	_draw_plate(img)
	if kind == InputDeviceTracker.Kind.PLAYSTATION:
		_draw_triangle(img)
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[kind] = tex
	return tex

## Rounded translucent black plate with a soft light border.
static func _draw_plate(img: Image) -> void:
	var half := TEX_SIZE * 0.5
	var center := Vector2(half, half)
	var extent := Vector2(half - 3.0, half - 3.0)
	var fill := Color(0.02, 0.02, 0.03, 0.72)
	var border := Color(0.92, 0.93, 1.0, 0.95)
	for y in TEX_SIZE:
		for x in TEX_SIZE:
			var d := _rounded_box_sdf(Vector2(x + 0.5, y + 0.5) - center, extent, CORNER_RADIUS)
			if d > 1.0:
				continue
			var outer := 1.0 - smoothstep(-1.0, 1.0, d)              # inside the plate
			var inner := 1.0 - smoothstep(-1.0, 1.0, d + BORDER)     # inside the fill
			var c := border
			c.a *= outer * (1.0 - inner)
			var f := fill
			f.a *= inner
			img.set_pixel(x, y, _over(c, f))

## PlayStation's triangle face button, stroked so it reads at a distance.
static func _draw_triangle(img: Image) -> void:
	var a := Vector2(64, 33)
	var b := Vector2(35, 84)
	var c := Vector2(93, 84)
	var stroke := 4.5
	var col := Color(0.38, 0.93, 0.78, 1.0)
	for y in TEX_SIZE:
		for x in TEX_SIZE:
			var p := Vector2(x + 0.5, y + 0.5)
			var d: float = minf(minf(_seg_dist(p, a, b), _seg_dist(p, b, c)), _seg_dist(p, c, a))
			var cov := 1.0 - smoothstep(stroke - 1.0, stroke + 1.0, d)
			if cov <= 0.0:
				continue
			var src := col
			src.a = cov
			img.set_pixel(x, y, _over(src, img.get_pixel(x, y)))

static func _rounded_box_sdf(p: Vector2, extent: Vector2, r: float) -> float:
	var q := Vector2(absf(p.x), absf(p.y)) - extent + Vector2(r, r)
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - r

static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)

## Straight alpha "source over destination" composite.
static func _over(src: Color, dst: Color) -> Color:
	var out_a := src.a + dst.a * (1.0 - src.a)
	if out_a <= 0.0001:
		return Color(0, 0, 0, 0)
	var rgb := (Vector3(src.r, src.g, src.b) * src.a
			+ Vector3(dst.r, dst.g, dst.b) * dst.a * (1.0 - src.a)) / out_a
	return Color(rgb.x, rgb.y, rgb.z, out_a)
