@tool
class_name IslandWorld
extends Node3D
## Island world root: generates collision for the island meshes at runtime,
## drops the enemy in near the player spawn point, and manages the distance
## fog (toggleable in the editor, always on in the game).

## Editor-only: show the distance fog in the editor viewport.
## The running game always has fog enabled regardless of this.
@export var editor_fog := false:
	set(v):
		editor_fog = v
		if Engine.is_editor_hint() and is_inside_tree():
			_apply_fog(editor_fog)

func _ready() -> void:
	if Engine.is_editor_hint():
		_apply_fog(editor_fog)
		return
	_apply_fog(true)
	# black out before the island is ever drawn — the intro plays over it
	IntroCutscene.arm()
	grow_collision($Island1)
	# world is up on this peer: server spawns pawns, clients ask for theirs
	Net.on_world_ready.call_deferred()

## Grow a ground collider from the render meshes under `root`. A glTF ships no
## collision shapes, so the island's floor IS its visible geometry — the real
## island and every private copy of it in the tutorial grow theirs the same way.
##
## THE MESH BEING ABSENT IS THE INTERESTING CASE. The dedicated-server export
## strips visual resources by default, which leaves every MeshInstance3D here
## with a null mesh, `create_trimesh_collision()` with nothing to build from,
## and a world with no ground in it — while the editor, which strips nothing,
## looks perfect. The server owns every position and counts a fall past KILL_Y
## as a death, so that reads to players as everything dropping through the
## island. Two engine errors buried in a log is not enough warning for that, so
## this counts them and says what it means, once, in a line that names the fix.
##
## Returns how many meshes were missing — 0 on a healthy build.
static func grow_collision(root: Node3D) -> int:
	var stripped := 0
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			stripped += 1
			continue
		mi.create_trimesh_collision()
	if stripped > 0:
		push_error(("[World] %d of the ground meshes under '%s' have no mesh, so "
				+ "that much of the island has NO COLLISION and things will fall "
				+ "through it. A dedicated-server export strips visuals: the "
				+ "island's folder must be marked \"keep\" in export_presets.cfg "
				+ "(see tests/test_server_export.tscn).") % [stripped, root.name])
	return stripped

func _apply_fog(enabled: bool) -> void:
	var env: Environment = $WorldEnvironment.environment
	env.fog_enabled = enabled
