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

## How far up the body the camera looks when this character talks: the eye line,
## not the crown.
const LOOK_FRACTION := 0.88
## For a speaker with no body to measure at all — a voice from nowhere.
const LOOK_FALLBACK := 1.5
## How quickly a character turns to face whoever just spoke to them.
const FACE_SPEED := 7.0

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
## Cached body measurements, taken on first ask. -1 = not measured yet; the rig
## has to have built itself before there is anything to measure, which it has by
## the time anybody is talking.
var _look_y := -1.0
var _height := -1.0

func _ready() -> void:
	add_to_group("npc_interactable")
	# ...and the group everything with a press-me bubble over it is in, which is
	# what the HUD actually draws (see PromptTarget). The one above stays: it is
	# how NPCs find EACH OTHER, so that two standing together never both prompt.
	add_to_group(PromptTarget.GROUP)

func _process(delta: float) -> void:
	_focused = _can_interact()
	prompt_alpha = move_toward(prompt_alpha, 1.0 if _focused else 0.0, FADE_SPEED * delta)

## Deliberately an *unhandled* input rather than polling the action: the dialog
## box marks its own interact presses handled, so the press that walks off the
## last line can no longer be seen here in the same frame and instantly reopen
## the conversation you were leaving.
func _unhandled_input(event: InputEvent) -> void:
	if _focused and event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		# hand ourselves over as the speaker: the camera frames whoever is
		# talking, and the cinematic bars come in while they are
		DialogSystem.start(dialog_id, self)

func prompt_anchor() -> Vector3:
	return global_position + prompt_offset

## Where the camera looks while this character is talking — their face.
##
## MEASURED off the body rather than being a constant, because the characters are
## not one height: the King stands 2.40 m and a villager 1.85 m, so any single
## number frames one of them and misses the other. It used to be a flat 1.5 m,
## which is the King's waist.
func look_anchor() -> Vector3:
	_measure()
	return global_position + Vector3.UP * _look_y

## How tall this character stands, in metres. The shot is framed off it: a 2.40 m
## King and a 1.85 m villager cannot share one camera distance and both end up
## in frame.
func body_height() -> float:
	_measure()
	return _height

## Turn to face `at` — where the player is standing. Nudged every frame while the
## conversation is up, so the character LOOKS UP at whoever spoke to them.
##
## Without this they answer you with their back turned, facing whichever way they
## were dropped into the level: an NPC is a prop with a fixed rotation, and
## nothing else in the game has any reason to turn one. It is the same kind of
## purely local, purely cosmetic move as the camera swing beside it — NPC
## transforms are not replicated, so this is one player's view of the scene.
func turn_toward(at: Vector3, delta: float) -> void:
	var body := _body_node()
	var to := at - body.global_position
	to.y = 0.0
	if to.length_squared() < 0.0025:
		return
	# the same yaw Enemy.face_toward uses, +PI and all: these rigs are modelled
	# facing +Z, so the plain look-at yaw would turn their back to the player
	var want := atan2(-to.x, -to.z) + PI
	body.rotation.y = lerp_angle(body.rotation.y, want, minf(delta * FACE_SPEED, 1.0))

func _measure() -> void:
	if _look_y >= 0.0:
		return
	var box := _body_bounds(_body_node())
	if box.size.y <= 0.01:
		_look_y = LOOK_FALLBACK
		_height = LOOK_FALLBACK
		return
	_height = box.size.y
	_look_y = (box.position.y - global_position.y) + box.size.y * LOOK_FRACTION

## The node that IS the character — the one to measure and the one to turn.
##
## Two layouts exist in the world and both have to keep working: this node is
## either the NPC's own root with the body underneath it (the blacksmith), or a
## child sitting at the NPC's origin (the King, and every built NPC). So the body
## is looked for here first and at the PARENT second — and only when that parent
## is a character, or a sibling arrangement would take the whole level.
func _body_node() -> Node3D:
	if _body_bounds(self).size.y > 0.01:
		return self
	var parent := get_parent()
	if parent is Node3D and _is_character(parent):
		return parent as Node3D
	return self

## Is this node the character we are hanging off, rather than whatever container
## a sibling arrangement happens to sit in? Two signals, either will do: the
## scene-level group every NPC in the world wears, and the `definition` a built
## NPC carries — so a villager dragged in and not yet grouped still measures.
func _is_character(node: Node) -> bool:
	return node.is_in_group("npc") or node.get("definition") != null

## Everything `root` draws, as one box in GLOBAL space.
func _body_bounds(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in _meshes(root):
		var box: AABB = mi.global_transform * mi.get_aabb()
		if first:
			out = box
			first = false
		else:
			out = out.merge(box)
	return out

func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for c in node.get_children():
		out.append_array(_meshes(c))
	return out

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
