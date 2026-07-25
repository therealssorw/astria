@tool
extends EditorPlugin
## Adds Project > Tools > "Remove Clouds from Sky": processes the current
## scene's panorama sky texture with CloudScrub, saves a *_noclouds.png next
## to the original, and assigns it to the sky material.

const MENU_LABEL := "Remove Clouds from Sky"

func _enter_tree() -> void:
	add_tool_menu_item(MENU_LABEL, _on_remove_clouds)

func _exit_tree() -> void:
	remove_tool_menu_item(MENU_LABEL)

func _on_remove_clouds() -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		_alert("Open the scene whose sky you want to process first.")
		return
	var world_env := _find_world_environment(root)
	if world_env == null or world_env.environment == null:
		_alert("No WorldEnvironment with an Environment found in this scene.")
		return
	var env: Environment = world_env.environment
	if env.sky == null or env.sky.sky_material == null:
		_alert("The Environment has no sky material.")
		return
	var mat := env.sky.sky_material
	if not (mat is PanoramaSkyMaterial):
		_alert("The sky is a %s — only PanoramaSkyMaterial has cloud imagery to remove. Procedural and physical skies are already cloud-free." % mat.get_class())
		return
	var pano: PanoramaSkyMaterial = mat
	if pano.panorama == null:
		_alert("The PanoramaSkyMaterial has no panorama texture.")
		return

	var src_path := pano.panorama.resource_path
	if src_path.get_basename().ends_with("_noclouds"):
		_alert("This sky already uses a _noclouds texture.")
		return

	var img := pano.panorama.get_image()
	if img == null:
		_alert("Couldn't read image data from the panorama texture.")
		return

	var cleaned := CloudScrub.remove_clouds(img)
	var out_path := src_path.get_basename() + "_noclouds.png"
	var err := cleaned.save_png(out_path)
	if err != OK:
		_alert("Failed to save %s (error %d)." % [out_path, err])
		return

	# import the new png, then swap it into the material
	var fs := EditorInterface.get_resource_filesystem()
	fs.update_file(out_path)
	fs.reimport_files([out_path])
	var tex := load(out_path)
	if tex is Texture2D:
		pano.panorama = tex
		EditorInterface.mark_scene_as_unsaved()
		_alert("Clouds removed.\nSaved and assigned: %s\n(The original texture is untouched — reassign it to revert.)" % out_path)
	else:
		_alert("Saved %s, but it couldn't be loaded yet — assign it to the sky manually." % out_path)

func _find_world_environment(n: Node) -> WorldEnvironment:
	if n is WorldEnvironment:
		return n
	for c in n.get_children():
		var r := _find_world_environment(c)
		if r:
			return r
	return null

func _alert(msg: String) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Sky Cloud Remover"
	dialog.dialog_text = msg
	EditorInterface.get_base_control().add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
