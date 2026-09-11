@tool
class_name DotPlayerAnimSet
extends Resource

## The table from a state or an action to a clip.

const CHANNEL := "player.anim"

@export var id: StringName = &""

@export var clips: Array[DotPlayerAnimClip] = []

## The clip used for a state the table has none for.
##
## Empty means "show nothing", which is visible and debuggable. The alternative — the
## first clip in the list — silently plays an idle for every unmapped state, and the
## symptom is a character that never animates for one of its actions.
@export var fallback: StringName = &""

var _by_id: Dictionary = {}
var _built: bool = false


func build() -> DotResult:
	_by_id.clear()

	if clips.is_empty():
		return DotResult.fail(DotError.CODE_INVALID, "An animation set with no clips.")

	for c in clips:
		if c == null or c.id == &"":
			return DotResult.fail(DotError.CODE_INVALID, "A clip with no id.")

		if _by_id.has(c.id):
			return DotResult.fail(
				DotError.CODE_INVALID, "Two clips are called '%s'." % String(c.id)
			)

		_by_id[c.id] = c

	if fallback != &"" and not _by_id.has(fallback):
		return DotResult.fail(
			DotError.CODE_INVALID,
			"The fallback clip '%s' is not in the set." % String(fallback)
		)

	_built = true
	return DotResult.success(null)


func _ensure_built() -> void:
	if not _built or _by_id.size() != clips.size():
		var res := build()
		if not res.ok:
			DotLog.error(CHANNEL, "animation set unusable", {"why": res.error.message})


func has_clip(clip_id: StringName) -> bool:
	_ensure_built()
	return _by_id.has(clip_id)


func clip(clip_id: StringName) -> DotPlayerAnimClip:
	_ensure_built()

	if _by_id.has(clip_id):
		return _by_id[clip_id]

	if fallback != &"" and _by_id.has(fallback):
		return _by_id[fallback]

	return null


func ids() -> Array[StringName]:
	_ensure_built()
	var out: Array[StringName] = []

	for c in clips:
		if c != null:
			out.append(c.id)

	return out


## Which states this set has no clip for, out of a list.
##
## What a content check asks. A state with no clip is invisible at runtime — the
## character simply keeps playing whatever it was — so it is worth being able to find
## them all at once rather than one report at a time.
func missing_for(states: Array[StringName]) -> Array[StringName]:
	_ensure_built()
	var out: Array[StringName] = []

	for s in states:
		if not _by_id.has(s):
			out.append(s)

	return out


func describe_lines() -> PackedStringArray:
	_ensure_built()
	var out := PackedStringArray()
	out.append("animations (%s): %d clips" % [String(id), clips.size()])

	for c in clips:
		if c != null:
			out.append("  " + c.describe())

	return out


func describe() -> String:
	return "DotPlayerAnimSet(%s, %d)" % [String(id), clips.size()]


func _to_string() -> String:
	return describe()


## The eleven locomotion states, mapped to rows 0-10 of a sheet.
##
## [b]A skeleton rather than content.[/b] Frame counts and rates are guesses; what the
## preset is actually for is the mapping, so a game only has to correct the numbers
## rather than discover the list. [method missing_for] over
## [method locomotion_states] is how it checks it did.
static func locomotion(p_id: StringName = &"locomotion") -> DotPlayerAnimSet:
	var set := DotPlayerAnimSet.new()
	set.id = p_id

	var idle := DotPlayerAnimClip.make(DotPlayerAnimState.IDLE, true, 0, 4)
	idle.fps = 6.0

	var walk := DotPlayerAnimClip.make(DotPlayerAnimState.WALK, true, 1, 8)
	walk.fps = 10.0
	walk.footsteps = PackedFloat32Array([0.1, 0.6])

	var run := DotPlayerAnimClip.make(DotPlayerAnimState.RUN, true, 2, 8)
	run.fps = 14.0
	run.footsteps = PackedFloat32Array([0.05, 0.55])

	var crouch_idle := DotPlayerAnimClip.make(DotPlayerAnimState.CROUCH_IDLE, true, 3, 4)
	crouch_idle.fps = 5.0

	var crouch_walk := DotPlayerAnimClip.make(DotPlayerAnimState.CROUCH_WALK, true, 4, 8)
	crouch_walk.fps = 7.0
	crouch_walk.footsteps = PackedFloat32Array([0.15, 0.65])

	var jump := DotPlayerAnimClip.make(DotPlayerAnimState.JUMP, false, 5, 3)
	jump.fps = 12.0

	var fall := DotPlayerAnimClip.make(DotPlayerAnimState.FALL, true, 6, 2)
	fall.fps = 6.0

	var land := DotPlayerAnimClip.make(DotPlayerAnimState.LAND, false, 7, 3)
	land.fps = 18.0
	land.footsteps = PackedFloat32Array([0.0])

	var climb := DotPlayerAnimClip.make(DotPlayerAnimState.CLIMB, true, 8, 6)
	climb.fps = 8.0

	var swim := DotPlayerAnimClip.make(DotPlayerAnimState.SWIM, true, 9, 6)
	swim.fps = 8.0

	var dead := DotPlayerAnimClip.make(DotPlayerAnimState.DEAD, false, 10, 4)
	dead.fps = 10.0

	set.clips = [
		idle, walk, run, crouch_idle, crouch_walk,
		jump, fall, land, climb, swim, dead,
	]
	set.fallback = DotPlayerAnimState.IDLE
	var _res := set.build()
	return set


## Every state [DotPlayerAnimState] can produce. For [method missing_for].
static func locomotion_states() -> Array[StringName]:
	return [
		DotPlayerAnimState.IDLE,
		DotPlayerAnimState.WALK,
		DotPlayerAnimState.RUN,
		DotPlayerAnimState.CROUCH_IDLE,
		DotPlayerAnimState.CROUCH_WALK,
		DotPlayerAnimState.JUMP,
		DotPlayerAnimState.FALL,
		DotPlayerAnimState.LAND,
		DotPlayerAnimState.CLIMB,
		DotPlayerAnimState.SWIM,
		DotPlayerAnimState.DEAD,
	]
