extends Node3D

## 32 armed people moving like a match's remote players (gun held, aim pitch, support grip, mixed
## distances), stepped with a fixed delta. Prints `ANIM_BENCH us_per_call=` (median of rounds), the
## phases with `--parts 1`, and `ANIM_DIGEST` (a hash of every pose_record every frame) to prove a
## change leaves the pose bit-identical. Args after `--`: --frames N --rounds N --parts 0|1 --native 0|1
## (the dot_sim pose layers when loaded, default 1; 0 times the script path) --ab 1 (script and native
## interleaved in one process).

const COUNT := 32
const DT := 1.0 / 60.0

var _people: Array[DotHumanoidFigure] = []
var _camera: Camera3D


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_camera = Camera3D.new()
	add_child(_camera)
	_camera.position = Vector3(0, 1.7, 0)
	_camera.current = true
	for i in COUNT:
		var f := DotHumanoidFigure.new()
		add_child(f)
		f.build(DotHumanoidLook.stock(i * 31 + 7), 1.8)
		var ring := 4.0 + float(i % 8) * 6.5
		var angle := float(i) * 0.7
		f.position = Vector3(sin(angle) * ring, 0, -cos(angle) * ring)
		f.set_hold(DotHumanoidFigure.Hold.GUN)
		_people.append(f)
	_run.call_deferred()


func _arg(name: String, fallback: int) -> int:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--" + name)
	return int(args[at + 1]) if at >= 0 and at + 1 < args.size() else fallback


func _step(frame: int) -> void:
	var t := float(frame) * DT
	for i in COUNT:
		var f := _people[i]
		var phase := t * 0.37 + float(i) * 0.9
		var speed := 0.0 if (frame / 90 + i) % 5 == 0 else 2.0 + 4.5 * (0.5 + 0.5 * sin(phase))
		var heading := phase * 0.6 + float(i)
		var v := Vector3(sin(heading), 0.0, cos(heading)) * speed
		var air := (frame + i * 13) % 240 < 30
		v.y = 3.0 - float((frame + i * 13) % 240) * 0.2 if air else 0.0
		f.rotation = Vector3(0.0, float(i) * 0.4 + t * 0.2, 0.0)
		f.set_motion({"on_floor": not air, "vertical": v.y, "crouched": (frame / 120 + i) % 7 == 0,
			"sliding": false, "swimming": false, "climbing": false, "alive": true, "wall_running": false,
			"velocity": v, "wall": Plane(), "aim": 0.4 * sin(t + float(i))})
		f.set_hold(DotHumanoidFigure.Hold.GUN)
		f.set_support_grip(f.global_transform * Vector3(0.05, 1.25, -0.45))
		f.animate(Vector2(v.x, v.z).length(), DT)


func _run() -> void:
	var frames := _arg("frames", 600)
	var rounds := _arg("rounds", 5)
	var parts := _arg("parts", 0) == 1
	DotHumanoidIk.native_enabled = _arg("native", 1) == 1
	print("ANIM_NATIVE %s" % (DotHumanoidIk.native() != null))
	# Digest: one fixed run from frame 0, every pose hashed every frame.
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for frame in frames:
		_step(frame)
		for f in _people:
			ctx.update(f.pose_record().to_byte_array())
	print("ANIM_DIGEST frames=%d sha256=%s" % [frames, ctx.finish().hex_encode()])
	var per_round: Array[float] = []
	for r in rounds:
		var total := 0
		for frame in frames:
			var t0 := Time.get_ticks_usec()
			_step(frames + r * frames + frame)
			total += Time.get_ticks_usec() - t0
		per_round.append(float(total) / float(frames * COUNT))
	per_round.sort()
	print("ANIM_BENCH us_per_call=%.2f rounds=%s" % [per_round[per_round.size() / 2], str(per_round)])
	if _arg("ab", 0) == 1:
		_ab(frames, rounds)
	if parts and _arg("ab", 0) == 1:
		for side in 2:
			DotHumanoidIk.native_enabled = side == 1
			_parts(frames, "native" if side == 1 else "script")
		DotHumanoidIk.native_enabled = true
	elif parts:
		_parts(frames, "")
	get_tree().quit()


## Script and native pose layers in one process, interleaved: each round times both, the order
## swapped every round, so box load drifts onto both alike. Prints `ANIM_AB` medians and the median
## of per-round native minus script.
func _ab(frames: int, rounds: int) -> void:
	var times: Array = [[], []]
	var deltas: Array[float] = []
	var at := frames * (rounds + 2)
	for r in rounds * 2:
		var pair := [0.0, 0.0]
		for k in 2:
			var side := k if r % 2 == 0 else 1 - k
			DotHumanoidIk.native_enabled = side == 1
			var total := 0
			for frame in frames:
				var t0 := Time.get_ticks_usec()
				_step(at + frame)
				total += Time.get_ticks_usec() - t0
			at += frames
			pair[side] = float(total) / float(frames * COUNT)
			times[side].append(pair[side])
		deltas.append(pair[1] - pair[0])
	DotHumanoidIk.native_enabled = true
	for side in 2:
		times[side].sort()
	deltas.sort()
	print("ANIM_AB script=%.2f native=%.2f delta_median=%.2f us/call deltas=%s" % [times[0][times[0].size() / 2],
		times[1][times[1].size() / 2], deltas[deltas.size() / 2], str(deltas)])


## Each phase called on its own after a normal step, timed per call. Mutates the pose (a second
## bend), so run after the digest; times only. `label` (with --ab, which path) prefixes each line.
func _parts(frames: int, label: String) -> void:
	var names := ["motion+machine", "legs.restore", "legs.update", "clip_for", "play", "step_for_distance",
		"anim.advance", "overlays", "aim", "ease", "legs.apply", "support", "swim", "crawl", "on_wall", "own.apply", "skeleton_up", "carry", "floor", "matched_rate"]
	var sums := {}
	for n in names:
		sums[n] = 0
	var start := frames * 10
	for frame in frames:
		_step(start + frame)
		for f in _people:
			var t := Time.get_ticks_usec()
			var m: Dictionary = f._motion.duplicate()
			m["speed"] = 3.0
			f._machine.advance(m, DT)
			t = _lap(sums, "motion+machine", t)
			f.legs.restore(f._skeleton)
			t = _lap(sums, "legs.restore", t)
			f.legs.update(f.global_basis, f._motion.get("velocity", Vector3.ZERO), DT)
			t = _lap(sums, "legs.update", t)
			var w: Array = f._clip_for(f.state, 3.0)
			t = _lap(sums, "clip_for", t)
			f._play(w[0], w[1])
			t = _lap(sums, "play", t)
			DotHumanoidFrames.step_for_distance(f, f._mesh)
			t = _lap(sums, "step_for_distance", t)
			f._anim.advance(DT)
			t = _lap(sums, "anim.advance", t)
			f._apply_overlays()
			t = _lap(sums, "overlays", t)
			f._apply_aim()
			t = _lap(sums, "aim", t)
			f._ease.step(f._skeleton, DT)
			t = _lap(sums, "ease", t)
			f.legs.apply(f._skeleton, f._skeleton_up())
			t = _lap(sums, "legs.apply", t)
			f._apply_support()
			t = _lap(sums, "support", t)
			f._apply_swim(DT)
			t = _lap(sums, "swim", t)
			f._apply_crawl_feet(3.0, DT)
			t = _lap(sums, "crawl", t)
			f.legs.on_wall(f._skeleton, Plane(), Vector3.UP, 0.0)
			t = _lap(sums, "on_wall", t)
			f._own.apply(f._skeleton, f._mesh)
			t = _lap(sums, "own.apply", t)
			f._skeleton_up()
			t = _lap(sums, "skeleton_up", t)
			f._apply_carry()
			t = _lap(sums, "carry", t)
			f._apply_floor()
			t = _lap(sums, "floor", t)
			f._matched_rate(3.0, DT)
			t = _lap(sums, "matched_rate", t)
	for n in names:
		print("ANIM_PART %s%-18s %.2f us/call" % [label + " " if label != "" else "", n, float(sums[n]) / float(frames * COUNT)])


func _lap(sums: Dictionary, key: String, since: int) -> int:
	var now := Time.get_ticks_usec()
	sums[key] += now - since
	return now
