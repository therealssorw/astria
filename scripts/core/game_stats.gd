extends Node
## Autoload: run-wide local stats that survive scene changes. Kills, deaths
## and gold are server-authoritative in the Net registry; `coins` here is a
## read-mostly MIRROR of your own registry gold (Net overwrites it on every
## registry sync) so local UI and shops can keep reading GameStats.coins.

var coins := 0
