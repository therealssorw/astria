class_name CombatLevels
extends RefCounted
## Where a weapon's level and an enemy's level meet — the ONE place the two
## ladders are turned into a damage number. Nothing else may invent its own
## curve, or two weapons will disagree about what a level is worth.
##
## Two ladders that never have to know about each other:
##
##   OFFENCE — what is in your hand. FISTS ARE LEVEL 0, AND FISTS ARE THE
##             BASELINE: bare-handed you deal exactly the numbers exported on
##             player.gd, and every level of weapon adds
##             DAMAGE_PER_WEAPON_LEVEL of that baseline on top. So the game as
##             it was tuned is the game you play with nothing equipped, and
##             every weapon you pick up is a straight gain.
##   DEFENCE — what you are swinging at. BASE_ENEMY_LEVEL (1) is the ordinary
##             enemy — every bandit in the game is one — and each level away
##             from that is worth another TOUGHNESS_PER_ENEMY_LEVEL, BOTH
##             ways: a higher-level enemy takes less and hits harder, a lower
##             one takes more and hits softer. A level 1 enemy therefore has
##             NO modifier at all: its exported health and damage are its real
##             ones.
##   ARMOR   — what you are wearing when something hits YOU. Nothing is the
##             baseline (1.0, take it all) and every armor level divides what
##             lands by another PROTECTION_PER_ARMOR_LEVEL. Levels come from
##             the pieces, one per slot, so a full suit is four of them.
##
##   damage = base * offence(weapon) / defence(target)
##   damage taken = incoming / protection(armor)
##
## which is why "make the bandits level 1" and "base the stats off fists"
## are the same statement: both sides of that fraction are 1 today, and
## picking up a wooden sword is the first thing that moves it.
##
## WHAT THE LADDERS ARE TUNED TO. The yardstick, written down so a change to
## any number above can be checked against something: carrying a full level 1
## set — wooden sword and all four flimsy pieces — you should be able to take
## on SIX level 0 enemies, or THREE level 1 enemies, and finish almost dead
## either way. Twice as many of the weaker ones for the same trip to the edge
## is exactly what falling one level either side of the baseline is worth: a
## level 0 enemy both dies quicker and hits softer, so it costs you about half
## as much (0.65 * 0.65 = 0.42 of a level 1) and six of them come to about
## three.
##
## It is a TARGET, not a promise the code can keep. How much you actually
## take depends on how well you block and dodge, which no formula here can
## know — so it is the thing to play against when retuning, not something a
## test can assert.
##
## Only DAMAGE is scaled. Knockback is deliberately left alone: the flinch and
## stagger thresholds (Enemy.flinch_knockback, the combo ender's
## combo_finisher_mult) are a readability contract about which hits rock an
## enemy back, and a levelled weapon must not quietly turn every jab into a
## stagger.

## The enemy that the game's exported numbers are written for. An enemy at
## this level takes damage exactly as written.
const BASE_ENEMY_LEVEL := 1

## What one level of weapon is worth, as a fraction of bare-handed damage.
const DAMAGE_PER_WEAPON_LEVEL := 0.35

## What one enemy level away from BASE_ENEMY_LEVEL is worth, as a fraction of
## the damage it would otherwise take — and of the damage it deals.
const TOUGHNESS_PER_ENEMY_LEVEL := 0.35

## What one level of ARMOR is worth, as a fraction of the damage it would
## otherwise let through. Levels add up across the four pieces, so a full
## level 1 suit is 4 of these — about a quarter less taken — and a full iron
## one is 12, which roughly halves everything that lands.
const PROTECTION_PER_ARMOR_LEVEL := 0.09

## Nothing goes below this fraction of its written numbers however far under
## the baseline it is, so a level 0 enemy is weak, not harmless.
const MIN_ENEMY_SCALE := 0.4

## How hard a level-`level` weapon hits, against bare hands (1.0).
static func weapon_power(level: int) -> float:
	return 1.0 + DAMAGE_PER_WEAPON_LEVEL * float(maxi(level, 0))

## How far from an ordinary enemy this one is, as a plain multiplier (1.0 at
## BASE_ENEMY_LEVEL). Used BOTH ways round on purpose — it is what a level says
## about an enemy, and an enemy that is harder to kill is also one that hits
## harder. Without the second half a "level 0" bandit would die faster while
## punching exactly as hard as its betters, which is not a weaker enemy.
static func enemy_scale(level: int) -> float:
	return maxf(1.0 + TOUGHNESS_PER_ENEMY_LEVEL * float(level - BASE_ENEMY_LEVEL),
			MIN_ENEMY_SCALE)

## How much a level-`level` enemy shrugs off, against an ordinary one (1.0).
static func enemy_toughness(level: int) -> float:
	return enemy_scale(level)

## How hard a level-`level` enemy hits, against an ordinary one (1.0).
static func enemy_power(level: int) -> float:
	return enemy_scale(level)

## The fraction of a blow that reaches you through `total_level` of armor —
## the summed levels of the pieces worn, one per slot. 1.0 with nothing on.
static func armor_protection(total_level: int) -> float:
	return 1.0 / (1.0 + PROTECTION_PER_ARMOR_LEVEL * float(maxi(total_level, 0)))

## The multiplier on a swing's damage: what is being swung against what is
## being hit. 1.0 is fists against an ordinary bandit.
static func damage_mult(weapon_level: int, target_level: int) -> float:
	return weapon_power(weapon_level) / enemy_toughness(target_level)

## What level something being hit counts as. Anything without a level of its
## own — another PLAYER, most obviously — is an ordinary target, so PvP is
## defended exactly as it always was and only the attacker's weapon matters.
static func level_of_target(target: Node) -> int:
	if target == null:
		return BASE_ENEMY_LEVEL
	var lv: Variant = target.get("level")
	return BASE_ENEMY_LEVEL if lv == null else int(lv)

## The damage multiplier for peer `attacker_id` swinging at `target`, read off
## the SERVER's own copy of what that peer is holding. Never take the item id
## from a client — `Net.held_of` is the server's bar on the server.
static func swing_mult(attacker_id: int, target: Node) -> float:
	return damage_mult(ItemDb.level_of(Net.held_of(attacker_id)),
			level_of_target(target))
