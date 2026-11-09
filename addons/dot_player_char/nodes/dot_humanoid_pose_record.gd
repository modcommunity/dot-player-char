class_name DotHumanoidPoseRecord
extends RefCounted

## A figure's drawn pose as a flat float array, for replay: [bone count, the model's basis and
## origin (12), every bone's rotation (4 each), the root bones' positions (3 each)].

## Meta on the skeleton holding [bone count, root bones], so they are worked out once.
const ROOTS_META := &"_dot_pose_record_roots"


## The pose as drawn now, for a replay: bone count, the model's transform, every bone's rotation
## and the root bones' positions. Includes overlays, aim, swim tilt; [method apply] puts it back.
static func record(skeleton: Skeleton3D, model: Node3D) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if skeleton == null or model == null:
		return out
	var n := skeleton.get_bone_count()
	var roots := _root_bones(skeleton)
	# Sized once and written in place: a killcam records every drawn body many times a second, and the
	# append_array of a fresh Array per bone was most of its cost.
	out.resize(13 + n * 4 + roots.size() * 3)
	out[0] = n
	var t := model.transform
	out[1] = t.basis.x.x
	out[2] = t.basis.x.y
	out[3] = t.basis.x.z
	out[4] = t.basis.y.x
	out[5] = t.basis.y.y
	out[6] = t.basis.y.z
	out[7] = t.basis.z.x
	out[8] = t.basis.z.y
	out[9] = t.basis.z.z
	out[10] = t.origin.x
	out[11] = t.origin.y
	out[12] = t.origin.z
	var k := 13
	for i in n:
		var q := skeleton.get_bone_pose_rotation(i)
		out[k] = q.x
		out[k + 1] = q.y
		out[k + 2] = q.z
		out[k + 3] = q.w
		k += 4
	for i in roots:
		var p := skeleton.get_bone_pose_position(i)
		out[k] = p.x
		out[k + 1] = p.y
		out[k + 2] = p.z
		k += 3
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
	var ta := Transform3D(Basis(_v3(a, 1), _v3(a, 4), _v3(a, 7)), _v3(a, 10))
	var tb := Transform3D(Basis(_v3(b, 1), _v3(b, 4), _v3(b, 7)), _v3(b, 10))
	model.transform = ta.interpolate_with(tb, alpha)
	for i in n:
		var k := 13 + i * 4
		var qa := Quaternion(a[k], a[k + 1], a[k + 2], a[k + 3])
		var qb := Quaternion(b[k], b[k + 1], b[k + 2], b[k + 3])
		skeleton.set_bone_pose_rotation(i, qa.normalized().slerp(qb.normalized(), alpha))
	var k := 13 + n * 4
	for i in roots:
		skeleton.set_bone_pose_position(i, _v3(a, k).lerp(_v3(b, k), alpha))
		k += 3
	return true


static func _v3(r: PackedFloat32Array, i: int) -> Vector3:
	return Vector3(r[i], r[i + 1], r[i + 2])


## Bones whose position a clip moves: those without a parent and their children (the hips). Worked out once per
## skeleton and bone count, and kept on the skeleton (a runtime meta, never saved: records are runtime only).
static func _root_bones(skeleton: Skeleton3D) -> PackedInt32Array:
	var n := skeleton.get_bone_count()
	var kept: Variant = skeleton.get_meta(ROOTS_META, null)
	if kept is Array and int(kept[0]) == n:
		return kept[1]
	var out := PackedInt32Array()
	for i in n:
		var parent := skeleton.get_bone_parent(i)
		if parent < 0 or skeleton.get_bone_parent(parent) < 0:
			out.append(i)
	skeleton.set_meta(ROOTS_META, [n, out])
	return out
