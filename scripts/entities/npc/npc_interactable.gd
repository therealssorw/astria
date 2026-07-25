extends Node3D
class_name NpcInteractable
## Drop this next to (or on) any NPC to make it talkable: it shows a floating
## button badge when the local player is close and opens the conversation named
## by `dialog_id` when they press interact.
##
## Reuse = instance scenes/entities/npc/npc_interactable.tscn, place it at the
## NPC, and set `dialog_id` to a key of DialogData.DIALOGS.

## Key of DialogData.DIALOGS to play.
@export var dialog_id := ""
## How close the local player must be for the prompt to appear (metres).
@export var interact_range := 3.5
## Where the badge floats, relative to this node.
@export var prompt_offset := Vector3(0, 2.1, 0)
## Small caption under the badge; leave empty for just the button.
@export var action_text := "Talk"

var _prompt: InteractPrompt
var _player: Node3D
var _focused := false

func _ready() -> void:
	add_to_group("npc_interactable")
	_prompt = InteractPrompt.new(action_text)
	_prompt.position = prompt_offset
	add_child(_prompt)

func _process(_delta: float) -> void:
	_set_focused(_can_interact())
	if _focused and Input.is_action_just_pressed("interact"):
		DialogSystem.start(dialog_id)

func _exit_tree() -> void:
	_set_focused(false)

## Closest in-range NPC wins, so two NPCs standing together never both prompt.
func _can_interact() -> bool:
	if dialog_id == "" or DialogSystem.is_open():
		return false
	if not is_instance_valid(_player):
		_player = _find_player()
		if _player == null:
			return false
	if _player.get("dead") or _player.get("ui_open"):
		return false
	var d := global_position.distance_to(_player.global_position)
	if d > interact_range:
		return false
	for other in get_tree().get_nodes_in_group("npc_interactable"):
		if other == self or not (other is NpcInteractable) or other.dialog_id == "":
			continue
		if other.global_position.distance_to(_player.global_position) < d:
			return false
	return true

func _set_focused(on: bool) -> void:
	if _focused == on:
		return
	_focused = on
	_prompt.show_prompt(on)
	# the inventory shares the E key, so it checks this group before toggling
	if on:
		add_to_group("npc_focused")
	else:
		remove_from_group("npc_focused")

func _find_player() -> Node3D:
	var found := get_tree().get_nodes_in_group("local_player")
	return found[0] as Node3D if found.size() > 0 else null
