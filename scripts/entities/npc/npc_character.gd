@tool
class_name NpcCharacter
extends Node3D
## A finished NPC: drop one in the world, point it at an NpcDefinition, done.
##
## The NPC Builder writes a scene with this as the root, so placing a villager
## is the same gesture as placing any other prop. Everything below it (the
## rigged visual, the talk marker) is generated at load time from the
## definition rather than being saved into the scene, which means re-colouring
## an NPC in the builder updates every copy already placed in the world.

@export var definition: NpcDefinition:
	set(value):
		definition = value
		_rebuild()

var visual: NpcVisual
var interactable: NpcInteractable

var _last_pos := Vector3.ZERO
var _has_last := false

func _ready() -> void:
	_rebuild()

## An NPC ANIMATES ITSELF, off its own movement. Nothing was ticking a placed
## NPC's visual at all, so every villager and King in the world stood in the pose
## its AnimationPlayer happened to load with — and the tutorial's villager slid
## across the island without moving her legs.
##
## Measuring its own ground speed rather than being told means anything that
## moves an NPC gets the walk for free, with no code on the other end: the
## tutorial arena just changes her position, as it always did.
func _process(delta: float) -> void:
	if Engine.is_editor_hint() or visual == null or not visual.has_clips():
		return
	var speed := 0.0
	if _has_last and delta > 0.0:
		speed = _last_pos.distance_to(global_position) / delta
	_last_pos = global_position
	_has_last = true
	visual.tick_motion(delta, speed)

func _rebuild() -> void:
	if not is_inside_tree():
		return
	for child in [visual, interactable]:
		if is_instance_valid(child):
			remove_child(child)
			child.free()
	visual = null
	interactable = null
	if definition == null:
		return

	visual = NpcVisual.new()
	visual.name = "Visual"
	visual.definition = definition
	# An NPC standing in the world view only has to look right, not walk, so
	# the editor skips the clip library. Adding it is what builds it -- asking
	# again afterwards would parent a second copy over the first.
	visual.build_clips = not Engine.is_editor_hint()
	add_child(visual)

	interactable = NpcInteractable.new()
	interactable.name = "Interactable"
	interactable.dialog_id = definition.dialog_id
	interactable.interact_range = definition.interact_range
	interactable.prompt_offset = Vector3.UP * (definition.height + definition.prompt_lift)
	add_child(interactable)
	# Deliberately no owner: these are rebuilt from the definition every load,
	# so they must not be serialised into whichever scene the NPC sits in.
