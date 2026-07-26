class_name GiftData
extends RefCounted
## Things an NPC hands over ONCE, and who hands them over.
##
##   "gift_id": {
##       "from":  <dialog_id of the NPC who gives it>,
##       "items": [<ItemDb ids>],
##   }
##
## A gift is not a quest and not a trade: nothing is asked for and nothing is
## paid. What makes it worth its own table is the "once" — the server remembers
## who has taken which, so the line that offers it can be shown the first time
## you walk up to somebody and never again.
##
## Adding one is an entry here plus a dialog answer carrying
## `"action": "take_gift:<id>"`, exactly the way a quest is one entry in
## QuestData plus `"action": "start_quest:<id>"`. No NPC needs code of its own.
##
## `from` is not decoration: it is the one thing about a gift the SERVER can
## check. Conversations are local, so it cannot see that the offer was ever
## made — what it can see is whether your pawn is really standing at that NPC.
## A gift with no `from` can therefore only be handed over by the server itself.

const GIFTS := {
	# Bram's leftovers, the first time you talk to him.
	"blacksmith_armor": {
		"from": "blacksmith",
		"items": ItemDb.ARMOR_SETS["flimsy"],
	},
}

static func has(gift_id: String) -> bool:
	return GIFTS.has(gift_id)

## The dialog_id of whoever hands this over, "" when only the server does.
static func giver(gift_id: String) -> String:
	return str(GIFTS.get(gift_id, {}).get("from", ""))

## What is in it. A copy, so a caller cannot edit the catalogue by accident.
static func items(gift_id: String) -> Array:
	return (GIFTS.get(gift_id, {}).get("items", []) as Array).duplicate()
