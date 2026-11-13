class_name DotHumanoidFrames
extends RefCounted

## Measures a figure's body: where its hand sits, how tall its mesh is, and the stand-in capsule.


## The hand's frame in its bone's, from the held-gun pose: forward is the figure's forward and up
## is up there, so a weapon model made pointing down -Z points where the gun clips aim.
static func hand_frame(skeleton: Skeleton3D, anim: AnimationPlayer, model: Node3D, to_figure: Transform3D) -> Transform3D:
	var bone_global := held_pose(skeleton, anim, model, skeleton.find_bone(DotHumanoidFigure.HAND_BONE))
	var bone_in_figure := to_figure * bone_global
	# Wanted: in the figure's frame, -Z forward, +Y up, metres; at the bone plus the grip offset.
	var wanted := Transform3D(Basis.IDENTITY, bone_in_figure.origin + DotHumanoidFigure.HAND_OFFSET)
	return bone_in_figure.affine_inverse() * wanted


## Bone [param bone]'s pose in skeleton space at the held-gun pose (the first key of
## [constant DotHumanoidClips.IDLE_GUN]; the rest pose for a bone it does not key).
static func held_pose(skeleton: Skeleton3D, anim: AnimationPlayer, model: Node3D, bone: int) -> Transform3D:
	var library := anim.get_animation_library(&"")
	var gun := library.get_animation(DotHumanoidClips.IDLE_GUN) if library != null and library.has_animation(DotHumanoidClips.IDLE_GUN) else null
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
	return global


## The body's height at rest, from its mesh (the unposed bind shape, which is standing).
static func measure(mesh: MeshInstance3D, model: Node3D) -> float:
	if mesh == null or mesh.mesh == null:
		return 1.8
	# The mesh's own transform under the model (the importer may scale the armature).
	return (to_model(mesh, model) * mesh.mesh.get_aabb()).size.y


## [param node]'s frame to [param model]'s, from the local transforms between them (no tree needed).
static func to_model(node: Node, model: Node3D) -> Transform3D:
	var out := Transform3D.IDENTITY
	while node != null and node != model:
		if node is Node3D:
			out = (node as Node3D).transform * out
		node = node.get_parent()
	return out


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


## [method _half_cone]'s last answer: for which camera, on which process frame.
static var _cone_camera := 0
static var _cone_frame := -1
static var _cone := 0.0


## How many frames apart a figure's clip is advanced at its distance from the camera, doubled out of view or hidden
## ([constant DotHumanoidFigure.OFFSCREEN_STEP]); also sets its shadow.
static func step_for_distance(figure: Node3D, mesh: MeshInstance3D) -> int:
	var viewport := figure.get_viewport() if figure.is_inside_tree() else null
	var camera := viewport.get_camera_3d() if viewport != null else null
	if camera == null:
		return 1
	var placed := figure.global_transform
	var at := placed.origin
	var eye := camera.global_transform
	var d := eye.origin.distance_to(at)
	if mesh != null:
		var shadow := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if d <= DotHumanoidFigure.SHADOW_RANGE else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mesh.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY and mesh.cast_shadow != shadow:
			mesh.cast_shadow = shadow
	var step := 1 if d <= DotHumanoidFigure.ANIM_NEAR else (2 if d <= DotHumanoidFigure.ANIM_FAR else 4)
	var tall := (figure as DotHumanoidFigure).height if figure is DotHumanoidFigure else 1.8
	if not figure.is_visible_in_tree() or not _in_cone(camera, eye, at + placed.basis.y.normalized() * tall * 0.5, tall):
		step *= DotHumanoidFigure.OFFSCREEN_STEP
	return step


## Whether a sphere of [param radius] about [param center] may be in [param camera]'s view. Tests a cone round the
## view's diagonal, so a sphere near a corner counts as in view; an orthogonal camera always sees it.
static func in_view(camera: Camera3D, center: Vector3, radius: float) -> bool:
	return _in_cone(camera, camera.global_transform, center, radius)


## [method in_view] with the camera's global transform [param eye] already read (a figure step reads it once).
static func _in_cone(camera: Camera3D, eye: Transform3D, center: Vector3, radius: float) -> bool:
	if camera.projection != Camera3D.PROJECTION_PERSPECTIVE:
		return true
	var to := center - eye.origin
	var dist := to.length()
	if dist <= radius:
		return true
	var cosine := to.dot(-eye.basis.z.normalized()) / dist
	return acos(clampf(cosine, -1.0, 1.0)) <= _half_cone(camera) + asin(radius / dist)


## The view cone's half angle round its diagonal: from the field of view and the viewport's aspect, worked out once
## a frame per camera (32 figures stepping in one frame all ask for it).
static func _half_cone(camera: Camera3D) -> float:
	var frame := Engine.get_process_frames()
	var id := camera.get_instance_id()
	if id == _cone_camera and frame == _cone_frame:
		return _cone
	var size := camera.get_viewport().get_visible_rect().size
	var aspect := size.x / maxf(size.y, 1.0)
	var t := tan(deg_to_rad(camera.fov) * 0.5)
	var diagonal := t * sqrt(1.0 + aspect * aspect) if camera.keep_aspect == Camera3D.KEEP_HEIGHT else t * sqrt(1.0 + 1.0 / (aspect * aspect))
	_cone = atan(diagonal)
	_cone_camera = id
	_cone_frame = frame
	return _cone
