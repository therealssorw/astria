extends Control
class_name QuestMarkerOverlay
## The gold star that leads you to your current quest, with how far away it is
## underneath it. Added by `hud.gd`; draws nothing at all when you have no
## quest, or when the quest's target is not in this level.
##
## Camera-projected and vector-drawn, the same technique as the enemy wind-up
## star in `hud.gd` and the NPC speech bubble in `npc_prompt_overlay.gd` — and
## deliberately the same star polygon and the same gold, because gold is the
## HUD's "pay attention" colour and a quest is exactly that. Godot's default
## font has no U+2605, so a typed star is tofu; every symbol here is drawn.
##
## The star does not vanish when the objective is off screen — that is when it
## is doing its job. It slides to the edge of the screen in the direction you
## would have to turn, so following it is just "keep the star ahead of you".
##
## Purely local: which way one player's screen points at their own quest is
## nobody else's business, and the quest itself is server-owned (GameStats.quest
## is a read-only mirror).

const GOLD := Color(0.95, 0.79, 0.42)
const STAR_OUTER := 11.0
const STAR_INNER := 4.9
## How far in from the screen edge a clamped star sits, so the whole star and
## its distance label stay on screen instead of half-hanging off it.
const EDGE_INSET := Vector2(46.0, 54.0)
## Star drawn dimmer while the objective is behind you or off to the side, so a
## marker you are facing reads as "this one" at a glance.
const OFFSCREEN_ALPHA := 0.62
const LABEL_SIZE := 14
const LABEL_GAP := 15.0

var _player: Node3D

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var quest := str(GameStats.quest)
	if quest == "":
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var target: Variant = QuestData.target_pos(get_tree(), quest)
	if target == null:
		return # the place this quest points at is not in this level
	var world: Vector3 = target

	var rect := Rect2(Vector2.ZERO, get_viewport_rect().size)
	var placed := place_marker(cam.unproject_position(world),
			cam.is_position_behind(world), rect)
	var at: Vector2 = placed["pos"]
	var on_screen: bool = placed["on_screen"]

	var color := Color(GOLD.r, GOLD.g, GOLD.b, 1.0 if on_screen else OFFSCREEN_ALPHA)
	draw_colored_polygon(_star_points(at, STAR_OUTER), color)
	_draw_distance(at, world, color)

## Where the star goes, given the raw projection of the target.
##
## Kept pure (no camera, no tree) so the awkward half — a target BEHIND the
## camera, whose unprojection lands mirrored through the centre and would
## otherwise send the star the wrong way round the screen — can be tested
## without standing a camera up in a headless run.
static func place_marker(raw: Vector2, behind: bool, rect: Rect2) -> Dictionary:
	var center := rect.size * 0.5
	var p := raw
	if behind:
		p = center * 2.0 - p
	var inset := Rect2(rect.position + EDGE_INSET, rect.size - EDGE_INSET * 2.0)
	if not behind and inset.has_point(p):
		return {"pos": p, "on_screen": true}
	return {"pos": _to_edge(p, center, inset), "on_screen": false}

## Slide a point out from the centre until it lands on the inset rect's edge,
## keeping its direction — which is the direction you have to turn.
static func _to_edge(p: Vector2, center: Vector2, inset: Rect2) -> Vector2:
	var d := p - center
	if d.length_squared() < 0.0001:
		d = Vector2(0, -1) # dead ahead but not visible: park it at the top
	var half := inset.size * 0.5
	var scale := minf(half.x / maxf(absf(d.x), 0.0001), half.y / maxf(absf(d.y), 0.0001))
	return center + d * scale

func _draw_distance(at: Vector2, world: Vector3, color: Color) -> void:
	var font := get_theme_default_font()
	if font == null:
		return
	if not is_instance_valid(_player):
		_player = _local_pawn()
		if _player == null:
			return
	var text := "%d m" % int(round(_player.global_position.distance_to(world)))
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE).x
	var pos := at + Vector2(-w * 0.5, LABEL_GAP + LABEL_SIZE)
	# outline first, then the text over it: the distance has to stay readable
	# against bright sky and water without a panel boxing it in
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE,
			4, Color(0, 0, 0, 0.75 * color.a))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, color)

func _local_pawn() -> Node3D:
	var found := get_tree().get_nodes_in_group("local_player")
	return found[0] as Node3D if found.size() > 0 else null

func _star_points(center: Vector2, outer: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var inner := outer * (STAR_INNER / STAR_OUTER)
	for i in 10:
		var r := outer if i % 2 == 0 else inner
		var a := -PI / 2.0 + TAU * i / 10.0
		pts.append(center + Vector2(cos(a), sin(a)) * r)
	return pts
