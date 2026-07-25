class_name RougeVisual
extends HumanoidVisual
## Rouge model (UE Manny rig) driven by Mixamo clips — both retargeted onto
## the shared humanoid profile at import, so the clips play directly on the
## character (the Godot equivalent of the spec's live IK retargeting).
##
## The rig and the clip library live in HumanoidVisual; this only supplies the
## mesh and rebinds its textures. Voxel NPCs are the other subclass, and they
## animate off the same library.

const MODEL := "res://Assets/Models/Entity/Humanoid/Human/rouge.fbx"
const TEX_DIR := "res://Assets/Textures/Humanoid/Human/Rouge/"

func _build_model() -> void:
	model = (load(MODEL) as PackedScene).instantiate()
	model.name = "Model"
	add_child(model)
	skeleton = _find_skeleton(model)
	_setup_materials()

func _setup_materials() -> void:
	# The FBX references its textures by filename, but they live in TEX_DIR
	# (not next to the model), so bind them here by matching material names
	# like "..._8_L_Calf_1_palette1.002" to files like "...-8-L_Calf-1.png".
	var tex_by_key := {}
	for f in DirAccess.get_files_at(TEX_DIR):
		var base := f.trim_suffix(".import")
		if base.ends_with(".png"):
			tex_by_key[_norm(base.trim_suffix(".png"))] = TEX_DIR + base
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s)
			if mat is StandardMaterial3D:
				var dup: StandardMaterial3D = mat.duplicate()
				if dup.albedo_texture == null:
					var key := _norm(mat.resource_name.split("_palette")[0])
					if tex_by_key.has(key):
						dup.albedo_texture = load(tex_by_key[key])
						# the FBX material's albedo color is near-black; the
						# texture is meant to carry the color
						dup.albedo_color = Color.WHITE
				mi.set_surface_override_material(s, dup)
				_mats.append(dup)

func _norm(s: String) -> String:
	var out := ""
	for ch in s.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
	return out
