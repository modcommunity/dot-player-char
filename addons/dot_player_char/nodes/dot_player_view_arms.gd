class_name DotPlayerViewArms
extends "dot_player_view_arms_mesh.gd"

## Your own arms in first person: put it under the camera's yaw pivot (not its pitch, or the arms swing with the look).
## [method set_downed] plays the crawl; [method set_held] poses the arms on a weapon mesh the host supplies ([DotViewGrip]).
## The head, neck and legs are shrunk away so only the arms and a little torso show; a game's own arms come from [member arms_factory].



## Builds the arms (once; a new [param p_look] rebuilds). Hidden until [method set_downed] says otherwise.
func build(p_look: DotHumanoidLook = null, p_height: float = 1.8) -> void:
	own_look = p_look if p_look != null else DotHumanoidLook.stock(0)
	look = _override if _override != null else own_look
	height = p_height
	_clear()

	if arms_factory.is_valid():
		_arms = arms_factory.call(look, height) as Node3D

	if _arms == null:
		var figure := DotHumanoidFigure.new()
		figure.name = "Arms"
		add_child(figure)
		figure.build(look, height)
		_arms = figure
		var skeleton := figure.skeleton()

		if skeleton != null:
			_head = skeleton.find_bone("Head")

			for bone in HIDDEN_BONES:
				var i := skeleton.find_bone(bone)
				if i >= 0:
					_bones.append(i)

			for root in FINGER_ROOTS:
				for side in [".L", ".R"]:
					var f := skeleton.find_bone(root + side)
					if f >= 0:
						_fingers.append(f)
		_strip_gear(figure)
		if detailed and figure.mesh() != null:
			figure.mesh().material_override = DotViewArmsMaterial.for_look(look)
			_detail_on = true
		if real_hands and skeleton != null and figure.mesh() != null:
			_make_hands(figure)
	else:
		add_child(_arms)

	_fitted = false
	_ticks = 0
	_apply_mode()


## A server's arm set for every player ([param p_look]), drawn in place of each one's own; null goes back to
## [member own_look]. Rebuilds only when the drawn look changes.
func set_look_override(p_look: DotHumanoidLook) -> void:
	var was := look
	_override = p_look
	if own_look != null and (_override if _override != null else own_look) != was:
		build(own_look, height)


## Shows the crawling arms while [param on]. Always the prone crawl: a player propped on their back sees the held weapon, not arms.
func set_downed(on: bool) -> void:
	_downed = on
	_apply_mode()


## Poses the arms on [param grip]'s weapon (null puts the mode away). While downed the crawl still wins; with no grip the arms are as before.
func set_held(grip: DotViewGrip) -> void:
	if grip != _grip:
		# A new weapon is a cut: the old gun's elbow side must not slew across 25 degrees a frame to the new one's (a 0.1 m a frame sweep).
		_last_pole_right = Vector3.ZERO
		_last_pole_left = Vector3.ZERO
	_grip = grip
	_apply_mode()


## Added to the host's weapon mount (metres, in the yaw pivot's frame) so the weapon breathes and bobs with the shoulders; the hands reach for the grip either way.
func sway() -> Vector3:
	return _sway


func _apply_mode() -> void:
	var was := shown
	shown = _downed or _grip != null

	if _arms == null:
		return

	_arms.visible = shown
	var held := _holding()
	if not (shown and held):
		for hand in _hands:
			hand.visible = false

	if _arms.has_method("set_motion"):
		_arms.call("set_motion", {"downed": _downed, "propped": false})
	if _arms.has_method("set_hold"):
		_arms.call("set_hold", DotHumanoidFigure.Hold.GUN if _grip != null and not _downed else DotHumanoidFigure.Hold.NONE)

	# Only a change of mode refits (the fit depends on nothing else): a refit on every weapon swap let two
	# unfitted ticks lean from where the last frame left the arms, then snapped them back, and the elbow jumped.
	if was != shown or held != _was_holding:
		_fitted = false
		_ticks = 0
	if was != shown or _grip != null or not _right.is_empty():
		_right.clear()
		_left.clear()
	_was_holding = held


## Advances the arms; [param speed] is the player's ground speed, which drives the crawl.
func tick(speed: float, delta: float) -> void:
	if _arms == null or not shown:
		return

	if _arms.has_method("animate"):
		_arms.call("animate", 0.0 if _holding() else speed, delta)

	_ticks += 1
	_advance_sway(speed, delta)

	if not _fitted and _ticks >= 3 and is_inside_tree():
		_fit()

	var skeleton: Skeleton3D = (_arms as DotHumanoidFigure).skeleton() if _arms is DotHumanoidFigure else null

	if skeleton != null:
		for i in _bones:
			skeleton.set_bone_pose_scale(i, Vector3.ONE * 0.001)

		# Eased: a weapon swap set the next weapon's scale in one frame, and the elbow jumped 0.1 m mid-holster.
		_fore = move_toward(_fore, clampf(forearm_scale, 0.2, 1.5) if _holding() else 1.0, FORE_RATE * delta)
		var fore := _fore

		# Real hands draw in the mitts' place: the kit's own shrink to the wrist, where the forearm still ends.
		var mitt := 0.001 if _real_on() else (hand_scale if _holding() else 1.0) / fore
		for i in _fingers:
			skeleton.set_bone_pose_scale(i, Vector3.ONE * mitt)

		_scale_left(skeleton, fore)
		_delta = delta
		_reach(skeleton)
	_place_hands(skeleton)


## The real hands are drawn: built, a weapon held, and the arms up.
func _real_on() -> bool:
	return real_hands and _hands.size() == 2 and _holding() and _grip.is_valid()

func _left_hidden() -> bool:
	return _holding() and not show_idle_left_arm and not _grip.is_two_hand() and not _runs_left()


func _runs_left() -> bool:
	return is_finite(run) and run > 0.0 and _grip != null and not _grip.is_two_hand() and not show_idle_left_arm


func _scale_left(skeleton: Skeleton3D, fore: float) -> void:
	var hide := _left_hidden()
	# The mesh without the arm when there is one; else the arm shrinks to its shoulder (a factory's own figure).
	var swap := _one_arm_mesh != null and _arms is DotHumanoidFigure and (_arms as DotHumanoidFigure).mesh() != null
	if swap:
		var instance := (_arms as DotHumanoidFigure).mesh()
		var want := _one_arm_mesh if hide else _two_arm_mesh
		if instance.mesh != want:
			instance.mesh = want

	# The upper arm carries the scale (its child, the forearm, inherits it) so the sleeve shrinks about the shoulder joint.
	# With the arm's mesh dropped the bones still fold to the shoulder (the collar stays, it has no arm on it), so a
	# hidden arm is never left straight out in its rest T-pose for anything that reads the bones.
	for bone in ["Shoulder.L", "UpperArm.L", "LowerArm.L"]:
		var i := skeleton.find_bone(bone)
		if i >= 0:
			var folded: bool = hide and not (swap and bone == "Shoulder.L")
			skeleton.set_bone_pose_scale(i, Vector3.ONE * (0.001 if folded else (fore if bone == "UpperArm.L" else 1.0)))

	var upper := skeleton.find_bone("UpperArm.R")
	if upper >= 0:
		skeleton.set_bone_pose_scale(upper, Vector3.ONE * fore)

	var right := skeleton.find_bone("LowerArm.R")
	if right >= 0:
		skeleton.set_bone_pose_scale(right, Vector3.ONE)


## Seats the posed head bone at this node's origin; the clip already lies the person head toward -Z.
func _fit() -> void:
	_fitted = true
	var skeleton: Skeleton3D = (_arms as DotHumanoidFigure).skeleton() if _arms is DotHumanoidFigure else null

	if skeleton == null or _head < 0:
		return

	_arms.transform = Transform3D.IDENTITY
	var head := _arms.global_transform.affine_inverse() * (skeleton.global_transform * skeleton.get_bone_global_pose(_head)).origin
	var eye := held_eye_from_head if _holding() else eye_from_head
	var basis := Basis.from_scale(Vector3(held_scale * held_spread, held_scale, held_scale)) if _holding() else Basis.IDENTITY
	_arms.transform = Transform3D(basis, -(basis * head + eye))
	_base = _arms.position


func _holding() -> bool:
	return _grip != null and not _downed


func _advance_sway(speed: float, delta: float) -> void:
	var run := clampf(speed / 6.0, 0.0, 1.0)
	_phase += delta * (TAU * 0.25 + run * TAU * 2.0)
	var breath := sin(_phase * 0.5) * breath_amplitude
	var step := run * bob_amplitude
	_sway = Vector3(cos(_phase) * step * 0.5, breath + absf(sin(_phase)) * step, 0.0) if _holding() else Vector3.ZERO

	if _fitted and _arms != null:
		_arms.position = _base + _sway * 0.5


## Two-bone IK of each hand onto the grip, after the clip: the firing arm (right, as the people hold a gun) and, for a two-hand grip, the left.
func _reach(skeleton: Skeleton3D) -> void:
	if not _holding() or not _grip.is_valid() or not (_arms is DotHumanoidFigure):
		return

	var figure := _arms as DotHumanoidFigure

	if _right.is_empty():
		_right = DotHumanoidIk.keyed_bones(skeleton, figure.body_node(), _clip_of(figure), ["UpperArm.R", "LowerArm.R", "Middle1.R"])
		_left = DotHumanoidIk.keyed_bones(skeleton, figure.body_node(), _clip_of(figure), ["UpperArm.L", "LowerArm.L", "Middle1.L"])

	for bone in _extended:
		skeleton.set_bone_pose_position(bone, skeleton.get_bone_rest(bone).origin)
	_extended.clear()
	reach_extended_right = 0.0
	reach_extended_left = 0.0

	var targets := wrist_targets(_grip)
	var right_target: Vector3 = targets[0]
	var support_target: Vector3 = targets[1]
	_lean(skeleton, figure, right_target, support_target)

	var to_skeleton := skeleton.global_transform.affine_inverse()
	var out := to_skeleton.basis * (figure.global_transform.basis * elbow_pole)
	var drawn: Array = []
	hand_gap_right = 0.0
	hand_gap_left = 0.0

	arm_depth_right = 0.0
	arm_depth_left = 0.0

	if not _right.is_empty():
		reach_extended_right = _extend(skeleton, _right, right_target)
		var pole := _clear_pole(skeleton, _right, to_skeleton * right_target, _steady_pole(skeleton, _right, to_skeleton * right_target, out), true)
		pole = _slew_pole(_last_pole_right, (to_skeleton * right_target) - DotHumanoidIk.global_pose(skeleton, _right[0]).origin, pole)
		_last_pole_right = pole
		DotHumanoidIk.two_bone(skeleton, _right, to_skeleton * right_target, pole, 1.0)
		drawn.append([_grip.grip_world(), right_target, "Middle1.R"])
		hand_gap_right = _gap(skeleton, _right, right_target)

	if not _left.is_empty() and not _left_hidden():
		var rest := figure.global_transform * (_base + LEFT_REST)
		var target := rest
		if _runs_left():
			var r := clampf(run, 0.0, 1.0)
			var swing := -sin(TAU * run_phase) if is_finite(run_phase) else 0.0
			target = global_transform * (run_left + run_left_pump * swing * r + RUN_LEFT_DROP * (1.0 - r))
		elif _grip.is_two_hand():
			reach_extended_left = _extend(skeleton, _left, support_target)
			# What the stretch could not cover slides toward the firing hand, as before it.
			target = _slide_to_reach(skeleton, _left, support_target, right_target + (support_target - _grip.support_world()))
		var left_pole := _steady_pole(skeleton, _left, to_skeleton * target, Vector3(-out.x, out.y, out.z))
		if _grip.is_two_hand():
			left_pole = _clear_pole(skeleton, _left, to_skeleton * target, left_pole, false)
		elif absf(_turn_left) > 0.5:
			# The support hand let go (a reload's mag hand): the turn it had eased to unwinds the same way, not in one frame.
			var line := (to_skeleton * target - DotHumanoidIk.global_pose(skeleton, _left[0]).origin).normalized()
			_turn_left = lerpf(_turn_left, 0.0, DotViewArmsClear.EASE)
			if line.is_normalized():
				left_pole = left_pole.rotated(line, deg_to_rad(_turn_left))
		left_pole = _slew_pole(_last_pole_left, (to_skeleton * target) - DotHumanoidIk.global_pose(skeleton, _left[0]).origin, left_pole)
		_last_pole_left = left_pole
		DotHumanoidIk.two_bone(skeleton, _left, to_skeleton * target, left_pole, 1.0)
		drawn.append([_grip.support_world() if _grip.is_two_hand() else rest, target, "Middle1.L"])
		hand_gap_left = _gap(skeleton, _left, target)

	if debug_pose:
		if _pose_debug == null:
			_pose_debug = DotViewArmsPoseDebug.new()
			add_child(_pose_debug)
		_pose_debug.draw(skeleton, drawn)


## The share of the unit pole that must lie across the shoulder-to-hand line before [method _steady_pole] leaves it alone.
const POLE_SIDE_MIN := 0.6


## [param pole] kept off the shoulder-to-[param target] line. A hand reaching across the body (ADS, a reload) lines the shoulder-to-hand line up with the sideways pole, the part of the pole across
## that line shrinks to nothing and flips, and the elbow jumped 0.4 m in a frame; below [constant POLE_SIDE_MIN] of the pole across the line, down is mixed in, so the elbow swings down and round instead.
func _steady_pole(skeleton: Skeleton3D, bones: Array[int], target: Vector3, pole: Vector3) -> Vector3:
	var line := target - DotHumanoidIk.global_pose(skeleton, bones[0]).origin
	if line.length() < 0.0001:
		return pole
	var dir := line.normalized()
	var unit := pole.normalized()
	var side := sqrt(maxf(1.0 - unit.dot(dir) * unit.dot(dir), 0.0))
	if side >= POLE_SIDE_MIN:
		return pole
	var down := skeleton.global_transform.basis.inverse() * (global_transform.basis * Vector3.DOWN)
	return unit + down.normalized() * (2.0 * (POLE_SIDE_MIN - side) / POLE_SIDE_MIN)


## The most the elbow turn may change in one frame, degrees.
const MAX_TURN_STEP := 4.0

## The most the elbow direction (the pole across the shoulder-to-hand line) may swing in one frame, degrees. The turn cap above only
## bounds the clearance scan; a hand crossing the shoulder line (an aim-out finishing, a reload) can spin the sideways pole 180 degrees
## in a frame whatever the scan does, and the forearm jumped 0.3 m for one frame, or lay straight out (a T-pose flash).
const MAX_POLE_STEP := 25.0
var _last_pole_right := Vector3.ZERO
var _last_pole_left := Vector3.ZERO


## [param pole] turned about [param line] no further than [constant MAX_POLE_STEP] from where [param last] pointed. Returns the unit sideways part
## (across [param line]) so [param last] next frame holds what the elbow used: a raw pole lying nearly along the line has a tiny sideways part
## that swings a long way for a small move of the line, and the elbow jumped 0.24 m the frame the aim-in finished.
func _slew_pole(last: Vector3, line: Vector3, pole: Vector3) -> Vector3:
	if line.length() < 0.0001 or last == Vector3.ZERO:
		return pole
	var dir := line.normalized()
	var was := last - dir * last.dot(dir)
	var now := pole - dir * pole.dot(dir)
	if was.length() < 0.0001 or now.length() < 0.0001:
		return pole
	var swing := was.signed_angle_to(now, dir)
	if absf(swing) <= deg_to_rad(MAX_POLE_STEP):
		return now.normalized()
	return was.normalized().rotated(dir, signf(swing) * deg_to_rad(MAX_POLE_STEP))


## The elbow direction (skeleton space) for an arm reaching [param target]: [param pole], turned about the
## shoulder-to-hand line to the least-buried of [constant CLEAR_ANGLES] when the arm would pass through the weapon.
## Eased part way each frame, so the elbow swings across rather than snapping.
func _clear_pole(skeleton: Skeleton3D, bones: Array[int], target: Vector3, pole: Vector3, right: bool) -> Vector3:
	var box := _grip.bounds_local().grow(arm_radius) if keep_arms_clear and _grip.bounds_local().has_volume() else AABB()
	var shoulder := DotHumanoidIk.global_pose(skeleton, bones[0]).origin
	var dir := (target - shoulder).normalized()
	if not box.has_volume() or not dir.is_normalized():
		return pole
	var lengths := _arm_lengths(skeleton, bones)
	var to_anchor := _grip.anchor.global_transform.affine_inverse() * skeleton.global_transform
	var up := skeleton.global_transform.basis.inverse() * (global_transform.basis * Vector3.UP)
	if not _native_tried:
		_native_tried = true
		if native_clear and ClassDB.class_exists(&"DotSimViewArms"):
			_native = ClassDB.instantiate(&"DotSimViewArms")
	var prev := _turn_right if right else _turn_left
	var r: PackedFloat64Array
	if _native != null:
		r = _native.clear_pole(shoulder, target, lengths, pole, dir, to_anchor, box, up, prev)
	else:
		r = DotViewArmsClear.scan(shoulder, target, lengths, pole, dir, to_anchor, box, up, prev)
	var turned := Vector3(r[0], r[1], r[2])
	var turn := r[3]
	var depth := r[4]
	# The scan eases a fraction of the gap, a big swing when the best angle flips by 60 degrees; cap the step so the forearm slews rather than jumps.
	if absf(turn - prev) > MAX_TURN_STEP:
		turn = prev + signf(turn - prev) * MAX_TURN_STEP
		turned = pole.rotated(dir, deg_to_rad(turn))
		depth = DotViewArmsClear.arm_depth(to_anchor, box, shoulder, DotViewArmsClear.elbow_for(shoulder, target, lengths, turned), target)
	if right:
		_turn_right = turn
		arm_depth_right = depth
	else:
		_turn_left = turn
		arm_depth_left = depth
	return turned


func _arm_lengths(skeleton: Skeleton3D, bones: Array[int]) -> Vector2:
	var upper := DotHumanoidIk.global_pose(skeleton, bones[0]).origin
	var lower := DotHumanoidIk.global_pose(skeleton, bones[1]).origin
	var wrist := DotHumanoidIk.global_pose(skeleton, bones[2]).origin
	return Vector2((lower - upper).length(), (wrist - lower).length())


## Leans the arms toward whichever hand target (firing or support) is furthest out of its arm's reach, a step at a time, by up to [member max_lean] in all.
func _lean(skeleton: Skeleton3D, figure: DotHumanoidFigure, target: Vector3, support_target: Vector3) -> void:
	if _right.is_empty() or max_lean <= 0.0 or not _fitted:
		_leaned = Vector3.ZERO
		return

	var goals: Array = [[_right, target]]

	if not _left.is_empty() and _grip.is_two_hand() and not _left_hidden() and support_target.is_finite():
		goals.append([_left, support_target])

	var shoulders: Array[Vector3] = []
	var reaches: Array[float] = []
	var to_local := skeleton.global_transform.basis.inverse()

	for goal: Array in goals:
		var bones: Array[int] = goal[0]
		shoulders.append(skeleton.global_transform * DotHumanoidIk.global_pose(skeleton, bones[0]).origin)
		reaches.append(_reach_local(skeleton, bones))

	var lean := Vector3.ZERO

	for step in 8:
		var worst := 0.0
		var toward := Vector3.ZERO

		for i in goals.size():
			var to: Vector3 = (goals[i][1] as Vector3) - (shoulders[i] + lean)
			var local := to_local * to
			var far: float = (local.length() - reaches[i] * LEAN_SLACK) * to.length() / maxf(local.length(), 0.0001)

			if far > worst:
				worst = far
				toward = to.normalized()

		if worst <= 0.001:
			break

		lean += toward * worst * 0.6

		if lean.length() > max_lean:
			lean = lean.normalized() * max_lean
			break

	# Eased only as the lean shrinks: more lean than needed still reaches. A lean that has to grow is taken at once,
	# or the support hand slid off a two-hand grip drawn after a one-hand one (grenade_launcher draw 0.26 m for 4 frames).
	if lean.length() >= _leaned.length():
		_leaned = lean
	else:
		_leaned = _leaned.move_toward(lean, LEAN_RATE * _delta)
	figure.global_position += _leaned

## The point on the segment from [param from] to [param to] nearest [param from] that the arm can reach, or the point nearest the shoulder when none is.
## The point on the segment from [param from] to [param to] nearest [param from] that the arm can reach (or [param to]).
func _slide_to_reach(skeleton: Skeleton3D, bones: Array[int], from: Vector3, to: Vector3) -> Vector3:
	if bones.is_empty():
		return from

	var inverse := skeleton.global_transform.affine_inverse()
	var shoulder := DotHumanoidIk.global_pose(skeleton, bones[0]).origin
	var radius := _reach_local(skeleton, bones)
	var d := inverse * to - inverse * from
	var f := inverse * from - shoulder

	if f.length() <= radius or d.length_squared() < 0.000001:
		return from

	var a := d.length_squared()
	var b := 2.0 * f.dot(d)
	var disc := b * b - 4.0 * a * (f.length_squared() - radius * radius)

	# A line that misses the reach ends at its nearest point to the shoulder, where the hit point would be as the line
	# grazes the reach. Answering [param to] there jumped the hand to the firing hand whenever the sway took the line
	# off the reach, and it flickered between the two from frame to frame.
	if disc < 0.0:
		return from + (to - from) * clampf(-b / (2.0 * a), 0.0, 1.0)

	return from + (to - from) * clampf((-b - sqrt(disc)) / (2.0 * a), 0.0, 1.0)


## Moves the arm's shoulder joint (the upper arm's pose position) out toward [param target] (world) by what the arm is
## still short of it, up to [member reach_extend_max]; the metres moved (figure space), 0 when it reaches already.
func _extend(skeleton: Skeleton3D, bones: Array[int], target: Vector3) -> float:
	if not extend_reach or bones.size() < 3 or not target.is_finite():
		return 0.0
	var to := skeleton.global_transform.affine_inverse() * target - DotHumanoidIk.global_pose(skeleton, bones[0]).origin
	var short := to.length() - _reach_local(skeleton, bones)
	if not (short > 0.0):
		return 0.0
	if reach_extend_max > 0.0:
		short = minf(short, reach_extend_max)
	var parent := skeleton.get_bone_parent(bones[0])
	var basis := DotHumanoidIk.global_pose(skeleton, parent).basis if parent >= 0 else Basis.IDENTITY
	skeleton.set_bone_pose_position(bones[0], skeleton.get_bone_pose_position(bones[0]) + basis.inverse() * (to.normalized() * short))
	_extended.append(bones[0])
	return short


## The firing and support hand poses for [param grip] from [member hand_poses] (the support one empty for one hand):
## its kind's, a rifle's for an unknown kind, a knife's blended toward the throw's pinch by [member throw_grip].
func _grip_hands(grip: DotViewGrip) -> Array:
	var rifle: Dictionary = hand_poses.get(DotViewHandPoses.RIFLE, {})
	var entry: Dictionary = hand_poses.get(grip.kind, rifle)
	var firing: Dictionary = entry.get(&"firing", rifle.get(&"firing", {}))
	if grip.kind == DotViewHandPoses.KNIFE and throw_grip > 0.0:
		var pinch: Dictionary = hand_poses.get(DotViewHandPoses.KNIFE_THROW, {})
		firing = DotViewHandPoses.blend(firing, pinch.get(&"firing", {}), clampf(throw_grip, 0.0, 1.0))
	var support: Dictionary = entry.get(&"support", {})
	if support.is_empty() and grip.is_two_hand():
		support = rifle.get(&"support", {})
	return [firing, support if grip.is_two_hand() else {}]


## A right-hand pose for the left hand: its directions mirrored across the weapon's vertical plane.
static func _mirrored(hand: Dictionary) -> Dictionary:
	var out := hand.duplicate()
	for key in [&"fingers", &"palm"]:
		if out.has(key):
			var v: Vector3 = out[key]
			out[key] = Vector3(-v.x, v.y, v.z)
	return out


## The real hands' world size: life size on the held arms, by [member hand_size] and [member hand_scale] over the mitts' 0.5.
func _hand_world_size() -> float:
	return held_scale * hand_size * hand_scale / 0.5 * global_transform.basis.get_scale().y


## Where each wrist (the kit's finger roots) goes on [param grip], world: [firing, support] (support INF for one hand).
## Real hands put the wrist where the hand's grip point lands on the weapon; the mitts take [member palm_offset].
func wrist_targets(grip: DotViewGrip) -> Array[Vector3]:
	var basis := global_transform.basis
	if not (real_hands and _hands.size() == 2):
		var mirrored := basis * Vector3(-palm_offset.x, palm_offset.y, palm_offset.z)
		return _kept_deep([grip.grip_world() + basis * palm_offset, grip.support_world() + mirrored if grip.is_two_hand() else Vector3.INF])
	var hands := _grip_hands(grip)
	var s := _hand_world_size()
	var forward := grip.forward_world()
	var up := grip.up_world()
	var centre: Vector3 = (hands[0] as Dictionary).get(&"centre", Vector3.ZERO)
	var right := grip.grip_world() - DotViewHandPoses.frame(hands[0], forward, up) * (centre * s)
	var left := Vector3.INF
	if grip.is_two_hand():
		var c: Vector3 = (hands[1] as Dictionary).get(&"centre", Vector3.ZERO)
		left = grip.support_world() - DotViewHandPoses.frame(hands[1], forward, up) * (Vector3(-c.x, c.y, c.z) * s)
	return _kept_deep([right, left])


## [param targets] with each finite one closer to the eye than [member hand_min_depth] moved out along the view's forward to it.
func _kept_deep(targets: Array[Vector3]) -> Array[Vector3]:
	if hand_min_depth <= 0.0:
		return targets
	var to_local := global_transform.affine_inverse()
	var ahead := -global_transform.basis.z.normalized()
	for i in targets.size():
		var p := targets[i]
		if not p.is_finite():
			continue
		var depth := -(to_local * p).z
		if depth < hand_min_depth:
			targets[i] = p + ahead * (hand_min_depth - depth)
	return targets


## Seats the real hands on the solved wrists and closes their fingers; hides them when they are not drawn.
func _place_hands(skeleton: Skeleton3D) -> void:
	if _hands.size() != 2:
		return
	var on := _real_on() and skeleton != null and not _right.is_empty()
	var left_on := on and not _left.is_empty() and not _left_hidden()
	_hands[0].visible = on
	_hands[1].visible = left_on
	if not on:
		return
	var hands := _grip_hands(_grip)
	var s := _hand_world_size()
	var rate := 1.0 if finger_rate <= 0.0 else 1.0 - exp(-finger_rate * _delta)
	var forward := _grip.forward_world()
	var up := _grip.up_world()
	_seat(_hands[0], skeleton, _right[2], hands[0], forward, up, s, rate)
	if not left_on:
		return
	var support: Dictionary = hands[1]
	if support.is_empty():
		# The free hand pumping in a sprint (or shown idle): a fist, knuckles to the view's front.
		support = _mirrored((hand_poses.get(DotViewHandPoses.FISTS, {}) as Dictionary).get(&"firing", {}))
		forward = global_transform.basis * Vector3.FORWARD
		up = global_transform.basis * Vector3.UP
	_seat(_hands[1], skeleton, _left[2], support, forward, up, s, rate)


func _seat(hand: DotViewHand, skeleton: Skeleton3D, wrist: int, pose: Dictionary, forward: Vector3, up: Vector3, s: float, rate: float) -> void:
	var at := skeleton.global_transform * DotHumanoidIk.global_pose(skeleton, wrist).origin
	hand.global_transform = Transform3D(DotViewHandPoses.frame(pose, forward, up) * s, at)
	hand.pose(pose, rate)


func _reach_local(skeleton: Skeleton3D, bones: Array[int]) -> float:
	var upper := DotHumanoidIk.global_pose(skeleton, bones[0]).origin
	var lower := DotHumanoidIk.global_pose(skeleton, bones[1]).origin
	var wrist := DotHumanoidIk.global_pose(skeleton, bones[2]).origin
	return (lower - upper).length() + (wrist - lower).length() - 0.01


func _gap(skeleton: Skeleton3D, bones: Array[int], target: Vector3) -> float:
	return (skeleton.global_transform * DotHumanoidIk.global_pose(skeleton, bones[2]).origin).distance_to(target)


func _clip_of(figure: DotHumanoidFigure) -> Animation:
	var player := figure.body_node().find_child("AnimationPlayer", true, false) as AnimationPlayer
	return player.get_animation(figure.clip) if player != null and player.has_animation(figure.clip) else null


## The arms node, or null before [method build].
func arms() -> Node3D:
	return _arms


## The real hands, [firing, support] ([DotViewHand]), or empty before [method build] or for a factory's own figure.
func hands() -> Array[DotViewHand]:
	var out: Array[DotViewHand] = []
	for hand in _hands:
		out.append(hand)
	return out


## Metres from each wrist (the kit's middle-finger root) to where it goes on [param grip] (the real hands' seat, or
## the grip point plus [member palm_offset] for the mitts), the worst of the two; -1 when the arms are not shown on that grip.
func hand_error(grip: DotViewGrip) -> float:
	if not shown or grip == null or not grip.is_valid() or not (_arms is DotHumanoidFigure):
		return -1.0
	var skeleton := (_arms as DotHumanoidFigure).skeleton()
	if skeleton == null:
		return -1.0
	var targets := wrist_targets(grip)
	var pairs := [["Middle1.R", targets[0]]]
	if grip.is_two_hand():
		pairs.append(["Middle1.L", targets[1]])
	var worst := 0.0
	for pair: Array in pairs:
		var bone := skeleton.find_bone(pair[0])
		if bone < 0:
			return -1.0
		var at := skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin
		worst = maxf(worst, at.distance_to(pair[1]))
	return worst


func describe() -> Dictionary:
	return {"built": _arms != null, "shown": shown, "held": _holding(), "custom": arms_factory.is_valid(), "hidden_bones": _bones.size(),
		"overridden": _override != null, "detailed": _detail_on, "run": snappedf(run, 0.01),
		"real_hands": _real_on(), "left_arm": _arms != null and shown and not _left_hidden(), "reach_extended": snappedf(maxf(reach_extended_right, reach_extended_left), 0.001)}


func _clear() -> void:
	if _arms != null:
		remove_child(_arms)
		_arms.queue_free()
		_arms = null

	for hand in _hands:
		if is_instance_valid(hand):
			remove_child(hand)
			hand.queue_free()
	_hands.clear()
	_extended.clear()
	_two_arm_mesh = null
	_one_arm_mesh = null
	_bones.clear()
	_fingers.clear()
	_detail_on = false
