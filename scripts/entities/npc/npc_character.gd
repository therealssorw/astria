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

func _ready() -> void:
	_rebuild()

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
	add_child(visual)
	if Engine.is_editor_hint():
		# NpcVisual is not a @tool script, so nothing built itself just now.
		# Do it by hand, minus the clip library -- an NPC standing in the world
		# view only has to look right, not walk.
		visual.build(false)

	interactable = NpcInteractable.new()
	interactable.name = "Interactable"
	interactable.dialog_id = definition.dialog_id
	interactable.interact_range = definition.interact_range
	interactable.prompt_offset = Vector3.UP * (definition.height + definition.prompt_lift)
	add_child(interactable)
	# Deliberately no owner: these are rebuilt from the definition every load,
	# so they must not be serialised into whichever scene the NPC sits in.
