extends Node3D

## Eight unarmed people with `auto_animate` on, 4 to 10 m in front of the camera, carried by a body that moves only on
## physics ticks (128 Hz) while frames come faster (the frame rate a windowed sandbox runs at), as game-playground's NPCs
## are. Prints `NPC_BENCH us_per_figure=` (median of rounds), `NPC_CLIP_CHANGES` (clip switches a second, per figure)
## and `NPC_POSES` (poses a second, per figure).
## Args after `--`: --frames N --rounds N --fps F --tick T.

const COUNT := 8

var _bodies: Array[Node3D] = []
var _people: Array[DotHumanoidFigure] = []


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(0, 1.7, 0)
	camera.current = true
	for i in COUNT:
		var body := Node3D.new()
		add_child(body)
		body.position = Vector3((floorf(i / 4.0) - 1.0) * 3.0, 0.0, -(4.0 + float(i % 4) * 2.0))
		var f := DotHumanoidFigure.new()
		body.add_child(f)
		f.build(DotHumanoidLook.stock(i * 31 + 7), 1.8)
		f.auto_animate = true
		f.set_process(false)
		_bodies.append(body)
		_people.append(f)
	_run.call_deferred()


func _arg(name: String, fallback: float) -> float:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--" + name)
	return float(args[at + 1]) if at >= 0 and at + 1 < args.size() else fallback


func _run() -> void:
	var frames := int(_arg("frames", 3000))
	var rounds := int(_arg("rounds", 5))
	var dt := 1.0 / _arg("fps", 355.0)
	var tick := 1.0 / _arg("tick", 128.0)
	var t := 0.0
	var next_tick := 0.0
	var changes := 0
	var per_round: Array[float] = []
	var poses := 0
	for r in rounds + 1:
		var total := 0
		for frame in frames:
			t += dt
			while next_tick <= t:
				next_tick += tick
				for i in COUNT:
					# A wander: walking pace, now and then a stop or a jog, turning slowly.
					var phase := next_tick * 0.3 + float(i) * 1.7
					var speed := 0.0 if fmod(phase, 4.0) < 0.6 else 1.6 + 2.4 * (0.5 + 0.5 * sin(phase * 0.7))
					var heading := phase * 0.5 + float(i)
					_bodies[i].position += Vector3(sin(heading), 0.0, cos(heading)) * speed * tick
					_bodies[i].rotation.y = heading
			var t0 := Time.get_ticks_usec()
			for f in _people:
				var was := f.clip
				var posed := f._frame
				f._process(dt)
				if r > 0:
					changes += 1 if f.clip != was else 0
					poses += f._frame - posed
			total += Time.get_ticks_usec() - t0
		if r > 0:
			per_round.append(float(total) / float(frames * COUNT))
	per_round.sort()
	print("NPC_BENCH us_per_figure=%.2f rounds=%s" % [per_round[per_round.size() / 2], str(per_round)])
	print("NPC_CLIP_CHANGES per_figure_second=%.2f" % (float(changes) / float(COUNT) / (float(frames * rounds) * dt)))
	print("NPC_POSES per_figure_second=%.1f" % (float(poses) / float(COUNT) / (float(frames * rounds) * dt)))
	get_tree().quit()

