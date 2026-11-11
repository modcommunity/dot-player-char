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
	var off := right.distance_to(weapon.to_global(grip))
	suite._check(arms.palm_offset != Vector3.ZERO and off > 0.015 and off < 0.05, "by default the wrist sits on the grip's side, off the centreline but not hanging below it (%.3f m)" % off)
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


## The arms keep out of the weapon's box, wear the detailed material, and take a server's arm set over their own.
func run_arms_dress() -> void:
	suite._section("your own arms clear of the weapon, dressed as you")
	var weapon := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.08, 0.16, 0.6)
	weapon.mesh = box
	suite.add_child(weapon)
	weapon.position = Vector3(0.08, -0.2, -0.4)
	var grip := Vector3(0.0, -0.06, 0.12)
	var fore := Vector3(0.0, -0.06, -0.15)
	var measured := DotViewGrip.two_hand(weapon, grip, fore).bounds_local()
	suite._check(measured.size.is_equal_approx(box.size), "a weapon's box is measured from its meshes when it gives none (%s)" % measured.size)
	# A rifle whose stock runs back to the shoulder and whose receiver is wide: the stock elbows go through it.
	var rifle := AABB(Vector3(-0.06, -0.22, -0.35), Vector3(0.22, 0.28, 0.75))
	var depths := []
	for clear in [false, true]:
		var arms := DotPlayerViewArms.new()
		arms.keep_arms_clear = clear
		suite.add_child(arms)
		arms.build(DotHumanoidLook.stock(3), 1.8)
		var held := DotViewGrip.two_hand(weapon, grip, fore)
		held.bounds = rifle
		arms.set_held(held)
		for i in 20:
			arms.tick(0.0, 1.0 / 30.0)
			await suite.get_tree().process_frame
		var sk: Skeleton3D = (arms.arms() as DotHumanoidFigure).skeleton()
		depths.append([_buried(arms, sk, held, "R"), _buried(arms, sk, held, "L"), arms.hand_error(held)])
		arms.queue_free()
	suite._check(depths[0][0] + depths[0][1] > 0.01, "the stock elbows put an arm through this gun (%.3f / %.3f m deep; the check can fail)" % [depths[0][0], depths[0][1]])
	suite._check(depths[1][0] + depths[1][1] < (depths[0][0] + depths[0][1]) * 0.6, "keep_arms_clear turns the elbows out of it (%.3f / %.3f m deep)" % [depths[1][0], depths[1][1]])
	suite._check(depths[1][2] >= 0.0 and depths[1][2] < 0.05, "and the hands still reach their grips (%.3f m)" % depths[1][2])

	var own := DotHumanoidLook.stock(3)
	var server := DotHumanoidLook.stock(9)
	var arms := DotPlayerViewArms.new()
	suite.add_child(arms)
	arms.build(own, 1.8)
	var mesh := (arms.arms() as DotHumanoidFigure).mesh()
	var material := mesh.material_override as ShaderMaterial
	suite._check(arms.describe()["detailed"] and material != DotHumanoidAssets.material_for(own) and material == DotViewArmsMaterial.for_look(own), "the arms wear the detailed material for their own look")
	suite._check(material.shader.code.contains("BACKLIGHT") and int(material.get_shader_parameter(&"skin_swaps")) > 0, "with skin swaps marked for the skin detail (%s)" % material.get_shader_parameter(&"skin_swaps"))
	var rest: PackedFloat32Array = mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_CUSTOM0]
	suite._check(rest.size() == (mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() * 4, "every vertex carries its rest position for the pattern (%d floats)" % rest.size())
	arms.set_look_override(server)
	suite._check(arms.look == server and arms.own_look == own and arms.describe()["overridden"], "a server's arm set is drawn over the player's own")
	suite._check((arms.arms() as DotHumanoidFigure).mesh().material_override == DotViewArmsMaterial.for_look(server), "in the server set's colours")
	arms.set_look_override(null)
	suite._check(arms.look == own and not arms.describe()["overridden"], "and clearing it gives the player's own arms back")
	arms.queue_free()
	weapon.queue_free()


## The deepest the arm's upper half and forearm (not its hand end) go into the grip's box, sampled from the bones.
func _buried(arms: DotPlayerViewArms, sk: Skeleton3D, grip: DotViewGrip, side: String) -> float:
	var box := grip.bounds_local()
	var to_anchor := grip.anchor.global_transform.affine_inverse()
	var shoulder := to_anchor * _bone_world(sk, "UpperArm." + side)
	var elbow := to_anchor * _bone_world(sk, "LowerArm." + side)
	var hand := (to_anchor * _bone_world(sk, "Middle1." + side)).lerp(elbow, DotPlayerViewArms.CLEAR_HAND_FREE)
	var deepest := 0.0
	for i in 9:
		for q: Vector3 in [shoulder.lerp(elbow, i / 8.0), elbow.lerp(hand, i / 8.0)]:
			if box.has_point(q):
				var low := q - box.position
				var high := box.end - q
				deepest = maxf(deepest, minf(minf(minf(low.x, high.x), minf(low.y, high.y)), minf(low.z, high.z)))
	return deepest


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


## A full-body action (dance, sit) is not flattened by the held-gun arms.
func run_full_body_action() -> void:
	suite._section("a held gun while a full-body action plays")
	var world := Node3D.new()
	suite.add_child(world)
	var armed := DotHumanoidFigure.new()
	var bare := DotHumanoidFigure.new()
	for f: DotHumanoidFigure in [armed, bare]:
		world.add_child(f)
		f.build(DotHumanoidLook.stock(21), 1.8)
		f.set_motion({"on_floor": true})
	armed.set_hold(DotHumanoidFigure.Hold.GUN)
	var played := armed.play_action(&"dance", true) and bare.play_action(&"dance", true)
	for i in 10:
		armed.animate(0.0, 1.0 / 60.0)
		bare.animate(0.0, 1.0 / 60.0)
	var gap := _pose_gap(armed.skeleton(), bare.skeleton(), true)
	suite._check(played, "both figures start the dance")
	suite._check(gap < 0.01, "the armed dancer's pose is the unarmed dancer's (gap %.4f rad)" % gap)
	world.queue_free()
	await suite.get_tree().process_frame


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
	var ref := PackedFloat32Array()
	var n := sk.get_bone_count()
	ref.append(n)
	var mdl: Node3D = live.get("_model")
	for v: Vector3 in [mdl.transform.basis.x, mdl.transform.basis.y, mdl.transform.basis.z, mdl.transform.origin]:
		ref.append_array([v.x, v.y, v.z])
	for i in n:
		var q := sk.get_bone_pose_rotation(i)
		ref.append_array([q.x, q.y, q.z, q.w])
	for i in n:
		var par := sk.get_bone_parent(i)
		if par < 0 or sk.get_bone_parent(par) < 0:
			var pp := sk.get_bone_pose_position(i)
			ref.append_array([pp.x, pp.y, pp.z])
	suite._check(live.pose_record() == ref, "the record is the plain layout: count, model transform, bone rotations, root positions (%d floats)" % ref.size())
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
