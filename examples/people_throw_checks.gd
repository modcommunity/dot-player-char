extends RefCounted

## The suite's knife-throw and sprinting-arms section ([method DotHumanoidFigure.set_throw_charge]), split out to
## keep people_selftest under the file-size gate. Reports through the suite's `_section` and `_check`.

const DT := 1.0 / 60.0

var suite: Node


func _init(host: Node) -> void:
	suite = host


func run() -> void:
	suite._section("a knife thrown and a sprint with a blade, as others see them")
	var f := DotHumanoidFigure.new()
	suite.add_child(f)
	f.build(DotHumanoidLook.stock(4), 1.8)
	f.set_hold(DotHumanoidFigure.Hold.MELEE)
	_frames(f, 0.0, 20)
	var rest := _arm(f, "R")
	var length: float = rest[0].distance_to(rest[1]) + rest[1].distance_to(rest[2])
	suite._check(length > 0.3 and length < 1.0, "the arm measures as an arm (%.2f m)" % length)

	f.set_throw_charge(0.0)
	_frames(f, 0.0, 20)
	var started := _arm(f, "R")
	suite._check(started[2].y > rest[2].y + 0.05, "a windup at an empty meter has already lifted the hand (%.2f to %.2f)" % [rest[2].y, started[2].y])
	f.set_throw_charge(0.5)
	_frames(f, 0.0, 20)
	var half := _arm(f, "R")
	f.set_throw_charge(1.0)
	_frames(f, 0.0, 30)
	var full := _arm(f, "R")
	var s: Vector3 = full[0]
	suite._check(full[2].y > s.y + 0.2 * length and full[2].z > s.z + 0.15 * length,
		"a full meter cocks the hand above and behind the shoulder (hand %s, shoulder %s)" % [full[2], s])
	suite._check(full[1].x > s.x and full[1].z > s.z - 0.05, "with the elbow out to the side and back (%s)" % full[1])
	suite._check(started[2].y < half[2].y and half[2].y < full[2].y and started[2].z < full[2].z,
		"the fuller the meter, the further back (%.2f, %.2f, %.2f)" % [started[2].y, half[2].y, full[2].y])

	f.throw_release()
	_frames(f, 0.0, 9)
	var thrown := _arm(f, "R")
	suite._check(thrown[2].z < thrown[0].z - 0.6 * length, "the release whips the hand out ahead of the shoulder (%s)" % thrown[2])
	_frames(f, 0.0, 60)
	var after := _arm(f, "R")
	suite._check(not f.arms.active() and after[2].distance_to(rest[2]) < 0.05,
		"and the arm is back to the clip's after it (%.3f m)" % after[2].distance_to(rest[2]))

	f.set_motion({"sprinting": true, "on_floor": true, "velocity": Vector3(0, 0, -7)})
	var right_z := PackedFloat32Array()
	var bent := true
	var hanging := true
	var finite := true
	for i in 60:
		_frames(f, 7.0, 1)
		if i < 20:
			continue
		for side in ["R", "L"] as Array[String]:
			var arm := _arm(f, side)
			for p: Vector3 in arm:
				finite = finite and p.is_finite()
			var up: Vector3 = arm[0] - arm[1]
			var down: Vector3 = arm[2] - arm[1]
			var elbow := rad_to_deg(up.angle_to(down))
			bent = bent and elbow > 65.0 and elbow < 115.0
			hanging = hanging and rad_to_deg((-up).angle_to(Vector3.DOWN)) < 50.0
		right_z.append(_arm(f, "R")[2].z)
	suite._check(f.arms.run > 0.99 and finite, "sprinting with a blade the arms run (%s)" % f.arms.describe())
	suite._check(bent, "both elbows bent near square through the stride")
	suite._check(hanging, "both upper arms near the sides")
	var swing := 0.0
	if not right_z.is_empty():
		var lo := right_z[0]
		var hi := right_z[0]
		for z in right_z:
			lo = minf(lo, z)
			hi = maxf(hi, z)
		swing = hi - lo
	suite._check(swing > 0.15 * length, "and they pump with the stride (%.2f m)" % swing)

	f.set_hold(DotHumanoidFigure.Hold.GUN)
	_frames(f, 7.0, 30)
	suite._check(f.arms.run < 0.01, "a gun keeps its own sprint carry (%.2f)" % f.arms.run)
	f.queue_free()
	await _view_run()


## Your own view: a one-hand blade while sprinting brings the free arm up as a pumping fist.
func _view_run() -> void:
	var arms := DotPlayerViewArms.new()
	suite.add_child(arms)
	var weapon := Node3D.new()
	suite.add_child(weapon)
	weapon.position = Vector3(0.08, -0.2, -0.4)
	arms.build(DotHumanoidLook.stock(3), 1.8)
	arms.set_held(DotViewGrip.one_hand(weapon, Vector3(0.0, -0.08, 0.1)))
	arms.tick(0.0, 1.0 / 30.0)
	var sk: Skeleton3D = (arms.arms() as DotHumanoidFigure).skeleton()
	var upper := sk.find_bone("UpperArm.L")
	suite._check(not arms.describe()["left_arm"], "in your view the free arm is hidden while not sprinting")
	arms.run = 1.0
	var fists: Array[Vector3] = []
	var finite := true
	for phase in [0.25, 0.75] as Array[float]:
		arms.run_phase = phase
		for i in 10:
			arms.tick(0.0, 1.0 / 30.0)
		var fist := _bone_world(sk, "Middle1.L")
		finite = finite and fist.is_finite()
		fists.append(arms.to_local(fist))
	suite._check(sk.get_bone_pose_scale(upper).x > 0.5 and finite and arms.describe()["run"] > 0.99,
		"sprinting, it is shown (%s)" % arms.describe()["run"])
	var pump := fists[0].distance_to(fists[1])
	suite._check(pump > 0.05 and fists[0].x < 0.0, "on the left, pumping with the stride (%.3f m)" % pump)
	arms.queue_free()
	weapon.queue_free()
	await suite.get_tree().process_frame


func _bone_world(sk: Skeleton3D, bone: String) -> Vector3:
	return (sk.global_transform * sk.get_bone_global_pose(sk.find_bone(bone))).origin


func _frames(f: DotHumanoidFigure, speed: float, n: int) -> void:
	for _i in n:
		f.animate(speed, DT)


## The [param side] arm's shoulder, elbow and hand in the figure's frame, from the poses as written this frame.
func _arm(f: DotHumanoidFigure, side: String) -> Array[Vector3]:
	var sk := f.skeleton()
	var to := f._to_figure()
	var out: Array[Vector3] = []
	for bone in ["UpperArm.", "LowerArm.", "Middle1."] as Array[String]:
		out.append(to * DotHumanoidIk.global_pose(sk, sk.find_bone(bone + side)).origin)
	return out
