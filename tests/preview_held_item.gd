extends Node3D
## Fitting aid, not a pass/fail test: renders Rouge holding an item and saves a
## PNG, so a new weapon's grip can be lined up without launching the game.
## Tweak ItemDb's "hold" entry (or HOLD_DEFAULTS), run this, look at the file:
##   godot --path . res://tests/preview_held_item.tscn
## It needs a real window — do NOT pass --headless, there is nothing to draw
## into. Change ITEM to preview a different one.

const ITEM := "iron_sword"
## Which pose to hold: "idle", "run", "attack_light_0"... anything tick() takes.
const ANIM := "idle"
## How many 60ths of a second to let it run before the shot — bump it to catch
## a later frame of a swing.
const FRAMES := 30
const OUT := "user://hold_preview.png"

func _ready() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, 35, 0)
	add_child(light)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.2, 0.22, 0.26)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.6, 0.65)
	e.ambient_light_energy = 0.8
	env.environment = e
	add_child(env)

	var vis: Node3D = (load("res://scripts/entities/rouge_visual.gd") as Script).new()
	add_child(vis)
	vis.set_held_item(ITEM)

	var cam := Camera3D.new()
	add_child(cam)
	cam.look_at_from_position(Vector3(1.6, 1.3, 2.0), Vector3(-0.1, 0.9, 0))
	cam.current = true

	# let the clip settle on a real pose, not the rest skeleton — with a sword
	# in hand that is the sword idle, which is the point of looking at this
	for i in FRAMES:
		vis.tick(1.0 / 60.0, ANIM, 0.0, 1.0)
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(OUT)
	print("PREVIEW saved=", ProjectSettings.globalize_path(OUT))
	get_tree().quit()
