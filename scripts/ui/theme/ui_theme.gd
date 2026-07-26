class_name UiTheme
extends RefCounted
## The look of every screen in the game, in ONE place: three greys and one
## sheet of cracked paint. No panel anywhere may mix its own background colour
## again — six screens each inventing their own black is exactly how they
## drifted apart, and a palette that lives in six files is not a palette.
##
## The three shades are a depth order, not a set of options. Pick by how far
## FORWARD the thing sits, never by taste:
##
##   INK   #232323 — the sheet everything is built on: full-screen backdrops
##                   and the body of a panel. The furthest back.
##   SLATE #343434 — anything sitting ON a panel: rows, tabs, slots, fields.
##   STONE #464646 — edges, and the piece you want to read as raised: a
##                   panel's border, a row under the pointer.
##
## Gold (`0.95, 0.79, 0.42`) is NOT in here on purpose. It is the game's
## "pay attention" accent — the wind-up star, the quest marker, an NPC bubble —
## and it means something. These three mean nothing at all, which is the job:
## they are the paper, not the writing.

## The sheet of cracked paint behind every screen. Missing art is survivable —
## everything falls back to the flat shade — because a texture that fails to
## load must never take a menu down with it.
const TEXTURE_PATH := "res://Assets/Textures/UI/panel_grunge.jpg"

const INK := Color("232323")
const SLATE := Color("343434")
const STONE := Color("464646")

## The sheet's own average grey. A tint MULTIPLIES the texture, so painting it
## with a shade straight would land the result far under that shade (0.14 * 0.56
## is nearly black); dividing by this first is what makes a sheet tinted INK
## actually average out AT INK, with the cracks reading as variation either
## side of it instead of as a wash of darkness.
const SHEET_MEAN := 0.56

## How strongly the grain reads over a panel body. Text sits on this, so it is
## deliberately faint — the paint is meant to be felt, not read.
const PANEL_GRAIN := 0.30
## Panels are this opaque over the world unless a screen says otherwise.
const PANEL_ALPHA := 0.94
## ...and a full-screen backdrop hides this much of the world behind it. There
## is no text on it, so the sheet is drawn at full strength.
const BACKDROP_ALPHA := 0.72

## Rows, tabs and slots resting on a panel body, and the same row lit up.
const ROW_ALPHA := 0.55
const ROW_HOT_ALPHA := 0.9

static var _sheet: Texture2D = null
static var _sheet_looked_up := false

## The cracked paint, or null if the file is gone. Looked up once: a texture
## that isn't there must not hit the disk again for every row of every screen.
static func sheet_texture() -> Texture2D:
	if not _sheet_looked_up:
		_sheet_looked_up = true
		if ResourceLoader.exists(TEXTURE_PATH):
			_sheet = load(TEXTURE_PATH)
		else:
			push_warning("UiTheme: no UI sheet at %s" % TEXTURE_PATH)
	return _sheet

## The same colour at a different opacity — every screen wants the palette at
## some alpha, and none of them should be re-typing the channels to get it.
static func tint(shade: Color, alpha: float) -> Color:
	return Color(shade.r, shade.g, shade.b, alpha)

## A full-rect sheet of the paint, tinted to average out at `shade`. `alpha` is
## how much of it lands: full for a backdrop, a whisper over a panel body.
## Falls back to a flat rectangle of the shade when the art is missing, so the
## screen is always built either way.
static func sheet(shade := INK, alpha := 1.0) -> Control:
	var tex := sheet_texture()
	if tex == null:
		var flat := ColorRect.new()
		flat.color = tint(shade, alpha)
		flat.set_anchors_preset(Control.PRESET_FULL_RECT)
		flat.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return flat
	var rect := TextureRect.new()
	rect.texture = tex
	# IGNORE_SIZE keeps the sheet out of the layout entirely: a panel is sized
	# by its content, and a 960px backdrop must never be what decides how wide
	# the shop is.
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.modulate = Color(shade.r / SHEET_MEAN, shade.g / SHEET_MEAN,
			shade.b / SHEET_MEAN, alpha)
	return rect

## The dark sheet behind an open panel — what used to be a flat black dim.
static func backdrop(alpha := BACKDROP_ALPHA) -> Control:
	return sheet(INK, alpha)

## A framed panel: the grey body, the paint over it, a STONE edge, rounded
## corners. Content goes into `body(frame)` — NEVER onto the frame itself, or
## it lands beside the sheet instead of on top of it.
##
## The padding lives in that inner margin rather than in the stylebox on
## purpose: a PanelContainer fits its children to the rect MINUS the style's
## content margins, so padding written the obvious way would inset the sheet
## too and leave an untextured border ring around every screen.
static func panel(shade := INK, alpha := PANEL_ALPHA,
		pad := Vector4i(24, 24, 18, 16), edge := STONE) -> PanelContainer:
	var frame := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = tint(shade, alpha)
	style.border_color = edge
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	frame.add_theme_stylebox_override("panel", style)
	frame.clip_contents = true # the paint stops at the frame
	frame.add_child(sheet(shade, PANEL_GRAIN)) # child 0: drawn under the content
	var body := MarginContainer.new()
	body.add_theme_constant_override("margin_left", pad.x)
	body.add_theme_constant_override("margin_right", pad.y)
	body.add_theme_constant_override("margin_top", pad.z)
	body.add_theme_constant_override("margin_bottom", pad.w)
	frame.add_child(body)
	return frame

## Where a panel's content goes.
static func body(frame: PanelContainer) -> Container:
	return frame.get_child(1) as Container

## A row, tab or slot resting on a panel body. `hot` is the same row with the
## pointer or focus on it: one step forward in the palette, never a colour of
## its own.
static func row_fill(hot := false) -> Color:
	return tint(STONE, ROW_HOT_ALPHA) if hot else tint(SLATE, ROW_ALPHA)
