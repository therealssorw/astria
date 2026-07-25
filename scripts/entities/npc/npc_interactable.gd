extends Node3D
class_name NpcInteractable
## Drop this next to (or on) any NPC to make it talkable: a speech-bubble
## marker appears over its head while the local player is close, and pressing
## interact opens the conversation named by `dialog_id`.
##
## This node only decides *whether* the marker should show and how faded it is
## — the HUD draws it (scripts/ui/dialog/npc_prompt_overlay.gd), the same way
## the enemy wind-up star is drawn.
##
## Reuse = instance scenes/entities/npc/npc_interactable.tscn, place it at the
## NPC, and set `dialog_id` to a key of DialogData.DIALOGS.

const FADE_SPEED := 6.0

## Key of DialogData.DIALOGS to play.
@export var dialog_id := ""
## How close the local player must be for the marker to appear (metres).
@export var interact_range := 3.5
## Where the bubble's tail points, relative to this node.
@export var prompt_offset := Vector3(0, 2.1, 0)

## 0..1, ramped so the marker fades instead of popping. Read by the HUD.
var prompt_alpha := 0.0

var _player: Node3D
var _focused := false

func _ready() -> void:
	add_to_group("npc_interactable")

func _process(delta: float) -> void:
	_focused = _can_interact()
	prompt_alpha = move_toward(prompt_alpha, 1.0 if _focused else 0.0, FADE_SPEED * delta)
	if _focused and Input.is_action_just_pressed("interact"):
		DialogSystem.start(dialog_id)

func prompt_anchor() -> Vector3:
	return global_position + prompt_offset

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

func _find_player() -> Node3D:
	var found := get_tree().get_nodes_in_group("local_player")
	return found[0] as Node3D if found.size() > 0 else null
