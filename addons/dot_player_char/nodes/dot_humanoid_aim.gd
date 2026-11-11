class_name DotHumanoidAim
extends RefCounted

## The view pitch bent into a figure's waist and chest, and its arms when it holds a gun.


## Bends the waist and chest by [member pitch] about the figure's left-to-right axis, after the clip
## and overlays. Not while down, dead, swimming or climbing, and only on bones the clip keys: an
## unkeyed bone keeps last frame's pose and the bend would accumulate.
static func apply(skeleton: Skeleton3D, model: Node3D, animation: Animation, to_figure: Transform3D, arm: bool, pitch: float, sprint_blend: float) -> void:
	apply_plan(skeleton, plan(skeleton, model, animation, arm), to_figure, pitch, sprint_blend)


## The bones [method apply] bends for [param animation]: per keyed bone its index, its parent, its
## share and whether it is the arm, flat. Depends only on the rig and the clip, so a figure keeps one
## per clip ([method DotHumanoidFigure._apply_aim]) instead of a path format and a track search per bone per frame.
static func plan(skeleton: Skeleton3D, model: Node3D, animation: Animation, arm: bool) -> Array:
	var out := []
	var prefix := String(model.get_path_to(skeleton))
	var shares: Dictionary = DotHumanoidClips.AIM_BONES
	if arm:
		shares = shares.merged(DotHumanoidClips.AIM_ARM)
	for bone: String in shares:
		var i := skeleton.find_bone(bone)
		if i < 0 or animation.find_track(NodePath("%s:%s" % [prefix, bone]), Animation.TYPE_ROTATION_3D) < 0:
			continue
		out.append_array([i, skeleton.get_bone_parent(i), float(shares[bone]), DotHumanoidClips.AIM_ARM.has(bone)])
	return out


## [method apply] with a [method plan] made earlier.
static func apply_plan(skeleton: Skeleton3D, bones: Array, to_figure: Transform3D, pitch: float, sprint_blend: float) -> void:
	# Figure right in skeleton space. A collapsed basis (a figure popping in or out) has no inverse:
	# keep the clip's pose rather than hand Quaternion a zero or NaN axis.
	var axis := Vector3.ZERO
	if absf(to_figure.basis.determinant()) > 1e-9:
		axis = (to_figure.basis.inverse() * Vector3.RIGHT).normalized()
	if not axis.is_finite() or axis.length_squared() < 0.5:
		return
	# Parents are read before any bone turns; turns about one axis commute, so each share goes on
	# through the parent's unturned frame: local' = P^-1 * turn * P * local. Use local poses up the
	# chain, not get_bone_global_pose, which is last frame's (with last frame's bend in it).
	var parents: Array[Quaternion] = []
	for k in range(0, bones.size(), 4):
		parents.append(DotHumanoidIk.chain_rotation(skeleton, bones[k + 1]))
	for n in parents.size():
		var k := n * 4
		var i: int = bones[k]
		var share: float = bones[k + 2]
		var p := parents[n]
		var drop := -DotHumanoidFigure.SPRINT_DROP * sprint_blend if bones[k + 3] else 0.0
		var turn := Quaternion(axis, pitch * share + drop)
		skeleton.set_bone_pose_rotation(i, (p.inverse() * turn * p * skeleton.get_bone_pose_rotation(i)).normalized())
