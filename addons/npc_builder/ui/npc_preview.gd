@tool
extends SubViewportContainer
## The turntable in the left half of the NPC Builder: a lit 3D view of the NPC
## currently being edited, orbited with the mouse.
##
## It drives a real NpcVisual, so what you are looking at is the same rigged,
## skinned character the game spawns -- including the animation clips, which is
## the only way to tell whether the auto-rig actually bends where it should.

const CLIPS := ["idle", "walk", "run"]

var _viewport: SubViewport
var _camera: Camera3D
var _visual: NpcVisual

var _yaw := 0.7
var _pitch := 0.12
var _distance := 3.4
var _focus := 0.95
var _dragging := false
var _turntable := true

func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(360, 420)

	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.handle_input_locally = false
	_viewport.msaa_3d = Viewport.MSAA_4X
	add_child(_viewport)

	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.09, 0.10, 0.13)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.52, 0.58, 0.72)
	env.ambient_light_energy = 0.9
	world.environment = env
	_viewport.add_child(world)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-45.0, 35.0, 0.0)
	key.light_energy = 1.5
	_viewport.add_child(key)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20.0, -140.0, 0.0)
	fill.light_energy = 0.4
	_viewport.add_child(fill)

	_viewport.add_child(_make_ground())

	_camera = Camera3D.new()
	_camera.fov = 38.0
	_viewport.add_child(_camera)
	_update_camera()

func _make_ground() -> MeshInstance3D:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(8.0, 8.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.17, 0.20)
	mat.roughness = 1.0
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	return mi

## Show `def`. Cheap enough to call on every keystroke -- the first call builds
## the rig, later ones only re-skin it.
func apply(def: NpcDefinition) -> void:
	if _visual == null:
		_visual = NpcVisual.new()
		_visual.name = "Npc"
		_visual.definition = def
		# Adding it builds it, clips and all -- the preview has an animation
		# picker. Do not also call build(): that is what draws the NPC twice.
		_viewport.add_child(_visual)
	else:
		_visual.rebuild(def)
	_focus = float(_visual.layout.get("crown", 1.85)) * 0.55
	_update_camera()

func play_clip(key: String) -> void:
	if _visual != null:
		_visual.preview_clip(key)

func set_turntable(on: bool) -> void:
	_turntable = on

func frame_character() -> void:
	_yaw = 0.7
	_pitch = 0.12
	_distance = 3.4
	_update_camera()

func _process(delta: float) -> void:
	if _turntable and not _dragging:
		_yaw += delta * 0.45
		_update_camera()

func _update_camera() -> void:
	if _camera == null:
		return
	var target := Vector3(0.0, _focus, 0.0)
	var offset := Vector3(
			sin(_yaw) * cos(_pitch),
			sin(_pitch),
			cos(_yaw) * cos(_pitch)) * _distance
	_camera.position = target + offset
	_camera.look_at(target, Vector3.UP)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		match button.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_distance = maxf(0.9, _distance - 0.25)
				_update_camera()
			MOUSE_BUTTON_WHEEL_DOWN:
				_distance = minf(12.0, _distance + 0.25)
				_update_camera()
			MOUSE_BUTTON_LEFT:
				_dragging = button.pressed
			_:
				return
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		_yaw -= motion.relative.x * 0.01
		_pitch = clampf(_pitch + motion.relative.y * 0.01, -1.2, 1.3)
		_update_camera()
		accept_event()
