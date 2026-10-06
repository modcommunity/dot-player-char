@tool
class_name DotPlayerBreakRules
extends DotConfig

## How a body comes apart when its player dies: not at all, a limb or two, or every piece.
##
## [b]Presentation only, and safe to drop.[/b] Nothing here is simulated or replicated: a
## server never builds a body and never breaks one, and a client that skips it (a low
## setting, a phone) loses a picture and nothing else. It is a [DotConfig] because a
## server owner turns it up, down or off per mode and per map like any other rule — the
## game sends the value, each client draws it.
##
## [b]The randomness is seeded from the death[/b] (the game passes the victim and the tick),
## so everybody watching sees the same arm come off in the same direction. That is the
## whole reason [DotPlayerBodyBreak] takes a seed instead of calling [code]randf()[/code].

enum Mode {
	## Nothing comes apart. The game's own death presentation is all there is.
	NONE,
	## [member limbs] of the body's limbs come off; the rest stays for the game to keep or hide.
	LIMBS,
	## Every piece flies apart and the body is hidden.
	EXPLODE,
}

@export var mode: Mode = Mode.LIMBS

## How many limbs come off in [constant Mode.LIMBS].
@export_range(1, 8, 1) var limbs: int = 1

## Only a lethal CRITICAL breaks the body; any other death leaves it whole. Off, every death does.
##
## On by default, because a body that comes apart on every death stops meaning anything,
## and one that comes apart on a headshot is a reward the shooter can see.
@export var criticals_only: bool = true

## Outward speed of a piece, in m/s, plus the hit's own push along its direction.
@export_range(0.0, 50.0, 0.5) var force: float = 5.0

## How much of the hit's direction is added, in m/s.
@export_range(0.0, 50.0, 0.5) var push: float = 4.0

## Upward speed added to every piece, in m/s, so they arc rather than skid.
@export_range(0.0, 30.0, 0.5) var lift: float = 3.0

## Tumble, in radians per second, at most.
@export_range(0.0, 60.0, 0.5) var spin: float = 10.0

## Seconds a piece lies there before it starts to fade.
@export_range(0.0, 60.0, 0.5) var lifetime: float = 4.0

## Seconds it takes to shrink away.
@export_range(0.05, 10.0, 0.05) var fade: float = 0.6

## Physics layers the pieces land on. Not players: a piece a player trips on is a piece
## that changes the game, and these must not.
@export_flags_3d_physics var collision_mask: int = 1

## Name fragments that make a mesh a limb, matched case-insensitively against the mesh and
## every ancestor up to the body. The humanoid mounts ([code]Head[/code], [code]LeftHand[/code],
## [code]RightFoot[/code]...) all match; a game with its own spelling adds its own.
@export var limb_names: PackedStringArray = PackedStringArray(["head", "arm", "hand", "leg", "foot"])


func env_prefix() -> String:
	return "DOT_BREAK_"


func cli_prefix() -> String:
	return "--break-"


## Whether a death with these properties breaks the body at all.
func breaks(lethal: bool, critical: bool) -> bool:
	if mode == Mode.NONE or not lethal:
		return false
	return critical or not criticals_only


func describe() -> Dictionary:
	return {
		"mode": Mode.keys()[mode],
		"limbs": limbs,
		"criticals_only": criticals_only,
		"force": force,
		"lifetime": lifetime,
	}
