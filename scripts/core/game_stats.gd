extends Node
## Autoload: run-wide local stats that survive scene changes. Kills and
## deaths moved to the server-authoritative registry in Net (multiplayer);
## only local currency lives here now.

var coins := 0      # placeholder currency for now
