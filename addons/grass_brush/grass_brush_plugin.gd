@tool
extends EditorPlugin
## Viewport brush for GrassPaint nodes. Select a GrassPaint node, then:
##   left-drag  = paint      Shift+left-drag = erase      [ / ] = brush size
## Terrain has no collision in the editor (world.gd builds it at runtime), so
## temporary unowned trimesh colliders are generated for raycasts and freed
## when the plugin deactivates; they are never saved into the scene.

const PAINTER_SCRIPT := preload("grass_paint.gd")

var painter: GrassPaint
var _stroke_active := false
var _stroke_erase := false
var _stroke_before: Array = []
var _last_dab := Vector3.INF
var _temp_bodies: Array[Node] = []
var _collision_scene_root: Node = null
var _preview: MeshInstance3D

func _enter_tree() -> void:
	add_custom_type("GrassPaint", "MultiMeshInstance3D", PAINTER_SCRIPT, null)

func _exit_tree() -> void:
	remove_custom_type("GrassPaint")
	_clear_temp_collision()
	_clear_preview()

func _handles(object: Object) -> bool:
	return object is GrassPaint

func _edit(object: Object) -> void:
	painter = object as GrassPaint
	if painter:
		_ensure_temp_collision()
	elif _preview:
		_preview.visible = false

func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if painter == null or not is_instance_valid(painter) or not painter.is_inside_tree():
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_BRACKETLEFT:
			painter.brush_radius = maxf(0.5, painter.brush_radius - 0.5)
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		if event.keycode == KEY_BRACKETRIGHT:
			painter.brush_radius = minf(20.0, painter.brush_radius + 0.5)
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	if event is InputEventMouseMotion:
		var hit := _mouse_hit(camera, event.position)
		_update_preview(hit, event.shift_pressed)
		if _stroke_active and not hit.is_empty():
			var pos: Vector3 = hit.position
			if _last_dab.distance_to(pos) >= painter.brush_radius * 0.45:
				_last_dab = pos
				painter.paint_dab(pos, _stroke_erase)
		return EditorPlugin.AFTER_GUI_INPUT_STOP if _stroke_active \
				else EditorPlugin.AFTER_GUI_INPUT_PASS

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var hit := _mouse_hit(camera, event.position)
			if hit.is_empty():
				return EditorPlugin.AFTER_GUI_INPUT_PASS
			_stroke_active = true
			_stroke_erase = event.shift_pressed
			_stroke_before = painter.snapshot()
			_last_dab = hit.position
			painter.paint_dab(hit.position, _stroke_erase)
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		elif _stroke_active:
			_stroke_active = false
			_commit_stroke()
			return EditorPlugin.AFTER_GUI_INPUT_STOP

	return EditorPlugin.AFTER_GUI_INPUT_PASS

func _commit_stroke() -> void:
	var after: Array = painter.snapshot()
	var ur := get_undo_redo()
	ur.create_action("Erase grass" if _stroke_erase else "Paint grass")
	ur.add_do_method(painter, "set_mm_data", after[0], after[1])
	ur.add_undo_method(painter, "set_mm_data", _stroke_before[0], _stroke_before[1])
	ur.commit_action()

# ---------------- raycast / temp collision ----------------

func _mouse_hit(camera: Camera3D, mouse_pos: Vector2) -> Dictionary:
	var from := camera.project_ray_origin(mouse_pos)
	var dir := camera.project_ray_normal(mouse_pos)
	var space := painter.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * 4000.0)
	return space.intersect_ray(query)

func _ensure_temp_collision() -> void:
	var root := get_editor_interface().get_edited_scene_root()
	if root == _collision_scene_root and not _temp_bodies.is_empty() \
			and is_instance_valid(_temp_bodies[0]):
		return
	_clear_temp_collision()
	if root == null:
		return
	_collision_scene_root = root
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or painter.is_ancestor_of(mi) or mi == painter:
			continue
		# skip grass itself and the animated ocean plane
		var mesh_path := mi.mesh.resource_path
		if mesh_path.contains("/Data/Grass/") or _has_ancestor_named(mi, root, "Ocean"):
			continue
		var before := mi.get_child_count()
		mi.create_trimesh_collision()
		for i in range(before, mi.get_child_count()):
			_temp_bodies.append(mi.get_child(i)) # unowned -> never saved

func _has_ancestor_named(node: Node, stop: Node, ancestor_name: String) -> bool:
	var n := node
	while n != null and n != stop:
		if n.name == ancestor_name:
			return true
		n = n.get_parent()
	return false

func _clear_temp_collision() -> void:
	for b in _temp_bodies:
		if is_instance_valid(b):
			b.queue_free()
	_temp_bodies.clear()
	_collision_scene_root = null

# ---------------- brush preview ring ----------------

func _update_preview(hit: Dictionary, erase: bool) -> void:
	if hit.is_empty() or painter == null:
		if _preview:
			_preview.visible = false
		return
	if _preview == null or not is_instance_valid(_preview):
		_preview = MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.94
		torus.outer_radius = 1.0
		torus.rings = 48
		_preview.mesh = torus
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.no_depth_test = true
		_preview.material_override = mat
		_preview.top_level = true
		_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		painter.add_child(_preview) # no owner -> never saved with the scene
	var mat: StandardMaterial3D = _preview.material_override
	mat.albedo_color = Color(1.0, 0.3, 0.2, 0.9) if erase else Color(0.3, 1.0, 0.3, 0.9)
	_preview.visible = true
	var r: float = painter.brush_radius
	_preview.global_transform = Transform3D(
			Basis().scaled(Vector3(r, r, r)),
			hit.position + Vector3.UP * 0.05)

func _clear_preview() -> void:
	if _preview and is_instance_valid(_preview):
		_preview.queue_free()
	_preview = null
