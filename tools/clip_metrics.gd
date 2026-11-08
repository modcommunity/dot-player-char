extends SceneTree

## Foot skate and pop/jerk per stance, headless; FLAG marks lines over the limits.
## godot --headless --fixed-fps 60 --path . --script res://tools/clip_metrics.gd
## Skate: speed ratio of a planted foot against the ground. Pop: biggest one-frame head step. Jerk: peak third difference of head height.

const SCENARIOS := [
	[&"idle", 0.0, 0.0, false],
	[&"walk", 2.0, 0.0, false],
	[&"run", 5.0, 0.0, false],
	[&"walk_arena", 4.05, 0.0, false],
	[&"sprint", 9.0, 0.0, false],
	[&"crouch", 0.0, 1.0, false],
	[&"crouch_walk", 1.4, 1.0, false],
	[&"slide", 6.0, 1.0, true],
]
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


func _initialize() -> void:
	_fig = DotHumanoidFigure.new()
	root.add_child(_fig)
	_fig.build(DotHumanoidLook.stock(3), 1.8)
	_fig.set_hold(DotHumanoidFigure.Hold.GUN)


## One sample per rendered frame: the skeleton only poses when the tree has processed it.
func _process(delta: float) -> bool:
	var s: Array = SCENARIOS[_i]
	var speed := float(s[1])
	_fig.set_motion({"on_floor": true, "alive": true, "crouched": float(s[2]) > 0.5, "crouch": float(s[2]),
		"sliding": bool(s[3]), "velocity": Vector3(0, 0, -speed), "aim": 0.0})
	_fig.animate(speed, delta)
	_frame += 1
	var sk := _fig.skeleton()
	if _frame > 60:
		_sample_bone_rate(sk)
		_head_pos.append(sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Head")).origin)
		_heads.append(_head_pos[-1].y)
		for f in 2:
			_foot_pos[f].append(sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Foot.L" if f == 0 else "Foot.R")).origin)
	if _frame < 240:
		return false
	_report(s)
	_frame = 0
	_heads.clear()
	_head_pos.clear()
	_foot_pos = [[], []]
	_rot_hist.clear()
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
	if speed > 0.5 and s[0] != &"slide":
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
	var moving: bool = speed > 0.5 and s[0] != &"slide"
	var flag := skate > MAX_SKATE or pop > (MAX_POP_MOVING if moving else MAX_POP) or jerk > (MAX_JERK_MOVING if moving else MAX_JERK) or _bone_step > MAX_BONE_STEP
	_failed = _failed or flag
	print("CLIPMETRICS ", s[0], " skate=", snappedf(skate, 0.01), " pop=", snappedf(pop, 0.001), " jerk=", roundi(jerk), " bone_deg_15hz=", roundi(_bone_step), "  FLAG" if flag else "")
