extends Node
## Autoload: run-wide local stats that survive scene changes. Kills, deaths,
## gold and carried items are server-authoritative in the Net registry; `coins`
## and `items` here are read-mostly MIRRORS of your own registry slice, which
## Net overwrites on every purse sync (cl_purse), so local UI and shops can
## keep reading GameStats without touching the network layer.
##
## NOTHING here is authoritative. Writing to it does not give you gold or
## items — it only makes your own screen lie until the next sync. Anything
## meant to actually change them goes through a Net request.

## The mirror was refreshed; the inventory grid and the shop redraw on this.
signal changed

var coins := 0
var items := {}   # item id (see ItemDb) -> how many are carried
var hotbar: Array = []  # 9 slots, each an item id or "" — filled by the server
var hot_slot := 0       # which of those slots is in hand
## Id of the quest being tracked (see QuestData), "" when there is none. Drives
## the HUD heading and the star that leads you to it.
var quest := ""
## Kills counted towards that quest, when it is one that asks for them. The
## server counts; this is the copy the heading reads as "7/25".
var quest_kills := 0
## GiftData ids already handed over, as id -> true. What a conversation reads to
## know whether it is the first time you have walked up to somebody. Like
## everything else here it is a MIRROR — clearing it locally does not earn a
## second suit of armor, the server refuses.
var gifts := {}

func item_count(id: String) -> int:
	return int(items.get(id, 0))

## Has this player already been handed that gift? False before the first purse
## sync, which is the right way round: an unknown answer must not hide a line
## the player has never seen.
func gift_taken(gift_id: String) -> bool:
	return gift_id != "" and bool(gifts.get(gift_id, false))

## Carried item ids, in the order the server holds them.
func owned_ids() -> Array:
	return items.keys()

## What the selected hotbar slot holds, or "" when it is empty.
func held_id() -> String:
	if hot_slot < 0 or hot_slot >= hotbar.size():
		return ""
	return str(hotbar[hot_slot])

## The item in a slot, or "" — safe to call before the first purse sync.
func hotbar_id(slot: int) -> String:
	if slot < 0 or slot >= hotbar.size():
		return ""
	return str(hotbar[slot])
