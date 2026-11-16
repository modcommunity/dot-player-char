extends SceneTree

## The downed first-person arms as the player sees them: crawl, six moments, looking 15 and 80 degrees down.
##   xvfb-run -a godot --path . --script tools/view_arms_sheet.gd -- [--out=res://screenshots] [--off=x,y,z (the eye in the figure's frame)]
##   --look=body,skin,hair,top,bottom (hex colours; solid colours show unclaimed swatches); a game's own body needs --register=id:path before it. --held (with --left to keep the idle left arm): held-weapon mode: rows one-hand / two-hand / side / looking 60 down, columns idle then walking.
##   --hands: the real hands' grips, a row per weapon kind (--kinds=rifle,pistol,... to pick), columns the player's view, then close-ups
##   from the right, the left and below; --mitts draws the old mitts instead, for a before/after.

const CELL := Vector2i(400, 260)
const MOMENTS := 6

var _out := "res://screenshots"
var _off := Vector3.INF
var _side := false
var _held := false
var _left := false
var _hands := false
var _mitts := false
var _kinds: PackedStringArray = ["rifle", "pistol", "shotgun", "launcher", "sniper", "grenade", "knife", "knife_throw"]
var _look: DotHumanoidLook = null


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--register="):
			for pair in arg.trim_prefix("--register=").split(","):
				var _ok := DotHumanoidAssets.register_body(StringName(pair.get_slice(":", 0)), pair.substr(pair.find(":") + 1))
		elif arg == "--held":
			_held = true
		elif arg == "--left":
			_left = true
		elif arg == "--hands":
			_hands = true
		elif arg == "--mitts":
			_mitts = true
		elif arg.begins_with("--kinds="):
			_kinds = arg.trim_prefix("--kinds=").split(",")
		elif arg.begins_with("--look="):
			var f := arg.trim_prefix("--look=").split(",")
			_look = DotHumanoidLook.make(StringName(f[0]), Color(f[1]), Color(f[2]), Color(f[3]), Color(f[4]))
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
	if _hands:
		await _hands_sheet(sub, world, cam)
		return
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
	arms.build(_look if _look != null else DotHumanoidLook.stock(7), 1.8)
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
	arms.build(_look if _look != null else DotHumanoidLook.stock(7), 1.8)
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


## A stand-in weapon for [param kind] under [param parent]: its body and where the hands go (grip, support or INF).
func _stand_in(parent: Node3D, kind: String) -> Array:
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color("2a2a2a")
	var parts: Array = []  # [size, position]
	var grip := Vector3(0.0, -0.075, 0.1)
	var support := Vector3(0.0, -0.035, -0.12)
	match kind:
		"pistol":
			parts = [[Vector3(0.035, 0.035, 0.2), Vector3(0, 0, -0.04)], [Vector3(0.03, 0.11, 0.045), Vector3(0, -0.06, 0.04)]]
			grip = Vector3(0.0, -0.07, 0.045)
			support = Vector3.INF
		"grenade":
			var ball := MeshInstance3D.new()
			var sp := SphereMesh.new()
			sp.radius = 0.035
			sp.height = 0.075
			ball.mesh = sp
			ball.material_override = wm
			parent.add_child(ball)
			return [Vector3.ZERO, Vector3.INF]
		"knife", "knife_throw":
			parts = [[Vector3(0.02, 0.11, 0.028), Vector3(0, 0, 0)], [Vector3(0.006, 0.16, 0.03), Vector3(0, 0.135, 0.004)]]
			grip = Vector3(0.0, 0.0, 0.0)
			support = Vector3.INF
		"launcher":
			parts = [[Vector3(0.11, 0.11, 0.8), Vector3(0, 0.05, -0.15)], [Vector3(0.03, 0.1, 0.04), Vector3(0, -0.06, 0.08)], [Vector3(0.03, 0.1, 0.04), Vector3(0, -0.06, -0.2)]]
			grip = Vector3(0.0, -0.08, 0.08)
			support = Vector3(0.0, -0.08, -0.2)
		"sniper":
			parts = [[Vector3(0.05, 0.07, 0.9), Vector3(0, 0, -0.2)], [Vector3(0.03, 0.09, 0.045), Vector3(0, -0.06, 0.1)]]
			support = Vector3(0.0, -0.04, -0.24)
		"shotgun":
			parts = [[Vector3(0.045, 0.06, 0.7), Vector3(0, 0, -0.15)], [Vector3(0.03, 0.09, 0.045), Vector3(0, -0.06, 0.1)], [Vector3(0.05, 0.05, 0.14), Vector3(0, -0.04, -0.16)]]
			support = Vector3(0.0, -0.045, -0.16)
		_:
			parts = [[Vector3(0.05, 0.08, 0.6), Vector3(0, 0, -0.1)], [Vector3(0.03, 0.09, 0.045), Vector3(0, -0.06, 0.1)], [Vector3(0.045, 0.045, 0.16), Vector3(0, -0.02, -0.13)]]
	for part: Array in parts:
		var m := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = part[0]
		m.mesh = box
		m.position = part[1]
		m.material_override = wm
		parent.add_child(m)
	return [grip, support]


func _hands_sheet(sub: SubViewport, world: Node3D, cam: Camera3D) -> void:
	var pivot := Node3D.new()
	world.add_child(pivot)
	var arms := DotPlayerViewArms.new()
	arms.real_hands = not _mitts
	pivot.add_child(arms)
	cam.get_parent().remove_child(cam)
	pivot.add_child(cam)
	cam.rotation_degrees.x = -5.0
	arms.build(_look if _look != null else DotHumanoidLook.stock(7), 1.8)
	var close := Camera3D.new()
	close.fov = 40
	pivot.add_child(close)
	var sheet := Image.create(CELL.x * 4, CELL.y * _kinds.size(), false, Image.FORMAT_RGBA8)
	for row in _kinds.size():
		var kind := _kinds[row]
		var weapon := Node3D.new()
		cam.add_child(weapon)
		var held_at := Vector3(0.08, -0.2, -0.4)
		if kind in ["grenade", "knife", "knife_throw"]:
			held_at = Vector3(0.14, -0.2, -0.38)
		if kind in ["knife", "knife_throw"]:
			weapon.rotation_degrees.x = -70.0 if kind == "knife" else 20.0
		if kind == "pistol":
			held_at = Vector3(0.0, -0.17, -0.42)
		weapon.position = held_at
		var points := _stand_in(weapon, kind)
		var grip := DotViewGrip.one_hand(weapon, points[0]) if not (points[1] as Vector3).is_finite() else DotViewGrip.two_hand(weapon, points[0], points[1])
		grip.kind = StringName("knife" if kind == "knife_throw" else kind)
		if kind in ["knife", "knife_throw"]:
			# The blade runs along the weapon's +Y; its forward is where the edge points.
			grip.forward = Vector3(0, 1, 0)
			grip.up = Vector3(0, 0, 1)
		arms.throw_grip = 1.0 if kind == "knife_throw" else 0.0
		arms.set_held(grip)
		for _i in 12:
			arms.tick(0.0, 1.0 / 30.0)
			weapon.position = held_at + arms.sway()
			await process_frame
		var focus := weapon.global_transform * (grip.grip if not grip.is_two_hand() else (grip.grip + grip.support) * 0.5)
		var views := [Vector3.ZERO, Vector3(0.45, 0.05, 0.0), Vector3(-0.45, 0.05, 0.0), Vector3(0.1, -0.4, 0.15)]
		for col in 4:
			cam.current = col == 0
			close.current = col != 0
			if col != 0:
				close.global_position = focus + pivot.global_transform.basis * views[col]
				close.look_at(focus, pivot.global_transform.basis.y if col != 3 else pivot.global_transform.basis * Vector3.FORWARD)
			arms.tick(0.0, 1.0 / 30.0)
			await process_frame
			await RenderingServer.frame_post_draw
			var img := sub.get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i(col * CELL.x, row * CELL.y))
		print("HANDS ", kind, " error=", snappedf(arms.hand_error(grip), 0.001), " ", arms.describe())
		cam.remove_child(weapon)
		weapon.queue_free()
	var path := ProjectSettings.globalize_path("%s/view_arms_hands%s.png" % [_out, "_mitts" if _mitts else ""])
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	print("SHEET ", path, " ", sheet.save_png(path))
	quit()
