class_name DotHumanoidPoseMath
extends RefCounted

## Skeleton-space pose arithmetic the synthesised clips of [DotHumanoidClips] are built from: local and global bone transforms, subtree moves, leg placement.


## Lays one leg along [param thigh_dir] from the hip and [param shin_dir] from the knee (both in
## skeleton space), and puts the foot (and the knee's pole target) where the shin now ends,
## [param shin] from the knee (measured from the pose when 0).
static func _place_leg(g: Array, skeleton: Skeleton3D, side: String, thigh_dir: Vector3, shin_dir: Vector3, shin: float = 0.0) -> void:
	var thigh := skeleton.find_bone("UpperLeg" + side)
	var knee := skeleton.find_bone("LowerLeg" + side)
	var foot := skeleton.find_bone("Foot" + side)
	if thigh < 0 or knee < 0 or foot < 0:
		return
	var shin_was: Vector3 = g[foot].origin - g[knee].origin
	if shin <= 0.0:
		shin = shin_was.length()
	var knee_was: Vector3 = g[knee].origin
	var foot_was: Vector3 = g[foot].origin
	# The foot does not follow the leg on this rig, so where the shin points is carried by hand:
	# the thigh's turn swings it round with the knee.
	var turned := _turn_subtree(g, skeleton, thigh, g[knee].origin - g[thigh].origin, thigh_dir)
	var _k := _turn_subtree(g, skeleton, knee, turned * shin_was, shin_dir)
	var ankle: Vector3 = g[knee].origin + shin_dir.normalized() * shin
	_move_subtree(g, skeleton, foot, Transform3D(Basis.IDENTITY, ankle - foot_was))
	var pole := skeleton.find_bone("PoleTarget" + side)
	if pole >= 0:
		_move_subtree(g, skeleton, pole, Transform3D(Basis.IDENTITY, g[knee].origin - knee_was))


## Turns bone [param bone] (and everything under it) about its own origin so that
## [param from_dir] points along [param to_dir]: the shortest turn, in skeleton space. Returns it.
static func _turn_subtree(g: Array, skeleton: Skeleton3D, bone: int, from_dir: Vector3, to_dir: Vector3) -> Basis:
	var a := from_dir.normalized()
	var b := to_dir.normalized()
	if a.is_zero_approx() or b.is_zero_approx() or a.is_equal_approx(b):
		return Basis.IDENTITY
	var turn := Basis(Quaternion(a, b))
	_move_subtree(g, skeleton, bone, _about(g[bone].origin, turn))
	return turn


## Points bone [param bone] at its child [param child] along [param to_dir].
static func _point_bone(g: Array, skeleton: Skeleton3D, bone: String, child: String, to_dir: Vector3) -> void:
	var i := skeleton.find_bone(bone)
	var j := skeleton.find_bone(child)
	if i < 0 or j < 0:
		return
	var _t := _turn_subtree(g, skeleton, i, g[j].origin - g[i].origin, to_dir)


## The local pose of every bone of [param skeleton] in [param animation] at [param time]: the
## clip's keys where it has them, the rest where it does not. Indexed by bone.
static func _locals(animation: Animation, time: float, skeleton: Skeleton3D) -> Array:
	var prefix := _skeleton_prefix(animation)
	var out := []
	for i in skeleton.get_bone_count():
		var rest := skeleton.get_bone_rest(i)
		var path := NodePath("%s:%s" % [prefix, skeleton.get_bone_name(i)])
		var rt := animation.find_track(path, Animation.TYPE_ROTATION_3D)
		var pt := animation.find_track(path, Animation.TYPE_POSITION_3D)
		var st := animation.find_track(path, Animation.TYPE_SCALE_3D)
		var q := rest.basis.get_rotation_quaternion() if rt < 0 else animation.rotation_track_interpolate(rt, time)
		var p := rest.origin if pt < 0 else animation.position_track_interpolate(pt, time)
		var s := rest.basis.get_scale() if st < 0 else animation.scale_track_interpolate(st, time)
		out.append(Transform3D(Basis(q).scaled(s), p))
	return out


static func _globals(locals: Array, skeleton: Skeleton3D) -> Array:
	var out := []
	out.resize(locals.size())
	for i in locals.size():
		_global_of(i, locals, skeleton, out)
	return out


static func _global_of(i: int, locals: Array, skeleton: Skeleton3D, out: Array) -> Transform3D:
	if out[i] != null:
		return out[i]
	var parent := skeleton.get_bone_parent(i)
	var g: Transform3D = locals[i] if parent < 0 else _global_of(parent, locals, skeleton, out) * (locals[i] as Transform3D)
	out[i] = g
	return g


static func _back_to_locals(globals: Array, skeleton: Skeleton3D) -> Array:
	var out := []
	for i in globals.size():
		var parent := skeleton.get_bone_parent(i)
		out.append(globals[i] if parent < 0 else (globals[parent] as Transform3D).affine_inverse() * (globals[i] as Transform3D))
	return out


## [param by] applied to bone [param bone] and everything under it, in skeleton space.
static func _move_subtree(globals: Array, skeleton: Skeleton3D, bone: int, by: Transform3D) -> void:
	for i in globals.size():
		var j := i
		while j >= 0 and j != bone:
			j = skeleton.get_bone_parent(j)
		if j == bone:
			globals[i] = by * (globals[i] as Transform3D)


## A turn [param basis] about the point [param at].
static func _about(at: Vector3, basis: Basis) -> Transform3D:
	return Transform3D(Basis.IDENTITY, at) * Transform3D(basis, Vector3.ZERO) * Transform3D(Basis.IDENTITY, -at)


## One key per bone at [param time]: rotation and position from [param locals], on the tracks
## [param like] uses (same node path), so the made clip binds where the kit's do.
static func _write_pose(made: Animation, like: Animation, locals: Array, skeleton: Skeleton3D, time: float) -> void:
	var prefix := _skeleton_prefix(like)
	for i in locals.size():
		var path := NodePath("%s:%s" % [prefix, skeleton.get_bone_name(i)])
		var local: Transform3D = locals[i]
		var rt := made.add_track(Animation.TYPE_ROTATION_3D)
		made.track_set_path(rt, path)
		var _r := made.rotation_track_insert_key(rt, time, local.basis.get_rotation_quaternion().normalized())
		var pt := made.add_track(Animation.TYPE_POSITION_3D)
		made.track_set_path(pt, path)
		var _p := made.position_track_insert_key(pt, time, local.origin)


## The node path in front of the bone names in [param animation]'s tracks
## (`CharacterArmature/Skeleton3D`).
static func _skeleton_prefix(animation: Animation) -> String:
	for t in animation.get_track_count():
		var path := animation.track_get_path(t)
		if path.get_subname_count() > 0:
			return String(path.get_concatenated_names())
	return "Skeleton3D"
