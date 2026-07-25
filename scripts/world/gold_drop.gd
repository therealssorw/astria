class_name GoldDrop
extends Node3D
## A pile of gold dropped by a dead bandit. Purely cosmetic on every peer —
## the SERVER decides who picks it up (nearest living player inside pickup
## range, checked in Net) and awards the amount into the player registry.
## Clients just render the bobbing, spinning pile.

var amount := 0

var _visual: Node3D
var _t := 0.0

func _ready() -> void:
	_visual = Node3D.new()
	add_child(_visual)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.78, 0.2)
	mat.metallic = 0.8
	mat.roughness = 0.35
	# soft self-glow so the pile pops even in shade / tall grass
	mat.emission_enabled = true
	mat.emission = Color(0.55, 0.4, 0.08)
	mat.emission_energy_multiplier = 0.7
	# small stack of coins, slightly scattered so it reads as a pile
	for i in 3:
		var coin := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.16
		mesh.bottom_radius = 0.16
		mesh.height = 0.05
		coin.mesh = mesh
		coin.material_override = mat
		coin.position = Vector3(cos(i * 2.4) * 0.09, 0.03 + i * 0.052, sin(i * 2.4) * 0.09)
		coin.rotation.y = i * 1.1
		_visual.add_child(coin)

func _process(delta: float) -> void:
	_t += delta
	_visual.position.y = 0.1 + sin(_t * 2.5) * 0.06
	_visual.rotation.y += delta * 1.8

## Floating "+N gold" feedback where a pile was collected (all peers).
static func spawn_pickup_text(parent: Node, pos: Vector3, gold: int) -> void:
	var label := Label3D.new()
	label.text = "+%d gold" % gold
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 48
	label.pixel_size = 0.004
	label.outline_size = 12
	label.modulate = Color(0.98, 0.85, 0.3)
	parent.add_child(label)
	label.global_position = pos + Vector3.UP * 0.6
	var tw := label.create_tween()
	tw.tween_property(label, "global_position", pos + Vector3.UP * 1.8, 0.9)
	tw.parallel().tween_property(label, "modulate:a", 0.0, 0.9)
	tw.tween_callback(label.queue_free)
