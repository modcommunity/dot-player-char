class_name DotPlayerAnimState
extends RefCounted

## Which locomotion state a character is in, as a pure function of how it is moving.
##
## [b]Pure, and with hysteresis, and the second is why it is worth a class.[/b] The
## naive version — [code]speed > walk_speed ? "run" : "walk"[/code] — flickers between
## two animations for a player holding a stick at exactly the threshold, and the fix is
## not a smaller epsilon, it is two thresholds: one to enter a state and a lower one to
## leave it. The same applies to leaving the ground, where a single frame of a stair
## step should not start a jump animation.
##
## Nothing here reads a node, a clock or an input device. [method advance] takes a
## description of the motion and returns a state, which is what lets a replay, a remote
## player and a server-side animation check all produce the same answer.

## The vocabulary. A game may use any [StringName]; these are the ones the presets map.
const IDLE := &"idle"
const WALK := &"walk"
const RUN := &"run"
const CROUCH_IDLE := &"crouch_idle"
const CROUCH_WALK := &"crouch_walk"
const JUMP := &"jump"
const FALL := &"fall"
const LAND := &"land"
const CLIMB := &"climb"
const SWIM := &"swim"
const DEAD := &"dead"

## Speed above which walking becomes running.
var run_speed: float = 4.0

## Speed below which running becomes walking again. Must be below [member run_speed].
var run_exit_speed: float = 3.4

## Speed above which standing still becomes walking.
var move_speed: float = 0.2

## Speed below which walking becomes standing still.
var move_exit_speed: float = 0.1

## Seconds of being off the ground before the air animations start.
##
## [b]Not zero.[/b] A stair step, a ramp seam and a physics jitter all take a character
## off the floor for one or two ticks, and a character that started a jump animation
## every time would twitch its way up a staircase.
var air_grace: float = 0.08

## Upward speed above which the air state is a jump rather than a fall.
var jump_speed: float = 0.5

## Seconds the landing animation holds before locomotion resumes.
var land_time: float = 0.15

## Downward speed on impact below which no landing animation plays at all.
var land_threshold: float = 3.0

var _state: StringName = IDLE
var _air_time: float = 0.0
var _land_time: float = 0.0
var _was_on_floor: bool = true


## One tick. [param motion] carries whatever the caller knows.
##
## Recognised keys, all optional: [code]speed[/code] (ground speed),
## [code]vertical[/code] (positive is up), [code]on_floor[/code], [code]crouched[/code],
## [code]climbing[/code], [code]swimming[/code], [code]alive[/code].
##
## Everything missing takes a default that means "no", so a game that only supplies a
## speed and a floor flag still gets sensible locomotion rather than a crash.
func advance(motion: Dictionary, delta: float) -> StringName:
	if not bool(motion.get("alive", true)):
		_state = DEAD
		return _state

	var on_floor := bool(motion.get("on_floor", true))
	var speed := float(motion.get("speed", 0.0))
	var vertical := float(motion.get("vertical", 0.0))
	var crouched := bool(motion.get("crouched", false))

	if bool(motion.get("swimming", false)):
		_state = SWIM
		_air_time = 0.0
		return _state

	if bool(motion.get("climbing", false)):
		_state = CLIMB
		_air_time = 0.0
		return _state

	if on_floor:
		if not _was_on_floor and vertical < -land_threshold and land_time > 0.0:
			_land_time = land_time

		_air_time = 0.0
	else:
		_air_time += delta

	_was_on_floor = on_floor

	if _land_time > 0.0:
		# Decremented before the test, so a long frame ends the landing in the same
		# call rather than one later. A tick that is longer than the whole landing is
		# not hypothetical: it is what a level load, or a headless suite stepping a
		# second at a time, produces.
		_land_time -= delta

		if _land_time > 0.0:
			_state = LAND
			return _state

	if not on_floor and _air_time >= air_grace:
		_state = JUMP if vertical > jump_speed else FALL
		return _state

	if not on_floor:
		# Inside the grace window: keep whatever was playing rather than committing to
		# an air state. This is the line that stops a staircase looking like a hop.
		return _state

	_state = _ground_state(speed, crouched)
	return _state


## The ground half, with the hysteresis.
func _ground_state(speed: float, crouched: bool) -> StringName:
	var moving := _moving(speed)

	if crouched:
		return CROUCH_WALK if moving else CROUCH_IDLE

	if not moving:
		return IDLE

	return RUN if _running(speed) else WALK


func _moving(speed: float) -> bool:
	var was_moving := _state in [WALK, RUN, CROUCH_WALK]
	return speed > (move_exit_speed if was_moving else move_speed)


func _running(speed: float) -> bool:
	return speed > (run_exit_speed if _state == RUN else run_speed)


func state() -> StringName:
	return _state


func is_airborne() -> bool:
	return _state == JUMP or _state == FALL


func is_moving() -> bool:
	return _state == WALK or _state == RUN or _state == CROUCH_WALK


## Puts the machine back where it started. For a respawn.
##
## [b]Not called [code]reset[/code].[/b] The family has already shipped one
## [code]reset_state[/code] that silently bound to [Resource]'s — see
## [code]docs/gdscript-hazards.md[/code] — and although this class extends
## [RefCounted], the habit is the point.
func forget_state() -> void:
	_state = IDLE
	_air_time = 0.0
	_land_time = 0.0
	_was_on_floor = true


func validate() -> DotResult:
	if run_exit_speed >= run_speed:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"The run threshold (%.2f) is not above the exit threshold (%.2f)."
			% [run_speed, run_exit_speed],
			"With no gap there is no hysteresis, and a player holding a stick at the "
			+ "threshold flickers between two animations every tick."
		)

	if move_exit_speed >= move_speed:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"The move threshold (%.2f) is not above its exit threshold (%.2f)."
			% [move_speed, move_exit_speed]
		)

	return DotResult.success(null)


func describe() -> String:
	return "%s (air %.2fs)" % [String(_state), _air_time]


func _to_string() -> String:
	return "DotPlayerAnimState(%s)" % describe()
