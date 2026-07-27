extends Node3D
## Photographs the generated dungeon shell. Run WITHOUT --headless — it renders:
##   godot --path . res://tests/preview_dungeon.tscn
## Writes a PNG per shot into user://dungeon_preview.
##
## The three faults this exists to catch are all invisible to an assertion and
## obvious in a picture:
##   - `seam`  is a camera on the floor with its nose against a wall, which is
##     where the crack along the bottom showed: a slot of daylight between the
##     wall's inner face and the edge of the floor.
##   - `ceiling` looks straight up, so a hole in the lid is a patch of sky.
##   - `room` and `stairs` are eye height, for how tall the place reads now that
##     the walls run up to a ceiling instead of stopping at 3.8 m.

const DUNGEON := preload("res://scenes/starterDungeon.tscn")
const OUT := "user://dungeon_preview"
const EYE := 1.7          # a player's eye height

var _shots: Array = []
var _cam: Camera3D
var _i := 0
var _waited := 0

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var scene: Node3D = DUNGEON.instantiate()
	add_child(scene)

	# The world's own sky and sun, so the shot is lit the way the game lights it
	# — the whole point of the lamps is what the dungeon looks like once the sun
	# cannot reach it.
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.05, 0.06, 0.09)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.60, 0.70)
	e.ambient_light_energy = 1.2
	env.environment = e
	add_child(env)

	var walls: Node3D = scene.find_child("Walls", true, false)
	var floor_root: Node3D = walls.get_parent()
	var ceiling: float = walls.ceiling_y()
	var here := floor_root.global_position

	_cam = Camera3D.new()
	add_child(_cam)
	_cam.current = true

	# Stood where the portal actually puts a player, rather than at some average
	# of the geometry: the middle of a ring of walls is as likely to be inside a
	# block as inside a room, which is exactly how the first draft of this file
	# photographed the inside of a wall four times.
	var anchor: Node3D = scene.find_child("ArrivalAnchor", true, false)
	if anchor == null:
		push_error("[preview_dungeon] the dungeon has no ArrivalAnchor to stand at")
		get_tree().quit(1)
		return
	var eye: Vector3 = anchor.global_position
	eye.y = here.y + _floor_at(walls, anchor.global_position) + EYE

	# The nearest wall, and the direction from it back to where we are stood —
	# which is into the room by construction.
	var nearest: Node3D = null
	var best := INF
	for p in walls.get_children():
		if not p.name.begins_with("Wall"):
			continue
		var d: float = (p as Node3D).global_position.distance_to(eye)
		if d < best:
			best = d
			nearest = p as Node3D
	if nearest == null:
		push_error("[preview_dungeon] nothing was built")
		get_tree().quit(1)
		return
	var foot := nearest.global_position
	var into := (eye - foot)
	into.y = 0.0
	into = into.normalized()
	var at_wall: Vector3 = foot + into * 3.0
	print("  floor at y=%.2f, ceiling at y=%.2f — %.2f m of head room"
		% [foot.y, here.y + ceiling, here.y + ceiling - foot.y])

	_shots = [
		# Ankle height, nose to the wall: the crack lived down here, and an
		# eye-height shot looks straight over it.
		{"name": "seam", "at": Vector3(at_wall.x, foot.y + 0.35, at_wall.z),
			"look": Vector3(foot.x, foot.y + 0.05, foot.z)},
		{"name": "room", "at": eye, "look": Vector3(foot.x, eye.y, foot.z)},
		# Up at 60 degrees rather than straight up: a look_at along the up
		# vector itself is degenerate and quietly leaves the camera where it was.
		{"name": "ceiling", "at": eye,
			"look": eye + Vector3(into.x, 1.7, into.z) * 6.0},
	]
	# Under a lamp, looking at the floor: with the sun shut out, this is the
	# only light the dungeon has, and how far it reaches is the whole question.
	var lamps: Node = walls.find_child("Lamps", false, false)
	if lamps != null and lamps.get_child_count() > 0:
		var lamp: Node3D = lamps.get_child(0)
		var under := lamp.global_position
		_shots.append({"name": "lamp",
			"at": Vector3(under.x, foot.y + EYE, under.z) - into * 6.0,
			"look": Vector3(under.x, foot.y, under.z)})

## The floor's own height under a point, taken off the wall the builder put
## nearest to it — the walls stand on the floor, so they are a floor probe that
## needs no ray and no physics.
func _floor_at(walls: Node3D, at: Vector3) -> float:
	var best := INF
	var y := 0.0
	for p in walls.get_children():
		if not p.name.begins_with("Wall"):
			continue
		var d: float = (p as Node3D).global_position.distance_to(at)
		if d < best:
			best = d
			y = (p as Node3D).position.y
	return y

func _process(_dt: float) -> void:
	if _shots.is_empty():
		return
	_waited += 1
	if _waited < 4:
		return
	_waited = 0
	var shot: Dictionary = _shots[_i]
	_cam.global_position = shot["at"]
	_cam.look_at(shot["look"], Vector3.UP)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [OUT, shot["name"]])
	print("  wrote %s/%s.png  from %v" % [OUT, shot["name"], shot["at"]])
	_i += 1
	if _i >= _shots.size():
		print("DUNGEONPREVIEW done -> ", ProjectSettings.globalize_path(OUT))
		get_tree().quit(0)
