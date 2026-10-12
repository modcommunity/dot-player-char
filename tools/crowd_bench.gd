extends Node3D

## 30 people running in a ring (`people_sheet.gd --crowd`'s layout), then the same with four of
## them fallen as skeletal ragdolls: frame time, draw calls and primitives over 300 frames,
## printed (in a browser, to the console) as `BENCH` lines, then `BENCH DONE`. The main scene of
## a scratch web export for measuring the people in a browser (docs/people.md, "What a crowd costs").

var _people: Array[DotHumanoidFigure] = []
var _camera: Camera3D
var _root: Node3D


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_root = self
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("9aa3ad")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.75, 0.8)
	env.environment.ambient_light_energy = 0.6
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(120, 120)
	floor.mesh = plane
	add_child(floor)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(120, 1, 120)
	shape.shape = box
	shape.position = Vector3(0, -0.5, 0)
	body.add_child(shape)
	add_child(body)
	_camera = Camera3D.new()
	_camera.fov = 70
	add_child(_camera)
	_camera.position = Vector3(0, 1.7, 4)
	_camera.look_at(Vector3(0, 1.0, -12))
	_camera.current = true
	for i in 30:
		var f := DotHumanoidFigure.new()
		add_child(f)
		f.build(DotHumanoidLook.stock(i * 31 + 7), 1.8)
		var ring := 6.0 + float(i % 5) * 6.0
		var angle := float(i) * 0.6
		f.position = Vector3(sin(angle) * ring * 0.6, 0, -ring)
		f.set_hold(DotHumanoidFigure.Hold.GUN)
		_people.append(f)
	_run()


func _measure(label: String, frames: int) -> String:
	var script_us := 0
	var draw := 0.0
	var prims := 0.0
	var worst := 0
	var start := Time.get_ticks_usec()
	var last := start
	for i in frames:
		var t0 := Time.get_ticks_usec()
		for f in _people:
			if is_instance_valid(f) and f.visible:
				f.animate(5.0, 1.0 / 60.0)
		script_us += Time.get_ticks_usec() - t0
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		worst = maxi(worst, now - last)
		last = now
		draw += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var total_ms := float(Time.get_ticks_usec() - start) / 1000.0 / frames
	var line := "BENCH %s: %.1f ms a frame (worst %.1f), %.1f us script per person, %.0f draw calls, %.0f primitives, %s" % [
		label, total_ms, worst / 1000.0, float(script_us) / frames / _people.size(), draw / frames, prims / frames,
		RenderingServer.get_video_adapter_name()]
	print(line)
	return line


func _run() -> void:
	for i in 60:
		await get_tree().process_frame
	var a := await _measure("30 people", 300)
	# Four of the nearest fall as skeletal ragdolls (the zombie-zone horde case), and stay down.
	var reactions := DotPlayerDeathReactions.stock()
	for i in 4:
		var death := DotPlayerDeath.new()
		death.reaction = &"limp"
		death.roll_seed = 99 + i
		death.direction = Vector3(1, 0, 0)
		death.damage = 100.0
		var rules := DotPlayerRagdollRules.new()
		rules.collision_mask = 1
		var _doll := DotPlayerRagdoll.build(_people[i], self, rules, reactions.find(&"limp"), death)
	var b := await _measure("30 people, 4 ragdolls falling", 300)
	DisplayServer.window_set_title("DONE")
	print("BENCH DONE")
