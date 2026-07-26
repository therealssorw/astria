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
## What you have ON, as armor slot (ItemDb.EQUIP_SLOTS) -> item id, "" for an
## empty slot. The equipment cross in the inventory draws this. A MIRROR like
## everything else here: putting an id in it dresses nobody and protects you
## from nothing, it only makes your own panel lie until the next sync.
var equipped := {}

func item_count(id: String) -> int:
	return int(items.get(id, 0))

## Has this player already been handed that gift? False before the first purse
## sync, which is the right way round: an unknown answer must not hide a line
## the player has never seen.
func gift_taken(gift_id: String) -> bool:
	return gift_id != "" and bool(gifts.get(gift_id, false))

## The item worn in an armor slot, or "" — safe before the first purse sync.
func equipped_in(slot: String) -> String:
	return str(equipped.get(slot, ""))

## Is this exact item on right now? What the bag grid ticks and what the use
## reply is really saying.
func is_equipped(item_id: String) -> bool:
	return item_id != "" and equipped_in(ItemDb.armor_slot(item_id)) == item_id

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
