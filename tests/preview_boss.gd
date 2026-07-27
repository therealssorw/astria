extends Node3D
## Look-at aid, not a pass/fail test: the juggernaut beside a player-sized
## villager for scale, and then the things about it that no assertion can see —
## the wind-up of each move with its own telegraph, the ground ring, and the
## armour before and after phase two.
##   godot --path . res://tests/preview_boss.tscn
## It needs a real window — do NOT pass --headless, there is nothing to draw
## into and a `_draw()` never runs without one. Shots land in user://boss_preview
## (the folder is printed).
##
## What to look for, in order:
##   scale.png   — is it big enough to read as a boss next to a person, and is
##                 the club in its hand rather than through it?
##   slam.png    — the orange ring on the floor: is it where the slam lands?
##   charge.png  — a different colour and a bigger star, with no ring.
##   phase2.png  — the armour gone, the same body underneath.

const OUT_DIR := "user://boss_preview"
## Let the rig settle: a visual fresh out of _ready is still on its rest pose.
const SETTLE := 24

var _boss: Boss
var _hud: CanvasLayer

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_light()
	_floor()

	_boss = preload("res://scenes/boss.tscn").instantiate() as Boss
	add_child(_boss)
	_boss.global_position = Vector3(1.4, 0, 0)
	# nothing is driving it here: no server, no player, no AI. The visual is
	# ticked by hand below, exactly as the arena ticks a villager.
	_boss.set_physics_process(false)
	_boss.set_process(false)

	var mate := NpcVisual.new()
	mate.definition = load("res://Assets/Data/Npcs/villager.tres")
	add_child(mate)
	mate.position = Vector3(-1.4, 0, 0)

	var cam := Camera3D.new()
	add_child(cam)
	cam.look_at_from_position(Vector3(0.0, 2.4, 7.4), Vector3(0, 1.3, 0))
	cam.current = true

	# the REAL HUD, so the telegraph and the ring below are the ones the game
	# draws rather than a copy of them written for the shot
	_hud = (load("res://scripts/ui/hud.gd") as GDScript).new()
	add_child(_hud)

	await _settle([mate])
	await _shot("scale")

	for move_id: String in Boss.MOVES:
		_boss.move_id = move_id
		_boss.move_did_hit = false
		# frozen most of the way through the wind-up: the ring is nearly full and
		# the star is at its brightest, which is the frame worth judging
		_boss.move_timer = float(Boss.MOVES[move_id]["windup"]) * 0.85
		await _settle([mate])
		await _shot(move_id)
	_boss.move_id = ""

	_boss.net_apply_phase(2)
	await _settle([mate])
	await _shot("phase2")

	print("PREVIEW saved=", ProjectSettings.globalize_path(OUT_DIR))
	get_tree().quit()

func _settle(others: Array) -> void:
	for i in SETTLE:
		_boss.body_visual.tick(1.0 / 60.0, "idle", 0.0, 0.0)
		for o in others:
			o.tick(1.0 / 60.0, "idle", 0.0, 0.0)
		await get_tree().process_frame

func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [OUT_DIR, shot_name])
	print("  ", shot_name)

func _light() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-42, 28, 0)
	add_child(light)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.10, 0.10, 0.12)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.7, 0.75)
	e.ambient_light_energy = 0.85
	env.environment = e
	add_child(env)

## Something for the ring to be drawn on, and for the pair to stand on.
func _floor() -> void:
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(24, 24)
	mi.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.19, 0.18)
	mi.material_override = mat
	add_child(mi)
