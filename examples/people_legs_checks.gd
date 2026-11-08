class_name DotPeopleLegsChecks
extends RefCounted

## The suite's legs sections (heading, backward, wall feet, first-person body), split out to keep
## people_selftest under the file-size gate. Reports through the suite's `_section` and `_check`.

const DT := 1.0 / 60.0

var suite: Node


func _init(host: Node) -> void:
	suite = host


func run() -> void:
	suite._section("legs follow the way you move")
	await _check_walk(Vector3(0, 0, 1.6), "backward")
	await _check_walk(Vector3(1.6, 0, 0), "strafing right")
	await _check_walk(Vector3(0, 0, -1.6), "forward")
	await _check_wall()
	suite._section("your own body in first person")
	await _check_own_view()


func _figure() -> DotHumanoidFigure:
	var g := DotHumanoidFigure.new()
	suite.add_child(g)
	g.build(DotHumanoidLook.stock(9), 1.8)
	return g


static func _yaw_of(basis: Basis) -> float:
	var z := basis.z
	return atan2(z.x, z.z)


## Carried at [param velocity] (world), the foot it stands on stays put and the hips turn toward
## the way it goes while the chest keeps facing -Z.
func _check_walk(velocity: Vector3, who: String) -> void:
	var g := _figure()
	var sk := g.skeleton()
	var feet := [sk.find_bone("Foot.L"), sk.find_bone("Foot.R")]
	var ground := INF
	var start: Array = []
	var worst := 0.0
	var stances := 0
	var turn := 0.0
	var rates: Array[float] = []
	for i in 150:
		g.position += velocity * DT
		g.set_motion({"on_floor": true, "velocity": velocity})
		g.animate(velocity.length(), DT)
		sk.force_update_all_bone_transforms()
		rates.append(g.body_node().get_node("AnimationPlayer").speed_scale)
		var at: Array = feet.map(func(b: int) -> Vector3: return sk.global_transform * sk.get_bone_global_pose(b).origin)
		var k := 0 if at[0].y < at[1].y else 1
		ground = minf(ground, at[k].y)
		if i == 120:
			var hips := sk.global_basis * sk.get_bone_global_pose(sk.find_bone("Body")).basis
			var chest := sk.global_basis * sk.get_bone_global_pose(sk.find_bone("Torso")).basis
			turn = rad_to_deg(wrapf(_yaw_of(hips) - _yaw_of(chest), -PI, PI))
		if i < 30 or at[k].y > ground + 0.02 or (not start.is_empty() and start[0] != k):
			start.clear()
			continue
		if start.is_empty():
			start = [k, at[k], i]
		elif (i - int(start[2])) * DT >= 0.1:
			var moved: Vector3 = at[k] - start[1]
			worst = maxf(worst, Vector2(moved.x, moved.z).length() / ((i - int(start[2])) * DT))
			stances += 1
	var want_turn := rad_to_deg(g.legs.twist)
	suite._check(stances > 10 and worst < 0.3, "%s: the planted foot stays put (%.2f m/s at most over %d windows)" % [who, worst, stances])
	var back := velocity.z > 1.0
	var expect := -DotHumanoidLegs.MAX_TWIST if velocity.x > 1.0 else 0.0
	suite._check(g.legs.backward == back and (rates.slice(60).all(func(r: float) -> bool: return r <= 0.0) if back else rates.slice(60).all(func(r: float) -> bool: return r >= 0.0)),
		"%s: the stride clip plays %s (backward %s)" % [who, "in reverse" if back else "forward", g.legs.backward])
	suite._check(is_equal_approx(g.legs.twist, expect) and absf(absf(turn) - absf(want_turn)) < 12.0,
		"%s: the hips turn %.0f degrees from the chest (twist %.0f, wanted %.0f)" % [who, turn, want_turn, rad_to_deg(expect)])
	g.queue_free()
	await suite.get_tree().process_frame


## Running along a wall at x = -0.45 (the runner's left), the wall-side foot is on the wall plane while it
## carries the body and swings off it between steps (the far one cannot reach upright; a game rolls the body).
func _check_wall() -> void:
	var g := _figure()
	var sk := g.skeleton()
	var wall := Plane(Vector3.RIGHT, -0.45)
	var seen: Array[Vector2] = []
	for i in 140:
		g.position += Vector3(0, 0, -5.0) * DT
		g.set_motion({"on_floor": false, "vertical": 0.0, "wall_running": true, "wall": wall, "velocity": Vector3(0, 0, -5.0)})
		g.animate(5.0, DT)
		await suite.get_tree().process_frame
		if i >= 20:
			var ankle: Vector3 = DotHumanoidLegs.ankles(sk)[0]
			seen.append(Vector2(ankle.y, absf(wall.distance_to(ankle))))
	var low: float = seen.map(func(v: Vector2) -> float: return v.x).min()
	var planted := seen.filter(func(v: Vector2) -> bool: return v.x < low + 0.05)
	var worst: float = planted.map(func(v: Vector2) -> float: return v.y).max()
	var swing: float = seen.map(func(v: Vector2) -> float: return v.y).max()
	suite._check(planted.size() >= 5 and worst < 0.02 and swing > 0.05,
		"wall run: the wall-side foot is on the wall plane in %d stance frames (%.3f m at most) and swings off (%.3f m)" % [planted.size(), worst, swing])
	g.set_motion({"on_floor": true, "velocity": Vector3.ZERO})
	for i in 30:
		g.animate(0.0, DT)
		await suite.get_tree().process_frame
	var ankles := DotHumanoidLegs.ankles(sk)
	suite._check(ankles.all(func(a: Vector3) -> bool: return absf(wall.distance_to(a)) > 0.2), "off the wall the feet are under the body again")
	g.queue_free()


func _check_own_view() -> void:
	var g := _figure()
	var sk := g.skeleton()
	var scale_of := func(bone: String) -> float: return sk.get_bone_pose_scale(sk.find_bone(bone)).x
	g.first_person = DotHumanoidOwnView.LEGS
	g.set_motion({"on_floor": true})
	for i in 5:
		g.animate(0.0, DT)
	suite._check(scale_of.call("Abdomen") < 0.01 and scale_of.call("Head") < 0.01 and scale_of.call("UpperLeg.L") > 0.9, "legs: everything from the belly up is gone, the legs are not")
	var shadow: Skeleton3D = g._own.shadow()
	suite._check(g.mesh().cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and shadow != null and shadow.get_bone_pose_scale(shadow.find_bone("Abdomen")).x > 0.9,
		"legs: the whole person's shadow comes from a shadow-only copy")
	var low: float = DotHumanoidLegs.ankles(sk).map(func(a: Vector3) -> float: return a.y).min()
	suite._check(absf(low) < 0.12, "legs: standing, the ankles are at the feet's origin (%.3f m)" % low)
	var hip_y := func() -> float:
		return (sk.global_transform * DotHumanoidIk.global_pose(sk, sk.find_bone("UpperLeg.L")).origin).y
	var stand_hip: float = hip_y.call()
	var leg: float = stand_hip - low
	suite._check(leg > 0.2 * g.height and leg < 0.65 * g.height, "legs: standing, hip to ankle is %.2f m of a %.2f m person (0.2 to 0.65; short cartoon legs)" % [leg, g.height])
	g.set_motion({"on_floor": true, "crouched": true})
	for i in 30:
		g.animate(0.0, DT)
	var crouch_low: float = DotHumanoidLegs.ankles(sk).map(func(a: Vector3) -> float: return a.y).min()
	var crouch_hip: float = hip_y.call()
	suite._check(absf(crouch_low) < 0.12 and crouch_hip < stand_hip - 0.02, "legs: crouched, the feet stay on the floor (%.3f m) and the hips drop (%.2f to %.2f m)" % [crouch_low, stand_hip, crouch_hip])
	g.set_motion({"on_floor": true})
	for i in 30:
		g.animate(0.0, DT)
	var back_at := func(pitch_degrees: float) -> float:
		g.aim(deg_to_rad(pitch_degrees))
		g.animate(0.0, DT)
		return g.body_node().position.z
	var level: float = back_at.call(0.0)
	var down: float = back_at.call(-89.0)
	var want := g.own_look_down_back * g.height / 1.8
	suite._check(absf(level) < 0.001 and want > 0.1 and absf(down - want) < 0.01,
		"legs: looking straight down the body trails %.2f m behind the eye (want %.2f), level it does not (%.3f)" % [down, want, level])
	g.first_person = DotHumanoidOwnView.THIRD
	var third: float = back_at.call(-89.0)
	g.first_person = DotHumanoidOwnView.LEGS
	suite._check(absf(third) < 0.001, "third person looking down: the body stays under the eye (%.3f)" % third)
	back_at.call(0.0)
	g.first_person = DotHumanoidOwnView.BODY
	g.animate(0.0, DT)
	suite._check(scale_of.call("Shoulder.L") < 0.01 and scale_of.call("Neck") < 0.01 and scale_of.call("Abdomen") > 0.9, "body: the head, neck and arms are gone, the chest is not")
	g.first_person = DotHumanoidOwnView.THIRD
	g.animate(0.0, DT)
	await suite.get_tree().process_frame
	suite._check(scale_of.call("Abdomen") > 0.9 and scale_of.call("Head") > 0.9 and g._own.shadow() == null and g.mesh().cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON,
		"third person: whole again, its own shadow, no copy")
	g.hide_head = true
	suite._check(scale_of.call("Head") < 0.01 and scale_of.call("Neck") > 0.9, "hide_head alone still takes only the head")
	g.hide_head = false
	await _check_cl_legs(g)
	g.queue_free()


## `cl_legs` off: first person draws nothing of the body (no shrunk bones, cap or shadow copy), only a shadow; on again brings the legs back.
func _check_cl_legs(g: DotHumanoidFigure) -> void:
	var sk := g.skeleton()
	var store := DotCLegsFake.new()
	DotOwnBodySetting.follow(g, store)
	g.first_person = DotHumanoidOwnView.LEGS
	g.animate(0.0, DT)
	suite._check(g.own_body_shown and sk.get_bone_pose_scale(sk.find_bone("Abdomen")).x < 0.01 and g._own.shadow() != null, "cl_legs on (default): the legs view is built")
	store.set_value(false)
	g.animate(0.0, DT)
	suite._check(not g.own_body_shown and sk.get_bone_pose_scale(sk.find_bone("Abdomen")).x > 0.9 and g._own.shadow() == null and g.mesh().cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY,
		"cl_legs off: nothing drawn, no shrunk bones or shadow copy, the shadow stays")
	store.set_value(true)
	g.animate(0.0, DT)
	suite._check(sk.get_bone_pose_scale(sk.find_bone("Abdomen")).x < 0.01 and g._own.shadow() != null, "cl_legs on again: the legs are back")
	g.first_person = DotHumanoidOwnView.THIRD
	g.animate(0.0, DT)
	DotOwnBodySetting.follow(g, store)
	suite._check(store.changed.get_connections().size() == 1, "following the same figure and settings twice connects once")
	var plain := DotCLegsPlain.new()
	plain.value = false
	DotOwnBodySetting.follow(g, plain)
	suite._check(not g.own_body_shown, "a settings object without a changed signal still applies")
	g.own_body_shown = true
	_check_first_person_body()


## The older first-person path (head shadow-only, body pulled back) obeys the same setting.
func _check_first_person_body() -> void:
	var body := Node3D.new()
	var chest := MeshInstance3D.new()
	chest.name = "Chest"
	chest.mesh = BoxMesh.new()
	body.add_child(chest)
	var head := MeshInstance3D.new()
	head.name = "Head"
	head.mesh = BoxMesh.new()
	body.add_child(head)
	suite.add_child(body)
	var fp := DotPlayerFirstPersonBody.new()
	var store := DotCLegsFake.new()
	DotOwnBodySetting.follow(fp, store)
	fp.apply(body)
	suite._check(chest.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON and is_equal_approx(body.position.z, fp.back_offset), "first-person body, cl_legs on: body drawn and pulled back")
	store.set_value(false)
	suite._check(chest.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY and body.position == Vector3.ZERO, "first-person body, cl_legs off: shadow only, not pulled back")
	store.set_value(true)
	suite._check(chest.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON and is_equal_approx(body.position.z, fp.back_offset), "first-person body, cl_legs on again: drawn")
	fp.restore()
	body.free()


class DotCLegsPlain extends RefCounted:
	var value := true

	func get_bool(_key: StringName, _fallback: bool = false) -> bool:
		return value


class DotCLegsFake extends RefCounted:
	signal changed(key: StringName, value: Variant, reason: StringName)
	var value := true

	func get_bool(_key: StringName, _fallback: bool = false) -> bool:
		return value

	func set_value(v: bool) -> void:
		value = v
		changed.emit(DotOwnBodySetting.KEY, v, &"user")
