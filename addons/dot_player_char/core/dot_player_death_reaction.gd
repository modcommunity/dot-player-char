@tool
class_name DotPlayerDeathReaction
extends Resource

## One way a body goes down: what kills may pick it, how heavily, and the push, the pose
## and the sounds that make it look like itself. A document: a game or a weapon adds its
## own without touching the addon (see [DotPlayerDeathReactions]).
##
## [b]Chosen once, by the server, and replayed by everybody.[/b] [DotPlayerDeathReactions.pick]
## is pure in its inputs and a seed, the server sends the id and the seed with the kill, and
## each client builds its own [DotPlayerRagdoll] from them. Physics is not bit-exact across
## machines, so two screens agree on the reaction, the direction and the strength, and differ
## by a few centimetres in where a hand lands, which nobody can see.

## How the body is posed and driven before physics takes it.
enum Pose {
	## Nothing special: the hit's own push, then gravity. The plain ragdoll.
	LIMP,
	## Stiff as a plank (one rigid piece), pitched straight forward onto the face; it becomes
	## the jointed body when the face meets the ground, which is where the smack is.
	FACE_PLANT,
	## The legs go first: the body drops where it stood and folds.
	CRUMPLE,
	## Thrown: [member launch_up] and [member launch_along] carry the whole body.
	LAUNCH,
}

@export var id: StringName = &""

@export var display_name: String = ""

## Relative chance among the reactions a death qualifies for. Zero never picks it, which is
## how a server turns one off without removing it.
@export_range(0.0, 100.0, 0.1) var weight: float = 1.0

@export var pose: Pose = Pose.LIMP

@export_group("When it may be picked")

## Only a headshot kill qualifies.
@export var needs_headshot: bool = false

## Only a kill whose weapon asked for a launch qualifies: the weapon def's
## [code]params.death_reaction[/code] names this id, or its [code]params.death_power[/code]
## reaches [member min_power]. See [method DotPlayerDeathReactions.weapon_power].
@export var needs_power: bool = false

## The weapon power (0 to 1) a [member needs_power] reaction wants.
@export_range(0.0, 1.0, 0.01) var min_power: float = 0.5

## The least damage the killing hit must have done. Zero takes any.
@export_range(0.0, 1000.0, 1.0) var min_damage: float = 0.0

@export_group("Motion")

## Push along the shot, in m/s added to the whole body, per 100 damage. Scaled by
## [member DotPlayerRagdollRules.force_scale].
@export_range(0.0, 50.0, 0.1) var push: float = 1.5

## Extra push at the part that was hit, in m/s, so the hit part leads the fall.
@export_range(0.0, 50.0, 0.1) var hit_push: float = 2.5

## Upward speed given to the whole body, in m/s.
@export_range(0.0, 40.0, 0.1) var launch_up: float = 0.0

## Speed along the shot given to the whole body, in m/s, on top of [member push].
@export_range(0.0, 40.0, 0.1) var launch_along: float = 0.0

## Tumble given to the torso, in radians per second, at most; seeded.
@export_range(0.0, 40.0, 0.1) var spin: float = 0.0

## How far each joint may swing, as a fraction of its normal limit. 1 is the plain ragdoll;
## below about 0.3 a hard landing can make the joints fight and fling the body, which is why
## [constant Pose.FACE_PLANT] is one rigid piece until it lands rather than tight joints.
@export_range(0.0, 2.0, 0.01) var looseness: float = 1.0

@export_group("Sound")

## Played where the body starts, at the moment of death. Empty for none.
@export var start_sound: StringName = &""

## Played once, where the body first hits something hard enough. Empty for none.
@export var land_sound: StringName = &""

## The impact speed, in m/s, that counts as hitting the ground for [member land_sound].
@export_range(0.0, 30.0, 0.1) var land_speed: float = 2.0


## Whether a death with these facts may pick this reaction at all, ignoring its weight.
func qualifies(headshot: bool, power: float, damage: float, named: bool) -> bool:
	if needs_headshot and not headshot:
		return false
	if needs_power and not named and power < min_power:
		return false
	return damage >= min_damage


func describe() -> Dictionary:
	return {
		"id": String(id),
		"weight": weight,
		"pose": Pose.keys()[pose],
		"needs": "%s%s" % ["headshot " if needs_headshot else "", "power " if needs_power else ""],
	}
