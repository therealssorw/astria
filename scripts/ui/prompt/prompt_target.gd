class_name PromptTarget
extends RefCounted
## THE CONTRACT FOR "A THING YOU CAN PRESS INTERACT AT", and nothing else.
##
## A talkable NPC was the first, a door into the catacombs is the second, and
## there will be more (a chest, a lever, a sign). None of them are the same kind
## of node, so the marker over them is not drawn by asking what they ARE — it is
## drawn for anything in one group that can answer two things:
##
##   prompt_alpha   — 0..1, how faded the bubble is right now. The node ramps it
##                    itself, so the HUD never decides whether you are in range.
##   prompt_anchor() — the point in the world the bubble's tail points at.
##
## Join `PromptTarget.GROUP` and answer those two and the speech bubble appears
## over you, with the right button for whatever device was last touched. That is
## the whole of it: see `scripts/ui/dialog/npc_prompt_overlay.gd`, which draws
## it, and `NpcInteractable` / `Portal`, which are the two today.
##
## It is a class rather than a loose string so the group name has ONE owner —
## a group typed out in three files is a group that will be misspelt in one.

const GROUP := "world_prompt"
