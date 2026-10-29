extends SceneTree

## The downed first-person arms as the player sees them: crawl, six moments, looking 15 and 80 degrees down, a camera at the eye.
##   xvfb-run -a godot --path . --script tools/view_arms_sheet.gd -- [--out=res://screenshots] [--off=x,y,z (the eye in the figure's frame)]
##   --left: with --held, keep the idle left arm in the one-hand row (the old look).
##   --held: the held-weapon mode instead, rows one-hand / two-hand / two-hand from the side / two-hand looking 60 down, columns idle then walking.

const CELL := Vector2i(400, 260)
const MOMENTS := 6

var _out := "res://screenshots"
var _off := Vector3.INF
var _side := false
var _held := false
var _left := false


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg == "--held":
			_held = true
		elif arg == "--left":
			_left = true
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
	if _held:
		await _held_sheet(sub, world, cam)
		return
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


func _held_sheet(sub: SubViewport, world: Node3D, cam: Camera3D) -> void:
	var pivot := Node3D.new()
	world.add_child(pivot)
	var arms := DotPlayerViewArms.new()
	pivot.add_child(arms)
	cam.get_parent().remove_child(cam)
	pivot.add_child(cam)
	var weapon := Node3D.new()
	cam.add_child(weapon)
	weapon.position = Vector3(0.08, -0.2, -0.4)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.06, 0.1, 0.5)
	mesh.mesh = box
	mesh.position = Vector3(0, 0.02, -0.1)
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color("222222")
	mesh.material_override = wm
	weapon.add_child(mesh)
	var fore := MeshInstance3D.new()
	var fb := BoxMesh.new()
	fb.size = Vector3(0.05, 0.05, 0.12)
	fore.mesh = fb
	fore.position = Vector3(-0.02, -0.04, -0.1)
	fore.material_override = wm
	weapon.add_child(fore)
	var marks := {}
	for n in ["grip", "support"]:
		var m := MeshInstance3D.new()
		var sp := SphereMesh.new()
		sp.radius = 0.012
		sp.height = 0.024
		m.mesh = sp
		var mm := StandardMaterial3D.new()
		mm.albedo_color = Color.RED if n == "grip" else Color.YELLOW
		mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.material_override = mm
		weapon.add_child(m)
		marks[n] = m
	var grip_pt := Vector3(0.0, -0.08, 0.1)
	var support_pt := Vector3(-0.03, -0.07, -0.1)
	marks["grip"].position = grip_pt
	marks["support"].position = support_pt
	arms.show_idle_left_arm = _left
	arms.build(DotHumanoidLook.stock(7), 1.8)
	var side_cam := Camera3D.new()
	side_cam.fov = 60
	pivot.add_child(side_cam)
	side_cam.position = Vector3(-1.4, -0.2, -0.3)
	side_cam.look_at(Vector3(0, -0.2, -0.3))
	var rows := 4
	var sheet := Image.create(CELL.x * 6, CELL.y * rows, false, Image.FORMAT_RGBA8)
	for row in rows:
		arms.set_held(DotViewGrip.one_hand(weapon, grip_pt) if row == 0 else DotViewGrip.two_hand(weapon, grip_pt, support_pt))
		cam.current = row != 2
		side_cam.current = row == 2
		cam.rotation_degrees.x = -60.0 if row == 3 else -5.0
		marks["support"].visible = row != 0
		for col in 6:
			var speed := 0.0 if col < 3 else 5.0
			for _i in 8:
				arms.tick(speed, 1.0 / 30.0)
				weapon.position = Vector3(0.08, -0.2, -0.4) + arms.sway()
				await process_frame
			arms.tick(speed, 1.0 / 30.0)
			await process_frame
			await RenderingServer.frame_post_draw
			var img := sub.get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i(col * CELL.x, row * CELL.y))
	var path := ProjectSettings.globalize_path("%s/view_arms_held.png" % _out)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	print("SHEET ", path, " ", sheet.save_png(path))
	quit()
