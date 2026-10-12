class_name DotPlayerDeathReactions
extends RefCounted

## The set of ways a body may go down, and the one rule that picks among them.
##
## [b]The pick is pure.[/b] [method pick] reads the facts of the kill (headshot, how powerful
## the weapon is, the damage, a reaction the weapon named) and a seed, and nothing else: no
## global generator, no clock, no node. The server calls it, sends the id and the seed with the
## kill, and a client never picks — so every screen shows the same fall, and a suite can
## assert the rule by counting picks over a thousand seeds.
##
## [b]The rule.[/b] A reaction the weapon names (its def's [code]params.death_reaction[/code])
## wins outright when it is enabled. Otherwise every enabled reaction whose conditions the kill
## meets ([method DotPlayerDeathReaction.qualifies]) goes into a weighted draw. Nothing
## qualifying is [constant LIMP], the plain ragdoll, which always exists.
##
## [b]Weights are a server's to set[/b] ([method apply_weights], from
## [code]sv_ragdoll_reactions[/code]); a game adds its own reactions with [method add], and the
## stock four plus the plain one cover what most deaths want.

const CHANNEL := "player.death"

const LIMP := &"limp"
const HEADSHOT_LAUNCH := &"headshot_launch"
const POWER_LAUNCH := &"power_launch"
const FACE_PLANT := &"face_plant"
const CRUMPLE := &"crumple"

## The stock sound ids, which [DotPlayerDeathSounds] gives files for.
const SOUND_WHOOSH := &"ragdoll.whoosh"
const SOUND_FACE_PLANT := &"ragdoll.face_plant"
const SOUND_THUD := &"ragdoll.thud"
const SOUND_SLUMP := &"ragdoll.slump"

## The weapon def params this reads (see [method weapon_reaction], [method weapon_power]).
const PARAM_REACTION := &"death_reaction"
const PARAM_POWER := &"death_power"

var _list: Array[DotPlayerDeathReaction] = []


## The stock set: limp, headshot launch, power launch, face plant, crumple.
static func stock() -> DotPlayerDeathReactions:
	var out := DotPlayerDeathReactions.new()

	var limp := DotPlayerDeathReaction.new()
	limp.id = LIMP
	limp.display_name = "Limp"
	limp.weight = 4.0
	limp.pose = DotPlayerDeathReaction.Pose.LIMP
	limp.land_sound = SOUND_THUD
	out.add(limp)

	# A headshot throws the head back and the body up after it: the reward the shooter sees.
	var head := DotPlayerDeathReaction.new()
	head.id = HEADSHOT_LAUNCH
	head.display_name = "Headshot launch"
	head.weight = 6.0
	head.pose = DotPlayerDeathReaction.Pose.LAUNCH
	head.needs_headshot = true
	head.push = 1.0
	head.hit_push = 7.0
	head.launch_up = 6.5
	head.launch_along = 3.0
	head.spin = 5.0
	head.start_sound = SOUND_WHOOSH
	head.land_sound = SOUND_THUD
	head.land_speed = 3.0
	out.add(head)

	# A heavy weapon carries the whole body along the shot.
	var power := DotPlayerDeathReaction.new()
	power.id = POWER_LAUNCH
	power.display_name = "Power launch"
	power.weight = 8.0
	power.pose = DotPlayerDeathReaction.Pose.LAUNCH
	power.needs_power = true
	power.min_power = 0.5
	power.push = 2.0
	power.hit_push = 4.0
	power.launch_up = 5.0
	power.launch_along = 9.0
	power.spin = 7.0
	power.start_sound = SOUND_WHOOSH
	power.land_sound = SOUND_THUD
	power.land_speed = 3.0
	out.add(power)

	# Straight down on the face, stiff, and a smack when it lands.
	var plant := DotPlayerDeathReaction.new()
	plant.id = FACE_PLANT
	plant.display_name = "Face plant"
	plant.weight = 1.5
	plant.pose = DotPlayerDeathReaction.Pose.FACE_PLANT
	plant.push = 0.0
	plant.hit_push = 0.0
	plant.land_sound = SOUND_FACE_PLANT
	plant.land_speed = 1.0
	out.add(plant)

	# The legs go: down where they stood.
	var crumple := DotPlayerDeathReaction.new()
	crumple.id = CRUMPLE
	crumple.display_name = "Crumple"
	crumple.weight = 2.5
	crumple.pose = DotPlayerDeathReaction.Pose.CRUMPLE
	crumple.push = 0.3
	crumple.hit_push = 0.8
	crumple.land_sound = SOUND_SLUMP
	crumple.land_speed = 1.0
	out.add(crumple)

	return out


## Adds [param reaction], replacing one with the same id. False for an empty id.
func add(reaction: DotPlayerDeathReaction) -> bool:
	if reaction == null or reaction.id == &"":
		return false
	for i in range(_list.size()):
		if _list[i].id == reaction.id:
			_list[i] = reaction
			return true
	_list.append(reaction)
	return true


func find(id: StringName) -> DotPlayerDeathReaction:
	for reaction in _list:
		if reaction.id == id:
			return reaction
	return null


func has(id: StringName) -> bool:
	return find(id) != null


## Every id, in the order they were added. The order is the wire's when a game sends an index.
func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for reaction in _list:
		out.append(reaction.id)
	return out


func size() -> int:
	return _list.size()


## Sets weights from text like [code]"headshot_launch=6,face_plant=0"[/code]: the server's
## [code]sv_ragdoll_reactions[/code]. Ids it does not name keep their weight; an unknown id or a
## value that is not a number is skipped and reported. Returns how many it set.
##
## [b]Zero turns one off[/b], which is the whole "which are enabled" setting: a reaction with no
## weight is never drawn and a weapon naming it falls through to the draw.
func apply_weights(text: String) -> int:
	var set_count := 0
	for item in text.split(",", false):
		var pair := item.strip_edges().split("=", false)
		if pair.size() != 2:
			pair = item.strip_edges().split(":", false)
		if pair.size() != 2:
			DotLog.warn(CHANNEL, "a reaction weight is not id=number; skipped", {"item": item})
			continue
		var reaction := find(StringName(pair[0].strip_edges()))
		var value := pair[1].strip_edges()
		if reaction == null or not value.is_valid_float():
			DotLog.warn(CHANNEL, "unknown reaction or bad weight; skipped", {"item": item})
			continue
		reaction.weight = clampf(value.to_float(), 0.0, 100.0)
		set_count += 1
	return set_count


## The weights as [method apply_weights] reads them, in [method ids] order.
func weights_text() -> String:
	var parts := PackedStringArray()
	for reaction in _list:
		parts.append("%s=%s" % [String(reaction.id), String.num(reaction.weight, 2).trim_suffix(".00")])
	return ",".join(parts)


## The reaction for one death. Pure in its arguments; see the class note for the rule.
##
## [param weapon_named] is the id a weapon asked for (see [method weapon_reaction]), or empty.
## [param power] is 0 to 1 (see [method weapon_power]).
func pick(
	headshot: bool, power: float, damage: float, weapon_named: StringName, p_seed: int
) -> StringName:
	if weapon_named != &"":
		var asked := find(weapon_named)
		if asked != null and asked.weight > 0.0 and asked.qualifies(headshot, power, damage, true):
			return asked.id

	var candidates: Array[DotPlayerDeathReaction] = []
	var total := 0.0
	for reaction in _list:
		if reaction.weight <= 0.0 or not reaction.qualifies(headshot, power, damage, false):
			continue
		candidates.append(reaction)
		total += reaction.weight

	if candidates.is_empty():
		return LIMP

	# Seeded, never randf(): the server's pick has to be the one every suite can repeat.
	var rng := RandomNumberGenerator.new()
	rng.seed = p_seed
	var roll := rng.randf() * total
	for reaction in candidates:
		roll -= reaction.weight
		if roll < 0.0:
			return reaction.id
	return candidates[candidates.size() - 1].id


## The reaction a weapon definition names, or empty. Duck-typed over anything with a
## [code]params[/code] dictionary (dot-weapon's [code]DotWeaponDef[/code]), so this addon names
## no weapon class.
static func weapon_reaction(weapon_def: Object) -> StringName:
	var params := _params_of(weapon_def)
	return StringName(str(params.get(PARAM_REACTION, ""))) if params.has(PARAM_REACTION) else &""


## How powerful a weapon is, 0 to 1, for [member DotPlayerDeathReaction.needs_power]: its def's
## [code]params.death_power[/code] when it has one, else 0. A game with no such field can pass
## its own number (damage over a threshold, say) to [method pick] instead.
static func weapon_power(weapon_def: Object) -> float:
	var params := _params_of(weapon_def)
	return clampf(float(params.get(PARAM_POWER, 0.0)), 0.0, 1.0)


static func _params_of(weapon_def: Object) -> Dictionary:
	if weapon_def == null:
		return {}
	var value: Variant = weapon_def.get(&"params")
	return value if value is Dictionary else {}


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()
	for reaction in _list:
		var d := reaction.describe()
		out.append("%s  weight %s  %s %s" % [d["id"], d["weight"], d["pose"], d["needs"]])
	return out
