extends Marker3D
## Player spawn point: Net spawns every player pawn (and respawns the dead)
## in a small ring around the first member of the "spawn_point" group.

func _enter_tree() -> void:
	add_to_group("spawn_point")
