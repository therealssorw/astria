@tool
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
	for mi: MeshInstance3D in $Island1.find_children("*", "MeshInstance3D", true, false):
		mi.create_trimesh_collision()
	# world is up on this peer: server spawns pawns, clients ask for theirs
	Net.on_world_ready.call_deferred()

func _apply_fog(enabled: bool) -> void:
	var env: Environment = $WorldEnvironment.environment
	env.fog_enabled = enabled
