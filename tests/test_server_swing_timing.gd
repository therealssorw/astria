extends Node
## Headless check that a DEDICATED-SERVER build can still time a swing.
## Run it against the project:
##   godot --headless --path . res://tests/test_server_swing_timing.tscn
## and against the exported server pack, which is the run that matters:
##   godot --headless --main-pack build/Astria.pck res://tests/test_server_swing_timing.tscn
## Prints SWINGTEST RESULT=PASS/FAIL and exits with the matching code.
##
## This is the island's floor again, one layer up (see test_server_export.gd).
## `Player._begin_swing` asks the BODY how long a punch takes — the numbers come
## off the real clip, so retrimming an animation retimes the fight. That makes the
## animation library part of the SERVER's combat sim, not decoration: the server
## decides when a hit lands, when a combo may chain and when the swing is over.
## Strip the clips out of the dedicated-server export and every one of those
## timings is wrong, on the box that owns them, while every client — which has
## the clips — animates to the right ones. A heavy is the loudest case: about a
## second on a client, and the damage would land at the fallback 0.18 s.
##
## It is invisible everywhere a test usually looks: the editor has every asset,
## a listen server has every asset, and only the stripped build is missing them.

const SLACK := 0.005

var _failures: Array[String] = []

func _ready() -> void:
	var visual := RougeVisual.new()
	add_child(visual)
	print("  skeleton: %s" % ("built" if visual.skeleton != null else "MISSING"))
	if visual.skeleton == null:
		_fail("the player body built no skeleton — the server cannot time anything")
	print("  animation player: %s" % ("built" if visual.anim_player != null else "MISSING"))
	if visual.anim_player == null:
		_fail("the player body built no animation library")

	# Every clip a swing is timed off. A length of 0 is what a stripped export
	# leaves behind, and it is also what would silently shorten a punch.
	for key: String in ["light_0", "light_1", "light_2", "heavy"]:
		var length := float(visual.clip_lengths.get(key, 0.0))
		print("  %-8s clip %.3fs" % [key, length])
		if length <= 0.0:
			_fail("clip '%s' is missing from the build" % key)

	# ...and the numbers the sim actually runs on, which is the pair the client
	# and the server have to agree about.
	for heavy in [false, true]:
		for section in ([0] if heavy else [0, 1, 2]):
			var info: Dictionary = visual.get_attack_info(heavy, section)
			var name := "heavy" if heavy else "light_%d" % section
			print("  %-8s duration %.3fs  hit %.3fs  combo %.3fs" % [name,
					info.get("duration", 0.0), info.get("hit", 0.0),
					info.get("combo", 0.0)])
			if float(info.get("duration", 0.0)) <= SLACK:
				_fail("%s has no swing window — the server would fall back to the export default" % name)

	if _failures.is_empty():
		print("SWINGTEST RESULT=PASS")
		get_tree().quit(0)
	else:
		for f in _failures:
			print("  FAIL: %s" % f)
		print("SWINGTEST RESULT=FAIL (%d)" % _failures.size())
		get_tree().quit(1)

func _fail(msg: String) -> void:
	_failures.append(msg)
