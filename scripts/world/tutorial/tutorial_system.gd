extends Node
## The tutorial: you wake up on a copy of the island while it is being raided,
## you are taught one fighting button at a time with the bandits switched on a
## piece at a time to suit, and when the last of them is down you are put on
## the real island. Autoload: Tutorial.
##
## Two halves in one file, because they are two views of the same script:
##
## SERVER — owns everything. It gives each player a private copy of the island
## (`TutorialData.slot_origin`), spawns their bandits, walks the step table,
## sets how much of the AI each step wants switched on, and finally drops them
## on the real island. The bandits of a copy are told only to the player they
## belong to, fight only that player, and are cleaned up with the copy.
##
## CLIENT — owns nothing but the screen. It instances its own copy of the arena
## scene at the same coordinates (the way every peer loads the world scene),
## plays the line the step names, and puts the button prompt up. It reports the
## press for gates the server cannot see for itself, and the moment a line that
## the bandits are waiting on has been read; everything else the server reads
## off the requests the player is already sending it.
##
## A gate is deliberately NOT a pause menu: the bandits are held, the player is
## not. You can still walk, turn the camera and look at the thing about to hit
## you. It opens on the real action, so the lesson cannot be clicked through
## without doing it — and then waits for that action to FINISH before the next
## line starts, so nothing talks over the swing it just asked for.
##
## All of the spoken text lives in DialogData under the `tut_*` ids.

## Emitted on the client each time the step changes, for the HUD overlay.
## `step` is the step dictionary, empty when the tutorial is not running.
signal step_changed(step: Dictionary)

# ---------------- server state ----------------

## peer_id -> {
##   "slot": int, "arena": TutorialArena, "index": int,
##   "bandits": Array[Node], "ready": bool, "gate_done": bool,
## }
var _runs := {}
var _used_slots := {}

# ---------------- client state ----------------

var _my_arena: TutorialArena = null
var _my_step := {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)

# ================= server =================

func server_running(id: int) -> bool:
	return _runs.has(id)

## Start `id`'s tutorial and answer with where they wake up, or ERR (Vector3.INF)
## when there is no room and they should just go to the island.
func server_begin(id: int) -> Vector3:
	if not multiplayer.is_server():
		return Vector3.INF
	if _runs.has(id):
		server_end(id, false)
	var slot := _free_slot()
	if slot < 0:
		push_warning("Tutorial: all %d copies are in use — skipping" % TutorialData.MAX_SLOTS)
		return Vector3.INF
	var arena := _build_arena(slot, id)
	if arena == null:
		return Vector3.INF
	_used_slots[slot] = id
	_runs[id] = {"slot": slot, "arena": arena, "index": 0, "bandits": [],
			"ready": false, "gate_done": false}
	Net.tutorial_enter(id, slot)
	set_process(true)
	_enter_step(id, 0)
	return arena.player_spawn()

## Where a player in the tutorial respawns after dying: back in their own city,
## not on the island they have not reached yet.
func server_respawn_position(id: int) -> Vector3:
	var run: Dictionary = _runs.get(id, {})
	if run.is_empty() or not is_instance_valid(run["arena"]):
		return Vector3.INF
	return (run["arena"] as TutorialArena).player_spawn()

## Tear it down. `graduate` sends the player to the island; a disconnect or a
## restart passes false and leaves placing them to the caller.
func server_end(id: int, graduate: bool) -> void:
	var run: Dictionary = _runs.get(id, {})
	if run.is_empty():
		return
	_runs.erase(id)
	_used_slots.erase(run["slot"])
	for b in run["bandits"]:
		if is_instance_valid(b):
			Net.server_despawn_enemy(b)
	if is_instance_valid(run["arena"]):
		# queue_free is deferred, so the old copy is still in the tree for the
		# rest of the frame. Take its name with it, or a restart in the same
		# slot (the cheat) finds the DYING island when it looks its copy up.
		var old: Node = run["arena"]
		old.name = "TutorialArena_gone_%d" % run["slot"]
		old.queue_free()
	Net.tutorial_leave(id)
	if _runs.is_empty():
		set_process(false)
	if graduate:
		Net.server_place_on_island(id)

## The client's cutscene finished — from here the city may start moving.
func server_report_ready(id: int) -> void:
	var run: Dictionary = _runs.get(id, {})
	if run.is_empty():
		return
	run["ready"] = true
	if _step_of(id).get("kind", "") == "wait_ready":
		_advance(id)

## A gate the server cannot watch for itself (lock-on lives entirely in the
## client's camera) says it was done. Only accepted for that kind of step.
func server_report_pressed(id: int, step_id: String) -> void:
	var step := _step_of(id)
	if step.get("id", "") != step_id:
		return
	if bool(step.get("client_gate", false)):
		_advance(id)

# ---------------- server: the walk through the table ----------------

func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	for id: int in _runs.keys():
		var run: Dictionary = _runs[id]
		var step := _step_of(id)
		match str(step.get("kind", "")):
			"clear":
				if _wave_cleared(id):
					_advance(id)
			"gate":
				var action := str(step.get("action", ""))
				if not bool(step.get("client_gate", false)):
					if not bool(run.get("gate_done", false)):
						if _gate_satisfied(id, action):
							run["gate_done"] = true
							run["done_time"] = 0.0
					else:
						# they did it — now let them FINISH it. Talking over the
						# swing you just asked for reads as not having noticed.
						run["done_time"] = float(run.get("done_time", 0.0)) + delta
						if _action_over(id, action) \
								or run["done_time"] >= TutorialData.FINISH_GRACE:
							_advance(id)
						continue
				# a gate is a lesson, not a lock: give in eventually rather than
				# leave a player in front of bandits frozen forever
				run["gate_time"] = float(run.get("gate_time", 0.0)) + delta
				if run["gate_time"] >= TutorialData.patience(step):
					print("[Tutorial] peer %d spent %.0fs on '%s' — moving on"
							% [id, TutorialData.patience(step), step.get("id", "")])
					_advance(id)

## Did the player really do it? Read off the SERVER's own copy of the pawn,
## which is where a swing and a raised guard already live for every player,
## host or remote — so a gate opens on the action itself and there is nothing
## for a client to claim.
func _gate_satisfied(id: int, action: String) -> bool:
	var pawn := Net.pawn_of(id)
	if pawn == null or pawn.dead:
		return false
	match action:
		"attack":
			# any swing counts: "swing at him" is not the place to be strict
			# about which swing it was
			return pawn.attacking
		"attack_heavy":
			return pawn.attacking and pawn.attack_is_heavy
		"block":
			return pawn.blocking
	return false

## Has the thing the gate asked for run its course? A guard lowered, a swing
## played out. Read off the server's own copy of the pawn, like the gate itself.
func _action_over(id: int, action: String) -> bool:
	var pawn := Net.pawn_of(id)
	if pawn == null or pawn.dead:
		return true
	match action:
		"attack", "attack_heavy":
			return not pawn.attacking
		"block":
			return not pawn.blocking
	return true

func _step_of(id: int) -> Dictionary:
	var run: Dictionary = _runs.get(id, {})
	if run.is_empty():
		return {}
	return TutorialData.step(run["index"])

func _advance(id: int) -> void:
	var run: Dictionary = _runs.get(id, {})
	if run.is_empty():
		return
	_enter_step(id, int(run["index"]) + 1)

func _enter_step(id: int, index: int) -> void:
	var run: Dictionary = _runs.get(id, {})
	if run.is_empty():
		return
	run["index"] = index
	run["gate_time"] = 0.0
	run["gate_done"] = false
	run["done_time"] = 0.0
	var step := TutorialData.step(index)
	if step.is_empty():
		server_end(id, true)
		return
	match str(step.get("kind", "")):
		"wait_ready":
			if bool(run["ready"]):
				_advance(id)
				return
		"wave":
			_spawn_wave(id, int(step.get("count", 1)), TutorialData.hold_for(step))
			Net.tutorial_step(id, str(step["id"]))
			_advance(id) # a wave is a beat, not a wait
			return
		"gate", "clear":
			_set_wave_ai(id, TutorialData.hold_for(step))
		"end":
			server_end(id, true)
			return
	Net.tutorial_step(id, str(step["id"]))

func _spawn_wave(id: int, count: int, hold: Enemy.Hold) -> void:
	var run: Dictionary = _runs.get(id, {})
	if run.is_empty():
		return
	var arena: TutorialArena = run["arena"]
	var spawned: int = int(run.get("spawned", 0))
	for i in count:
		var bandit := Net.server_spawn_tutorial_bandit(id,
				arena.bandit_spawn(spawned + i), hold)
		if bandit:
			run["bandits"].append(bandit)
	run["spawned"] = spawned + count

## Switch every bandit of this run down (or up) to what the step wants of them.
func _set_wave_ai(id: int, hold: Enemy.Hold) -> void:
	var run: Dictionary = _runs.get(id, {})
	if run.is_empty():
		return
	for b in run["bandits"]:
		if is_instance_valid(b) and not b.dead:
			b.set_hold(hold)

func _wave_cleared(id: int) -> bool:
	var run: Dictionary = _runs.get(id, {})
	if run.is_empty():
		return false
	for b in run["bandits"]:
		if is_instance_valid(b) and not b.dead:
			return false
	return true

func _free_slot() -> int:
	for slot in TutorialData.MAX_SLOTS:
		if not _used_slots.has(slot):
			return slot
	return -1

func _build_arena(slot: int, id: int) -> TutorialArena:
	var world := get_tree().current_scene
	if world == null:
		return null
	var arena := TutorialData.ARENA_SCENE.instantiate() as TutorialArena
	arena.name = "TutorialArena_%d" % slot
	arena.owner_peer = id
	world.add_child(arena)
	arena.global_position = TutorialData.slot_origin(slot)
	return arena

# ================= client =================

## My copy of the city, at the same coordinates as the server's.
func client_enter(slot: int) -> void:
	client_leave()
	var world := get_tree().current_scene
	if world == null:
		return
	# the host is both peers at once: it already built this one as the server
	var existing := world.get_node_or_null("TutorialArena_%d" % slot)
	if existing:
		_my_arena = existing as TutorialArena
	else:
		_my_arena = TutorialData.ARENA_SCENE.instantiate() as TutorialArena
		_my_arena.name = "TutorialArena_%d" % slot
		_my_arena.owner_peer = multiplayer.get_unique_id()
		world.add_child(_my_arena)
		_my_arena.global_position = TutorialData.slot_origin(slot)

func client_leave() -> void:
	if is_instance_valid(_my_arena):
		# the server's own copy is freed by server_end; only free one we made
		if not multiplayer.is_server():
			_my_arena.queue_free()
	_my_arena = null
	_my_step = {}
	step_changed.emit(_my_step)

func client_step(step_id: String) -> void:
	# the popup is drawn straight off this by the HUD overlay; there is nothing
	# to say and nothing to wait for
	_my_step = TutorialData.step(TutorialData.index_of(step_id))
	step_changed.emit(_my_step)

func client_is_running() -> bool:
	return not _my_step.is_empty()

## The step the HUD should be drawing, empty when there is nothing to draw.
func client_step_data() -> Dictionary:
	return _my_step

## Gates the server cannot see (lock-on) are watched here and reported.
func _unhandled_input(event: InputEvent) -> void:
	if _my_step.is_empty() or str(_my_step.get("kind", "")) != "gate":
		return
	if not bool(_my_step.get("client_gate", false)):
		return
	var action := str(_my_step.get("action", ""))
	if action != "" and event.is_action_pressed(action):
		Net.report_tutorial_pressed(str(_my_step["id"]))
