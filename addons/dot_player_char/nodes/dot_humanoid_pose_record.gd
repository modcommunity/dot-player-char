class_name DotHumanoidPoseRecord
extends RefCounted

## A figure's drawn pose as a flat float array, for replay: [bone count, the model's basis and
## origin (12), every bone's rotation (4 each), the root bones' positions (3 each)].


## The pose as drawn now, for a replay: bone count, the model's transform, every bone's rotation
## and the root bones' positions. Includes overlays, aim, swim tilt; [method apply] puts it back.
static func record(skeleton: Skeleton3D, model: Node3D) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if skeleton == null or model == null:
		return out
	var n := skeleton.get_bone_count()
	var t := model.transform
	out.append(n)
	for v: Vector3 in [t.basis.x, t.basis.y, t.basis.z, t.origin]:
		out.append_array([v.x, v.y, v.z])
	for i in n:
		var q := skeleton.get_bone_pose_rotation(i)
		out.append_array([q.x, q.y, q.z, q.w])
	for i in _root_bones(skeleton):
		var p := skeleton.get_bone_pose_position(i)
		out.append_array([p.x, p.y, p.z])
	return out


## Draws the pose between two [method pose_record]s, [param alpha] of the way to [param b]. False
## (and nothing changed) when either is from another skeleton.
static func apply(skeleton: Skeleton3D, model: Node3D, a: PackedFloat32Array, b: PackedFloat32Array, alpha: float) -> bool:
	if skeleton == null or model == null or a.is_empty() or a.size() != b.size():
		return false
	var n := skeleton.get_bone_count()
	var roots := _root_bones(skeleton)
	if int(a[0]) != n or a.size() != 13 + n * 4 + roots.size() * 3:
		return false
	var at := func(r: PackedFloat32Array, i: int) -> Vector3: return Vector3(r[i], r[i + 1], r[i + 2])
	var ta := Transform3D(Basis(at.call(a, 1), at.call(a, 4), at.call(a, 7)), at.call(a, 10))
	var tb := Transform3D(Basis(at.call(b, 1), at.call(b, 4), at.call(b, 7)), at.call(b, 10))
	model.transform = ta.interpolate_with(tb, alpha)
	for i in n:
		var k := 13 + i * 4
		var qa := Quaternion(a[k], a[k + 1], a[k + 2], a[k + 3])
		var qb := Quaternion(b[k], b[k + 1], b[k + 2], b[k + 3])
		skeleton.set_bone_pose_rotation(i, qa.normalized().slerp(qb.normalized(), alpha))
	var k := 13 + n * 4
	for i in roots:
		skeleton.set_bone_pose_position(i, (at.call(a, k) as Vector3).lerp(at.call(b, k), alpha))
		k += 3
	return true


## Bones whose position a clip moves: those without a parent and their children (the hips).
static func _root_bones(skeleton: Skeleton3D) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in skeleton.get_bone_count():
		var parent := skeleton.get_bone_parent(i)
		if parent < 0 or skeleton.get_bone_parent(parent) < 0:
			out.append(i)
	return out
