class_name DotPlayerViewArms
extends Node3D

## Your own arms in first person: put it under the camera's yaw pivot (not its pitch, or the arms swing with the look).
## [method set_downed] plays the crawl; [method set_held] poses the arms on a weapon mesh the host supplies ([DotViewGrip]).
## The head, neck and legs are shrunk away so only the arms and a little torso show; a game's own arms come from [member arms_factory].

const CHANNEL := "player.view_arms"
## Bones shrunk to nothing; the arms hang off the chest, so they stay.
const HIDDEN_BONES: Array[String] = ["Head", "Neck", "UpperLeg.L", "UpperLeg.R"]
## The pack is part of the one skinned mesh, bound to the hips: its vertices are the hip-bound ones this far behind the body.
const PACK_BONE := "Hips"
const PACK_BEHIND := -0.3

## Extension point: `func(look: DotHumanoidLook, height: float) -> Node3D`. The node it returns is parented here and
## drawn as is, in place of the person; if it has `set_motion` and `animate` (a [DotHumanoidFigure]) they are driven.
var arms_factory: Callable = Callable()
## Extension point: `func(bone: StringName, rest_position: Vector3) -> bool`, true for a vertex that is carried gear
## (a backpack) and must not show; triangles touching one are dropped. The default is the stock kit's pack.
var hide_vertex_fn: Callable = Callable()
## Where the camera sits relative to the crawling figure's head bone, in the figure's own frame (the clip lies the
## person along Z; the eye is measured from the posed head, not assumed, so a game's own figure fits too).
var eye_from_head: Vector3 = Vector3(0.0, 0.3, -0.4)
var look: DotHumanoidLook = null
var height: float = 1.8
var shown: bool = false
## Where the camera sits from the head bone when holding a weapon (upright figure, forward is -Z).
var held_eye_from_head: Vector3 = Vector3(0.0, 0.1, -0.05)
## Elbow directions in the arms' frame (right arm; the left is mirrored): out, down, a little back.
## Where the idle hand rests, from the arms node, out of the view, when the weapon is held with one hand.
const LEFT_REST := Vector3(-0.25, 0.9, 0.1)
var elbow_pole: Vector3 = Vector3(0.5, -1.0, 0.4)
## Idle breathing and walk bob, metres: [method sway] is what the host adds to its weapon mount.
var breath_amplitude: float = 0.003
var bob_amplitude: float = 0.012

var _arms: Node3D = null
var _bones: Array[int] = []
var _fitted := false
var _ticks := 0
var _head: int = -1
var _downed := false
var _grip: DotViewGrip = null
var _phase := 0.0
var _sway := Vector3.ZERO
var _base := Vector3.ZERO
var _right: Array[int] = []
var _left: Array[int] = []


## Builds the arms (once; a new [param p_look] rebuilds). Hidden until [method set_downed] says otherwise.
func build(p_look: DotHumanoidLook = null, p_height: float = 1.8) -> void:
	look = p_look if p_look != null else DotHumanoidLook.stock(0)
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
		_strip_gear(figure)
	else:
		add_child(_arms)

	_fitted = false
	_ticks = 0
	_apply_mode()


## Gear is skinned into the body mesh, so it goes by dropping its triangles from this figure's own copy of the mesh.
func _strip_gear(figure: DotHumanoidFigure) -> void:
	var instance := figure.mesh()
	var skeleton := figure.skeleton()

	if instance == null or skeleton == null or instance.mesh == null:
		return

	var old := instance.mesh
	var out := ArrayMesh.new()

	for s in old.get_surface_count():
		var arrays := old.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES] if arrays[Mesh.ARRAY_BONES] != null else PackedInt32Array()
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS] if arrays[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
		var per := bones.size() / maxi(verts.size(), 1)
		var gear := PackedByteArray()
		gear.resize(verts.size())

		for v in verts.size():
			if per < 1 or weights.size() < verts.size() * per:
				break

			var best := 0
			for k in per:
				if weights[v * per + k] > weights[v * per + best]:
					best = k

			var bone := StringName(skeleton.get_bone_name(bones[v * per + best]))
			gear[v] = 1 if _is_gear(bone, verts[v]) else 0

		var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if index.is_empty():
			index.resize(verts.size())
			for i in verts.size():
				index[i] = i

		var kept := PackedInt32Array()
		for t in range(0, index.size() - 2, 3):
			if gear[index[t]] == 0 and gear[index[t + 1]] == 0 and gear[index[t + 2]] == 0:
				kept.append_array(index.slice(t, t + 3))

		arrays[Mesh.ARRAY_INDEX] = kept
		out.add_surface_from_arrays(old.surface_get_primitive_type(s), arrays)
		out.surface_set_material(s, old.surface_get_material(s))

	instance.mesh = out


func _is_gear(bone: StringName, rest: Vector3) -> bool:
	if hide_vertex_fn.is_valid():
		return bool(hide_vertex_fn.call(bone, rest))

	return bone == PACK_BONE and rest.z < PACK_BEHIND


## Shows the crawling arms while [param on]. Always the prone crawl: a player propped on their back sees the held weapon, not arms.
func set_downed(on: bool) -> void:
	_downed = on
	_apply_mode()


## Poses the arms on [param grip]'s weapon (null puts the mode away). While downed the crawl still wins; with no grip the arms are as before.
func set_held(grip: DotViewGrip) -> void:
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

	if _arms.has_method("set_motion"):
		_arms.call("set_motion", {"downed": _downed, "propped": false})
	if _arms.has_method("set_hold"):
		_arms.call("set_hold", DotHumanoidFigure.Hold.GUN if _grip != null and not _downed else DotHumanoidFigure.Hold.NONE)

	if was != shown or _grip != null or not _right.is_empty():
		_fitted = false
		_ticks = 0
		_right.clear()
		_left.clear()


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

		_reach(skeleton)


## Seats the posed head bone at this node's origin; the clip already lies the person head toward -Z.
func _fit() -> void:
	_fitted = true
	var skeleton: Skeleton3D = (_arms as DotHumanoidFigure).skeleton() if _arms is DotHumanoidFigure else null

	if skeleton == null or _head < 0:
		return

	_arms.transform = Transform3D.IDENTITY
	var head := _arms.global_transform.affine_inverse() * (skeleton.global_transform * skeleton.get_bone_global_pose(_head)).origin
	var eye := held_eye_from_head if _holding() else eye_from_head
	_arms.transform = Transform3D(Basis.IDENTITY, -(head + eye))
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
	var to_skeleton := skeleton.global_transform.affine_inverse()
	var out := to_skeleton.basis * (figure.global_transform.basis * elbow_pole)

	if _right.is_empty():
		_right = DotHumanoidIk.keyed_bones(skeleton, figure.body_node(), _clip_of(figure), ["UpperArm.R", "LowerArm.R", "Middle1.R"])
		_left = DotHumanoidIk.keyed_bones(skeleton, figure.body_node(), _clip_of(figure), ["UpperArm.L", "LowerArm.L", "Middle1.L"])

	if not _right.is_empty():
		DotHumanoidIk.two_bone(skeleton, _right, to_skeleton * _grip.grip_world(), out, 1.0)

	if not _left.is_empty():
		var rest := figure.global_transform * (_base + LEFT_REST)
		var target := _grip.support_world() if _grip.is_two_hand() else rest
		DotHumanoidIk.two_bone(skeleton, _left, to_skeleton * target, Vector3(-out.x, out.y, out.z), 1.0)


func _clip_of(figure: DotHumanoidFigure) -> Animation:
	var player := figure.body_node().find_child("AnimationPlayer", true, false) as AnimationPlayer
	return player.get_animation(figure.clip) if player != null and player.has_animation(figure.clip) else null


## The arms node, or null before [method build].
func arms() -> Node3D:
	return _arms


func describe() -> Dictionary:
	return {"built": _arms != null, "shown": shown, "held": _holding(), "custom": arms_factory.is_valid(), "hidden_bones": _bones.size()}


func _clear() -> void:
	if _arms != null:
		remove_child(_arms)
		_arms.queue_free()
		_arms = null

	_bones.clear()
