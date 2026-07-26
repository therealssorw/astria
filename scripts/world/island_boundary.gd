@tool
extends StaticBody3D
## Invisible wall around the playable map: a ring of box colliders that follows
## the StarterIsland shoreline, so players can't walk off the coast and fall
## through the (collision-free) ocean forever.
##
## SHORE_RADIUS is baked from Island1.glb: the island mesh was sampled at the
## water plane (Ocean node Y 11.32 + sea_level 25.0 = world Y 36.32) and, for
## each of 72 five-degree sectors around the island centre, the distance to the
## furthest above-water vertex was recorded. Segment i therefore sits exactly on
## the coast of its own sector instead of on one crude circle, which on this
## island would otherwise leave 140 m of open water on the narrow sides.
##
## Children are rebuilt on demand and never given an owner, so they stay out of
## the saved .tscn — same trick ocean.gd uses for its wave tiles.

const BINS := 72

## Distance from the island centre to the outermost above-water vertex, per
## 5-degree sector, starting at +X and turning towards +Z (atan2(dz, dx)).
const SHORE_RADIUS := PackedFloat32Array([
	375.6, 379.3, 383.7, 389.2, 391.9, 396.9, 408.0, 426.8, 430.7, 429.5, 414.5, 392.6,
	383.0, 377.0, 376.5, 370.0, 369.1, 374.9, 374.5, 362.1, 360.2, 361.2, 368.2, 375.5,
	396.4, 399.1, 396.6, 396.5, 405.3, 414.3, 417.2, 423.1, 423.0, 436.5, 442.8, 437.9,
	436.6, 410.4, 418.6, 430.2, 462.6, 473.0, 483.1, 491.9, 500.5, 494.9, 452.6, 426.4,
	416.7, 410.0, 395.4, 384.4, 391.0, 398.2, 398.3, 410.8, 426.7, 438.2, 452.9, 481.0,
	477.2, 479.7, 490.4, 496.2, 454.7, 436.0, 421.8, 403.8, 388.9, 372.7, 371.4, 367.7,
])

## Island centre in world space (Island1's own XZ translation).
@export var centre := Vector3(14.0139475, 0.0, 35.034847)
## Pull the wall this far back from the last above-water vertex, so the player
## is stopped on sand rather than on the lip of the drop.
@export var inset := 3.0
## Radial thickness. Generous on purpose: a thin wall can be tunnelled through
## at speed or at a grazing angle.
@export var thickness := 24.0
## Wall spans this Y range. Bottom is under the waterline (36.3); top clears the
## coastal cliffs so the wall can't be jumped or fallen over.
@export var wall_bottom := 15.0
@export var wall_top := 130.0
## Tangential overlap between neighbouring segments. >1 closes the wedge gaps
## that open up wherever two adjacent sectors sit at different radii.
@export var overlap := 1.8
## Draw the wall as translucent boxes. Editor + debug only.
@export var show_debug := false:
	set(v):
		show_debug = v
		if is_inside_tree():
			build()
## Tick to rebuild after changing anything above.
@export var rebuild := false:
	set(_v):
		rebuild = false
		if is_inside_tree():
			build()


func _ready() -> void:
	build()


## Clear and regenerate every wall segment.
func build() -> void:
	for child in get_children():
		remove_child(child)
		child.free()

	var debug_material: StandardMaterial3D = null
	if show_debug:
		debug_material = StandardMaterial3D.new()
		debug_material.albedo_color = Color(1.0, 0.25, 0.35, 0.25)
		debug_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		debug_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		debug_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var height := wall_top - wall_bottom
	var mid_y := wall_bottom + height * 0.5

	for i in BINS:
		var angle := (float(i) + 0.5) * TAU / float(BINS)
		var radius: float = SHORE_RADIUS[i] - inset
		var size := Vector3(thickness, height, TAU * radius / float(BINS) * overlap)

		var shape := BoxShape3D.new()
		shape.size = size

		# Local +X points radially outward, local +Z runs along the coast.
		var basis := Basis(Vector3.UP, -angle)
		var origin := centre + Vector3(cos(angle), 0.0, sin(angle)) * radius
		origin.y = mid_y

		var collider := CollisionShape3D.new()
		collider.shape = shape
		collider.transform = Transform3D(basis, origin)
		collider.name = "Segment%02d" % i
		add_child(collider)

		if debug_material != null:
			var mesh := BoxMesh.new()
			mesh.size = size
			var visual := MeshInstance3D.new()
			visual.mesh = mesh
			visual.material_override = debug_material
			visual.transform = Transform3D(basis, origin)
			visual.name = "SegmentView%02d" % i
			add_child(visual)


## World-space distance from the island centre out to the wall on the bearing of
## `point` — handy for spawners that need to stay inside the playable area.
func wall_radius_towards(point: Vector3) -> float:
	var offset := point - centre
	var angle := atan2(offset.z, offset.x)
	if angle < 0.0:
		angle += TAU
	var bin := int(floor(angle / TAU * float(BINS))) % BINS
	return SHORE_RADIUS[bin] - inset
