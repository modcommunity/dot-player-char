extends SceneTree

## One person through stand, run, crouch, crouch walk, slide, stand, for `--write-movie`, from the side.
##   xvfb-run -a godot --path . --resolution 960x540 --fixed-fps 30 --write-movie out.avi --script res://tools/stance_strip.gd
## Frames are cut with ffmpeg (tools/shot_stance.sh). Prints the hip height per phase.

const PHASES := [
	[&"stand", 1.0, 0.0, 0.0, false, false],
	[&"run", 1.2, 5.0, 0.0, false, false],
	[&"crouch", 1.4, 0.0, 1.0, false, false],
	[&"crouch_walk", 1.4, 1.4, 1.0, false, false],
	[&"slide", 1.4, 6.0, 1.0, true, false],
	[&"stand_up", 1.2, 0.0, 0.0, false, false],
]

var _fig: DotHumanoidFigure
var _t := 0.0
var _crouch := 0.0
var _last_head := Vector3.ZERO
var _worst_pop := 0.0


func _initialize() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.62, 0.7)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.8, 0.85)
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	root.add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20, 20)
	floor_mesh.mesh = plane
	root.add_child(floor_mesh)
	_fig = DotHumanoidFigure.new()
	root.add_child(_fig)
	_fig.build(DotHumanoidLook.stock(3), 1.8)
	_fig.set_hold(DotHumanoidFigure.Hold.GUN)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true
	cam.fov = 35.0
	cam.look_at_from_position(Vector3(4.2, 1.0, 0.0), Vector3(0, 0.85, 0))


func _process(delta: float) -> bool:
	_t += delta
	var at := _t
	for p: Array in PHASES:
		if at < float(p[1]):
			var target := float(p[3])
			_crouch = move_toward(_crouch, target, delta / 0.2)
			var v := Vector3(0, 0, -float(p[2]))
			_fig.set_motion({"on_floor": true, "alive": true, "crouched": _crouch > 0.5, "crouch": _crouch,
				"sliding": bool(p[4]), "velocity": v, "aim": 0.0})
			_fig.animate(float(p[2]), delta)
			var hip := _fig.skeleton().get_bone_global_pose(_fig.skeleton().find_bone("Hips")).origin.y if _fig.skeleton() != null else -1.0
			var head := _fig.skeleton().get_bone_global_pose(_fig.skeleton().find_bone("Head")).origin if _fig.skeleton() != null else Vector3.ZERO
			if _t > delta * 2.0:
				_worst_pop = maxf(_worst_pop, head.distance_to(_last_head))
			_last_head = head
			if int(_t * 30.0) % 10 == 0:
				print("STANCE %.2f %s clip=%s hip=%.3f" % [_t, p[0], _fig.clip, hip])
			return false
		at -= float(p[1])
	print("STANCE worst head step per frame %.3f m" % _worst_pop)
	quit(0)
	return false
