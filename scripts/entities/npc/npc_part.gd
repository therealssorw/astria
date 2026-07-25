class_name NpcPart
extends Resource
## One slot of a built NPC: which voxel model fills it, how it is coloured, and
## the nudges the NPC Builder lets you dial in when a part was not modelled in
## quite the same place as the rest.

## res:// path to the part model (a Goxel glTF export under
## Assets/Models/Entity/Humanoid/VoxelNpc/Parts/<Slot>/).
@export var model_path := ""

## One colour per palette entry of that model, in NpcRig.palette_of() order.
## Shorter than the palette = the remaining entries keep the model's own
## colours, so an empty array means "leave it exactly as authored".
@export var colors := PackedColorArray()

## Multiplied over every colour of the part. Swatches are the precise tool, but
## a hand-shaded model can carry a hundred palette entries and no one wants a
## hundred colour pickers -- a tint recolours it in one move.
@export var tint := Color.WHITE

## Nudge in voxels, in character space (+X left, +Y up, +Z forward). Parts are
## auto-centred and stacked, so this is only for art that needs it.
@export var offset := Vector3.ZERO

## Multiplier on this part's size, 1.0 = as modelled.
@export var scale := 1.0

func duplicate_part() -> NpcPart:
	var out := NpcPart.new()
	out.model_path = model_path
	out.colors = colors.duplicate()
	out.tint = tint
	out.offset = offset
	out.scale = scale
	return out
