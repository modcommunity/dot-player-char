class_name DotHumanoidStride
extends RefCounted

## Reads a stride clip's tracks: how far the lower foot travels back through it, and which moment
## of a clip puts the feet where they are now. Pure functions of a skeleton and an animation.

const SAMPLES := 48
## How far above the clip's lowest foot the lower foot is in flight (a run's both-feet-up stretch).
const AIRBORNE_M := 0.06


## Metres over the ground at each of [constant SAMPLES] steps through [param animation]: the
## lower foot's backward travel in the figure's frame, never under a third of the mean so the
## clip does not race through a moment the foot stands still in it, and in flight no less than
## a stance step, so a run's swing plays at the clip's own pace.
static func table_for(animation: Animation, skeleton: Skeleton3D, model: Node3D, to_figure: Transform3D) -> PackedFloat32Array:
	var table := PackedFloat32Array()
	var feet := [skeleton.find_bone("Foot.L"), skeleton.find_bone("Foot.R")]
	if animation == null or feet.has(-1) or animation.length <= 0.0:
		return table
	var prefix := String(model.get_path_to(skeleton))
	var points: Array = []
	for i in SAMPLES + 1:
		var t := animation.length * i / SAMPLES
		points.append(feet.map(func(b: int) -> Vector3: return to_figure * bone_at(skeleton, animation, prefix, b, t).origin))
	var steps := PackedFloat32Array()
	var airborne: Array[bool] = []
	var total := 0.0
	var floor_y := INF
	for p: Array in points:
		floor_y = minf(floor_y, minf(p[0].y, p[1].y))
	var stance := 0.0
	var stance_steps := 0
	for i in range(1, points.size()):
		var k := 0 if points[i][0].y + points[i - 1][0].y < points[i][1].y + points[i - 1][1].y else 1
		var back: float = maxf(0.0, points[i][k].z - points[i - 1][k].z)
		steps.append(back)
		total += back
		airborne.append(minf(points[i][k].y, points[i - 1][k].y) > floor_y + AIRBORNE_M)
		if not airborne[-1] and back > 0.0:
			stance += back
			stance_steps += 1
	var least := total / SAMPLES / 3.0
	# Both feet up: the body flies on at the pace the clip's stance sets, so a run's flight is not raced through.
	var flight := stance / stance_steps if stance_steps > 0 else least
	table.append(0.0)
	for i in steps.size():
		table.append(table[-1] + (maxf(steps[i], flight) if airborne[i] else maxf(steps[i], least)))
	return table


## [param bone]'s skeleton-space transform in [param animation] at [param t], from its tracks or its rest.
static func bone_at(skeleton: Skeleton3D, animation: Animation, prefix: String, bone: int, t: float) -> Transform3D:
	var path := NodePath("%s:%s" % [prefix, skeleton.get_bone_name(bone)])
	var rest := skeleton.get_bone_rest(bone)
	var at := rest.origin
	var turn := rest.basis.get_rotation_quaternion()
	var track := animation.find_track(path, Animation.TYPE_POSITION_3D)
	if track >= 0:
		at = animation.position_track_interpolate(track, t)
	track = animation.find_track(path, Animation.TYPE_ROTATION_3D)
	if track >= 0:
		turn = animation.rotation_track_interpolate(track, t)
	var local := Transform3D(Basis(turn).scaled(rest.basis.get_scale()), at)
	var parent := skeleton.get_bone_parent(bone)
	return local if parent < 0 else bone_at(skeleton, animation, prefix, parent, t) * local


static func distance_at(table: PackedFloat32Array, phase: float) -> float:
	var x := clampf(phase, 0.0, 1.0) * (table.size() - 1)
	var i := mini(int(x), table.size() - 2)
	return lerpf(table[i], table[i + 1], x - i)


static func phase_at(table: PackedFloat32Array, distance: float) -> float:
	var hi := table.bsearch(distance)
	hi = clampi(hi, 1, table.size() - 1)
	var span := table[hi] - table[hi - 1]
	var x := float(hi - 1) + (clampf((distance - table[hi - 1]) / span, 0.0, 1.0) if span > 0.0 else 0.0)
	return x / (table.size() - 1)


## The feet's figure-frame positions in the pose on screen now.
static func feet_now(skeleton: Skeleton3D, to_figure: Transform3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	for foot in [&"Foot.L", &"Foot.R"]:
		var b := skeleton.find_bone(foot)
		if b < 0:
			return PackedVector3Array()
		out.append(to_figure * (skeleton.get_bone_global_pose(b).origin))
	return out


## The time in [param animation] whose feet sit closest to [param feet], so a clip entered there carries the planted (lower) foot on as it was.
static func matching_time(animation: Animation, skeleton: Skeleton3D, model: Node3D, to_figure: Transform3D, feet: PackedVector3Array) -> float:
	var prefix := String(model.get_path_to(skeleton))
	var ids := [skeleton.find_bone("Foot.L"), skeleton.find_bone("Foot.R")]
	var low := 0 if feet[0].y <= feet[1].y else 1
	var best := 0.0
	var least := INF
	for i in SAMPLES * 2:
		var t := animation.length * i / (SAMPLES * 2)
		var at: Array[Vector3] = [to_figure * bone_at(skeleton, animation, prefix, ids[0], t).origin, to_figure * bone_at(skeleton, animation, prefix, ids[1], t).origin]
		# The planted foot must be the clip's lower one too: a run's flight would lift it off the ground.
		if (at[0].y <= at[1].y) != (low == 0):
			continue
		var cost := 0.0
		for k in 2:
			cost += at[k].distance_squared_to(feet[k]) * (20.0 if k == low else 1.0)
		if cost < least:
			least = cost
			best = t
	return best
