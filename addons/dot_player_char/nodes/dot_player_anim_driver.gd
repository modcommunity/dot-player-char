class_name DotPlayerAnimDriver
extends DotPlayerComponent

## Decides what should be playing, and tells every sink under it.
##
## [b]The decision and the playing are separate, and the decision is pure.[/b] A
## locomotion state comes out of [DotPlayerAnimState] given a description of the motion;
## a clip comes out of [DotPlayerAnimSet] given the state; and a sink makes it happen.
## So a headless server can run the same state machine as a client and check what it
## claims to be doing — which is the only way an animation-driven hitbox is ever
## trustworthy — and a suite can exercise the whole of it with no rig at all.
##
## [codeblock]
## DotPlayer
##   DotPlayerChar
##   DotPlayerAnimDriver            set = DotPlayerAnimSet.locomotion()
##     DotPlayerAnimPlayerSink      (3D)   or  DotPlayerAnimSpriteSink (2D)
## [/codeblock]

## Not [code]CHANNEL[/code]: [DotPlayerComponent] already declares one.
const ANIM_CHANNEL := "player.anim"

## The locomotion state changed.
signal state_changed(from: StringName, to: StringName)

## A one-shot action started.
signal action_started(action: StringName)

## A one-shot action finished, or was interrupted.
signal action_finished(action: StringName, interrupted: bool)

## A clip event fired: a footstep, a muzzle flash, a shell ejecting.
##
## [b]Emitted from the clip's own timeline, not from a [Timer].[/b] A footstep played on
## a wall clock drifts out of step with the animation the moment the frame rate changes,
## and the mismatch is the kind of thing everybody notices and nobody can describe.
signal clip_event(event: StringName, elapsed: float)

@export var anim_set: DotPlayerAnimSet = null

## Whether to run the state machine from the player's body every frame.
##
## Off for a game that computes its own motion description and calls
## [method drive] itself — which is what a server replaying commands does.
@export var auto_drive: bool = true

## The state machine. Exposed so a game can retune the thresholds.
var states: DotPlayerAnimState = null

var _clip: DotPlayerAnimClip = null
var _elapsed: float = 0.0
var _action: StringName = &""
var _action_clip: DotPlayerAnimClip = null
var _action_elapsed: float = 0.0
var _facing: float = 0.0


func _ready() -> void:
	if states == null:
		states = DotPlayerAnimState.new()

	super()


func _process(delta: float) -> void:
	if not auto_drive or not is_active():
		return

	drive(_motion_from_body(), delta)


# --- Driving ----------------------------------------------------------------

## One frame. [param motion] is whatever the caller knows; see [DotPlayerAnimState].
##
## Returns the clip that is playing, which a caller can ignore.
func drive(motion: Dictionary, delta: float) -> DotPlayerAnimClip:
	if anim_set == null:
		return null

	if states == null:
		states = DotPlayerAnimState.new()

	var before := states.state()
	var after := states.advance(motion, delta)

	if after != before:
		state_changed.emit(before, after)

	# A one-shot action plays over the locomotion state rather than instead of it: a
	# character reloading while running is doing both, and a driver that replaced the
	# state would stop their legs.
	if _action != &"":
		_advance_action(delta)

	var wanted := anim_set.clip(after)

	if wanted != _clip:
		_clip = wanted
		_elapsed = 0.0

		for sink in sinks():
			if sink.is_ready_to_play():
				sink.play(_clip, 0.0)
	else:
		_advance_clip(delta)

	if motion.has("facing"):
		set_facing(float(motion["facing"]))

	return _clip


## Starts a one-shot: an attack, a reload, a gesture.
##
## Returns a failure for an action the set has no clip for, rather than silently doing
## nothing — an animation that never plays is invisible, and the report is usually
## "the reload does not work".
func play_action(action: StringName) -> DotResult:
	if anim_set == null or not anim_set.has_clip(action):
		return DotResult.fail(
			DotError.CODE_INVALID,
			"No animation clip called '%s'." % String(action),
			"Known: %s" % ", ".join(_ids())
		)

	if _action != &"":
		action_finished.emit(_action, true)

	_action = action
	_action_clip = anim_set.clip(action)
	_action_elapsed = 0.0

	for sink in sinks():
		if sink.is_ready_to_play():
			sink.play(_action_clip, 0.0)

	action_started.emit(action)
	return DotResult.success(action)


func cancel_action() -> void:
	if _action == &"":
		return

	var was := _action
	_action = &""
	_action_clip = null
	_action_elapsed = 0.0
	action_finished.emit(was, true)


## Which way the character is pointing. Passed to any sink that can use it.
func set_facing(angle: float) -> void:
	if is_equal_approx(angle, _facing):
		return

	_facing = angle

	# Duck-typed through the sink, for the same reason the sprite sink itself is: this
	# driver does not depend on [DotPlayerSpriteVisual], and a sink whose target happens
	# to understand a facing angle should get one.
	for sink in sinks():
		if not sink.has_method("target"):
			continue

		var node: Variant = sink.call("target")

		if node is Node and (node as Node).has_method("set_facing_angle"):
			(node as Node).call("set_facing_angle", angle)


func forget_state() -> void:
	if states != null:
		states.forget_state()

	_clip = null
	_action = &""
	_action_clip = null
	_elapsed = 0.0
	_action_elapsed = 0.0

	for sink in sinks():
		sink.stop()


# --- Reading ----------------------------------------------------------------

func state() -> StringName:
	return states.state() if states != null else &""


func clip() -> DotPlayerAnimClip:
	return _clip


func elapsed() -> float:
	return _elapsed


func action() -> StringName:
	return _action


func sinks() -> Array[DotPlayerAnimSink]:
	var out: Array[DotPlayerAnimSink] = []

	for child in get_children():
		var s := child as DotPlayerAnimSink
		if s != null:
			out.append(s)

	return out


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()
	out.append("animation: %s%s, %.2fs in" % [
		String(state()),
		"" if _action == &"" else " + %s" % String(_action),
		_elapsed,
	])

	for sink in sinks():
		out.append_array(sink.describe_lines())

	return out


# --- Internals --------------------------------------------------------------

func _advance_clip(delta: float) -> void:
	if _clip == null:
		return

	var from := _elapsed
	_elapsed += delta

	for event in _clip.events_between(from, _elapsed):
		clip_event.emit(StringName(event), _elapsed)

	for sink in sinks():
		if sink.is_ready_to_play():
			sink.advance_to(_clip, _elapsed)


func _advance_action(delta: float) -> void:
	if _action_clip == null:
		_action = &""
		return

	var from := _action_elapsed
	_action_elapsed += delta

	for event in _action_clip.events_between(from, _action_elapsed):
		clip_event.emit(StringName(event), _action_elapsed)

	for sink in sinks():
		if sink.is_ready_to_play():
			sink.advance_to(_action_clip, _action_elapsed)

	if _action_clip.finished_at(_action_elapsed):
		var was := _action
		_action = &""
		_action_clip = null
		_action_elapsed = 0.0
		action_finished.emit(was, false)


## Reads the motion out of the player's body, for the automatic case.
##
## Everything it cannot work out is left out of the dictionary rather than guessed, so
## [DotPlayerAnimState]'s defaults apply — which is why a game with a body that is not a
## [CharacterBody3D] still gets idle and walk rather than nothing.
func _motion_from_body() -> Dictionary:
	var motion: Dictionary = {}

	if not is_bound():
		return motion

	var body := player().body()

	if body is CharacterBody3D:
		var b3 := body as CharacterBody3D
		motion["speed"] = Vector2(b3.velocity.x, b3.velocity.z).length()
		motion["vertical"] = b3.velocity.y
		motion["on_floor"] = b3.is_on_floor()
	elif body is CharacterBody2D:
		var b2 := body as CharacterBody2D
		motion["speed"] = absf(b2.velocity.x)
		# Screen Y grows downward, so an upward velocity is negative and has to be
		# flipped before the state machine — which thinks in world terms — sees it.
		motion["vertical"] = -b2.velocity.y
		motion["on_floor"] = b2.is_on_floor()
		motion["facing"] = _heading_of(b2.velocity)

	var ch := player().component(&"DotPlayerChar")

	if ch != null and ch.has_method("is_crouched"):
		motion["crouched"] = bool(ch.call("is_crouched"))

	motion["alive"] = player().is_alive() if player().is_bound() else true
	return motion


## The heading of a 2D velocity, keeping the previous one when it is standing still.
##
## [DotPlayerSpriteFacing.angle_of] is the same question and is in this addon, so it is
## asked rather than re-answered. It was a duplicate while the sprite half was a
## separate addon a 3D game would not have installed; it is not one now.
func _heading_of(velocity: Vector2) -> float:
	return DotPlayerSpriteFacing.angle_of(velocity, _facing)


func _ids() -> PackedStringArray:
	var out := PackedStringArray()

	if anim_set != null:
		for i in anim_set.ids():
			out.append(String(i))

	return out
