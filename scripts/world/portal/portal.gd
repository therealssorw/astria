@tool
extends Node3D
class_name Portal
## A doorway between two places that are nowhere near each other in the level.
## It comes in two flavours, and which one a door is is ONE EXPORT:
##
##   walk-in (default)      — you are through the moment you are inside it. What
##                            a way OUT should be: nobody wants to press a button
##                            to leave a room they are done with.
##   `require_interact`     — you stand in it and PRESS (E / pad Y, the same
##                            binding that talks to an NPC), with the same speech
##                            bubble over it. What a way IN should be: a door you
##                            can walk past without being swallowed by it.
##
## The mechanism is one and the same either way — both ends call
## `Net.server_teleport_to`, so a portal can be switched from one to the other
## without anything else in the level changing.
##
## The destination is a NAME, never a coordinate — the same "a marker in a
## group IS the place" trick as `TeleportAnchor`, `QuestAnchor` and
## `spawn_point.gd`. So a portal points at a `TeleportData` id, the landing spot
## is whatever `TeleportAnchor` wears that id, and moving either end in the
## editor moves it. Nothing here knows where anything is.
##
## SERVER-AUTHORITATIVE, like every other way a pawn moves. A walk-in portal is
## polled by the server against its OWN copy of each pawn (the position it has
## already speed-validated). A press is a REQUEST that names nothing at all: the
## server finds the interact portal its own copy of that pawn is standing in
## (`Net._server_portal_enter`), so the worst a patched client can do is press a
## button at a door it is really standing at.
##
## Deliberately NOT an Area3D. A trigger volume answers "is a body touching my
## shape", which needs the pawn on the right collision layer and reports on the
## CLIENT too, where the answer means nothing. A distance against the server's
## own copy is the thing actually being asked, and it is one line.

## Key of `TeleportData.DESTINATIONS` to send players to.
@export var destination_id := ""

## How close counts as being in the doorway, in metres. The same range decides
## the walk-in, the prompt and what the server will honour a press for.
@export var radius := 3.5

## How far above or below the portal still counts, so a doorway on a slope
## still works and one you walk over on a bridge does not.
@export var height := 4.0

## PRESS TO GO THROUGH, rather than being taken through by standing there. The
## prompt only exists in this mode — a walk-in portal has nothing to tell you.
@export var require_interact := false

## Where the bubble's tail points, relative to this node. Same idea as
## `NpcInteractable.prompt_offset`.
@export var prompt_offset := Vector3(0, 2.4, 0)

## Group every portal joins, so the server can find the one a player is standing
## in without the client naming it.
const GROUP := "portal"

const FADE_SPEED := 6.0

## 0..1, ramped so the bubble fades instead of popping. Read by the HUD — the
## same contract `NpcInteractable` answers (see npc_prompt_overlay.gd).
var prompt_alpha := 0.0

## Peers seen OUTSIDE the radius at least once, which is what makes a player
## ARRIVING inside a portal not immediately go back through it. A return
## portal and the anchor players land on are near each other by nature, and
## without this the two ends bounce a player between them forever. Walking up
## to a portal is always seen from outside first, so the ordinary case is
## unaffected. It guards the PRESS as well: arriving on top of a door must not
## let the button you are still holding send you straight back.
var _seen_outside := {}

var _player: Node3D
var _focused := false

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	add_to_group(GROUP)
	if require_interact:
		add_to_group(PromptTarget.GROUP) # the HUD draws whatever is in here

func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not require_interact:
		return
	_focused = _can_interact()
	prompt_alpha = move_toward(prompt_alpha, 1.0 if _focused else 0.0, FADE_SPEED * delta)

## Deliberately an *unhandled* input rather than polling the action, for the
## reason NpcInteractable documents: a panel or a dialog box marks its own
## interact presses handled, and a poll would see one it was never meant to.
func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or not require_interact:
		return
	if _focused and event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		# names nothing: the server works out which door this is from its own
		# copy of where the pawn is standing
		Net.request_portal_enter()

func prompt_anchor() -> Vector3:
	return global_position + prompt_offset

## Is `pos` inside this doorway? The one place the shape of a portal is decided,
## asked by the walk-in poll, by the prompt and by the server when it validates a
## press — so the thing you can see you are standing in is the thing that opens.
func contains(pos: Vector3) -> bool:
	var to := pos - global_position
	return Vector2(to.x, to.z).length() <= radius and absf(to.y) <= height

## SERVER: has this peer been seen outside the door since it last went through?
## What stops an arrival counting as an entry, in both modes.
func may_enter(id: int) -> bool:
	return bool(_seen_outside.get(id, false))

## SERVER: they have gone through — the next entry needs another approach.
func consume(id: int) -> void:
	_seen_outside[id] = false

func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or not multiplayer.is_server():
		return
	if destination_id == "":
		return
	for pawn in get_tree().get_nodes_in_group("player"):
		if not pawn is Node3D or pawn.dead:
			continue
		var id: int = pawn.peer_id
		if not contains((pawn as Node3D).global_position):
			_seen_outside[id] = true
			continue
		# INSIDE it. A walk-in door takes them now; one that wants a press just
		# remembers they are here, and waits (see Net._server_portal_enter).
		if require_interact or not may_enter(id):
			continue
		consume(id)
		Net.server_teleport_to(id, destination_id)

## Local, and only ever about the player at this screen: near enough, alive, and
## not busy with something that owns the interact button.
func _can_interact() -> bool:
	if destination_id == "" or DialogSystem.is_open():
		return false
	if not is_instance_valid(_player):
		var found := get_tree().get_nodes_in_group("local_player")
		_player = found[0] as Node3D if found.size() > 0 else null
		if _player == null:
			return false
	if _player.get("dead") or _player.get("ui_open"):
		return false
	if not contains(_player.global_position):
		return false
	# A DOOR YIELDS TO A PERSON. One button, so two prompts at once would be two
	# things it might do — and which one won would come down to tree order. An
	# NPC standing in a doorway is the case, and they are the more interesting
	# half of it.
	for npc in get_tree().get_nodes_in_group("npc_interactable"):
		if is_instance_valid(npc) and float(npc.get("prompt_alpha")) > 0.001:
			return false
	return true
