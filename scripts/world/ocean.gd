@tool
extends Node3D
## Endless-looking ocean: a grid of wave-shader tiles kept centered on the
## player. Distance fog (set on the WorldEnvironment) hides the outer edge,
## so a small grid is enough — no endless sea generation needed.
## Runs as @tool so the animated waves also show in the editor viewport
## (tiles are transient children and never get saved into the scene).

@export var sea_level := 25.0         # island's lowest shore ring is ~y 15.5
@export var tile_size := 800.0
@export var grid_radius := 4          # 4 -> 9x9 tiles, 3600 m in every direction
@export var subdivisions := 96        # near tiles: ~8 m vertex spacing
@export var far_subdivisions := 32    # tiles beyond near_rings (cheaper, fog-distance)
@export var near_rings := 2           # rings of full-detail tiles around the player
## Editor-only: the wave pattern shows frozen at this time offset (seconds)
## for cinematic shots — scrub it to pick the wave shape you like.
## The running game always animates normally.
@export_range(0.0, 60.0, 0.05) var editor_wave_phase := 3.0:
	set(v):
		if v == null:
			v = 3.0
		editor_wave_phase = v
		_apply_freeze()

var tiles: Array[MeshInstance3D] = []
var player: Node3D
var grid_center := Vector2.INF
var wave_material: Material

func _ready() -> void:
	# clear tiles from a previous tool-script run (e.g. script reload)
	tiles.clear()
	for c in get_children():
		if c is MeshInstance3D:
			c.queue_free()
	# share the material from the wave_mesh asset so tuning its shader
	# parameters keeps affecting the whole ocean
	var wave_scene: Node = (load("res://Assets/Models/World/wave_mesh.tscn") as PackedScene).instantiate()
	wave_material = (wave_scene as MeshInstance3D).mesh.surface_get_material(0)
	wave_scene.free()
	_apply_freeze()

	# two detail levels: full waves near the player, cheaper tiles toward
	# the fog wall where facet density is invisible anyway
	var near_plane := _make_plane(subdivisions)
	var far_plane := _make_plane(far_subdivisions)

	var side := grid_radius * 2 + 1
	for i in side * side:
		@warning_ignore("integer_division")
		var ring := maxi(absi((i / side) - grid_radius), absi((i % side) - grid_radius))
		var mi := MeshInstance3D.new()
		mi.mesh = near_plane if ring <= near_rings else far_plane
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		tiles.append(mi)
	_recenter(Vector2.ZERO)

func _make_plane(subdiv: int) -> PlaneMesh:
	var plane := PlaneMesh.new()
	plane.size = Vector2(tile_size, tile_size)
	plane.subdivide_width = subdiv
	plane.subdivide_depth = subdiv
	plane.material = wave_material
	return plane

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return  # in the editor the grid just sits at the origin
	if not is_instance_valid(player):
		var players := get_tree().get_nodes_in_group("player")
		if players.is_empty():
			return
		player = players[0]
	var p := Vector2(player.global_position.x, player.global_position.z)
	var snapped_center := (p / tile_size).round() * tile_size
	if snapped_center != grid_center:
		_recenter(snapped_center)

## Editor: waves frozen at editor_wave_phase. Game: animated normally.
func _apply_freeze() -> void:
	if wave_material == null:
		return
	wave_material.set_shader_parameter("freeze_time", Engine.is_editor_hint())
	wave_material.set_shader_parameter("frozen_time", editor_wave_phase)

func _recenter(center: Vector2) -> void:
	grid_center = center
	var side := grid_radius * 2 + 1
	for i in tiles.size():
		@warning_ignore("integer_division")
		var gx := (i / side) - grid_radius
		var gz := (i % side) - grid_radius
		# water height = this node's Y + sea_level, so dragging the Ocean
		# node in the editor moves the sea as expected
		tiles[i].global_position = Vector3(
			center.x + gx * tile_size, global_position.y + sea_level,
			center.y + gz * tile_size)
