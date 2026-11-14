class_name DotFigureNativeChecks
extends RefCounted

## The native pose layers ([constant DotHumanoidIk.NATIVE_CLASS], from dot_sim) against the script: two
## crowds driven alike, one posed by each, every bone compared every frame. Skipped when the extension
## is not loaded (the script is then the only path). Reports through the suite's `_section` and `_check`.

const DT := 1.0 / 60.0
const COUNT := 6
const FRAMES := 240
## Largest difference allowed in a bone's rotation (quaternion component) and in the support point (m):
## the two round differently (the script carries doubles between engine calls), not by more.
const TOLERANCE := 1e-4

var suite: Node


func _init(host: Node) -> void:
	suite = host


func run() -> void:
	suite._section("the native pose layers match the script")
	DotHumanoidIk.native_enabled = true
	if DotHumanoidIk.native() == null:
		suite._check(true, "skipped: no %s (dot_sim not loaded), the script poses alone" % DotHumanoidIk.NATIVE_CLASS)
		suite._check(true, "skipped: the other hand's point too")
		return
	var crowds: Array = [[], []]
	for side in 2:
		for i in COUNT:
			var f := DotHumanoidFigure.new()
			suite.add_child(f)
			f.build(DotHumanoidLook.stock(i * 31 + 7), 1.8)
			f.position = Vector3(float(i) * 2.0, 0.0, -3.0)
			f.set_hold(DotHumanoidFigure.Hold.GUN)
			# Half carry a gun the game chose (a foregrip hand), half the implicit carry with a weapon's grip.
			if i % 2 == 0:
				f.carry.set_class([&"rifle", &"pistol", &"sniper"][i / 2 % 3])
			crowds[side].append(f)
	var worst_rot := 0.0
	var worst_grip := 0.0
	var native_grips := 0
	var lifts := [0, 0]
	for frame in FRAMES:
		for side in 2:
			DotHumanoidIk.native_enabled = side == 1
			for i in COUNT:
				_step(crowds[side][i], frame, i)
		DotHumanoidIk.native_enabled = true
		for i in COUNT:
			var a: DotHumanoidFigure = crowds[0][i]
			var b: DotHumanoidFigure = crowds[1][i]
			var sa := a.skeleton()
			var sb := b.skeleton()
			for bone in sa.get_bone_count():
				var qa := sa.get_bone_pose_rotation(bone)
				var qb := sb.get_bone_pose_rotation(bone)
				worst_rot = maxf(worst_rot, maxf(maxf(absf(qa.x - qb.x), absf(qa.y - qb.y)), maxf(absf(qa.z - qb.z), absf(qa.w - qb.w))))
			# A leg the floor lifted this frame: the restore holds its upper bone.
			for leg: Array in a.legs._floor_legs:
				lifts[0] += 1 if a.legs._saved.has(leg[0]) else 0
				lifts[1] += 1 if b.legs._saved.has(leg[0]) else 0
			var ga := a.carry.support_grip
			var gb := b.carry.support_grip
			if ga.is_finite() != gb.is_finite():
				worst_grip = INF
			elif ga.is_finite():
				native_grips += 1
				worst_grip = maxf(worst_grip, ga.distance_to(gb))
	for side in 2:
		for f: DotHumanoidFigure in crowds[side]:
			f.queue_free()
	suite._check(worst_rot < TOLERANCE and lifts[0] > 0 and lifts[0] == lifts[1],
		"%d people, %d frames: every bone within %s of the script (worst %s), legs lifted off the floor %d and %d times"
		% [COUNT, FRAMES, str(TOLERANCE), str(worst_rot), lifts[0], lifts[1]])
	suite._check(native_grips > 0 and worst_grip < TOLERANCE,
		"and the other hand's point, %d times (worst %s m)" % [native_grips, str(worst_grip)])


## One frame of a remote player: walking, sprinting, jumping, crouching, the view pitched, shooting and reloading in turn.
func _step(f: DotHumanoidFigure, frame: int, i: int) -> void:
	var t := float(frame) * DT
	var phase := t * 0.37 + float(i) * 0.9
	var speed := 0.0 if (frame / 40 + i) % 5 == 0 else 2.0 + 4.5 * (0.5 + 0.5 * sin(phase * 3.0))
	var heading := phase * 0.6 + float(i)
	var v := Vector3(sin(heading), 0.0, cos(heading)) * speed
	var air := (frame + i * 13) % 120 < 20
	v.y = 2.0 - float((frame + i * 13) % 120) * 0.2 if air else 0.0
	f.rotation = Vector3(0.0, float(i) * 0.4 + t * 0.2, 0.0)
	f.set_motion({"on_floor": not air, "vertical": v.y, "crouched": (frame / 60 + i) % 7 == 0,
		"sliding": false, "swimming": false, "climbing": false, "alive": true, "wall_running": false,
		"velocity": v, "wall": Plane(), "aim": 0.6 * sin(t * 2.0 + float(i))})
	f.set_hold(DotHumanoidFigure.Hold.GUN)
	f.set_support_grip(f.global_transform * Vector3(0.05, 1.25, -0.45) if i % 2 == 1 else Vector3.INF)
	f.carry.raised = (frame / 50 + i) % 3 == 0
	f.carry.reloading = (frame + i * 17) % 160 < 70
	if (frame + i * 7) % 45 == 0:
		f.carry.fired()
	f.animate(Vector2(v.x, v.z).length(), DT)
