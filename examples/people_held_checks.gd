class_name DotPeopleHeldChecks
extends RefCounted

## The suite's held-weapon and recorded-pose sections, split out to keep people_selftest under the
## file-size gate. Reports through the suite's `_section` and `_check`.

var suite: Node


func _init(host: Node) -> void:
	suite = host


func run_arms() -> void:
	suite._section("your own arms holding a weapon")
	var arms := DotPlayerViewArms.new()
	suite.add_child(arms)
	var weapon := Node3D.new()
	suite.add_child(weapon)
	weapon.position = Vector3(0.08, -0.2, -0.4)
	arms.build(DotHumanoidLook.stock(3), 1.8)
	suite._check(not arms.arms().visible and not arms.describe()["held"], "off by default: nothing shown")
	var grip := Vector3(0.0, -0.08, 0.1)
	var fore := Vector3(-0.03, -0.07, -0.1)
	arms.set_held(DotViewGrip.two_hand(weapon, grip, fore))
	for i in 8:
		arms.tick(0.0, 1.0 / 30.0)
		await suite.get_tree().process_frame
	var sk: Skeleton3D = (arms.arms() as DotHumanoidFigure).skeleton()
	suite._check(arms.arms().visible and arms.describe()["held"], "shown while a grip is set")
	var right := _bone_world(sk, "Middle1.R")
	suite._check(right.distance_to(_palm(arms, weapon.to_global(grip))) < 0.03, "the firing hand is palm_offset from the grip (%.3f m)" % right.distance_to(_palm(arms, weapon.to_global(grip))))
	suite._check(arms.palm_offset != Vector3.ZERO and right.distance_to(weapon.to_global(grip)) > 0.05, "by default the wrist is off the gun's centreline so the hand does not cover it (%.3f m)" % right.distance_to(weapon.to_global(grip)))
	var left := _bone_world(sk, "Middle1.L")
	suite._check(left.distance_to(_palm(arms, weapon.to_global(fore), true)) < 0.05, "the support hand reaches the foregrip (%.3f m)" % left.distance_to(_palm(arms, weapon.to_global(fore), true)))
	var held_grip := DotViewGrip.two_hand(weapon, grip, fore)
	arms.set_held(held_grip)
	arms.tick(0.0, 1.0 / 30.0)
	suite._check(arms.hand_error(held_grip) >= 0.0 and arms.hand_error(held_grip) < 0.05, "hand_error is small on the grip it holds (%.3f m)" % arms.hand_error(held_grip))
	suite._check(arms.hand_error(null) == -1.0, "hand_error is -1 with no grip")
	suite._check(sk.get_bone_pose_scale(sk.find_bone("Head")).x < 0.01 and sk.get_bone_pose_scale(sk.find_bone("UpperLeg.L")).x < 0.01, "head and legs are shrunk away")
	weapon.position += Vector3(0.1, 0.05, -0.05)
	for i in 3:
		arms.tick(0.0, 1.0 / 30.0)
	var moved := _bone_world(sk, "Middle1.R")
	suite._check(moved.distance_to(_palm(arms, weapon.to_global(grip))) < 0.03 and moved.distance_to(right) > 0.05, "the hand follows the weapon when it moves (%.3f m off)" % moved.distance_to(_palm(arms, weapon.to_global(grip))))
	var before := arms.sway()
	for i in 20:
		arms.tick(5.0, 1.0 / 30.0)
	suite._check(arms.sway().length() > 0.001 and not arms.sway().is_equal_approx(before), "walking sways the weapon mount (%.4f m)" % arms.sway().length())
	var worst := 0.0
	for i in 150:
		arms.tick(5.0, 1.0 / 30.0)
		worst = maxf(worst, _bone_world(sk, "Middle1.R").distance_to(_palm(arms, weapon.to_global(grip))))
		worst = maxf(worst, _bone_world(sk, "LowerArm.R").distance_to(weapon.to_global(grip)) - 0.6)
	suite._check(worst < 0.03, "the hand stays on the grip through a long walk (worst %.3f m)" % worst)
	arms.set_held(DotViewGrip.one_hand(weapon, grip))
	arms.tick(0.0, 1.0 / 30.0)
	var rest_left := _bone_world(sk, "Middle1.L")
	suite._check(rest_left.distance_to(weapon.to_global(fore)) > 0.1, "a one-hand grip leaves the other hand off the foregrip (%.2f m away)" % rest_left.distance_to(weapon.to_global(fore)))
	suite._check(sk.get_bone_pose_scale(sk.find_bone("UpperArm.L")).x < 0.01, "a one-hand grip hides the idle left arm")
	arms.show_idle_left_arm = true
	arms.tick(0.0, 1.0 / 30.0)
	suite._check(sk.get_bone_pose_scale(sk.find_bone("UpperArm.L")).x > 0.5, "show_idle_left_arm keeps it")
	arms.show_idle_left_arm = false
	arms.set_held(DotViewGrip.two_hand(weapon, grip, fore))
	arms.tick(0.0, 1.0 / 30.0)
	suite._check(sk.get_bone_pose_scale(sk.find_bone("UpperArm.L")).x > 0.5, "a two-hand grip shows the left arm")
	arms.set_held(DotViewGrip.two_hand(weapon, grip, Vector3(0.0, 5.0, 0.0)))
	arms.tick(0.0, 1.0 / 30.0)
	suite._check(_bone_world(sk, "Middle1.L").distance_to(weapon.to_global(Vector3(0.0, 5.0, 0.0))) > 1.0, "a support point out of reach is not reached (the check can fail)")
	arms.set_held(DotViewGrip.two_hand(weapon, grip, fore))
	arms.set_downed(true)
	for i in 4:
		arms.tick(1.0, 1.0 / 30.0)
		await suite.get_tree().process_frame
	suite._check(not arms.describe()["held"] and (arms.arms() as DotHumanoidFigure).downed, "downed wins over a held weapon")
	var head := _bone_world(sk, "Head")
	var crawl_hand := _bone_world(sk, "Middle1.L")
	suite._check(crawl_hand.z < head.z - 0.2 and crawl_hand.y < head.y, "and the crawl is as without a grip: the hand ahead of the eye")
	arms.set_downed(false)
	arms.set_held(null)
	suite._check(not arms.arms().visible and arms.sway() == Vector3.ZERO, "mode off hides the arms and stops the sway")
	suite._check(not DotViewGrip.new().is_valid(), "a grip with no anchor is not valid, so the arms rest")
	arms.queue_free()
	weapon.queue_free()


## Where the wrist should be for a grip point: the point shifted by palm_offset in the arms' frame (x mirrored for the support hand).
func _palm(arms: DotPlayerViewArms, point: Vector3, support := false) -> Vector3:
	var o := arms.palm_offset
	return point + arms.global_transform.basis * Vector3(-o.x if support else o.x, o.y, o.z)


func _bone_world(sk: Skeleton3D, bone: String) -> Vector3:
	return (sk.global_transform * sk.get_bone_global_pose(sk.find_bone(bone))).origin


## A gun in the hand stays put when the pace flickers across the walk, run and sprint thresholds
## (a bot's noisy speed, a remote player's interpolation): the stride cut must not snap the arm.
func run_gun_steady() -> void:
	suite._section("a held gun while the pace flickers")
	var world := Node3D.new()
	suite.add_child(world)
	var f := DotHumanoidFigure.new()
	world.add_child(f)
	f.build(DotHumanoidLook.stock(21), 1.8)
	f.set_hold(DotHumanoidFigure.Hold.GUN)
	var hand := f.attachment(&"right_hand")
	var worst := {}
	for pair: Array in [[2.0, 4.6], [4.6, 6.5]]:
		var last := Transform3D.IDENTITY
		var big := 0.0
		var far := 0.0
		for i in 240:
			f.animate(pair[0] if (i / 6) % 2 == 0 else pair[1], 1.0 / 60.0)
			await suite.get_tree().process_frame
			var now: Transform3D = f.global_transform.affine_inverse() * hand.global_transform
			if i > 30:
				big = maxf(big, last.basis.get_rotation_quaternion().angle_to(now.basis.get_rotation_quaternion()))
				far = maxf(far, (now.origin - last.origin).length())
			last = now
		worst[pair[1]] = [rad_to_deg(big), far]
	var sprint: Array = worst[6.5]
	var run: Array = worst[4.6]
	suite._check(run[0] < 8.0 and sprint[0] < 8.0, "the hand turns under 8 degrees a frame (%.1f / %.1f)" % [run[0], sprint[0]])
	suite._check(run[1] < 0.08 and sprint[1] < 0.08, "the hand moves under 8 cm a frame (%.3f / %.3f)" % [run[1], sprint[1]])
	f.queue_free()
	suite._check(true, "the flicker run finished")


func run_pose_record() -> void:
	suite._section("a recorded pose replays as drawn")
	var world := Node3D.new()
	suite.add_child(world)
	var live := DotHumanoidFigure.new()
	var copy := DotHumanoidFigure.new()
	for f: DotHumanoidFigure in [live, copy]:
		world.add_child(f)
		f.build(DotHumanoidLook.stock(21), 1.8)
		f.set_hold(DotHumanoidFigure.Hold.GUN)
	var sk := live.skeleton()
	var steps: Array = []
	for i in 30:
		steps.append([{"on_floor": true, "aim": 0.3}, 4.6])
	for i in 30:
		steps.append([{"on_floor": true, "crouched": true, "aim": -0.4}, 1.5])
	for i in 30:
		steps.append([{"on_floor": true, "aim": 0.6}, 0.0])
	var worst := 0.0
	var off_rest := INF
	var applied := true
	var last := PackedFloat32Array()
	for step: Array in steps:
		live.set_motion(step[0])
		live.animate(step[1], 1.0 / 60.0)
		var rec := live.pose_record()
		applied = copy.pose_apply(rec, rec, 0.0) and applied
		worst = maxf(worst, _pose_gap(sk, copy.skeleton(), true))
		off_rest = minf(off_rest, _pose_gap(sk, sk, false))
		last = rec
	suite._check(applied and worst < 0.001, "each frame of run, crouch and aim applied to another figure is the live pose (worst %.5f rad)" % worst)
	suite._check(off_rest > 0.5, "and none of them is the rest pose (least %.2f rad from it)" % off_rest)
	var first := steps.size()
	live.set_motion({"on_floor": true})
	live.animate(0.0, 1.0 / 60.0)
	var other := live.pose_record()
	suite._check(copy.pose_apply(last, other, 0.5) and not copy.pose_apply(last, other.slice(0, other.size() - 3), 0.5),
		"two records blend; records of different sizes are refused (%d floats a pose)" % last.size())
	var still := DotHumanoidFigure.new()
	world.add_child(still)
	still.build(DotHumanoidLook.stock(21), 1.8)
	still.set_hold(DotHumanoidFigure.Hold.GUN)
	still.set_motion({"on_floor": true})
	still.animate(4.6, 0.0)
	var frozen := still.pose_record()
	for i in 20:
		still.animate(4.6, 0.0)
	var gap := _pose_gap(still.skeleton(), still.skeleton(), false)
	suite._check(gap > 0.0 and still.pose_record() == frozen and first > 0,
		"a body posed by speed alone, with no time, stands frozen at a run (%.2f rad from rest): why a replay records the pose" % gap)
	world.queue_free()
	await suite.get_tree().process_frame


## Largest bone rotation gap, in radians: between two skeletons' poses, or (same=false) a pose and its rest.
func _pose_gap(a: Skeleton3D, b: Skeleton3D, same: bool) -> float:
	var gap := 0.0
	for i in a.get_bone_count():
		var qa := a.get_bone_pose_rotation(i)
		var qb := b.get_bone_pose_rotation(i) if same else b.get_bone_rest(i).basis.get_rotation_quaternion()
		gap = maxf(gap, qa.normalized().angle_to(qb.normalized()))
	return gap
