extends CanvasLayer
## Code-built HUD: HP bar, stamina bar, lock-on reticle, hold-P scoreboard,
## death overlay. Binds to the LOCAL player's pawn (group "local_player").

const SCOREBOARD := preload("res://scripts/ui/scoreboard.gd")
const NPC_PROMPTS := preload("res://scripts/ui/dialog/npc_prompt_overlay.gd")

var player: Player
var hp_fill: ColorRect
var stam_fill: ColorRect
var reticle: Control
var death_overlay: Control

const BAR_W := 280.0

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

	var telegraph := TelegraphControl.new()
	telegraph.set_anchors_preset(Control.PRESET_FULL_RECT)
	telegraph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(telegraph)

	root.add_child(NPC_PROMPTS.new())
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
	bg.color = Color(0, 0, 0, 0.55)
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
		return
	hp_fill.size.x = (BAR_W - 4) * clampf(player.health / player.max_health, 0.0, 1.0)
	stam_fill.size.x = (BAR_W - 4) * clampf(player.stamina / player.max_stamina, 0.0, 1.0)
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
	var player: Player

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if not is_instance_valid(player) or not is_instance_valid(player.lock_target):
			return
		var cam := get_viewport().get_camera_3d()
		if cam == null:
			return
		var world_pos: Vector3 = player.lock_target.global_position + Vector3.UP * 1.4
		if cam.is_position_behind(world_pos):
			return
		var p := cam.unproject_position(world_pos)
		draw_arc(p, 18.0, 0, TAU, 32, Color(1, 0.35, 0.25, 0.9), 3.0)
		draw_circle(p, 3.0, Color(1, 0.35, 0.25, 0.9))
