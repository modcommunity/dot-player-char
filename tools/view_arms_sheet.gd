extends SceneTree

## The downed first-person arms as the player sees them: crawl, six moments, looking 15 and 80 degrees down, a camera at the eye.
##   xvfb-run -a godot --path . --script tools/view_arms_sheet.gd -- [--out=res://screenshots] [--off=x,y,z (the eye in the figure's frame)]

const CELL := Vector2i(400, 260)
const MOMENTS := 6

var _out := "res://screenshots"
var _off := Vector3.INF
var _side := false


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg == "--side":
			_side = true
		elif arg.begins_with("--off="):
			var p := arg.trim_prefix("--off=").split_floats(",")
			_off = Vector3(p[0], p[1], p[2])
	_run.call_deferred()


func _run() -> void:
	var sub := SubViewport.new()
	sub.size = CELL
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub.own_world_3d = true
	root.add_child(sub)
	var world := Node3D.new()
	sub.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("9aa3ad")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.75, 0.8)
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	world.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color("6f7a68")
	ground.material_override = gm
	ground.position.y = -0.9
	world.add_child(ground)
	var cam := Camera3D.new()
	cam.fov = 90
	cam.current = true
	cam.rotation_degrees.x = -15.0
	world.add_child(cam)
	var arms := DotPlayerViewArms.new()
	if _off.is_finite():
		arms.eye_from_head = _off
	if _side:
		world.add_child(arms)
		cam.position = Vector3(-1.6, 0.5, -0.9)
		cam.look_at(Vector3(0, 0.1, -0.5))
	else:
		world.add_child(arms)
	arms.build(DotHumanoidLook.stock(7), 1.8)
	arms.set_downed(true)
	arms.tick(1.0, 0.05)
	for _i in 4:
		arms.tick(1.0, 1.0 / 30.0)
		await process_frame
	var sheet := Image.create(CELL.x * MOMENTS, CELL.y * 2, false, Image.FORMAT_RGBA8)
	for row in 2:
		cam.rotation_degrees.x = -15.0 if row == 0 else -80.0
		arms.set_downed(true)
		for col in MOMENTS * 6:
			arms.tick(1.0, 1.0 / 30.0)
			if col % 6 != 5:
				continue
			await process_frame
			await RenderingServer.frame_post_draw
			var img := sub.get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i((col / 6) * CELL.x, row * CELL.y))
	var path := ProjectSettings.globalize_path("%s/view_arms.png" % _out)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	print("SHEET ", path, " ", sheet.save_png(path))
	quit()
