class_name DotHumanoidFrames
extends RefCounted

## Measures a figure's body: where its hand sits, how tall its mesh is, and the stand-in capsule.


## The hand's frame in its bone's, from the held-gun pose: forward is the figure's forward and up
## is up there, so a weapon model made pointing down -Z points where the gun clips aim.
static func hand_frame(skeleton: Skeleton3D, anim: AnimationPlayer, model: Node3D, to_figure: Transform3D) -> Transform3D:
	var bone := skeleton.find_bone(DotHumanoidFigure.HAND_BONE)
	var library := anim.get_animation_library(&"")
	var gun := library.get_animation(DotHumanoidClips.IDLE_GUN) if library != null and library.has_animation(DotHumanoidClips.IDLE_GUN) else null
	# The bone's pose in skeleton space at the held-gun pose, computed from the clip's keys.
	var poses: Dictionary = {}
	var chain: Array[int] = []
	var i := bone
	while i >= 0:
		chain.push_front(i)
		i = skeleton.get_bone_parent(i)
	var global := Transform3D.IDENTITY
	for b in chain:
		var local := skeleton.get_bone_rest(b)
		if gun != null:
			var path := NodePath("%s:%s" % [model.get_path_to(skeleton), skeleton.get_bone_name(b)])
			var rt := gun.find_track(path, Animation.TYPE_ROTATION_3D)
			var pt := gun.find_track(path, Animation.TYPE_POSITION_3D)
			var q := local.basis.get_rotation_quaternion() if rt < 0 else gun.rotation_track_interpolate(rt, 0.0)
			var p := local.origin if pt < 0 else gun.position_track_interpolate(pt, 0.0)
			local = Transform3D(Basis(q).scaled(local.basis.get_scale()), p)
		global = global * local
		poses[b] = global
	var bone_global: Transform3D = poses[bone]
	var bone_in_figure := to_figure * bone_global
	# Wanted: in the figure's frame, -Z forward, +Y up, metres; at the bone plus the grip offset.
	var wanted := Transform3D(Basis.IDENTITY, bone_in_figure.origin + DotHumanoidFigure.HAND_OFFSET)
	return bone_in_figure.affine_inverse() * wanted


## The body's height at rest, from its mesh (the unposed bind shape, which is standing).
static func measure(mesh: MeshInstance3D, model: Node3D) -> float:
	if mesh == null or mesh.mesh == null:
		return 1.8
	var aabb := mesh.mesh.get_aabb()
	# The mesh's own transform under the model (the importer may scale the armature).
	var tomodel := Transform3D.IDENTITY
	var node: Node = mesh
	while node != null and node != model:
		if node is Node3D:
			tomodel = (node as Node3D).transform * tomodel
		node = node.get_parent()
	return (tomodel * aabb).size.y


static func capsule(p_height: float, colour: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "Capsule"
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	var trunk := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.32
	capsule.height = p_height
	trunk.mesh = capsule
	trunk.material_override = material
	trunk.position = Vector3(0.0, p_height * 0.5, 0.0)
	trunk.name = "torso"
	root.add_child(trunk)
	return root


## The crown of the head in the head bone's frame: straight over it at the mesh's top, upright and metre scale.
static func crown_local(skeleton: Skeleton3D, to_figure: Transform3D, height: float) -> Transform3D:
	var head_in_figure := to_figure * skeleton.get_bone_global_rest(skeleton.find_bone(DotHumanoidFigure.HEAD_BONE))
	var top := Vector3(head_in_figure.origin.x, height, head_in_figure.origin.z)
	return head_in_figure.affine_inverse() * Transform3D(Basis.IDENTITY, top)


## How many frames apart a figure's clip is advanced at its distance from the camera; also sets its shadow.
static func step_for_distance(figure: Node3D, mesh: MeshInstance3D) -> int:
	var viewport := figure.get_viewport() if figure.is_inside_tree() else null
	var camera := viewport.get_camera_3d() if viewport != null else null
	if camera == null:
		return 1
	var d := camera.global_position.distance_to(figure.global_position)
	if mesh != null:
		var shadow := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if d <= DotHumanoidFigure.SHADOW_RANGE else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mesh.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY and mesh.cast_shadow != shadow:
			mesh.cast_shadow = shadow
	if d <= DotHumanoidFigure.ANIM_NEAR:
		return 1
	return 2 if d <= DotHumanoidFigure.ANIM_FAR else 4
