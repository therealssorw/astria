extends Node3D
## Look-at aid, not a pass/fail test: stands the same villager bare, in the
## suit as drawn, and in a recoloured suit, and saves a PNG.
##   godot --path . res://tests/preview_npc_armor.tscn
## It needs a real window — do NOT pass --headless, there is nothing to draw
## into. The shot lands in user://npc_armor_preview.png (the path is printed).
##
## The rig's own tests check the fit as numbers (concentric, wrapping, not
## floating). This is for the half a number cannot answer: whether the plate
## reads as armour on a person.

const SET := "Base"
const SUIT := "Armor1"
const OUT := "user://npc_armor_preview.png"
## Let the pose settle before the shot — a rig fresh out of _ready is still on
## its rest pose.
const FRAMES := 20

func _ready() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-38, 35, 0)
	add_child(light)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.16, 0.17, 0.2)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.65, 0.65, 0.72)
	e.ambient_light_energy = 0.9
	env.environment = e
	add_child(env)

	var visuals: Array[Node3D] = []
	visuals.append(_stand(_villager(false), -2.6))
	visuals.append(_stand(_villager(true), 0.0))
	visuals.append(_stand(_recoloured(), 2.6))

	var cam := Camera3D.new()
	add_child(cam)
	cam.look_at_from_position(Vector3(0.1, 1.3, 5.6), Vector3(0, 0.9, 0))
	cam.current = true

	for i in FRAMES:
		for v in visuals:
			v.tick(1.0 / 60.0, "idle", 0.0, 0.0)
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT)
	print("PREVIEW saved=", ProjectSettings.globalize_path(OUT))
	get_tree().quit()

func _stand(def: NpcDefinition, x: float) -> Node3D:
	var visual := NpcVisual.new()
	visual.definition = def
	add_child(visual)
	visual.position.x = x
	return visual

func _villager(armoured: bool) -> NpcDefinition:
	var def := NpcDefinition.new()
	for slot: String in NpcDefinition.SLOTS:
		var models := NpcRig.list_parts(slot, SET)
		if not models.is_empty():
			def.get_part(slot).model_path = models[0]
	if not armoured:
		return def
	for slot: String in NpcDefinition.ARMOR_SLOTS:
		var plates := NpcRig.list_parts(slot, SUIT)
		if not plates.is_empty():
			def.get_part(slot).model_path = plates[0]
	return def

## Steel-blue plate over the same villager: the suit's own palette, replaced
## entry by entry, which is what the builder's swatches do.
func _recoloured() -> NpcDefinition:
	var def := _villager(true)
	for slot: String in NpcDefinition.ARMOR_SLOTS:
		var part := def.get_part(slot)
		var palette := NpcRig.palette_of(part.model_path)
		var colours := PackedColorArray()
		for i in palette.size():
			# keep the suit's own light/dark ordering, just move its hue
			colours.append(Color.from_hsv(0.58, 0.35, clampf(palette[i].v, 0.25, 0.95)))
		part.colors = colours
	return def
