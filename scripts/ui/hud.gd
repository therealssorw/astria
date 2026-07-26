extends CanvasLayer
## Code-built HUD: HP bar, stamina bar, quest heading, lock-on reticle, hold-P
## scoreboard, death overlay. Binds to the LOCAL player's pawn (group
## "local_player").

const SCOREBOARD := preload("res://scripts/ui/scoreboard.gd")
const NPC_PROMPTS := preload("res://scripts/ui/dialog/npc_prompt_overlay.gd")
const QUEST_TRACKER := preload("res://scripts/ui/quest/quest_tracker.gd")
const QUEST_MARKER := preload("res://scripts/ui/quest/quest_marker_overlay.gd")
const TUTORIAL_OVERLAY := preload("res://scripts/ui/tutorial/tutorial_overlay.gd")

var player: Player
var hp_fill: ColorRect
var stam_fill: ColorRect
var reticle: Control
var combat_fx: Control
var death_overlay: Control

const BAR_W := 280.0
## The stamina bar doubles as the guard meter — it reads as one while blocking,
## and as a warning the moment the guard is gone.
const STAMINA_COLOR := Color(0.95, 0.8, 0.25)
const GUARD_COLOR := Color(0.45, 0.72, 1.0)
const BROKEN_COLOR := Color(1.0, 0.35, 0.2)

func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	hp_fill = _bar(root, Vector2(24, 24), Color(0.85, 0.2, 0.2))
	stam_fill = _bar(root, Vector2(24, 52), Color(0.95, 0.8, 0.25))

	reticle = ReticleControl.new()
	reticle.set_anchors_preset(Control.PRESET_FULL_RECT)
	reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(reticle)

	combat_fx = CombatFxControl.new()
	combat_fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	combat_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(combat_fx)

	var telegraph := TelegraphControl.new()
	telegraph.set_anchors_preset(Control.PRESET_FULL_RECT)
	telegraph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(telegraph)

	root.add_child(NPC_PROMPTS.new())
	root.add_child(QUEST_MARKER.new())
	root.add_child(QUEST_TRACKER.new())
	var tut_overlay: Control = TUTORIAL_OVERLAY.new()
	tut_overlay.name = "TutorialOverlay" # found by name from the tutorial test
	root.add_child(tut_overlay)
	root.add_child(SCOREBOARD.new())
	_build_death_overlay(root)

	var hint := Label.new()
	hint.text = "hold P — scoreboard"
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hint.position = Vector2(24, -32)
	root.add_child(hint)

func _build_death_overlay(root: Control) -> void:
	death_overlay = Control.new()
	death_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	death_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	death_overlay.visible = false
	root.add_child(death_overlay)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.1, 0, 0, 0.35)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	death_overlay.add_child(dim)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	death_overlay.add_child(box)
	var died := Label.new()
	died.text = "YOU DIED"
	died.add_theme_font_size_override("font_size", 64)
	died.add_theme_color_override("font_color", Color(0.85, 0.2, 0.2))
	died.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(died)
	var sub := Label.new()
	sub.text = "respawning..."
	sub.add_theme_font_size_override("font_size", 16)
	sub.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)

func _bar(parent: Control, pos: Vector2, color: Color) -> ColorRect:
	var bg := ColorRect.new()
	bg.position = pos
	bg.size = Vector2(BAR_W, 20)
	bg.color = UiTheme.tint(UiTheme.INK, 0.55)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bg)
	var fill := ColorRect.new()
	fill.position = Vector2(2, 2)
	fill.size = Vector2(BAR_W - 4, 16)
	fill.color = color
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(fill)
	return fill

func _process(_delta: float) -> void:
	if not is_instance_valid(player):
		var players := get_tree().get_nodes_in_group("local_player")
		if players.size() > 0:
			player = players[0]
			(reticle as ReticleControl).player = player
			(combat_fx as CombatFxControl).player = player
		return
	hp_fill.size.x = (BAR_W - 4) * clampf(player.health / player.max_health, 0.0, 1.0)
	stam_fill.size.x = (BAR_W - 4) * clampf(player.stamina / player.max_stamina, 0.0, 1.0)
	if player.stagger_time > 0.0:
		stam_fill.color = BROKEN_COLOR
	elif player.blocking:
		stam_fill.color = GUARD_COLOR
	else:
		stam_fill.color = STAMINA_COLOR
	death_overlay.visible = player.dead


class TelegraphControl:
	extends Control
	## Small star above an enemy's head that lights up during its attack wind-up.

	const STAR_OUTER := 9.0
	const STAR_INNER := 4.0

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var cam := get_viewport().get_camera_3d()
		if cam == null:
			return
		for e in get_tree().get_nodes_in_group("enemies"):
			if not is_instance_valid(e) or e.get("dead"):
				continue
			if not e.has_method("is_winding_up") or not e.is_winding_up():
				continue
			var world_pos: Vector3 = e.global_position + Vector3.UP * 2.1
			if cam.is_position_behind(world_pos):
				continue
			var p := cam.unproject_position(world_pos)
			var glow: float = e.windup_progress()
			var color := Color(1.0, 0.85, 0.25, 0.35 + 0.65 * glow)
			draw_colored_polygon(_star_points(p, STAR_OUTER * (1.0 + 0.35 * glow)), color)

	func _star_points(center: Vector2, outer: float) -> PackedVector2Array:
		var pts := PackedVector2Array()
		var inner := outer * (STAR_INNER / STAR_OUTER)
		for i in 10:
			var r := outer if i % 2 == 0 else inner
			var a := -PI / 2.0 + TAU * i / 10.0
			pts.append(center + Vector2(cos(a), sin(a)) * r)
		return pts


class ReticleControl:
	extends Control
	## Lock-on ring. The ring itself reports whether the target can be hurt
	## right now — amber and wide once they're staggered — and the centre
	## reports their guard: a shield while it's up, so you can see a swing
	## will be soaked before you throw it. The two never collide, because a
	## staggered fighter has no guard. Steel blue rather than the gold used by
	## the wind-up star and the NPC prompt — this reads "defended", not
	## "danger".

	const SHIELD_HALF_W := 8.0
	const SHIELD_H := 21.0
	const SHIELD_TAPER := 8          # samples down each curved edge
	const SHIELD_PULSE_SPEED := 4.0
	const SHIELD_PULSE := 0.06

	const RETICLE := Color(1, 0.35, 0.25, 0.9)
	## Amber ring = the target is staggered: punish it now.
	const OPEN_COLOR := Color(1.0, 0.8, 0.25, 0.95)
	const SHIELD_FILL := Color(0.55, 0.72, 0.95, 0.85)
	const SHIELD_EDGE := Color(0.90, 0.96, 1.0, 0.95)

	var player: Player
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		if not is_instance_valid(player) or not is_instance_valid(player.lock_target):
			return
		var cam := get_viewport().get_camera_3d()
		if cam == null:
			return
		var target: Node3D = player.lock_target
		var world_pos: Vector3 = target.global_position + Vector3.UP * 1.4
		if cam.is_position_behind(world_pos):
			return
		var p := cam.unproject_position(world_pos)
		var open := _target_is_open(target)
		var ring := OPEN_COLOR if open else RETICLE
		draw_arc(p, 22.0 if open else 18.0, 0, TAU, 32, ring, 3.0)
		if target.has_method("is_blocking") and target.is_blocking():
			_draw_shield(p)
		else:
			draw_circle(p, 3.0, ring)

	## Enemies count down `stagger_left`, players `stagger_time` — either way
	## the target is helpless right now.
	func _target_is_open(target: Node) -> bool:
		var left: Variant = target.get("stagger_left")
		if left == null:
			left = target.get("stagger_time")
		return left != null and float(left) > 0.0

	func _draw_shield(c: Vector2) -> void:
		var s: float = 1.0 + SHIELD_PULSE * sin(_t * SHIELD_PULSE_SPEED)
		var pts := _shield_points(c, SHIELD_HALF_W * s, SHIELD_H * s)
		draw_colored_polygon(pts, SHIELD_FILL)
		var outline := pts.duplicate()
		outline.append(pts[0])
		draw_polyline(outline, SHIELD_EDGE, 2.0, true)

	## Heater shield: square shoulders, straight sides, then an elliptical
	## taper down to the point.
	func _shield_points(c: Vector2, w: float, h: float) -> PackedVector2Array:
		var pts := PackedVector2Array()
		var top := c.y - h * 0.5
		var shoulder := top + h * 0.34
		var tip := c.y + h * 0.5
		pts.append(Vector2(c.x - w, top))
		pts.append(Vector2(c.x + w, top))
		pts.append(Vector2(c.x + w, shoulder))
		for i in range(1, SHIELD_TAPER + 1):
			var t := float(i) / SHIELD_TAPER
			pts.append(Vector2(c.x + w * sqrt(maxf(1.0 - t * t, 0.0)), lerpf(shoulder, tip, t)))
		for i in range(SHIELD_TAPER - 1, 0, -1):
			var t := float(i) / SHIELD_TAPER
			pts.append(Vector2(c.x - w * sqrt(maxf(1.0 - t * t, 0.0)), lerpf(shoulder, tip, t)))
		pts.append(Vector2(c.x - w, shoulder))
		return pts


class CombatFxControl:
	extends Control
	## Screen-centre combat reads: hit confirms on your own punches, and the
	## two guard events worth calling out — a parry and a broken guard.

	var player: Player

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if not is_instance_valid(player):
			return
		var mid := size / 2.0
		if player.fx_hitmarker_time > 0.0:
			_draw_hitmarker(mid, clampf(player.fx_hitmarker_time / 0.18, 0.0, 1.0))
		if player.fx_parry_time > 0.0:
			_draw_banner(mid, "PARRY", Color(1.0, 0.95, 0.6),
					clampf(player.fx_parry_time / 0.55, 0.0, 1.0))
		elif player.fx_break_time > 0.0:
			_draw_banner(mid, "GUARD BROKEN", Color(1.0, 0.4, 0.25),
					clampf(player.fx_break_time / 0.9, 0.0, 1.0))

	## Four ticks flicking outward from the crosshair as they fade.
	func _draw_hitmarker(mid: Vector2, life: float) -> void:
		var color := Color(1, 1, 1, 0.9 * life)
		var inner := 7.0 + 6.0 * (1.0 - life)
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			draw_line(mid + d * inner, mid + d * (inner + 7.0), color, 2.0)

	func _draw_banner(mid: Vector2, text: String, color: Color, life: float) -> void:
		var font := get_theme_default_font()
		if font == null:
			return
		var font_size := 34
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var pos := mid + Vector2(-w * 0.5, -64.0 - 14.0 * (1.0 - life))
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
				Color(color.r, color.g, color.b, life))
