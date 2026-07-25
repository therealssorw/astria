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

func item_count(id: String) -> int:
	return int(items.get(id, 0))

## Carried item ids, in the order the server holds them.
func owned_ids() -> Array:
	return items.keys()
