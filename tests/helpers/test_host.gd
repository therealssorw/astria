extends RefCounted
## Shared boot step for the headless integration tests: host a listen server
## and wait until this peer's own pawn is standing in the world.
##
## Every test that needs a world used to carry its own copy of the same loop —
## call Net.host_game(), then spin 900 physics frames looking for the first
## child of World/Players, and print "pawn never spawned" if it never turned
## up. That loop had two faults, and both of them read as that one message:
##
## - It never looked at whether HOSTING WORKED. `Net.host_game` returns an
##   Error and gives up BEFORE changing scene when the port will not bind, so a
##   port that was busy for a moment produced fifteen silent seconds and then a
##   complaint about pawns. That is the whole flake: roughly one run in four,
##   passing on the rerun, because whatever held the port had let go by then.
##   The engine says "Couldn't create an ENet host" three lines above the
##   failure and nothing joined the two up.
## - It counted PHYSICS FRAMES, which stop being a clock the moment a frame
##   runs longer than `max_physics_steps_per_frame`: loading the island and
##   growing its trimesh collision is exactly that kind of hitch, so the budget
##   is spent on wall-clock the test never asked for.
##
## So the bind is retried over a private band of ports (a test never has to
## care which one it gets), the wait is on wall clock, and every step of the
## boot — the scene swap, the Players container, the pawn itself — is waited
## for separately so a failure names the step that never happened.

## Where each test hosts. A band per test rather than one shared port: the
## tests get run back to back and sometimes at once, and Net.DEFAULT_PORT is
## also whatever game is already running from the editor.
const PORTS := {
	"tutorial": 27140,
	"hotbar": 27150,
	"teleport": 27160,
	"gold": 27170,
	"quest": 27180,
}
const BAND := 6              # ports tried, counting up from the band's base
const BIND_PASSES := 3       # walks of the band before giving up
const BIND_PAUSE := 0.75     # seconds between passes
const BOOT_TIMEOUT := 60.0   # seconds allowed for each step of the boot

## Why boot() gave up, naming the step. Empty until it does.
var error := ""
## The port hosting actually got — not necessarily the band's base.
var port := 0

## Hosts on `band`'s ports and hands back this peer's pawn, or null with the
## reason in `error`.
func boot(tree: SceneTree, band: String, username := "Tester") -> Node3D:
	if not await _host(tree, band, username):
		return null
	# 1. the scene swap. host_game defers it, and world.tscn is an island.
	if not await _wait(tree, func() -> bool:
			var s := tree.current_scene
			return s != null and String(s.name) == "World"):
		error = "the world scene never loaded (still on '%s' %.0fs after hosting on %d)" % [
				_scene_name(tree), BOOT_TIMEOUT, port]
		return null
	# 2. the container the server spawns into
	if not await _wait(tree, func() -> bool:
			return tree.current_scene.get_node_or_null("Players") != null):
		error = "the world loaded but has no Players container after %.0fs" % BOOT_TIMEOUT
		return null
	# 3. the pawn, which waits on world.gd's _ready calling Net.on_world_ready
	var pn: Node = tree.current_scene.get_node("Players")
	if not await _wait(tree, func() -> bool: return pn.get_child_count() > 0):
		error = "the server never put a pawn in World/Players after %.0fs (registered: %s)" % [
				BOOT_TIMEOUT, str(Net.players.keys())]
		return null
	return pn.get_child(0)

## Walks the band until one port binds. A busy port is transient — a sibling
## test still dying, Steam, a game left running — so the band is walked again
## after a pause rather than failing the run on one unlucky moment.
func _host(tree: SceneTree, band: String, username: String) -> bool:
	var base: int = PORTS.get(band, Net.DEFAULT_PORT)
	for _pass in BIND_PASSES:
		for step in BAND:
			if Net.host_game(username, false, base + step) == OK:
				port = base + step
				return true
		await tree.create_timer(BIND_PAUSE).timeout
	error = "could not open a port to host on: tried %d-%d, %d times over %.0fs (%s)" % [
			base, base + BAND - 1, BIND_PASSES, BIND_PASSES * BIND_PAUSE, Net.last_error]
	return false

## Frames until `cond` holds or `seconds` of WALL CLOCK have gone by. Not a
## frame count: the world's first frames are heavy enough that physics falls
## behind real time, so counting them measures the load and not the wait.
func _wait(tree: SceneTree, cond: Callable, seconds := BOOT_TIMEOUT) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if cond.call():
			return true
		await tree.physics_frame
	return cond.call()

func _scene_name(tree: SceneTree) -> String:
	var s := tree.current_scene
	return String(s.name) if s != null else "<none>"
