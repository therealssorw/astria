class_name NpcVisual
extends HumanoidVisual
## A built voxel NPC, rigged onto the same skeleton Rouge uses.
##
## The skeleton comes from rouge.fbx itself -- Rouge's meshes are thrown away
## and only the bones are kept, then NpcRig reshapes them to the voxel model's
## proportions and skins the parts on. Because it is literally the same rig,
## the clip library in HumanoidVisual plays without any extra retargeting.

const RIG_SOURCE := "res://Assets/Models/Entity/Humanoid/Human/rouge.fbx"

## NPCs stand around and walk; they never fight, so the combat and traversal
## clips are not built (each one is an FBX load).
const NPC_CLIPS := ["idle", "walk", "run"]

@export var definition: NpcDefinition

## Metrics NpcRig measured off the parts -- crown height, hip height, the voxel
## size it settled on. Used for the collision capsule and the dialog prompt.
var layout := {}

func _clip_keys() -> Array:
	return NPC_CLIPS

func _build_model() -> void:
	model = (load(RIG_SOURCE) as PackedScene).instantiate()
	model.name = "Model"
	add_child(model)
	skeleton = _find_skeleton(model)
	if skeleton == null:
		return
	# Only the bones are wanted; Rouge's own body is dropped before the voxel
	# parts go on (immediately, not queue_free, so it never renders).
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mi.get_parent().remove_child(mi)
		mi.free()

	# An empty definition still rigs -- a correctly proportioned skeleton with
	# nothing on it. That is indistinguishable from "the mesh was lost" once it
	# is on screen, so it is worth a line of its own rather than leaving the
	# caller to work out why their NPC is a set of bones.
	if definition == null:
		push_error("NpcVisual '%s' was built with no definition — it will be a bare skeleton"
				% (get_path() if is_inside_tree() else name))
	var def: NpcDefinition = definition if definition != null else NpcDefinition.new()
	layout = NpcRig.rig(def, skeleton)
	_collect_materials()

## Re-rigs in place against a changed definition -- what the NPC Builder's
## preview does on every edit. Cheap unless the pelvis moved, because that is
## the one thing the baked clips depend on.
func rebuild(def: NpcDefinition) -> void:
	if skeleton == null:
		return
	definition = def
	var previous_hip: float = layout.get("hip_y", 0.0)
	for mi: MeshInstance3D in skeleton.find_children("*", "MeshInstance3D", false, false):
		skeleton.remove_child(mi)
		mi.free()
	_mats.clear()
	layout = NpcRig.rig(def, skeleton)
	_collect_materials()
	if not is_equal_approx(previous_hip, layout.get("hip_y", 0.0)):
		build_animations()
		_play("idle", 0.0)

## Plays one clip by name (the preview's animation picker); no-op if unknown.
func preview_clip(key: String) -> void:
	if anim_player != null and anim_player.has_animation("lib/" + key):
		_play(key, 0.15)

func _collect_materials() -> void:
	for mi: MeshInstance3D in skeleton.find_children("*", "MeshInstance3D", false, false):
		var mat := mi.mesh.surface_get_material(0) as StandardMaterial3D
		if mat != null:
			_mats.append(mat)

## The clips move the Hips in absolute metres around a human pelvis; a voxel
## NPC's is somewhere else entirely (short legs, big head), so the motion is
## rebased onto ours and scaled by the same ratio. Without this the model would
## be yanked to Rouge's hip height the moment a clip started.
func _adapt_hips(v: Vector3) -> Vector3:
	var reference: float = layout.get("ref_hip_y", 0.0)
	var hip: float = layout.get("hip_y", 0.0)
	if reference <= 0.0001 or hip <= 0.0001:
		return v
	var k: float = hip / reference
	return Vector3(v.x * k, hip + (v.y - reference) * k, v.z * k)
