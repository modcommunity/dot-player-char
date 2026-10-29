## Feet that stand still on the ground while a body walks: over a gait phase each foot is locked
## to a world point for its stance and swings in a clamped arc to where it lands next. Pure maths;
## [method DotHumanoidIk.two_bone_to] bends a leg to a target. One instance per body.
class_name DotFootPlant
extends RefCounted

## Share of a cycle each foot stands on the ground.
var duty := 0.6
## Highest a swinging foot rises above the line between lift-off and landing, metres.
var lift := 0.16
## Share of a swing at each end spent lifting or setting down with no travel, so a foot never
## skates on its way into or out of the ground.
var settle := 0.15
## The phase (0 to 1) at which each foot lands.
var touchdown: Array[float] = [0.0, 0.5]
## A planted foot further than this from where it should be (the body turned or was moved) is
## planted again where it should be.
var reach := 0.6

var _planted: Array[bool] = []
var _at: Array[Vector3] = []


## Forgets every plant, so the next [method step] starts the feet where the phase puts them.
func reset() -> void:
	_planted.clear()
	_at.clear()


## Whether foot [param i] is on the ground at the last [method step].
func is_planted(i: int) -> bool:
	return i < _planted.size() and _planted[i]


## World targets for each foot at gait [param phase] (0 to 1, any count of whole cycles): [param home]
## is each foot's neutral ground point under the body now (world), [param velocity] the body's ground
## velocity and [param cycle] the seconds one gait cycle takes.
func step(phase: float, home: Array[Vector3], velocity: Vector3, cycle: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var stride := Vector3(velocity.x, 0.0, velocity.z) * maxf(cycle, 0.0)

	if _planted.size() != home.size():
		_planted.resize(home.size())
		_planted.fill(false)
		_at.resize(home.size())
		_at.fill(Vector3.INF)

	for i in home.size():
		var p := fposmod(phase - (touchdown[i] if i < touchdown.size() else 0.0), 1.0)
		# Where a foot in stance at this phase stands: ahead of home at landing, behind at lift-off.
		var stance_at := home[i] + stride * (duty * 0.5 - p)

		if p < duty:
			if not _planted[i] or _at[i] == Vector3.INF or _at[i].distance_to(stance_at) > reach:
				_at[i] = stance_at
			_planted[i] = true
			out.append(_at[i])
			continue

		# A foot that stood lifts off from where it stood; one that never did starts where it would have.
		if _at[i] == Vector3.INF or _at[i].distance_to(stance_at) > reach:
			_at[i] = stance_at
		_planted[i] = false
		var s := (p - duty) / maxf(1.0 - duty, 0.001)
		var land := home[i] + stride * (1.0 - p + duty * 0.5)
		var along := smoothstep(0.0, 1.0, clampf((s - settle) / maxf(1.0 - 2.0 * settle, 0.001), 0.0, 1.0))
		var foot := _at[i].lerp(land, along)
		foot.y += lift * sin(PI * s)
		out.append(foot)

	return out


func describe() -> Dictionary:
	return {"duty": duty, "lift": lift, "settle": settle, "touchdown": touchdown, "planted": _planted.duplicate()}
