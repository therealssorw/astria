class_name ItemDrop
extends Node3D
## An item lying on the ground — what the juggernaut leaves behind. Purely
## cosmetic on every peer, exactly like [GoldDrop]: the SERVER decides who picks
## it up (nearest living player inside pickup range, checked in Net) and puts it
## in their bag. Clients just render the turning model.
##
## The model is the item's OWN art, through `ItemDb.build_model` — the same file
## its icon is a photograph of and the same one a character is seen holding. So a
## club that is repainted or resized in the catalogue changes here too, and there
## is nothing per-item to draw. An item with no art at all still drops: it comes
## up as a plain marker rather than nothing, because a reward you cannot see on
## the floor is a reward that was never given.

## Turn rate and bob, so a drop reads as lootable rather than as scenery.
const SPIN := 1.1
const BOB := 0.09
const BOB_RATE := 2.0
## How far off the ground the art floats before bobbing.
const LIFT := 0.55
## Fallback marker for an item with no art (see the note above).
const MARKER_SIZE := 0.35

var item_id := ""

var _visual: Node3D
var _t := 0.0

func _ready() -> void:
	_visual = Node3D.new()
	add_child(_visual)
	var art := ItemDb.build_model(item_id)
	if art == null:
		art = _marker()
	_visual.add_child(art)
	# stand it up off the floor: art is authored around its own origin, and a
	# blade dropped at ground level is half buried in it
	art.position = Vector3.UP * LIFT

func _process(delta: float) -> void:
	_t += delta
	_visual.position.y = sin(_t * BOB_RATE) * BOB
	_visual.rotation.y += delta * SPIN

func _marker() -> Node3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * MARKER_SIZE
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.78, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(0.5, 0.38, 0.08)
	mi.material_override = mat
	return mi

## Floating "Item Name" feedback where a drop was collected (all peers). The same
## gesture the gold uses, so a pickup reads the same however it was earned.
static func spawn_pickup_text(parent: Node, pos: Vector3, id: String) -> void:
	var label := Label3D.new()
	label.text = ItemDb.item_name(id)
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
