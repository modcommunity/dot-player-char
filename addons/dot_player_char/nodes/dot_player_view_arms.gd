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
## The finger roots, all at the wrist: scaling them shrinks the hand about the wrist, so the forearm and the reach are untouched.
const FINGER_ROOTS: Array[String] = ["Pinky1", "Middle1", "Index1", "Thumb1"]

## Extension point: `func(look: DotHumanoidLook, height: float) -> Node3D`. The node it returns is parented here and
## drawn as is, in place of the person; if it has `set_motion` and `animate` (a [DotHumanoidFigure]) they are driven.
## Fraction of the arm the lean aims to need, so the slide to reach never trims a hand the lean just brought in.
const LEAN_SLACK := 0.97

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
## Where the camera sits from the head bone when holding a weapon (upright figure, forward is -Z). A little behind it:
## further forward a near grip (a pump gun's) folds the elbow up beside the eye and the forearm fans across the view.
var held_eye_from_head: Vector3 = Vector3(0.0, 0.18, 0.06)
## Elbow directions in the arms' frame (right arm; the left is mirrored): out, down, a little back.
## Where the idle hand rests, from the arms node, out of the view, when the weapon is held with one hand.
const LEFT_REST := Vector3(-0.25, 0.9, 0.1)
var elbow_pole: Vector3 = Vector3(1.0, -1.2, 0.5)
## The held arms' size and how much wider apart the shoulders sit: slimmer arms leave the weapon visible.
var held_scale: float = 0.75
var held_spread: float = 1.25
## Draw the support forearm and hand as the firing ones mirrored, so one-sided forearm gear never crosses the view.
var mirror_support_forearm: bool = true
## Show the idle left arm in a one-hand grip. Off: it has no hand in view, only its sleeve at the screen edge.
var show_idle_left_arm: bool = false
## The hand's size with a weapon (1 is the kit's own mitts).
var hand_scale: float = 0.5
## The forearm's size with a weapon (1 is the kit's own); the hand keeps [member hand_scale]. A short grip close to the eye wants a slimmer, shorter forearm.
var forearm_scale: float = 1.0
## Where the wrist sits from the grip point, in the arms' frame (x out to the hand's side, y up, -z forward): the grip
## points are on a gun's centreline, so a wrist left on them lays the whole hand over the gun and its sights.
var palm_offset: Vector3 = Vector3(0.0, -0.04, 0.07)
## How far the shoulders may lean toward a firing-hand target out of the arm's reach, metres; past it the hand stays short.
var max_lean: float = 0.4
## Metres between the hand and its target after the last solve (firing hand, support hand); 0 when that hand is unused.
var hand_gap_right: float = 0.0
var hand_gap_left: float = 0.0
## Draws the grip sockets, hand targets and arm bone axes over the view ([DotViewArmsPoseDebug]).
var debug_pose: bool = false:
	set(value):
		debug_pose = value
		if not value and _pose_debug != null:
			_pose_debug.queue_free()
			_pose_debug = null
var _pose_debug: DotViewArmsPoseDebug = null
## Idle breathing and walk bob, metres: [method sway] is what the host adds to its weapon mount.
var breath_amplitude: float = 0.003
var bob_amplitude: float = 0.012

var _arms: Node3D = null
var _bones: Array[int] = []
var _fingers: Array[int] = []
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

			for root in FINGER_ROOTS:
				for side in [".L", ".R"]:
					var f := skeleton.find_bone(root + side)
					if f >= 0:
						_fingers.append(f)
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
		if mirror_support_forearm and instance.skin != null:
			_mirror_forearm(arrays, skeleton, instance.skin)
		out.add_surface_from_arrays(old.surface_get_primitive_type(s), arrays)
		out.surface_set_material(s, old.surface_get_material(s))

	instance.mesh = out


## Replaces the support forearm and hand with the firing ones mirrored across the body (x = the forearms' midpoint).
## A body's one-sided forearm gear (a bandage's loose wraps) otherwise crosses the view as torn-looking strips.
func _mirror_forearm(arrays: Array, skeleton: Skeleton3D, skin: Skin) -> void:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES] if arrays[Mesh.ARRAY_BONES] != null else PackedInt32Array()
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS] if arrays[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
	var n := verts.size()
	var per := bones.size() / maxi(n, 1)
	var bind_of := {}
	var at := {}
	for b in skin.get_bind_count():
		var bone := _bind_bone(skeleton, skin, b)
		if bone >= 0:
			bind_of[skeleton.get_bone_name(bone)] = b
			at[skeleton.get_bone_name(bone)] = skin.get_bind_pose(b).affine_inverse().origin
	if per < 1 or weights.size() < n * per or not at.has("LowerArm.L") or not at.has("LowerArm.R"):
		return
	var l: Vector3 = at["LowerArm.L"]
	var r: Vector3 = at["LowerArm.R"]
	if absf(l.y - r.y) > 0.01 or absf(l.z - r.z) > 0.01:
		return
	var mid := (l.x + r.x) * 0.5
	var side := PackedByteArray()
	side.resize(n)
	for v in n:
		var best := 0
		for k in per:
			if weights[v * per + k] > weights[v * per + best]:
				best = k
		side[v] = _forearm_side(skeleton, skin, bones[v * per + best])
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var kept := PackedInt32Array()
	var copied := {}
	var added := PackedInt32Array()
	for t in range(0, index.size() - 2, 3):
		var tri := [index[t], index[t + 1], index[t + 2]]
		if side[tri[0]] == 1 and side[tri[1]] == 1 and side[tri[2]] == 1:
			continue
		kept.append_array(index.slice(t, t + 3))
		if side[tri[0]] == 2 and side[tri[1]] == 2 and side[tri[2]] == 2:
			for c in [0, 2, 1]:
				if not copied.has(tri[c]):
					copied[tri[c]] = n + copied.size()
					added.append(tri[c])
				kept.append(copied[tri[c]])
	for a in arrays.size():
		var src = arrays[a]
		if a == Mesh.ARRAY_INDEX or not (src is PackedVector3Array or src is PackedFloat32Array or src is PackedVector2Array or src is PackedInt32Array or src is PackedColorArray):
			continue
		var w: int = src.size() / n
		for v in added:
			for k in w:
				var value = src[v * w + k]
				if a == Mesh.ARRAY_VERTEX:
					value = Vector3(2.0 * mid - value.x, value.y, value.z)
				elif a == Mesh.ARRAY_NORMAL:
					value = Vector3(-value.x, value.y, value.z)
				elif a == Mesh.ARRAY_TANGENT and (k == 0 or k == 3):
					value = -value
				elif a == Mesh.ARRAY_BONES:
					value = bind_of.get(String(skeleton.get_bone_name(_bind_bone(skeleton, skin, value))).trim_suffix(".R") + ".L", value)
				src.append(value)
		arrays[a] = src
	arrays[Mesh.ARRAY_INDEX] = kept


## 1 for a bind on the support forearm or hand (LowerArm.L and below), 2 on the firing one, else 0.
func _forearm_side(skeleton: Skeleton3D, skin: Skin, bind: int) -> int:
	var bone := _bind_bone(skeleton, skin, bind)
	while bone >= 0:
		var bone_name := skeleton.get_bone_name(bone)
		if bone_name == "LowerArm.L":
			return 1
		if bone_name == "LowerArm.R":
			return 2
		bone = skeleton.get_bone_parent(bone)
	return 0


func _bind_bone(skeleton: Skeleton3D, skin: Skin, bind: int) -> int:
	return skeleton.find_bone(skin.get_bind_name(bind)) if skin.get_bind_name(bind) != &"" else skin.get_bind_bone(bind)


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

		var fore := clampf(forearm_scale, 0.2, 1.5) if _holding() else 1.0

		for i in _fingers:
			skeleton.set_bone_pose_scale(i, Vector3.ONE * ((hand_scale if _holding() else 1.0) / fore))

		_scale_left(skeleton, fore)
		_reach(skeleton)


func _left_hidden() -> bool:
	return _holding() and not show_idle_left_arm and not _grip.is_two_hand()


func _scale_left(skeleton: Skeleton3D, fore: float) -> void:
	var hide := _left_hidden()

	for bone in ["Shoulder.L", "UpperArm.L", "LowerArm.L"]:
		var i := skeleton.find_bone(bone)
		if i >= 0:
			skeleton.set_bone_pose_scale(i, Vector3.ONE * (0.001 if hide else (fore if bone == "LowerArm.L" else 1.0)))

	var right := skeleton.find_bone("LowerArm.R")
	if right >= 0:
		skeleton.set_bone_pose_scale(right, Vector3.ONE * fore)


## Seats the posed head bone at this node's origin; the clip already lies the person head toward -Z.
func _fit() -> void:
	_fitted = true
	var skeleton: Skeleton3D = (_arms as DotHumanoidFigure).skeleton() if _arms is DotHumanoidFigure else null

	if skeleton == null or _head < 0:
		return

	_arms.transform = Transform3D.IDENTITY
	var head := _arms.global_transform.affine_inverse() * (skeleton.global_transform * skeleton.get_bone_global_pose(_head)).origin
	var eye := held_eye_from_head if _holding() else eye_from_head
	var basis := Basis.from_scale(Vector3(held_scale * held_spread, held_scale, held_scale)) if _holding() else Basis.IDENTITY
	_arms.transform = Transform3D(basis, -(basis * head + eye))
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

	if _right.is_empty():
		_right = DotHumanoidIk.keyed_bones(skeleton, figure.body_node(), _clip_of(figure), ["UpperArm.R", "LowerArm.R", "Middle1.R"])
		_left = DotHumanoidIk.keyed_bones(skeleton, figure.body_node(), _clip_of(figure), ["UpperArm.L", "LowerArm.L", "Middle1.L"])

	var shift := global_transform.basis * palm_offset
	var right_target := _grip.grip_world() + shift
	_lean(skeleton, figure, right_target)

	var to_skeleton := skeleton.global_transform.affine_inverse()
	var out := to_skeleton.basis * (figure.global_transform.basis * elbow_pole)
	var drawn: Array = []
	hand_gap_right = 0.0
	hand_gap_left = 0.0

	if not _right.is_empty():
		DotHumanoidIk.two_bone(skeleton, _right, to_skeleton * right_target, out, 1.0)
		drawn.append([_grip.grip_world(), right_target, "Middle1.R"])
		hand_gap_right = _gap(skeleton, _right, right_target)

	if not _left.is_empty() and not _left_hidden():
		var rest := figure.global_transform * (_base + LEFT_REST)
		var target := rest
		if _grip.is_two_hand():
			var mirrored := global_transform.basis * Vector3(-palm_offset.x, palm_offset.y, palm_offset.z)
			target = _slide_to_reach(skeleton, _left, _grip.support_world() + mirrored, right_target + mirrored)
		DotHumanoidIk.two_bone(skeleton, _left, to_skeleton * target, Vector3(-out.x, out.y, out.z), 1.0)
		drawn.append([_grip.support_world() if _grip.is_two_hand() else rest, target, "Middle1.L"])
		hand_gap_left = _gap(skeleton, _left, target)

	if debug_pose:
		if _pose_debug == null:
			_pose_debug = DotViewArmsPoseDebug.new()
			add_child(_pose_debug)
		_pose_debug.draw(skeleton, drawn)


## Leans the arms toward whichever hand target (firing or support) is furthest out of its arm's reach, a step at a time, by up to [member max_lean] in all.
func _lean(skeleton: Skeleton3D, figure: DotHumanoidFigure, target: Vector3) -> void:
	if _right.is_empty() or max_lean <= 0.0:
		return

	var goals: Array = [[_right, target]]

	if not _left.is_empty() and _grip.is_two_hand() and not _left_hidden():
		goals.append([_left, _grip.support_world() + global_transform.basis * Vector3(-palm_offset.x, palm_offset.y, palm_offset.z)])

	var shoulders: Array[Vector3] = []
	var reaches: Array[float] = []
	var to_local := skeleton.global_transform.basis.inverse()

	for goal: Array in goals:
		var bones: Array[int] = goal[0]
		shoulders.append(skeleton.global_transform * DotHumanoidIk.global_pose(skeleton, bones[0]).origin)
		reaches.append(_reach_local(skeleton, bones))

	var lean := Vector3.ZERO

	for step in 8:
		var worst := 0.0
		var toward := Vector3.ZERO

		for i in goals.size():
			var to: Vector3 = (goals[i][1] as Vector3) - (shoulders[i] + lean)
			var local := to_local * to
			var far: float = (local.length() - reaches[i] * LEAN_SLACK) * to.length() / maxf(local.length(), 0.0001)

			if far > worst:
				worst = far
				toward = to.normalized()

		if worst <= 0.001:
			break

		lean += toward * worst * 0.6

		if lean.length() > max_lean:
			lean = lean.normalized() * max_lean
			break

	figure.global_position += lean


## The point on the segment from [param from] to [param to] nearest [param from] that the arm can reach (or [param to]).
func _slide_to_reach(skeleton: Skeleton3D, bones: Array[int], from: Vector3, to: Vector3) -> Vector3:
	if bones.is_empty():
		return from

	var inverse := skeleton.global_transform.affine_inverse()
	var shoulder := DotHumanoidIk.global_pose(skeleton, bones[0]).origin
	var radius := _reach_local(skeleton, bones)
	var d := inverse * to - inverse * from
	var f := inverse * from - shoulder

	if f.length() <= radius or d.length_squared() < 0.000001:
		return from

	var a := d.length_squared()
	var b := 2.0 * f.dot(d)
	var disc := b * b - 4.0 * a * (f.length_squared() - radius * radius)

	if disc < 0.0:
		return to

	return from + (to - from) * clampf((-b - sqrt(disc)) / (2.0 * a), 0.0, 1.0)


func _reach_local(skeleton: Skeleton3D, bones: Array[int]) -> float:
	var upper := DotHumanoidIk.global_pose(skeleton, bones[0]).origin
	var lower := DotHumanoidIk.global_pose(skeleton, bones[1]).origin
	var wrist := DotHumanoidIk.global_pose(skeleton, bones[2]).origin
	return (lower - upper).length() + (wrist - lower).length() - 0.01


func _gap(skeleton: Skeleton3D, bones: Array[int], target: Vector3) -> float:
	return (skeleton.global_transform * DotHumanoidIk.global_pose(skeleton, bones[2]).origin).distance_to(target)


func _clip_of(figure: DotHumanoidFigure) -> Animation:
	var player := figure.body_node().find_child("AnimationPlayer", true, false) as AnimationPlayer
	return player.get_animation(figure.clip) if player != null and player.has_animation(figure.clip) else null


## The arms node, or null before [method build].
func arms() -> Node3D:
	return _arms


## Metres from each hand's middle-finger bone to its [param grip] point plus [member palm_offset], the worst of the two; -1 when the arms are not shown on that grip.
func hand_error(grip: DotViewGrip) -> float:
	if not shown or grip == null or not grip.is_valid() or not (_arms is DotHumanoidFigure):
		return -1.0
	var skeleton := (_arms as DotHumanoidFigure).skeleton()
	if skeleton == null:
		return -1.0
	var basis := global_transform.basis
	var pairs := [["Middle1.R", grip.grip_world() + basis * palm_offset]]
	if grip.is_two_hand():
		pairs.append(["Middle1.L", grip.support_world() + basis * Vector3(-palm_offset.x, palm_offset.y, palm_offset.z)])
	var worst := 0.0
	for pair: Array in pairs:
		var bone := skeleton.find_bone(pair[0])
		if bone < 0:
			return -1.0
		var at := skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin
		worst = maxf(worst, at.distance_to(pair[1]))
	return worst


func describe() -> Dictionary:
	return {"built": _arms != null, "shown": shown, "held": _holding(), "custom": arms_factory.is_valid(), "hidden_bones": _bones.size()}


func _clear() -> void:
	if _arms != null:
		remove_child(_arms)
		_arms.queue_free()
		_arms = null

	_bones.clear()
	_fingers.clear()
