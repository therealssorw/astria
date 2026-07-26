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
##             enemy — every bandit in the game is one — and each level above
##             that divides what it takes by another
##             TOUGHNESS_PER_ENEMY_LEVEL. A level 1 enemy therefore has NO
##             modifier at all: its exported health and damage are its real
##             ones.
##
##   damage = base * offence(weapon) / defence(target)
##
## which is why "make the bandits level 1" and "base the stats off fists"
## are the same statement: both sides of that fraction are 1 today, and
## picking up a wooden sword is the first thing that moves it.
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

## What one enemy level above BASE_ENEMY_LEVEL is worth, as a fraction of the
## damage it would otherwise take.
const TOUGHNESS_PER_ENEMY_LEVEL := 0.35

## How hard a level-`level` weapon hits, against bare hands (1.0).
static func weapon_power(level: int) -> float:
	return 1.0 + DAMAGE_PER_WEAPON_LEVEL * float(maxi(level, 0))

## How much a level-`level` enemy shrugs off, against an ordinary one (1.0).
static func enemy_toughness(level: int) -> float:
	return 1.0 + TOUGHNESS_PER_ENEMY_LEVEL * float(maxi(level - BASE_ENEMY_LEVEL, 0))

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
