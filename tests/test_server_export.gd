extends Node
## Headless check that the DEDICATED-SERVER export still ships the ground. Run:
##   godot --headless --path . res://tests/test_server_export.tscn
## Prints EXPORTTEST RESULT=PASS/FAIL and exits with the matching code.
##
## This guards one bug that has now happened twice, is invisible in the editor,
## and is catastrophic in play.
##
## The island's floor is not authored: `IslandWorld.grow_collision` builds it at
## runtime out of the RENDER meshes, because a glTF ships no collision shapes.
## The dedicated-server preset strips visual resources — which is the point of
## it, the box has 414 MiB and never draws a frame — so unless the island is
## marked "keep", the server stands up a world with no ground in it. Every
## client looks fine, the editor looks fine, and on the live server everything
## falls through the island and dies to the KILL_Y check on a loop.
##
## It regressed the first time because Godot REWRITES export_presets.cfg
## whenever anyone touches a preset in the editor, and dropped the entry (commit
## 0bf5524, "Build out the starter island"). Hence a test rather than a comment.
##
## Nothing here exports anything: it reads the preset file and the scenes, which
## is exactly the pair that has to agree.

const PRESETS := "res://export_presets.cfg"
## Every scene that grows a floor out of its meshes at runtime. The glb each one
## uses is read out of the scene rather than written here, so re-authoring the
## island from a different file moves this check with it.
const GROUND_SCENES := [
	"res://scenes/world.tscn",
	"res://scenes/world/tutorial/tutorial_arena.tscn",
]
## The node whose children become the collider, in each of those scenes.
const GROUND_NODE := "Island1"

var _failures: Array[String] = []

func _ready() -> void:
	var keeps := _kept_paths()
	print("  keep entries in the dedicated-server preset: %s" % [keeps])
	if keeps.is_empty():
		_fail("the dedicated-server preset keeps NOTHING — every mesh is stripped")

	for scene: String in GROUND_SCENES:
		var ground := _ground_source(scene)
		if ground.is_empty():
			_fail("%s has no '%s' to grow a floor from" % [scene, GROUND_NODE])
			continue
		var kept_by := ""
		for k: String in keeps:
			if ground.begins_with(k):
				kept_by = k
				break
		print("  %s -> %s -> %s" % [scene.get_file(), ground.get_file(),
				"kept by '%s'" % kept_by if kept_by != "" else "STRIPPED"])
		if kept_by == "":
			_fail(("%s builds its collision from %s, which the server export "
					+ "strips — the server would have no ground") % [scene, ground])
			continue
		# The FOLDER form on purpose: an entry naming the single .glb worked for
		# one export and was dropped the next time Godot rewrote the file, which
		# is exactly how this regressed before.
		if not kept_by.ends_with("/"):
			_fail(("the keep entry '%s' names a file, not a folder — Godot drops "
					+ "those when it rewrites export_presets.cfg") % kept_by)

	if _failures.is_empty():
		print("EXPORTTEST RESULT=PASS")
		get_tree().quit(0)
	else:
		for f in _failures:
			print("  FAIL: %s" % f)
		print("EXPORTTEST RESULT=FAIL (%d)" % _failures.size())
		get_tree().quit(1)

func _fail(msg: String) -> void:
	_failures.append(msg)

## Paths marked "keep" in whichever preset is the dedicated server. Found by the
## FLAG rather than by the preset's name, so renaming "Linux" does not quietly
## stop this test from checking anything.
func _kept_paths() -> Array:
	var text := FileAccess.get_file_as_string(PRESETS)
	var out: Array = []
	var dedicated := false
	var in_block := false
	for raw: String in text.split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("[preset."):
			dedicated = false  # a new preset section: earn the flag again
			in_block = false
		elif line == "dedicated_server=true":
			dedicated = true
		elif line.begins_with("customized_files="):
			in_block = dedicated
		elif in_block:
			if line.begins_with("}"):
				in_block = false
			elif line.ends_with("\"keep\"") or line.ends_with("\"keep\","):
				out.append(line.get_slice("\"", 1))
	return out

## The file the ground node is instanced from, read out of the .tscn text: find
## the node, take its ExtResource id, and look that id up in the header.
func _ground_source(scene_path: String) -> String:
	var text := FileAccess.get_file_as_string(scene_path)
	if text.is_empty():
		return ""
	var id := ""
	for raw: String in text.split("\n"):
		if raw.begins_with("[node name=\"%s\"" % GROUND_NODE) and "ExtResource(" in raw:
			id = raw.get_slice("ExtResource(\"", 1).get_slice("\"", 0)
			break
	if id.is_empty():
		return ""
	for raw: String in text.split("\n"):
		if raw.begins_with("[ext_resource") and "id=\"%s\"" % id in raw:
			return raw.get_slice("path=\"", 1).get_slice("\"", 0)
	return ""
