@tool
class_name GrassPaint
extends MultiMeshInstance3D
## Paintable grass layer. Every brushed blade is an instance in this node's
## single MultiMesh — one draw call no matter how much is painted — using the
## same blade mesh + wind-noise shader as the grass.tscn prefab.

const BLADE_MESH := "res://Assets/Models/World/Prefab/Data/Grass/grass.res"
const GRASS_SHADER := "res://Assets/Textures/Shaders/grass.gdshader"

@export var brush_radius := 3.0
@export var blades_per_dab := 24
@export var min_blade_scale := 0.8
@export var max_blade_scale := 1.3
@export var max_slope_deg := 50.0
## 0 = blades always straight up, 1 = fully aligned to the ground normal.
@export_range(0.0, 1.0) var align_to_ground := 0.3

func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if multimesh == null:
		multimesh = MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = load(BLADE_MESH)
	if material_override == null:
		var mat := ShaderMaterial.new()
		mat.shader = load(GRASS_SHADER)
		# same look as the grass.tscn prefab material
		mat.set_shader_parameter("color", Color(0.0, 0.55, 0.0))
		mat.set_shader_parameter("color2", Color(0.0, 0.7235624, 0.0))
		mat.set_shader_parameter("noiseScale", 20.0)
		material_override = mat

## Verbatim state for undo/redo: [instance_count, buffer].
func snapshot() -> Array:
	return [multimesh.instance_count, multimesh.buffer.duplicate()]

func set_mm_data(count: int, buf: PackedFloat32Array) -> void:
	multimesh.instance_count = count
	if count > 0:
		multimesh.buffer = buf

## One brush dab at a world-space point (erase removes blades in the radius).
func paint_dab(center: Vector3, erase: bool) -> void:
	if erase:
		_erase(center)
	else:
		_paint(center)

func _paint(center: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	var inv := global_transform.affine_inverse()
	var min_ny := cos(deg_to_rad(max_slope_deg))
	var new_xforms: Array[Transform3D] = []
	for i in blades_per_dab:
		# uniform random point in the brush disc
		var ang := randf() * TAU
		var r := brush_radius * sqrt(randf())
		var p := center + Vector3(cos(ang) * r, 0.0, sin(ang) * r)
		var query := PhysicsRayQueryParameters3D.create(
				p + Vector3.UP * 4.0, p + Vector3.DOWN * 12.0)
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue
		var n: Vector3 = hit.normal
		if n.y < min_ny:
			continue
		var up := Vector3.UP.slerp(n, align_to_ground).normalized()
		var basis := Basis(Quaternion(Vector3.UP, up) * Quaternion(Vector3.UP, randf() * TAU))
		var s := randf_range(min_blade_scale, max_blade_scale)
		new_xforms.append(inv * Transform3D(basis.scaled(Vector3(s, s, s)), hit.position))
	if new_xforms.is_empty():
		return
	# append: grow the buffer verbatim (setting instance_count clears it),
	# then write only the new tail via the server — no per-instance rebuild
	var old_count := multimesh.instance_count
	var old_buf := multimesh.buffer
	var grown := PackedFloat32Array()
	grown.resize(old_buf.size() + new_xforms.size() * 12)
	for i in old_buf.size():
		grown[i] = old_buf[i]
	multimesh.instance_count = old_count + new_xforms.size()
	multimesh.buffer = grown
	for i in new_xforms.size():
		multimesh.set_instance_transform(old_count + i, new_xforms[i])

func _erase(center: Vector3) -> void:
	var count := multimesh.instance_count
	if count == 0:
		return
	var local_center := global_transform.affine_inverse() * center
	var r2 := brush_radius * brush_radius
	var kept: Array[Transform3D] = []
	for i in count:
		var xf := multimesh.get_instance_transform(i)
		var d := xf.origin - local_center
		if d.x * d.x + d.z * d.z > r2:
			kept.append(xf)
	if kept.size() == count:
		return
	multimesh.instance_count = kept.size()
	for i in kept.size():
		multimesh.set_instance_transform(i, kept[i])
