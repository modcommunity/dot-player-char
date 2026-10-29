extends SceneTree

## Made clip (left) against the library clip (right), same camera, same share of the cycle, plus the
## numbers: how steady the planted foot's ground speed is, and how high it floats or sinks.
##   xvfb-run -a godot --path . --script tools/survivor_compare.gd -- [--out=res://screenshots]

const CELL := Vector2i(420, 300)
const MOMENTS := 6
## made clip, library clip
const PAIRS := [
	["run", "ual_sprint"], ["run", "ual_jog"], ["walk", "ual_jog"], ["crouch_walk", "ual_crouch_walk"], ["walk", "crouch_walk"],
	["hit", "ual_hit_chest"], ["hit", "ual_hit_head"], ["death", "ual_knockback"],
]

var _sub: SubViewport
var _out := "res://screenshots"


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	_run.call_deferred()


func _run() -> void:
	_sub = SubViewport.new()
	_sub.size = CELL
	_sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sub.own_world_3d = true
	root.add_child(_sub)
	var world := Node3D.new()
	_sub.add_child(world)
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
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	floor.mesh = plane
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color("6f7a68")
	floor.material_override = fm
	world.add_child(floor)
	var cam := Camera3D.new()
	cam.fov = 22
	world.add_child(cam)
	cam.position = Vector3(8.5, 1.0, 0)
	cam.look_at(Vector3(0, 0.95, 0))
	# Camera on +X looking -X: screen right is -Z, so the made figure at +Z is on the left.
	var look := DotHumanoidLook.stock(7)
	look.body = DotHumanoidFigure.CLIP_BODY
	var figs: Array[DotHumanoidFigure] = []
	for z in [1.0, -1.0]:
		var f := DotHumanoidFigure.new()
		world.add_child(f)
		f.build(look, 1.8)
		f.position = Vector3(0, 0, z)
		figs.append(f)
	var sheet := Image.create(CELL.x * MOMENTS, CELL.y * PAIRS.size(), false, Image.FORMAT_RGBA8)
	for row in PAIRS.size():
		var names: Array = PAIRS[row]
		var lens := []
		for k in 2:
			var anim := figs[k].body_node().find_child("AnimationPlayer", true, false) as AnimationPlayer
			if not anim.has_animation(names[k]):
				print("MISSING ", names[k])
				continue
			lens.append(anim.get_animation(names[k]).length)
			anim.play(names[k])
			anim.speed_scale = 0.0
			print("METRICS %s %s" % [names[k], _metrics(figs[k], anim, names[k])])
		for col in MOMENTS:
			var share := float(col) / float(MOMENTS)
			for k in 2:
				var anim := figs[k].body_node().find_child("AnimationPlayer", true, false) as AnimationPlayer
				anim.seek(minf(share * lens[k], lens[k] - 0.001), true)
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			var img := _sub.get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i(col * CELL.x, row * CELL.y))
		print("ROW %d %s | %s lengths %s" % [row, names[0], names[1], lens])
	var path := ProjectSettings.globalize_path("%s/survivor_compare.png" % _out)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	print("SHEET ", path, " ", sheet.save_png(path))
	quit()


## Planted foot (the lower one) in the figure's frame over the cycle: ground speed it implies,
## its spread (the slide a constant-speed walker would show), and the foot height range.
func _metrics(f: DotHumanoidFigure, anim: AnimationPlayer, clip: StringName) -> String:
	var sk := f.skeleton()
	var feet: Array[int] = [sk.find_bone("Foot.L"), sk.find_bone("Foot.R")]
	var length: float = anim.get_animation(clip).length
	var steps := 60
	var dt := length / steps
	var prev: Array = []
	var speeds: Array[float] = []
	var lo := INF
	var hi := -INF
	var top := -INF
	for i in steps + 1:
		anim.seek(minf(dt * i, length - 0.0005), true)
		var p: Array = []
		for b in feet:
			p.append((f.global_transform.affine_inverse() * sk.global_transform * sk.get_bone_global_pose(b)).origin)
		var k := 0 if p[0].y < p[1].y else 1
		top = maxf(top, maxf(p[0].y, p[1].y))
		if not prev.is_empty() and p[k].y < minf(p[0].y, p[1].y) + 0.001 and prev[k].y < p[k].y + 0.03:
			speeds.append(-(p[k].z - prev[k].z) / dt)
		lo = minf(lo, minf(p[0].y, p[1].y))
		hi = maxf(hi, minf(p[0].y, p[1].y))
		prev = p
	var mean := 0.0
	for s in speeds:
		mean += s
	mean /= maxf(speeds.size(), 1)
	var dev := 0.0
	for s in speeds:
		dev += (s - mean) * (s - mean)
	dev = sqrt(dev / maxf(speeds.size(), 1))
	return "len %.2fs planted speed %.2f m/s spread %.2f lowest foot y %.3f..%.3f (floats %.3f) highest foot %.3f" % [length, mean, dev, lo, hi, hi - lo, top]
