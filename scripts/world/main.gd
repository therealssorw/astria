extends Node3D
## Arena root: bakes the navmesh at runtime so enemies can pathfind.

@onready var nav_region: NavigationRegion3D = $NavigationRegion3D

func _ready() -> void:
	var mesh := NavigationMesh.new()
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.agent_radius = 0.5
	mesh.agent_height = 2.0
	mesh.cell_size = 0.25
	mesh.cell_height = 0.25
	nav_region.navigation_mesh = mesh
	nav_region.bake_navigation_mesh.call_deferred()
