class_name DotPlayerAnimState
extends RefCounted

## Which locomotion state a character is in, as a pure function of how it is moving.
## Hysteresis (a higher threshold to enter a state than to leave it) stops flicker at a
## threshold; nothing reads a node or clock, so replays and remote players agree.

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
## Not zero: stair steps and physics jitter leave the floor for a tick or two.
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


## One tick. [param motion] keys, all optional: speed, vertical (up positive), on_floor,
## crouched, climbing, swimming, alive. A missing key defaults to "no". [param speed_now], when given, stands in
## for the `speed` key (a caller with its own speed need not copy the dictionary to add it).
func advance(motion: Dictionary, delta: float, speed_now: float = NAN) -> StringName:
	if not bool(motion.get("alive", true)):
		_state = DEAD
		return _state

	var on_floor := bool(motion.get("on_floor", true))
	var speed := float(motion.get("speed", 0.0)) if is_nan(speed_now) else speed_now
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
		# Decremented before the test so a long frame (a level load, a suite stepping a
		# second) ends the landing in the same call.
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
## Not called [code]reset[/code]: see [code]docs/gdscript-hazards.md[/code] on [Resource]'s
## name clash.
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
