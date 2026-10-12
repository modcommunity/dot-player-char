extends SceneTree

## Renders contact sheets of the people: every clip of the family set at six moments, per body,
## and one sheet of looks (stock and site avatars). The check no assertion makes.
##
## [codeblock]
## xvfb-run -a godot --path . --script tools/people_sheet.gd -- [--out=DIR] [--bodies=matt,lis] [--clips=walk,run] [--looks] [--ragdoll]
## [/codeblock]
##
## xvfb-run, not --headless: the headless display renders nothing and saves a blank frame.
## Add `--rendering-method gl_compatibility` to see what a browser sees.

const CELL := Vector2i(256, 320)
const MOMENTS := 6

var _out := "res://screenshots/people"
var _bodies: Array = DotHumanoidLook.BODIES.duplicate()
var _clips: Array = DotHumanoidClips.ALL.duplicate()
var _looks := false
var _ragdoll := false
var _root: Node3D
var _camera: Camera3D
var _sub: SubViewport


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--bodies="):
			_bodies = Array(arg.trim_prefix("--bodies=").split(","))
		elif arg.begins_with("--clips="):
			_clips = Array(arg.trim_prefix("--clips=").split(","))
		elif arg == "--looks":
			_looks = true
		elif arg == "--ragdoll":
			_ragdoll = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	_run.call_deferred()


func _stage() -> void:
	_sub = SubViewport.new()
	_sub.size = CELL
	_sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sub.own_world_3d = true
	root.add_child(_sub)
	_root = Node3D.new()
	_sub.add_child(_root)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("9aa3ad")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.75, 0.8)
	env.environment.ambient_light_energy = 0.6
	_root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	_root.add_child(sun)
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	floor.mesh = plane
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color("6f7a68")
	floor.material_override = fm
	_root.add_child(floor)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	shape.shape = box
	shape.position = Vector3(0, -0.5, 0)
	body.add_child(shape)
	_root.add_child(body)
	_camera = Camera3D.new()
	_camera.fov = 40
	_root.add_child(_camera)


func _frame() -> Image:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	return _sub.get_texture().get_image()


func _label(img: Image, text: String) -> void:
	# No font in a SceneTree script without a theme; a coloured strip with the index is enough,
	# the sheet's file name and row order say which clip.
	pass


func _run() -> void:
	_stage()
	if _looks:
		await _sheet_looks()
	elif _ragdoll:
		await _sheet_ragdoll()
	else:
		for body in _bodies:
			await _sheet_body(StringName(body))
	quit()


func _figure(look: DotHumanoidLook) -> DotHumanoidFigure:
	var f := DotHumanoidFigure.new()
	_root.add_child(f)
	f.build(look, 1.8)
	return f


## One row per clip, MOMENTS columns across its length, side view (three-quarter).
func _sheet_body(body: StringName) -> void:
	var look := DotHumanoidLook.stock(7)
	look.body = body
	var f := _figure(look)
	_camera.position = Vector3(2.6, 1.3, -2.6)
	_camera.look_at(Vector3(0, 0.9, 0))
	var sheet := Image.create(CELL.x * MOMENTS, CELL.y * _clips.size(), false, Image.FORMAT_RGBA8)
	var anim := f.body_node().find_child("AnimationPlayer", true, false) as AnimationPlayer
	for row in _clips.size():
		var clip := StringName(_clips[row])
		if not anim.has_animation(clip):
			print("MISSING clip ", clip, " on ", body)
			continue
		var length := maxf(anim.get_animation(clip).length, 0.05)
		anim.play(clip)
		anim.speed_scale = 1.0
		for col in MOMENTS:
			var t := length * float(col) / float(MOMENTS - 1) if MOMENTS > 1 else 0.0
			anim.seek(minf(t, length - 0.001), true)
			var img := await _frame()
			img.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i(col * CELL.x, row * CELL.y))
	var path := "%s/clips_%s.png" % [_out, body]
	sheet.save_png(ProjectSettings.globalize_path(path))
	print("SHEET ", path, " rows ", " ".join(_clips))
	f.queue_free()
	await process_frame


## Stock looks and site avatars side by side, each body.
func _sheet_looks() -> void:
	var looks: Array[DotHumanoidLook] = []
	for seed in range(8):
		looks.append(DotHumanoidLook.stock(seed * 7919 + 13))
	for letter in ["a", "b", "d", "f", "i", "l", "n", "o"]:
		var doc := _SiteDoc.new()
		doc.parts = {&"face": "face.skin-%s" % letter, &"top": "top.skin-%s" % letter, &"legs": "legs.skin-%s" % letter}
		looks.append(DotHumanoidLook.from_site(doc))
	var cols := 8
	var rows := ceili(looks.size() / float(cols))
	var sheet := Image.create(CELL.x * cols, CELL.y * rows, false, Image.FORMAT_RGBA8)
	_camera.position = Vector3(0, 1.2, -3.4)
	_camera.look_at(Vector3(0, 0.9, 0))
	for i in looks.size():
		var f := _figure(looks[i])
		f.rotation.y = deg_to_rad(20)
		f.animate(0.0, 0.3)
		var img := await _frame()
		img.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i((i % cols) * CELL.x, (i / cols) * CELL.y))
		f.free()
	var path := "%s/looks.png" % _out
	sheet.save_png(ProjectSettings.globalize_path(path))
	print("SHEET ", path, " materials ", DotHumanoidFigure.material_count())


## A skinned body falling as a ragdoll with each stock reaction, at the moments docs/ragdolls.md
## names.
func _sheet_ragdoll() -> void:
	var moments := [0.0, 0.1, 0.2, 0.35, 0.5, 0.75, 1.0, 1.5, 2.5, 4.0]
	var reactions := DotPlayerDeathReactions.stock()
	var ids: Array[StringName] = [&"limp", &"headshot_launch", &"power_launch", &"face_plant", &"crumple"]
	var sheet := Image.create(CELL.x * moments.size(), CELL.y * ids.size(), false, Image.FORMAT_RGBA8)
	_camera.position = Vector3(4.2, 2.0, -4.2)
	_camera.look_at(Vector3(0.6, 0.5, 0))
	for row in ids.size():
		var f := _figure(DotHumanoidLook.stock(row + 3))
		f.animate(2.5, 0.4)
		var death := DotPlayerDeath.new()
		death.reaction = ids[row]
		death.roll_seed = 1234 + row
		death.direction = Vector3(1, 0, 0)
		death.damage = 120.0
		death.headshot = ids[row] == &"headshot_launch"
		var rules := DotPlayerRagdollRules.new()
		rules.collision_mask = 1
		var doll := DotPlayerRagdoll.build(f, _root, rules, reactions.find(ids[row]), death)
		var t := 0.0
		for col in moments.size():
			var target: float = moments[col]
			while t < target - 0.0001:
				var step := minf(1.0 / 60.0, target - t)
				await physics_frame
				t += 1.0 / 60.0
			if doll != null and is_instance_valid(doll):
				# Follows the body, so a launch is seen landing.
				var c := doll.centre()
				_camera.position = Vector3(c.x + 3.4, 1.8, c.z - 3.4)
				_camera.look_at(Vector3(c.x, 0.4, c.z))
			var img := await _frame()
			img.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i(col * CELL.x, row * CELL.y))
		print("RAGDOLL ", ids[row], " ", doll.describe() if doll != null else "none")
		if doll != null:
			doll.queue_free()
		f.queue_free()
		await process_frame
	var path := "%s/ragdoll.png" % _out
	sheet.save_png(ProjectSettings.globalize_path(path))
	print("SHEET ", path)


## A stand-in for the site's avatar document: `schema_id` and `part_in`.
class _SiteDoc:
	extends RefCounted
	var schema_id: StringName = &"builtin"
	var parts: Dictionary = {}

	func part_in(slot: StringName) -> StringName:
		return StringName(str(parts.get(slot, "")))
