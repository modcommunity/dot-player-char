class_name DotViewArmsClear
extends RefCounted

## The view arms' elbow clearance scan, free of nodes: which turn of the elbow pole about the shoulder-to-hand line keeps
## the arm out of the weapon. [DotPlayerViewArms] runs it per arm per frame; dot-sim's [code]DotSimViewArms[/code]
## ("arms" module) is the native twin, bit-identical (dot-sim's selftest compares the two on seeded inputs), and this
## script is the fallback where the extension is not loaded (web, a build without it).

## Turns tried, degrees; ties go to the earlier (smaller) one.
const ANGLES: Array[float] = [0.0, 15.0, -15.0, 30.0, -30.0, 45.0, -45.0, 60.0, -60.0, 80.0, -80.0]
## The share of the forearm, from the hand end, left out of the depth (a hand on the grip is meant to touch it).
const HAND_FREE := 0.35
## How far each frame's turn eases toward the best angle.
const EASE := 0.35


## The eased turn for an arm: [param pole] turned about [param dir] (the unit shoulder-to-[param target] line) part way
## from [param prev_turn] toward the least-buried angle of [constant ANGLES], scored by depth into [param box]
## (anchor space, through [param to_anchor]), a small cost per degree, and a cost for an elbow above the shoulder
## along [param up]. All points in skeleton space; [param lengths] are the upper arm and forearm.
## Returns [turned.x, turned.y, turned.z, turn (degrees), depth of the turned arm (metres)].
static func scan(shoulder: Vector3, target: Vector3, lengths: Vector2, pole: Vector3, dir: Vector3, to_anchor: Transform3D,
		box: AABB, up: Vector3, prev_turn: float) -> PackedFloat64Array:
	var best := 0.0
	var best_score := INF
	for angle in ANGLES:
		var elbow := elbow_for(shoulder, target, lengths, pole.rotated(dir, deg_to_rad(angle)))
		# Ties go to the smaller turn; an elbow raised above the shoulder crosses the view, so it scores worse.
		var score := arm_depth(to_anchor, box, shoulder, elbow, target) + absf(angle) * 0.00005 + (0.05 if (elbow - shoulder).dot(up) > 0.0 else 0.0)
		if score < best_score - 0.002:
			best_score = score
			best = angle
	var turn := lerpf(prev_turn, best, EASE)
	var turned := pole.rotated(dir, deg_to_rad(turn))
	var depth := arm_depth(to_anchor, box, shoulder, elbow_for(shoulder, target, lengths, turned), target)
	return PackedFloat64Array([turned.x, turned.y, turned.z, turn, depth])


## Where [method DotHumanoidIk.two_bone] puts the elbow for this target and pole, without posing anything.
static func elbow_for(shoulder: Vector3, target: Vector3, lengths: Vector2, pole: Vector3) -> Vector3:
	var la := lengths.x
	var lb := lengths.y
	var to_target := target - shoulder
	if la < 0.0001 or lb < 0.0001 or to_target.length() < 0.0001:
		return shoulder
	var reach := clampf(to_target.length(), absf(la - lb) + 0.001, la + lb - 0.001)
	var dir := to_target.normalized()
	var along := (la * la - lb * lb + reach * reach) / (2.0 * reach)
	var side := pole - dir * pole.dot(dir)
	side = side.normalized() if side.length_squared() > 0.000001 else Vector3.UP
	return shoulder + dir * along + side * sqrt(maxf(la * la - along * along, 0.0))


## How deep the upper arm and the forearm (all but its hand end) go into [param box] (anchor space), metres.
static func arm_depth(to_anchor: Transform3D, box: AABB, shoulder: Vector3, elbow: Vector3, target: Vector3) -> float:
	var s := to_anchor * shoulder
	var e := to_anchor * elbow
	var h := to_anchor * target.lerp(elbow, HAND_FREE)
	# Most elbows miss the weapon: two native segment tests rule that out before the eighteen samples.
	if box.intersects_segment(s, e) == null and box.intersects_segment(e, h) == null:
		return 0.0
	var deepest := 0.0
	for i in 9:
		var t := i / 8.0
		deepest = maxf(deepest, maxf(depth_in(box, s.lerp(e, t)), depth_in(box, e.lerp(h, t))))
	return deepest


## How far [param q] is inside [param box] from its nearest face, or 0 outside.
static func depth_in(box: AABB, q: Vector3) -> float:
	if not box.has_point(q):
		return 0.0
	var low := q - box.position
	var high := box.end - q
	return minf(minf(minf(low.x, high.x), minf(low.y, high.y)), minf(low.z, high.z))
