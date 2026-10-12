class_name DotPlayerDeath
extends RefCounted

## One death as the server decided it: which reaction, the seed, which way the shot went and
## how hard. The thing that travels with a kill, so every client builds the same fall.
##
## [b]Small on purpose.[/b] No pose, no positions: a client already draws the victim where it
## is, and a ragdoll is built from that drawn body. What a client cannot know is what the
## server rolled, so that and the shot's direction and strength are all there is. A game puts
## [method to_dict]'s keys in its own kill message (game-arena writes them on its KILL event,
## optional at the end, so an older client reads a kill without them).

## The reaction's id in a [DotPlayerDeathReactions].
var reaction: StringName = DotPlayerDeathReactions.LIMP

## Seeds the ragdoll's small variations (the tumble, which way the knees go).
var roll_seed: int = 0

## Which way the killing shot travelled, horizontal-ish, unit length or zero for none.
var direction: Vector3 = Vector3.ZERO

## The killing hit's damage, which scales the push.
var damage: float = 0.0

## Whether the kill was a headshot: the head takes the hit's push.
var headshot: bool = false


## The server's decision for one kill. [param weapon_def] is the killing weapon's definition
## or null; [param power] overrides its [code]death_power[/code] when not negative (a game
## without weapon defs passes its own 0-to-1 number).
static func decide(
	reactions: DotPlayerDeathReactions,
	p_headshot: bool,
	p_damage: float,
	p_direction: Vector3,
	p_seed: int,
	weapon_def: Object = null,
	power: float = -1.0
) -> DotPlayerDeath:
	var out := DotPlayerDeath.new()
	out.roll_seed = p_seed & 0x7fffffff
	out.headshot = p_headshot
	out.damage = maxf(p_damage, 0.0)
	out.direction = p_direction.normalized() if p_direction.length_squared() > 0.0001 else Vector3.ZERO

	var weapon_power := power if power >= 0.0 else DotPlayerDeathReactions.weapon_power(weapon_def)
	var named := DotPlayerDeathReactions.weapon_reaction(weapon_def)

	if reactions != null:
		out.reaction = reactions.pick(p_headshot, weapon_power, out.damage, named, out.roll_seed)

	return out


## A seed from things both ends know, for a game that has nothing better: the victim and the
## tick, mixed so neighbouring ticks do not give neighbouring rolls.
static func seed_of(victim: int, tick: int) -> int:
	var h := (victim * 0x9E3779B1 + tick * 0x85EBCA77) & 0x7fffffff
	h = ((h ^ (h >> 15)) * 0x2C1B3C6D) & 0x7fffffff
	return h ^ (h >> 12)


func to_dict() -> Dictionary:
	return {
		"death_reaction": String(reaction),
		"death_seed": roll_seed,
		"death_dir": direction,
		"death_damage": damage,
		"headshot": headshot,
	}


## Reads [method to_dict]'s keys out of a kill message; missing keys keep the defaults, so a
## kill from an older server is a plain limp fall pushed by nothing.
static func from_dict(data: Dictionary) -> DotPlayerDeath:
	var out := DotPlayerDeath.new()
	var r := str(data.get("death_reaction", ""))
	out.reaction = StringName(r) if r != "" else DotPlayerDeathReactions.LIMP
	out.roll_seed = int(data.get("death_seed", 0))
	var dir: Variant = data.get("death_dir", Vector3.ZERO)
	out.direction = (dir as Vector3) if dir is Vector3 else Vector3.ZERO
	out.damage = float(data.get("death_damage", 0.0))
	out.headshot = bool(data.get("headshot", false))
	return out


## Longest reaction id [method write_to] carries.
const REACTION_BYTES := 24


## Writes this death onto a dot-net [code]DotNetWriter[/code] (duck-typed: this addon does not
## depend on dot-net): the reaction as a short string, because a game or a server may add its
## own; the seed, the damage and, when there is one, the direction. About seven bytes. Put it
## LAST in a message and read it only when bytes remain, so an older client reads the rest.
func write_to(writer: Object) -> void:
	writer.call(&"write_string", String(reaction), REACTION_BYTES)
	writer.call(&"write_varint", roll_seed)
	writer.call(&"write_varint", clampi(roundi(damage), 0, 10000))
	var has_dir := direction.length_squared() > 0.0001
	writer.call(&"write_bool", has_dir)
	if has_dir:
		writer.call(&"write_direction", direction, 10)
	writer.call(&"write_bool", headshot)


## Reads [method write_to]'s fields off a dot-net [code]DotNetReader[/code].
static func read_from(reader: Object) -> DotPlayerDeath:
	var out := DotPlayerDeath.new()
	var r := String(reader.call(&"read_string", REACTION_BYTES))
	out.reaction = StringName(r) if r != "" else DotPlayerDeathReactions.LIMP
	out.roll_seed = int(reader.call(&"read_varint"))
	out.damage = float(int(reader.call(&"read_varint")))
	out.direction = reader.call(&"read_direction", 10) if bool(reader.call(&"read_bool")) else Vector3.ZERO
	out.headshot = bool(reader.call(&"read_bool"))
	return out


func describe() -> Dictionary:
	return {
		"reaction": String(reaction),
		"seed": roll_seed,
		"direction": direction.snapped(Vector3.ONE * 0.01),
		"damage": damage,
		"headshot": headshot,
	}
