extends Node3D
## Look-at aid, not a pass/fail test: stands the player in front of each talking
## character in the game and takes the shot the CAMERA actually frames when a
## conversation opens.
##   godot --path . res://tests/preview_dialog_camera.tscn
## Needs a real window — do NOT pass --headless. Shots land in
## user://dialog_camera_preview.
##
## This is the only way to see the thing it exists to check. Cinematic aims at a
## height above the speaker's origin, and the characters in this game are voxel
## NPCs of very different heights — a number tuned on one of them frames the next
## one's chest, or the empty air over their head. The print-out beside each shot
## is the measurement the aim is derived from.

const OUT_DIR := "user://dialog_camera_preview"
const PLAYER := preload("res://scenes/player.tscn")
const INTERACTABLE := preload("res://scenes/entities/npc/npc_interactable.tscn")

## Who to stand in front of: scene, the conversation they open, how far away.
const CAST := [
	{"scene": "res://scenes/entities/npc/built/kingnpc.tscn", "dialog": "king"},
	{"scene": "res://scenes/entities/npc/built/villager.tscn", "dialog": "tut_mayor"},
]

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	Net.players[1] = {"name": "Tester", "kills": 0, "deaths": 0}

	var pawn: Node3D = PLAYER.instantiate()
	pawn.name = "1"
	pawn.peer_id = 1
	pawn.username = "Tester"
	$Players.add_child(pawn)
	pawn.global_position = Vector3.ZERO
	pawn.set_physics_process(false)
	await get_tree().process_frame

	for row: Dictionary in CAST:
		var npc: Node3D = load(str(row["scene"])).instantiate()
		npc.add_to_group("npc") # as the world tags them; see CLAUDE.md on groups
		add_child(npc)
		npc.global_position = Vector3(0.0, 0.0, -2.6) # in front of the player
		# TURNED AWAY on purpose: an NPC faces whichever way it was dropped into
		# the level and the player walks up from wherever they like, so being
		# talked to from behind is the ordinary case, not the odd one. A preview
		# that stands them already facing you proves nothing.
		npc.rotation.y = PI
		var talk: Node3D = INTERACTABLE.instantiate()
		talk.dialog_id = str(row["dialog"])
		npc.add_child(talk)
		# a few frames for the rig to build itself before it is measured
		for _i in 6:
			await get_tree().process_frame
		var aabb := _bounds(npc)
		print("PREVIEW %s: height=%.2f -> face %.2f, camera %.2f back" % [
				npc.name, aabb.size.y,
				Cinematic.look_point(talk).y - npc.global_position.y,
				Cinematic.frame_spring(talk)])

		var before := npc.rotation.y
		DialogSystem.start(str(row["dialog"]), talk)
		await _shot(str(row["dialog"]))
		print("PREVIEW %s: yaw %.2f -> %.2f (player is at +Z)" % [npc.name, before,
				npc.rotation.y])
		DialogSystem.close()
		Cinematic.unfocus()
		npc.queue_free()
		await get_tree().process_frame

	print("PREVIEW saved=", ProjectSettings.globalize_path(OUT_DIR))
	get_tree().quit()

## Every mesh under `node`, in the node's own space — what the character really
## occupies, which is not something a Node3D knows on its own.
func _bounds(node: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi: MeshInstance3D in _meshes(node):
		var box := mi.get_aabb()
		var xf := node.global_transform.affine_inverse() * mi.global_transform
		box = xf * box
		if first:
			out = box
			first = false
		else:
			out = out.merge(box)
	return out

func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_meshes(c))
	return out

func _shot(shot_name: String) -> void:
	# long enough for the camera to swing on and the box to type itself in
	for _i in 100:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [OUT_DIR, shot_name])
