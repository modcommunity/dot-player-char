extends Node

## Exercises dot-player-char's animation half with no rig, no sheet and no renderer.
##
## Which covers the half that matters: the state machine is a pure function, so every
## branch of it — including the two kinds of flicker it exists to prevent — is checkable
## as arithmetic. The sinks are checked against a real [AnimationPlayer] and a stub
## sprite, because "did it only call the setter on a change" is not a question a value
## can answer.
##
## [codeblock]
## godot --headless --path . res://examples/anim_selftest.tscn
## [/codeblock]

const SECTIONS := 6
const CHECKS := 98

var _passed := 0
var _failed := 0
var _section_count := 0


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run()


func _run() -> void:
	_line("dot-player-char animation self-test")
	_line("")

	_test_states()
	_test_hysteresis()
	_test_clips()
	_test_set()
	await _test_driver()
	await _test_sinks()

	_line("")
	_line("%d sections, %d passed, %d failed" % [_section_count, _passed, _failed])

	if _section_count != SECTIONS:
		_line("ERROR: %d of %d sections ran." % [_section_count, SECTIONS])
		get_tree().quit(1)
		return

	if _passed + _failed != CHECKS:
		_line(
			"ERROR: %d checks ran, %d expected. A section aborted part-way."
			% [_passed + _failed, CHECKS]
		)
		get_tree().quit(1)
		return

	get_tree().quit(1 if _failed > 0 else 0)


## Stands in for [DotPlayerSpriteVisual], which the driver must never name.
class StubSprite extends Node:
	var row := -1
	var frame := -1
	var angle := 0.0
	var row_calls := 0
	var frame_calls := 0

	func set_row(p_row: int) -> void:
		row = p_row
		row_calls += 1

	func set_frame(p_frame: int) -> void:
		frame = p_frame
		frame_calls += 1

	func set_facing_angle(p_angle: float) -> void:
		angle = p_angle


func _ground(speed: float, crouched: bool = false) -> Dictionary:
	return {"speed": speed, "on_floor": true, "crouched": crouched, "vertical": 0.0}


func _air(vertical: float) -> Dictionary:
	return {"speed": 0.0, "on_floor": false, "vertical": vertical}


# --- The state machine ------------------------------------------------------

func _test_states() -> void:
	_section("locomotion states")

	var s := DotPlayerAnimState.new()
	_check(s.validate().ok, "the defaults validate")
	_check(s.state() == DotPlayerAnimState.IDLE, "and it starts idle")

	_check(s.advance(_ground(0.0), 0.016) == DotPlayerAnimState.IDLE, "standing still is idle")
	_check(s.advance(_ground(1.0), 0.016) == DotPlayerAnimState.WALK, "a slow speed is a walk")
	_check(s.advance(_ground(8.0), 0.016) == DotPlayerAnimState.RUN, "a fast one is a run")
	_check(s.is_moving(), "and it says so")
	_check(s.advance(_ground(0.0), 0.016) == DotPlayerAnimState.IDLE, "and back to idle")

	_check(
		s.advance(_ground(0.0, true), 0.016) == DotPlayerAnimState.CROUCH_IDLE,
		"crouching still is its own state"
	)
	_check(
		s.advance(_ground(2.0, true), 0.016) == DotPlayerAnimState.CROUCH_WALK,
		"and so is crouching along"
	)

	# Air, with the grace window.
	s.forget_state()
	_check(
		s.advance(_air(0.0), 0.016) == DotPlayerAnimState.IDLE,
		"one frame off the ground is not a jump — a stair step, a ramp seam and a "
		+ "physics jitter all leave the floor for a tick, and a character that started "
		+ "a jump animation each time would twitch its way upstairs"
	)

	var state := s.advance(_air(5.0), 0.2)
	_check(state == DotPlayerAnimState.JUMP, "but a real one, going up, is a jump")
	_check(s.is_airborne(), "and it says so")
	_check(s.advance(_air(-5.0), 0.016) == DotPlayerAnimState.FALL, "going down is a fall")

	var landing := s.advance(
		{"speed": 0.0, "on_floor": true, "vertical": -10.0}, 0.016
	)
	_check(landing == DotPlayerAnimState.LAND, "a hard landing plays a landing")
	_check(
		s.advance(_ground(0.0), 0.016) == DotPlayerAnimState.LAND,
		"which holds for its own time rather than being gone the next frame"
	)
	_check(
		s.advance(_ground(0.0), 1.0) == DotPlayerAnimState.IDLE,
		"and then lets locomotion resume"
	)

	s.forget_state()
	var _fell := s.advance(_air(-1.0), 0.2)
	var soft := s.advance({"speed": 0.0, "on_floor": true, "vertical": -1.0}, 0.016)
	_check(
		soft != DotPlayerAnimState.LAND,
		"and a gentle landing plays nothing, so walking off a kerb is not an event"
	)

	_check(
		s.advance({"climbing": true}, 0.016) == DotPlayerAnimState.CLIMB,
		"climbing overrides everything"
	)
	_check(
		s.advance({"swimming": true}, 0.016) == DotPlayerAnimState.SWIM,
		"and so does swimming"
	)
	_check(
		s.advance({"alive": false, "speed": 9.0}, 0.016) == DotPlayerAnimState.DEAD,
		"and being dead overrides both"
	)

	s.forget_state()
	_check(s.state() == DotPlayerAnimState.IDLE, "it can be put back for a respawn")
	_check(
		s.advance({}, 0.016) == DotPlayerAnimState.IDLE,
		"and a caller that knows nothing still gets a state rather than a crash"
	)

	var bad := DotPlayerAnimState.new()
	bad.run_exit_speed = 9.0
	_check(not bad.validate().ok, "thresholds with no gap between them are refused")

	var bad2 := DotPlayerAnimState.new()
	bad2.move_exit_speed = 5.0
	_check(not bad2.validate().ok, "at either end")
	_check(s.describe().contains("idle"), "and it describes itself")


func _test_hysteresis() -> void:
	_section("hysteresis")

	var s := DotPlayerAnimState.new()
	s.run_speed = 4.0
	s.run_exit_speed = 3.4

	_check(s.advance(_ground(3.7), 0.016) == DotPlayerAnimState.WALK, "3.7 from a walk is a walk")
	_check(s.advance(_ground(4.2), 0.016) == DotPlayerAnimState.RUN, "4.2 becomes a run")
	_check(
		s.advance(_ground(3.7), 0.016) == DotPlayerAnimState.RUN,
		"and 3.7 from a RUN is still a run — which is the whole point: one threshold "
		+ "makes a player holding a stick at the boundary flicker every tick"
	)
	_check(s.advance(_ground(3.0), 0.016) == DotPlayerAnimState.WALK, "below the exit, it walks")

	# The flicker, measured. A single-threshold machine changes state on every tick of
	# this sequence; a hysteretic one changes twice.
	var noisy := DotPlayerAnimState.new()
	noisy.forget_state()
	var changes := 0
	var last := noisy.state()

	for i in range(40):
		var speed := 4.0 + (0.15 if i % 2 == 0 else -0.15)
		var now := noisy.advance(_ground(speed), 0.016)
		if now != last:
			changes += 1
			last = now

	_check(
		changes <= 2,
		"forty ticks of speed jittering either side of the threshold produce %d state "
		% changes + "changes, not forty"
	)

	var stop := DotPlayerAnimState.new()
	_check(stop.advance(_ground(0.15), 0.016) == DotPlayerAnimState.IDLE, "0.15 from idle is idle")
	_check(stop.advance(_ground(0.3), 0.016) == DotPlayerAnimState.WALK, "0.3 starts a walk")
	_check(
		stop.advance(_ground(0.15), 0.016) == DotPlayerAnimState.WALK,
		"and the same trick applies at the standing-still boundary, where it stops a "
		+ "character twitching while being pushed by a slope"
	)


# --- Clips ------------------------------------------------------------------

func _test_clips() -> void:
	_section("clips")

	var c := DotPlayerAnimClip.make(&"walk", true, 1, 8)
	c.fps = 10.0
	_check(c.name_for_player() == &"walk", "a clip names itself for an AnimationPlayer")

	c.clip_name = &"Walk_Forward"
	_check(c.name_for_player() == &"Walk_Forward", "or carries an explicit name")

	_check(is_equal_approx(c.sheet_duration(), 0.8), "eight frames at 10 fps is 0.8 s")
	_check(c.frame_at(0.0) == 0, "it starts on frame zero")
	_check(c.frame_at(0.25) == 2, "and advances")
	_check(c.frame_at(0.85) == 0, "and a looping clip wraps")

	var once := DotPlayerAnimClip.make(&"land", false, 7, 3)
	once.fps = 10.0
	_check(
		once.frame_at(9.0) == 2,
		"a one-shot holds its last frame instead of snapping back, which would read as "
		+ "the animation being cut off rather than as having finished"
	)
	_check(once.finished_at(0.35), "and says when it is done")
	_check(not once.finished_at(0.1), "and when it is not")
	_check(not c.finished_at(999.0), "while a looping clip is never finished")

	# Events, which are the part that is wrong in a way nobody can describe.
	var stepper := DotPlayerAnimClip.make(&"walk", true, 1, 8)
	stepper.fps = 10.0
	stepper.footsteps = PackedFloat32Array([0.25])
	stepper.events = {"swish": 0.75}

	_check(
		stepper.events_between(0.0, 0.1).is_empty(),
		"an event before its moment does not fire"
	)
	_check(
		stepper.events_between(0.15, 0.25).has("footstep"),
		"an event whose moment falls inside the window does"
	)
	_check(
		stepper.events_between(0.25, 0.35).is_empty(),
		"and does not fire again the next tick — a window rather than an instant is "
		+ "the only thing that fires an event exactly once"
	)
	_check(stepper.events_between(0.55, 0.65).has("swish"), "named events fire too")

	var fired := 0
	var t := 0.0
	while t < 1.6:
		fired += stepper.events_between(t, t + 0.05).size()
		t += 0.05
	_check(
		fired == 4,
		"and over two full loops, two events fire twice each (%d) — a looping clip's "
		% fired + "events fire once per pass"
	)

	_check(c.describe().contains("walk"), "and a clip describes itself")


func _test_set() -> void:
	_section("an animation set")

	var set := DotPlayerAnimSet.locomotion()
	_check(set.build().ok, "the locomotion preset builds")
	_check(set.ids().size() == 11, "with eleven clips")
	_check(
		set.missing_for(DotPlayerAnimSet.locomotion_states()).is_empty(),
		"covering every state the machine can produce — a state with no clip is "
		+ "invisible at runtime, because the character just keeps playing what it was"
	)

	_check(set.clip(DotPlayerAnimState.RUN).id == &"run", "a state resolves to its clip")
	_check(
		set.clip(&"nonsense").id == DotPlayerAnimState.IDLE,
		"and an unmapped one falls back, because the set declared a fallback"
	)

	var strict := DotPlayerAnimSet.locomotion()
	strict.fallback = &""
	_check(
		strict.clip(&"nonsense") == null,
		"a set with no fallback answers nothing, which is visible — the alternative, "
		+ "quietly using the first clip, plays an idle for every unmapped action"
	)

	var partial := DotPlayerAnimSet.new()
	partial.clips = [DotPlayerAnimClip.make(&"idle")]
	_check(partial.build().ok, "a smaller set builds")
	_check(
		partial.missing_for(DotPlayerAnimSet.locomotion_states()).size() == 10,
		"and reports every state it cannot cover, all at once rather than one bug "
		+ "report at a time"
	)

	var dup := DotPlayerAnimSet.new()
	dup.clips = [DotPlayerAnimClip.make(&"a"), DotPlayerAnimClip.make(&"a")]
	_check(not dup.build().ok, "two clips with one name are refused")

	var bad := DotPlayerAnimSet.new()
	bad.clips = [DotPlayerAnimClip.make(&"a")]
	bad.fallback = &"missing"
	_check(not bad.build().ok, "and a fallback that is not in the set")
	_check(not DotPlayerAnimSet.new().build().ok, "and an empty one")
	_check(set.describe_lines().size() == 12, "and a set describes itself")


# --- The driver -------------------------------------------------------------

func _test_driver() -> void:
	_section("the driver")

	var player := DotPlayer.new()
	add_child(player)

	var driver := DotPlayerAnimDriver.new()
	driver.anim_set = DotPlayerAnimSet.locomotion()
	driver.auto_drive = false
	player.add_child(driver)

	await get_tree().process_frame

	var changes: Array = []
	driver.state_changed.connect(func(from: StringName, to: StringName) -> void:
		changes.append([String(from), String(to)])
	)
	var events: Array = []
	driver.clip_event.connect(func(event: StringName, _at: float) -> void:
		events.append(String(event))
	)

	_check(driver.state() == DotPlayerAnimState.IDLE, "the driver starts idle")

	var clip := driver.drive(_ground(8.0), 0.016)
	_check(clip != null and clip.id == DotPlayerAnimState.RUN, "driving picks a clip")
	_check(changes.size() == 1, "with a signal when the state changed")
	_check(driver.elapsed() == 0.0, "and a fresh clip starts at zero")

	driver.drive(_ground(8.0), 0.1)
	_check(driver.elapsed() > 0.0, "and then advances")
	_check(
		events.size() > 0,
		"firing the clip's own events — a footstep on a wall clock drifts out of step "
		+ "with the animation the moment the frame rate changes"
	)

	# One-shot actions over the base.
	var actions: Array = []
	driver.action_started.connect(func(a: StringName) -> void: actions.append(String(a)))
	var finished: Array = []
	driver.action_finished.connect(func(a: StringName, interrupted: bool) -> void:
		finished.append([String(a), interrupted])
	)

	_check(not driver.play_action(&"nonexistent").ok, "an unmapped action is refused")
	_check(
		driver.play_action(&"nonexistent").error.message.contains("nonexistent"),
		"by name, because an animation that never plays is invisible and gets reported "
		+ "as 'the reload does not work'"
	)

	_check(driver.play_action(DotPlayerAnimState.LAND).ok, "a mapped one starts")
	_check(actions.size() == 1, "with a signal")
	_check(driver.action() == DotPlayerAnimState.LAND, "and is current")

	driver.drive(_ground(8.0), 0.016)
	_check(
		driver.state() == DotPlayerAnimState.RUN,
		"and the locomotion state carries on underneath — a character reloading while "
		+ "running is doing both, and a driver that replaced the state stops their legs"
	)

	driver.drive(_ground(8.0), 2.0)
	_check(driver.action() == &"", "a one-shot finishes on its own")
	_check(finished.size() == 1 and not bool(finished[0][1]), "reporting it was not interrupted")

	var _a := driver.play_action(DotPlayerAnimState.LAND)
	var _b := driver.play_action(DotPlayerAnimState.JUMP)
	_check(
		finished.size() == 2 and bool(finished[1][1]),
		"and one started over another reports the first as interrupted"
	)

	driver.cancel_action()
	_check(driver.action() == &"", "an action can be cancelled")
	driver.cancel_action()
	_check(finished.size() == 3, "and cancelling nothing fires nothing")

	driver.forget_state()
	_check(driver.state() == DotPlayerAnimState.IDLE, "everything can be put back")
	_check(driver.clip() == null, "with no clip playing")

	var setless := DotPlayerAnimDriver.new()
	setless.auto_drive = false
	player.add_child(setless)
	await get_tree().process_frame
	_check(
		setless.drive(_ground(1.0), 0.016) == null,
		"a driver with no set drives nothing rather than erroring"
	)

	_check(driver.describe_lines().size() >= 1, "and it describes itself")

	player.queue_free()


func _test_sinks() -> void:
	_section("sinks")

	var player := DotPlayer.new()
	add_child(player)

	var driver := DotPlayerAnimDriver.new()
	driver.anim_set = DotPlayerAnimSet.locomotion()
	driver.auto_drive = false
	player.add_child(driver)

	# The sprite sink, duck-typed.
	var sprite_sink := DotPlayerAnimSpriteSink.new()
	driver.add_child(sprite_sink)

	var stub := StubSprite.new()
	driver.add_child(stub)

	await get_tree().process_frame

	_check(
		sprite_sink.target() == stub,
		"a sprite sink finds anything with set_row and set_frame — which is how this "
		+ "driver reaches a sprite visual without naming its class"
	)
	_check(sprite_sink.is_ready_to_play(), "and is ready")

	driver.drive(_ground(8.0), 0.016)
	_check(stub.row == 2, "driving sets the clip's row on the target")
	_check(stub.frame >= 0, "and a frame")

	var row_calls := stub.row_calls
	driver.drive(_ground(8.0), 0.001)
	_check(
		stub.row_calls == row_calls,
		"and the row is only set on a change — this runs once a frame for every "
		+ "visible character, and a setter called sixty times a second for the same "
		+ "value is sixty wasted calls per character"
	)

	driver.set_facing(1.25)
	_check(
		is_equal_approx(stub.angle, 1.25),
		"and a facing angle reaches a target that understands one"
	)

	sprite_sink.stop()
	driver.drive(_ground(0.0), 0.016)
	_check(stub.row == 0, "stopping resets the sink, so the next frame sets everything")

	# The AnimationPlayer sink, against a real one.
	var anim_player := AnimationPlayer.new()
	var library := AnimationLibrary.new()
	var animation := Animation.new()
	animation.length = 1.0
	var _added := library.add_animation(&"run", animation)
	var _lib := anim_player.add_animation_library(&"", library)

	var player_sink := DotPlayerAnimPlayerSink.new()
	driver.add_child(player_sink)
	player_sink.add_child(anim_player)

	await get_tree().process_frame

	_check(player_sink.player() == anim_player, "an AnimationPlayer sink finds its player")
	_check(player_sink.is_ready_to_play(), "and is ready")

	player_sink.play(driver.anim_set.clip(DotPlayerAnimState.RUN), 0.0)
	_check(player_sink.playing() == &"run", "and plays a clip it has")

	player_sink.play(driver.anim_set.clip(DotPlayerAnimState.SWIM), 0.0)
	_check(
		player_sink.playing() == &"run",
		"while a clip it does not have leaves the previous one alone and warns once — "
		+ "a missing clip otherwise looks like the animation system not working at all"
	)

	player_sink.stop()
	_check(player_sink.playing() == &"", "and it can be stopped")

	var orphan := DotPlayerAnimPlayerSink.new()
	add_child(orphan)
	await get_tree().process_frame
	_check(
		not orphan.is_ready_to_play(),
		"a sink with nothing to drive says so, and a driver skips it"
	)
	orphan.play(driver.anim_set.clip(DotPlayerAnimState.RUN), 0.0)
	_check(orphan.playing() == &"", "and driving it does nothing rather than crashing")

	_check(player_sink.describe_lines().size() == 1, "sinks describe themselves")
	_check(sprite_sink.describe_lines().size() == 1, "both of them")

	orphan.queue_free()
	player.queue_free()


# --- Harness ---------------------------------------------------------------

func _section(title: String) -> void:
	_section_count += 1
	_line("")
	_line("-- %s" % title)


func _check(condition: bool, what: String) -> void:
	if condition:
		_passed += 1
		_line("   ok   %s" % what)
	else:
		_failed += 1
		_line("  FAIL  %s" % what)


func _line(text: String) -> void:
	print(text)
