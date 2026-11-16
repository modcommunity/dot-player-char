extends Node3D

## 64 avatars of one prepared model (tools/avatar_prep) in a ring, drawn windowed on a real GPU: frame time,
## draw calls and primitives over 300 frames per scenario as `BENCH` lines, then `BENCH DONE`.
## Args after `--`: `--model <name>` (files `res://bench_assets/<name>_lod0.glb` ... lod2; `<name>_source.glb`
## is the untouched download), `--count <n>` (default 64). The assets are private, so bench_assets/ is
## untracked; copy the prep output there before running (docs/avatar-prep.md).
## Poses are procedural: a few bones rotate each update, which costs what an AnimationPlayer
## writing the same bones would. The distance plan updates LOD0 every frame, LOD1 every 3rd, LOD2 every 6th.

const FRAMES := 300
const UPDATE_EVERY := {0: 1, 1: 3, 2: 6}

var _model: String = "military"
var _count: int = 64
var _people: Array[Node3D] = []
var _skeletons: Array[Skeleton3D] = []
var _lods: Array[int] = []
var _tick: int = 0


func _arg(name: String, fallback: String) -> String:
	var args := OS.get_cmdline_user_args()
	var i := args.find(name)
	if i >= 0 and i + 1 < args.size():
		return args[i + 1]
	return fallback


func _ready() -> void:
	_model = _arg("--model", "military")
	_count = int(_arg("--count", "64"))
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
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(160, 160)
	floor_mesh.mesh = plane
	add_child(floor_mesh)
	var cam := Camera3D.new()
	cam.fov = 70
	add_child(cam)
	cam.position = Vector3(0, 1.7, 6)
	cam.look_at(Vector3(0, 1.0, -14))
	cam.current = true
	_run()


func _load(file: String) -> Node3D:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file("res://bench_assets/" + file, state)
	if err != OK:
		push_error("cannot load " + file)
		return null
	return doc.generate_scene(state) as Node3D


func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n as Skeleton3D
	for c in n.get_children():
		var s := _find_skeleton(c)
		if s != null:
			return s
	return null


func _clear() -> void:
	for p in _people:
		p.queue_free()
	_people.clear()
	_skeletons.clear()
	_lods.clear()


## `plan` gives the LOD of person i; the glb for it is loaded once and duplicated (shared mesh, material, atlas).
func _spawn(files: Array[String], plan: Callable) -> void:
	_clear()
	var protos: Array[Node3D] = []
	for f in files:
		protos.append(_load(f))
	for i in _count:
		var lod: int = plan.call(i)
		var proto: Node3D = protos[mini(lod, protos.size() - 1)]
		var p := proto.duplicate() as Node3D
		add_child(p)
		var ring := 4.0 + float(i % 8) * 4.0
		var angle := float(i) * 0.7
		p.position = Vector3(sin(angle) * ring * 0.7, 0, -ring)
		p.rotation.y = angle
		_people.append(p)
		_skeletons.append(_find_skeleton(p))
		_lods.append(lod)
	for pr in protos:
		pr.free()


func _pose(i: int, t: float) -> void:
	var sk := _skeletons[i]
	if sk == null:
		return
	for bone_name in ["LeftUpLeg", "RightUpLeg", "LeftArm", "RightArm", "Spine1", "Head"]:
		var b := sk.find_bone(bone_name)
		if b >= 0:
			var swing := sin(t * 6.0 + float(i) + float(b)) * 0.4
			sk.set_bone_pose_rotation(b, Quaternion(Vector3.RIGHT, swing))


func _measure(label: String) -> void:
	var draw := 0.0
	var prims := 0.0
	var worst := 0
	var script_us := 0
	var start := Time.get_ticks_usec()
	var last := start
	for f in FRAMES:
		var t0 := Time.get_ticks_usec()
		_tick += 1
		for i in _people.size():
			if _tick % int(UPDATE_EVERY[_lods[i]]) == i % int(UPDATE_EVERY[_lods[i]]):
				_pose(i, float(_tick) / 60.0)
		script_us += Time.get_ticks_usec() - t0
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		worst = maxi(worst, now - last)
		last = now
		draw += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var ms := float(Time.get_ticks_usec() - start) / 1000.0 / FRAMES
	print("BENCH %s %s: %.2f ms a frame (worst %.1f), %.0f us script a frame, %.0f draw calls, %.0f primitives, %s" % [
		_model, label, ms, worst / 1000.0, float(script_us) / FRAMES, draw / FRAMES, prims / FRAMES,
		RenderingServer.get_video_adapter_name()])


func _run() -> void:
	for i in 30:
		await get_tree().process_frame
	var m := _model
	_spawn([m + "_lod0.glb"], func(_i: int) -> int: return 0)
	await get_tree().process_frame
	await _measure("%d at LOD0" % _count)
	_spawn([m + "_lod0.glb", m + "_lod1.glb", m + "_lod2.glb"], func(i: int) -> int: return 0 if i < _count / 8 else (1 if i < _count / 2 else 2))
	await get_tree().process_frame
	await _measure("%d on the distance plan (1/8 LOD0, 3/8 LOD1, 1/2 LOD2)" % _count)
	_spawn([m + "_lod1.glb"], func(_i: int) -> int: return 0)
	await get_tree().process_frame
	await _measure("%d at LOD1 only" % _count)
	if FileAccess.file_exists("res://bench_assets/" + m + "_source.glb"):
		_spawn([m + "_source.glb"], func(_i: int) -> int: return 0)
		await get_tree().process_frame
		await _measure("%d untouched source model" % _count)
	print("BENCH DONE")
	get_tree().quit()
