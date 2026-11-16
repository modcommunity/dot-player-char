extends RefCounted

## The suite's real-hands section: DotViewHand's fingers and DotPlayerViewArms closing them on each weapon kind.
## Split out to keep people_selftest under the file-size gate; reports through the suite's `_section` and `_check`.

var suite: Node


func _init(host: Node) -> void:
	suite = host


func run() -> void:
	_check_hand_mesh()

	var arms := DotPlayerViewArms.new()
	arms.finger_rate = 0.0
	suite.add_child(arms)
	arms.build(DotHumanoidLook.stock(3), 1.8)
	var weapon := Node3D.new()
	suite.add_child(weapon)
	weapon.position = Vector3(0.08, -0.2, -0.4)
	var grip := Vector3(0.0, -0.08, 0.1)
	var fore := Vector3(0.0, -0.05, -0.12)
	var rifle := DotViewGrip.two_hand(weapon, grip, fore)
	arms.set_held(rifle)
	await _settle(arms, 8)
	var hands := arms.hands()
	suite._check(hands.size() == 2 and arms.describe()["real_hands"] and hands[0].visible and hands[1].visible, "a two-hand weapon is held in both real hands")
	var material := (arms.arms() as DotHumanoidFigure).mesh().material_override
	suite._check(material != null and hands[0].mesh_instance().material_override == material, "the hands wear the arms' own material (one skin family with the bodies)")
	suite._check(arms.hand_error(rifle) >= 0.0 and arms.hand_error(rifle) < 0.03, "the wrists sit where the hands close on the grips (%.3f m)" % arms.hand_error(rifle))
	var firing: Dictionary = (DotViewHandPoses.table()[DotViewHandPoses.RIFLE] as Dictionary)[&"firing"]
	var held := hands[0].global_transform * (firing[&"centre"] as Vector3)
	suite._check(held.distance_to(rifle.grip_world()) < 0.01, "the grip point is inside the firing hand (%.3f m off)" % held.distance_to(rifle.grip_world()))

	var near := Node3D.new()
	suite.add_child(near)
	near.position = Vector3(0.06, -0.12, -0.08)
	var pulled := DotViewGrip.two_hand(near, grip, Vector3(0.0, -0.05, 0.02))
	var to_arms := arms.global_transform.affine_inverse()
	var raw: float = minf(-(to_arms * arms.wrist_targets(pulled)[0]).z, -(to_arms * arms.wrist_targets(pulled)[1]).z)
	arms.hand_min_depth = 0.1
	arms.set_held(pulled)
	await _settle(arms, 8)
	var kept: float = minf(-(to_arms * arms.wrist_targets(pulled)[0]).z, -(to_arms * arms.wrist_targets(pulled)[1]).z)
	suite._check(raw < 0.1 and kept > 0.099 and arms.hand_error(pulled) < 0.03, "hand_min_depth slides a gun pulled to the eye's hands out past it (%.3f m to %.3f m, hands %.3f m off)" % [raw, kept, arms.hand_error(pulled)])
	arms.hand_min_depth = -1.0
	suite._check(is_equal_approx(arms.hand_min_depth, 0.1), "a negative hand_min_depth is refused (kept %.2f)" % arms.hand_min_depth)
	arms.hand_min_depth = 0.0
	near.queue_free()

	var worst := 0.0
	var named := ""
	for kind: StringName in [DotViewHandPoses.PISTOL, DotViewHandPoses.SHOTGUN, DotViewHandPoses.LAUNCHER, DotViewHandPoses.SNIPER,
			DotViewHandPoses.GRENADE, DotViewHandPoses.KNIFE, &"no_such_kind"]:
		var one := kind in [DotViewHandPoses.GRENADE, DotViewHandPoses.KNIFE]
		var g := DotViewGrip.one_hand(weapon, grip) if one else DotViewGrip.two_hand(weapon, grip, fore)
		g.kind = kind
		arms.set_held(g)
		await _settle(arms, 6)
		var error := arms.hand_error(g)
		var wrong_hands := not hands[0].visible or hands[1].visible == one
		if error < 0.0 or error > worst or wrong_hands:
			worst = maxf(worst, 1.0 if error < 0.0 or wrong_hands else error)
			named = "%s %.3f m, hands %s/%s" % [kind, error, hands[0].visible, hands[1].visible]
	suite._check(worst < 0.03, "every kind (and an unknown one, as a rifle) is held in its hands, one-hand ones in one (worst %s)" % named)

	await _check_grenade(arms, weapon, grip, hands)
	await _check_knife(arms, weapon, grip, hands)
	await _check_extended_reach(arms, grip)

	arms.real_hands = false
	arms.set_held(rifle)
	await _settle(arms, 3)
	suite._check(not hands[0].visible and not hands[1].visible and arms.hand_error(rifle) < 0.03, "real_hands off draws the kit's own hands again (%.3f m)" % arms.hand_error(rifle))
	arms.real_hands = true
	arms.set_held(null)
	suite._check(not hands[0].visible and not hands[1].visible, "putting the weapon away hides the hands")
	arms.queue_free()
	weapon.queue_free()


func _check_hand_mesh() -> void:
	suite._section("your own real hands, a grip per weapon")
	var hand := DotViewHand.new()
	suite.add_child(hand)
	var verts := (hand.mesh_instance().mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	suite._check(verts > 400, "a hand is one skinned mesh with five jointed fingers (%d vertices)" % verts)
	var open := hand.tip(&"index").distance_to(Vector3(0.0, 0.05, 0.03))
	hand.pose((DotViewHandPoses.table()[DotViewHandPoses.FISTS] as Dictionary)[&"firing"])
	var fist := hand.tip(&"index").distance_to(Vector3(0.0, 0.05, 0.03))
	suite._check(fist < open - 0.03, "a fist pose closes the fingers into the palm (index tip %.3f m from it, open %.3f m)" % [fist, open])
	var left := DotViewHand.new()
	left.right = false
	suite.add_child(left)
	suite._check(hand.tip(&"thumb").x > 0.0 and left.tip(&"thumb").x < 0.0, "a left hand is the right one mirrored (thumb x %.3f / %.3f)" % [hand.tip(&"thumb").x, left.tip(&"thumb").x])
	hand.queue_free()
	left.queue_free()


func _check_grenade(arms: DotPlayerViewArms, weapon: Node3D, grip: Vector3, hands: Array) -> void:
	var grenade := DotViewGrip.one_hand(weapon, grip)
	grenade.kind = DotViewHandPoses.GRENADE
	arms.set_held(grenade)
	await _settle(arms, 3)
	suite._check(hands[0].visible and arms.describe()["real_hands"], "a grenade is held in a hand you can see (it was drawn with none)")
	var pose: Dictionary = DotViewHandPoses.table()[DotViewHandPoses.GRENADE][&"firing"]
	var tilt_a := DotViewHandPoses.frame(pose, Vector3.UP, Vector3(0.0002, 1.0, 0.0))
	var tilt_b := DotViewHandPoses.frame(pose, Vector3.UP, Vector3(-0.0002, 1.0, 0.0001))
	suite._check(tilt_a.is_equal_approx(tilt_b) and tilt_a.is_conformal(), "an up along the forward (a grenade's) gives one steady hand frame, not noise")


func _check_knife(arms: DotPlayerViewArms, weapon: Node3D, grip: Vector3, hands: Array) -> void:
	var knife := DotViewGrip.one_hand(weapon, grip)
	knife.kind = DotViewHandPoses.KNIFE
	arms.set_held(knife)
	await _settle(arms, 3)
	var fist_index: Vector3 = hands[0].curls()[&"index"]
	arms.throw_grip = 1.0
	await _settle(arms, 3)
	var pinch_index: Vector3 = hands[0].curls()[&"index"]
	suite._check(pinch_index.y < fist_index.y - 30.0, "a knife wound back to throw opens to a pinch (index %.0f to %.0f degrees)" % [fist_index.y, pinch_index.y])
	arms.throw_grip = 0.0
	arms.run = 1.0
	await _settle(arms, 3)
	suite._check(hands[0].visible and hands[1].visible, "sprinting with a knife pumps the free hand too, a fist")
	arms.run = 0.0


func _check_extended_reach(arms: DotPlayerViewArms, grip: Vector3) -> void:
	var far := Node3D.new()
	suite.add_child(far)
	far.position = Vector3(0.1, -0.2, -0.45)
	var long := DotViewGrip.two_hand(far, grip, Vector3(-0.02, -0.04, -0.5))
	long.kind = DotViewHandPoses.SNIPER
	var errors := []
	for extend in [false, true]:
		arms.extend_reach = extend
		arms.set_held(long)
		await _settle(arms, 10)
		errors.append(arms.hand_error(long))
	suite._check(errors[0] > 0.05, "a long forend is out of the arm's plain reach (%.3f m short; the check can fail)" % errors[0])
	suite._check(errors[1] < 0.03 and arms.describe()["reach_extended"] > 0.0, "extend_reach moves the shoulder out so the support hand lands on it (%.3f m, moved %.3f)" % [errors[1], arms.describe()["reach_extended"]])
	far.queue_free()


func _settle(arms: DotPlayerViewArms, frames: int) -> void:
	for i in frames:
		arms.tick(0.0, 1.0 / 30.0)
		await suite.get_tree().process_frame
