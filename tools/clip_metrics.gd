extends SceneTree

## Foot skate and pop/jerk per stance, headless; FLAG marks lines over the limits.
## godot --headless --fixed-fps 60 --path . --script res://tools/clip_metrics.gd
## Skate: speed ratio of a planted foot against the ground. Pop: biggest one-frame head step. Jerk: peak third difference of head height.
## Sole: the lowest foot's sole against the floor the figure stands on (absolute metres; its drawn ankle, the end of the leg as [DotClipMetrics] finds it, less the ankle's rest
## height over the mesh bottom), its minimum and the share of frames under -1 cm. `-- --height 1.372 --body sam` draws a shorter body, or another one.

const SCENARIOS := [
	[&"idle", 0.0, 0.0, false],
	[&"walk", 2.0, 0.0, false],
	[&"run", 5.0, 0.0, false],
	[&"walk_arena", 4.05, 0.0, false],
	[&"sprint", 9.0, 0.0, false],
	[&"crouch", 0.0, 1.0, false],
	[&"crouch_walk", 1.4, 1.0, false],
	[&"slide", 6.0, 1.0, true],
	# A game at a short body's speeds (Fatal Contact: 1.372 m, walk 2.58, run 5.74, sprint 7.17, crouch 2.58).
	[&"walk_2.6", 2.58, 0.0, false],
	[&"walk_4.6", 4.64, 0.0, false],
	[&"run_5.7", 5.74, 0.0, false],
	[&"sprint_7.2", 7.17, 0.0, false],
	[&"crouch_walk_2.6", 2.58, 1.0, false],
	# Moving off the facing (degrees): the legs turn toward the motion and the hips turn back.
	[&"strafe45_2.6", 2.58, 0.0, false, 45.0],
	[&"strafe45_5.7", 5.74, 0.0, false, 45.0],
	[&"strafe90_5.7", 5.74, 0.0, false, 90.0],
	[&"strafe135_4.6", 4.64, 0.0, false, 135.0],
	[&"crouch_strafe90_2.6", 2.58, 1.0, false, 90.0],
	# Changing gait: the speed swaps to the sixth entry every half second and the motion turns by the seventh (degrees/s).
	[&"walk_sprint_swap", 2.58, 0.0, false, 0.0, 7.17, 0.0],
	[&"run_sprint_swap", 4.64, 0.0, false, 0.0, 5.74, 0.0],
	[&"sprint_turning", 5.74, 0.0, false, 0.0, 5.74, 120.0],
	[&"walk_turning", 2.58, 0.0, false, 0.0, 4.64, 200.0],
	[&"stop_start", 0.0, 0.0, false, 0.0, 5.74, 90.0],
]
## Lowest a sole may go under the floor (metres) before a frame counts as sunk, and the share of sunk frames allowed.
const SUNK := -0.01
const MAX_SUNK_SHARE := 0.005
const MAX_SKATE := 0.35
## A gait's head moves with every step, so a moving scenario gets wider limits than a held pose.
const MAX_POP := 0.02
const MAX_JERK := 1000.0
const MAX_POP_MOVING := 0.2
const MAX_JERK_MOVING := 60000.0
## Most any bone may turn between two samples 1/15 s apart (degrees): the filmstrip's bone_pop gate.
const MAX_BONE_STEP := 135.0
const BONE_STRIDE := 4
const DT := 1.0 / 60.0

var _failed := false
var _fig: DotHumanoidFigure
var _i := 0
var _frame := 0
var _heads: Array[float] = []
var _head_pos: Array[Vector3] = []
var _foot_pos: Array = [[], []]
var _rot_hist: Array = []
var _bone_step := 0.0
var _height := 1.8
var _body := &""
## Per foot: [bone, the leg that draws it (an IK foot control is not drawn) or null, ankle rest height over the mesh bottom].
var _feet: Array = []
var _soles: Array[float] = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for k in range(args.size() - 1):
		if args[k] == "--height":
			_height = float(args[k + 1])
		elif args[k] == "--body":
			_body = StringName(args[k + 1])
	_fig = DotHumanoidFigure.new()
	root.add_child(_fig)
	var look := DotHumanoidLook.stock(3)
	if _body != &"":
		look.body = _body
	_fig.build(look, _height)
	_fig.set_hold(DotHumanoidFigure.Hold.GUN)
	print("CLIPMETRICS height ", _height, " body ", look.body)


## Each foot's ankle rest height over the mesh bottom, measured once the figure is in the tree.
func _measure_feet() -> void:
	var sk := _fig.skeleton()
	var mesh := _fig.mesh()
	var bottom := (mesh.global_transform * mesh.mesh.get_aabb()).position.y
	for name: String in ["Foot.L", "Foot.R"]:
		var b := sk.find_bone(name)
		_feet.append([b, DotClipMetrics._leg_anchor(sk, b), (sk.global_transform * sk.get_bone_global_rest(b).origin).y - bottom])


## One sample per rendered frame: the skeleton only poses when the tree has processed it.
func _process(delta: float) -> bool:
	if _feet.is_empty():
		_measure_feet()
	var s: Array = SCENARIOS[_i]
	var speed := float(s[1])
	var off := deg_to_rad(float(s[4])) if s.size() > 4 else 0.0
	if s.size() > 6:
		speed = float(s[5]) if (_frame / 30) % 2 == 1 else speed
		off += deg_to_rad(float(s[6])) * _frame * DT
	_fig.set_motion({"on_floor": true, "alive": true, "crouched": float(s[2]) > 0.5, "crouch": float(s[2]),
		"sliding": bool(s[3]), "velocity": Vector3(sin(off), 0, -cos(off)) * speed, "aim": 0.0})
	_fig.animate(speed, delta)
	_frame += 1
	var sk := _fig.skeleton()
	if _frame > 60:
		_sample_bone_rate(sk)
		_head_pos.append(sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Head")).origin)
		_heads.append(_head_pos[-1].y)
		for f in 2:
			_foot_pos[f].append(sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Foot.L" if f == 0 else "Foot.R")).origin)
		var low := INF
		for foot: Array in _feet:
			var at := sk.get_bone_global_pose(foot[0]).origin
			if foot[1] != null:
				at = sk.get_bone_global_pose(foot[1][0]) * (foot[1][1] as Vector3)
			low = minf(low, (sk.global_transform * at).y - float(foot[2]))
		_soles.append(low - _fig.global_position.y)
	if _frame < 240:
		return false
	_report(s)
	_frame = 0
	_heads.clear()
	_head_pos.clear()
	_foot_pos = [[], []]
	_rot_hist.clear()
	_soles.clear()
	_bone_step = 0.0
	_i += 1
	if _i >= SCENARIOS.size():
		print("CLIPMETRICS ", "flagged" if _failed else "ok")
		quit(0)
	return false


## Tracks the biggest turn of any bone over 1/15 s.
func _sample_bone_rate(sk: Skeleton3D) -> void:
	var cur: Array[Quaternion] = []
	for b in sk.get_bone_count():
		cur.append(sk.get_bone_pose_rotation(b))
	_rot_hist.append(cur)
	if _rot_hist.size() > BONE_STRIDE:
		var old: Array = _rot_hist.pop_front()
		for b in cur.size():
			_bone_step = maxf(_bone_step, rad_to_deg((old[b] as Quaternion).angle_to(cur[b])))


func _report(s: Array) -> void:
	var speed := float(s[1])
	var head_pos := _head_pos
	var heads := _heads
	var foot_pos := _foot_pos
	var pop := 0.0
	for i in range(1, head_pos.size()):
		pop = maxf(pop, head_pos[i].distance_to(head_pos[i - 1]))
	var jerk := 0.0
	for i in range(3, heads.size()):
		jerk = maxf(jerk, absf(heads[i] - 3.0 * heads[i - 1] + 3.0 * heads[i - 2] - heads[i - 3]) / pow(DT, 3))
	var skate := 0.0
	if speed > 0.5 and s[0] != &"slide" and s.size() < 5:
		var err := 0.0
		var n := 0
		for f in 2:
			var low := 1e9
			for p: Vector3 in foot_pos[f]:
				low = minf(low, p.y)
			for i in range(1, foot_pos[f].size()):
				var a: Vector3 = foot_pos[f][i]
				var b: Vector3 = foot_pos[f][i - 1]
				if a.y < low + 0.04 and b.y < low + 0.04:
					err += absf(Vector2(a.x - b.x, a.z - b.z).length() / DT - speed)
					n += 1
		skate = err / maxf(n, 1) / speed
	var moving: bool = (speed > 0.5 or s.size() > 6) and s[0] != &"slide"
	var sole_min := INF
	var sunk := 0
	for y in _soles:
		sole_min = minf(sole_min, y)
		if y < SUNK:
			sunk += 1
	var sunk_share := float(sunk) / maxf(_soles.size(), 1)
	var flag := sunk_share > MAX_SUNK_SHARE or skate > MAX_SKATE or pop > (MAX_POP_MOVING if moving else MAX_POP) or jerk > (MAX_JERK_MOVING if moving else MAX_JERK) or _bone_step > MAX_BONE_STEP
	_failed = _failed or flag
	print("CLIPMETRICS ", s[0], " skate=", snappedf(skate, 0.01), " pop=", snappedf(pop, 0.001), " jerk=", roundi(jerk), " bone_deg_15hz=", roundi(_bone_step),
		" sole_min=", snappedf(sole_min, 0.001), " sunk=", snappedf(100.0 * sunk_share, 0.1), "%", "  FLAG" if flag else "")
