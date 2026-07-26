extends Node

func _ready() -> void:
	for slot in ["feet", "body", "arms", "head"]:
		for p in NpcRig.list_parts(slot, "Base"):
			print("%s  %s" % [p, NpcRig.palette_of(p)])
	get_tree().quit()
