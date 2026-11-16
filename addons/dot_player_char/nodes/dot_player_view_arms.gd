class_name DotPlayerViewArms
extends Node3D

## Your own arms in first person: put it under the camera's yaw pivot (not its pitch, or the arms swing with the look).
## [method set_downed] plays the crawl; [method set_held] poses the arms on a weapon mesh the host supplies ([DotViewGrip]).
## The head, neck and legs are shrunk away so only the arms and a little torso show; a game's own arms come from [member arms_factory].

## Bones shrunk to nothing; the arms hang off the chest, so they stay.
const HIDDEN_BONES: Array[String] = ["Head", "Neck", "UpperLeg.L", "UpperLeg.R"]
## The pack is part of the one skinned mesh, bound to the hips: its vertices are the hip-bound ones this far behind the body.
const PACK_BONE := "Hips"
const PACK_BEHIND := -0.3
## The finger roots, all at the wrist: scaling them shrinks the hand about the wrist, so the forearm and the reach are untouched.
const FINGER_ROOTS: Array[String] = ["Pinky1", "Middle1", "Index1", "Thumb1"]
## The support arm, dropped from the mesh drawn while a weapon is held one-handed (a second copy of the mesh, swapped in:
## shrinking the bones instead pulled the sleeve into a flap at the screen's edge).
const LEFT_ARM_BONES: Array[String] = ["Shoulder.L"]
## A vertex carrying more than this weight on a dropped bone takes its triangles with it.
const TOUCH_WEIGHT := 0.01

## Extension point: `func(look: DotHumanoidLook, height: float) -> Node3D`. The node it returns is parented here and
## drawn as is, in place of the person; if it has `set_motion` and `animate` (a [DotHumanoidFigure]) they are driven.
## Fraction of the arm the lean aims to need, so the slide to reach never trims a hand the lean just brought in.
const LEAN_SLACK := 0.97
## How fast the drawn forearm scale follows a new [member forearm_scale], per second.
const FORE_RATE := 2.0
## How fast the drawn lean shrinks to the lean a grip needs, metres per second: a swap from a two-hand grip (the support
## hand far out) to a one-hand one moved the shoulder 0.27 m in one frame and the elbow with it, the hand still. A lean
## that has to grow is taken at once (a hand short of its grip is worse than a step).
const LEAN_RATE := 1.2
## Elbow turns tried about the shoulder-to-hand line (degrees) to take an arm out of the weapon's box, and how much
## of the forearm next to the hand may stay inside it (the hand is on the gun).
## The scan itself is [DotViewArmsClear], native when dot-sim's "arms" module is loaded.
const CLEAR_ANGLES: Array[float] = DotViewArmsClear.ANGLES
const CLEAR_HAND_FREE := DotViewArmsClear.HAND_FREE

var arms_factory: Callable = Callable()
## Extension point: `func(bone: StringName, rest_position: Vector3) -> bool`, true for a vertex that is carried gear
## (a backpack) and must not show; triangles touching one are dropped. The default is the stock kit's pack.
var hide_vertex_fn: Callable = Callable()
## Where the camera sits relative to the crawling figure's head bone, in the figure's own frame (the clip lies the
## person along Z; the eye is measured from the posed head, not assumed, so a game's own figure fits too).
var eye_from_head: Vector3 = Vector3(0.0, 0.3, -0.4)
## The look drawn: [member own_look], or the server's [method set_look_override] while one is set.
var look: DotHumanoidLook = null
## The look [method build] was given: the player's own avatar, so each player's arms are their own.
var own_look: DotHumanoidLook = null
## The arms' close-up material ([DotViewArmsMaterial]: skin and cloth detail). Off: the crowd's flat palette.
var detailed: bool = true
## Turn the elbows so the arms do not pass through the weapon ([member DotViewGrip.bounds]); its radius in metres.
var keep_arms_clear: bool = true
var arm_radius: float = 0.03
## How deep each arm (firing, support) sat inside the weapon's box after the last solve, metres; 0 is clear.
var arm_depth_right: float = 0.0
var arm_depth_left: float = 0.0
## Run the elbow clearance scan in dot-sim's native [code]DotSimViewArms[/code] when it is loaded (bit-identical to
## [DotViewArmsClear]); false keeps the script (the A/B baseline). Read once, on the first scan.
var native_clear: bool = true
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
## A sprint with one hand on the weapon (0 to 1, the host sets it each frame): the free arm pumps into view as a
## fist at [member run_left] (from this node), swinging by [member run_left_pump] against the stride, [member run_phase] (0 to 1).
var run: float = 0.0
var run_phase: float = 0.0
var run_left: Vector3 = Vector3(-0.2, -0.3, -0.32)
var run_left_pump: Vector3 = Vector3(0.0, 0.07, -0.1)
## How far below the view the pumping fist starts as [member run] eases in, so it rises into view, not pops.
const RUN_LEFT_DROP := Vector3(0.0, -0.3, 0.1)
## The hand's size with a weapon (1 is the kit's own mitts).
var hand_scale: float = 0.5
## The forearm's size with a weapon (1 is the kit's own); the hand keeps [member hand_scale]. A short grip close to the eye wants a slimmer, shorter forearm.
var forearm_scale: float = 1.0
## Where the wrist sits from the grip point, in the arms' frame (x out to the hand's side, y up, -z forward): just off
## the gun's centreline, so the hand wraps the grip's side instead of covering the sights or hanging below the grip.
var palm_offset: Vector3 = Vector3(0.015, -0.01, 0.02)
## How far the shoulders may lean toward a firing-hand target out of the arm's reach, metres; past it the hand stays short.
var max_lean: float = 0.4
## Draw [DotViewHand]s, five jointed fingers closed on the weapon with a [DotViewHandPoses] grip, in place of the
## kit's mitts while a weapon is held (false: the mitts and [member palm_offset], as before). Read by [method build].
var real_hands: bool = true
## The grips the real hands close into, by [member DotViewGrip.kind] ([method DotViewHandPoses.table]; edit or add kinds).
var hand_poses: Dictionary = DotViewHandPoses.table()
## The real hands' size against life size on the held arms (it follows [member held_scale] and [member hand_scale]
## over the kit's 0.5, so a game's per-weapon hand size still applies).
var hand_size: float = 1.0
## How far a knife hand has gone from its fist toward the throw's pinch ([constant DotViewHandPoses.KNIFE_THROW]),
## 0 to 1; the host sets it each frame from the throw's wind-back.
var throw_grip: float = 0.0
## How fast the fingers close into a new grip, per second; 0 closes them at once.
var finger_rate: float = 14.0
## Move the shoulder joint out toward a hand target the lean left out of the arm's reach (a long forend), so the hand
## lands on it instead of short; false leaves the hand short (the old slide toward the firing hand still applies).
var extend_reach: bool = true
## The most [member extend_reach] moves a shoulder, in the figure's own metres; 0 is no limit.
var reach_extend_max: float = 0.3
## Metres between the hand and its target after the last solve (firing hand, support hand); 0 when that hand is unused.
var hand_gap_right: float = 0.0
var hand_gap_left: float = 0.0
## The nearest a wrist target may come to the eye, metres along the view's forward: a hand the gun brings closer (a
## reload pulled to the chest, a gun pushed back by a wall) slides out along the forward to it, so its fingers stay past
## the camera's near plane. 0 is off (the old seat); a negative or non-finite value is refused with an error.
var hand_min_depth: float = 0.0:
	set(value):
		if value < 0.0 or not is_finite(value):
			push_error("DotPlayerViewArms.hand_min_depth must be 0 or more, got %s" % value)
			return
		hand_min_depth = value
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
var _override: DotHumanoidLook = null
var _detail_on := false
var _turn_right := 0.0
var _turn_left := 0.0
## dot-sim's DotSimViewArms, made on the first scan when [member native_clear] and the class exists; reached by name
## (never typed) so this addon loads without the extension. [member _native_tried] keeps it to one probe.
var _native: Object = null
var _native_tried := false
## The forearm scale drawn, eased toward [member forearm_scale] (or 1 without a weapon) at [constant FORE_RATE].
var _fore := 1.0
## The lean drawn, eased toward the one the grip needs at [constant LEAN_RATE]; [member _delta] is this tick's step.
var _leaned := Vector3.ZERO
var _delta := 1.0 / 60.0
var _was_holding := false
## The real hands, firing (right) then support (left); empty with [member real_hands] off or a factory's arms.
var _hands: Array[DotViewHand] = []
## Upper-arm bones [method _extend] moved this tick, put back to their rest the next.
var _extended: Array[int] = []
## How far each shoulder was moved out last tick (firing, support), figure metres.
var reach_extended_right: float = 0.0
var reach_extended_left: float = 0.0
## The figure's mesh with both arms and with the support arm dropped ([constant LEFT_ARM_BONES]).
var _two_arm_mesh: Mesh = null
var _one_arm_mesh: Mesh = null


## Builds the arms (once; a new [param p_look] rebuilds). Hidden until [method set_downed] says otherwise.
func build(p_look: DotHumanoidLook = null, p_height: float = 1.8) -> void:
	own_look = p_look if p_look != null else DotHumanoidLook.stock(0)
	look = _override if _override != null else own_look
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
		if detailed and figure.mesh() != null:
			figure.mesh().material_override = DotViewArmsMaterial.for_look(look)
			_detail_on = true
		if real_hands and skeleton != null and figure.mesh() != null:
			_make_hands(figure)
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
	var one_arm := ArrayMesh.new()

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
		arrays[Mesh.ARRAY_CUSTOM0] = _rest_positions(verts)
		if mirror_support_forearm and instance.skin != null:
			_mirror_forearm(arrays, skeleton, instance.skin)
		# Shrunk to a point, a hidden bone still pulls every vertex that carries any of its weight: the collar and hip
		# triangles blended onto the head or a leg stretched into a skin wedge across the lower view (PLAYLOT).
		arrays[Mesh.ARRAY_INDEX] = _keep_off(arrays, skeleton, instance.skin, HIDDEN_BONES)
		out.add_surface_from_arrays(old.surface_get_primitive_type(s), arrays, [], {}, DotViewArmsMaterial.REST_FORMAT)
		out.surface_set_material(s, old.surface_get_material(s))
		var one := arrays.duplicate()
		one[Mesh.ARRAY_INDEX] = _keep_off(arrays, skeleton, instance.skin, LEFT_ARM_BONES)
		one_arm.add_surface_from_arrays(old.surface_get_primitive_type(s), one, [], {}, DotViewArmsMaterial.REST_FORMAT)
		one_arm.surface_set_material(s, old.surface_get_material(s))

	instance.mesh = out
	_two_arm_mesh = out
	_one_arm_mesh = one_arm


## [param arrays]' triangle indices less the triangles with a vertex carrying more than [constant TOUCH_WEIGHT] on a bone
## at or under one of [param roots].
func _keep_off(arrays: Array, skeleton: Skeleton3D, skin: Skin, roots: Array[String]) -> PackedInt32Array:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES] if arrays[Mesh.ARRAY_BONES] != null else PackedInt32Array()
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS] if arrays[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var n := verts.size()
	var per := bones.size() / maxi(n, 1)
	if per < 1 or weights.size() < n * per:
		return index
	var under := {}
	var touch := PackedByteArray()
	touch.resize(n)
	for v in n:
		for k in per:
			if weights[v * per + k] <= TOUCH_WEIGHT:
				continue
			var b := bones[v * per + k]
			if not under.has(b):
				under[b] = _under(skeleton, _bind_bone(skeleton, skin, b) if skin != null else b, roots)
			if under[b]:
				touch[v] = 1
				break
	var kept := PackedInt32Array()
	for t in range(0, index.size() - 2, 3):
		if touch[index[t]] == 0 and touch[index[t + 1]] == 0 and touch[index[t + 2]] == 0:
			kept.append_array(index.slice(t, t + 3))
	# A surface wholly on those bones keeps one empty triangle: an empty one fails to build, and the surfaces after it
	# would shift onto the wrong materials.
	if kept.is_empty() and n > 0:
		kept = PackedInt32Array([0, 0, 0])
	return kept


func _under(skeleton: Skeleton3D, bone: int, roots: Array[String]) -> bool:
	while bone >= 0:
		if skeleton.get_bone_name(bone) in roots:
			return true
		bone = skeleton.get_bone_parent(bone)
	return false


## The two real hands, coloured as the kit's own hand is drawn: the arms' material and its hand's spot on the atlas.
func _make_hands(figure: DotHumanoidFigure) -> void:
	var instance := figure.mesh()
	var material: Material = instance.material_override if instance.material_override != null else instance.get_active_material(0)
	for right in [true, false]:
		var hand := DotViewHand.new()
		hand.name = "HandR" if right else "HandL"
		hand.right = right
		hand.skin_uv = _hand_uv(instance, figure.skeleton(), ".R" if right else ".L")
		hand.material = material
		hand.build()
		hand.visible = false
		add_child(hand)
		_hands.append(hand)


## The atlas spot of the kit hand on [param side] (".R"): the UV of a vertex bound mostly to a finger root, so a gloved
## outfit's hands stay gloved. Vector2.ZERO when the mesh has none.
func _hand_uv(instance: MeshInstance3D, skeleton: Skeleton3D, side: String) -> Vector2:
	var mesh := instance.mesh
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES] if arrays[Mesh.ARRAY_BONES] != null else PackedInt32Array()
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS] if arrays[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
		var n := uvs.size()
		var per := bones.size() / maxi(n, 1)
		if n == 0 or per < 1 or weights.size() < n * per:
			continue
		for v in n:
			var best := 0
			for k in per:
				if weights[v * per + k] > weights[v * per + best]:
					best = k
			if weights[v * per + best] < 0.9:
				continue
			var b := bones[v * per + best]
			var bone := _bind_bone(skeleton, instance.skin, b) if instance.skin != null else b
			if bone >= 0 and skeleton.get_bone_name(bone).trim_suffix(side) in FINGER_ROOTS and skeleton.get_bone_name(bone).ends_with(side):
				return uvs[v]
	return Vector2.ZERO


## Each vertex's rest position for [DotViewArmsMaterial]'s pattern, four floats a vertex.
func _rest_positions(verts: PackedVector3Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(verts.size() * 4)
	for v in verts.size():
		out[v * 4] = verts[v].x
		out[v * 4 + 1] = verts[v].y
		out[v * 4 + 2] = verts[v].z
		out[v * 4 + 3] = 1.0
	return out


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


## A server's arm set for every player ([param p_look]), drawn in place of each one's own; null goes back to
## [member own_look]. Rebuilds only when the drawn look changes.
func set_look_override(p_look: DotHumanoidLook) -> void:
	var was := look
	_override = p_look
	if own_look != null and (_override if _override != null else own_look) != was:
		build(own_look, height)


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
	var held := _holding()
	if not (shown and held):
		for hand in _hands:
			hand.visible = false

	if _arms.has_method("set_motion"):
		_arms.call("set_motion", {"downed": _downed, "propped": false})
	if _arms.has_method("set_hold"):
		_arms.call("set_hold", DotHumanoidFigure.Hold.GUN if _grip != null and not _downed else DotHumanoidFigure.Hold.NONE)

	# Only a change of mode refits (the fit depends on nothing else): a refit on every weapon swap let two
	# unfitted ticks lean from where the last frame left the arms, then snapped them back, and the elbow jumped.
	if was != shown or held != _was_holding:
		_fitted = false
		_ticks = 0
	if was != shown or _grip != null or not _right.is_empty():
		_right.clear()
		_left.clear()
	_was_holding = held


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

		# Eased: a weapon swap set the next weapon's scale in one frame, and the elbow jumped 0.1 m mid-holster.
		_fore = move_toward(_fore, clampf(forearm_scale, 0.2, 1.5) if _holding() else 1.0, FORE_RATE * delta)
		var fore := _fore

		# Real hands draw in the mitts' place: the kit's own shrink to the wrist, where the forearm still ends.
		var mitt := 0.001 if _real_on() else (hand_scale if _holding() else 1.0) / fore
		for i in _fingers:
			skeleton.set_bone_pose_scale(i, Vector3.ONE * mitt)

		_scale_left(skeleton, fore)
		_delta = delta
		_reach(skeleton)
	_place_hands(skeleton)


## The real hands are drawn: built, a weapon held, and the arms up.
func _real_on() -> bool:
	return real_hands and _hands.size() == 2 and _holding() and _grip.is_valid()

func _left_hidden() -> bool:
	return _holding() and not show_idle_left_arm and not _grip.is_two_hand() and not _runs_left()


func _runs_left() -> bool:
	return is_finite(run) and run > 0.0 and _grip != null and not _grip.is_two_hand() and not show_idle_left_arm


func _scale_left(skeleton: Skeleton3D, fore: float) -> void:
	var hide := _left_hidden()
	# The mesh without the arm when there is one; else the arm shrinks to its shoulder (a factory's own figure).
	var swap := _one_arm_mesh != null and _arms is DotHumanoidFigure and (_arms as DotHumanoidFigure).mesh() != null
	if swap:
		var instance := (_arms as DotHumanoidFigure).mesh()
		var want := _one_arm_mesh if hide else _two_arm_mesh
		if instance.mesh != want:
			instance.mesh = want

	# The upper arm carries the scale (its child, the forearm, inherits it) so the sleeve shrinks about the shoulder joint.
	# With the arm's mesh dropped the bones still fold to the shoulder (the collar stays, it has no arm on it), so a
	# hidden arm is never left straight out in its rest T-pose for anything that reads the bones.
	for bone in ["Shoulder.L", "UpperArm.L", "LowerArm.L"]:
		var i := skeleton.find_bone(bone)
		if i >= 0:
			var folded: bool = hide and not (swap and bone == "Shoulder.L")
			skeleton.set_bone_pose_scale(i, Vector3.ONE * (0.001 if folded else (fore if bone == "UpperArm.L" else 1.0)))

	var upper := skeleton.find_bone("UpperArm.R")
	if upper >= 0:
		skeleton.set_bone_pose_scale(upper, Vector3.ONE * fore)

	var right := skeleton.find_bone("LowerArm.R")
	if right >= 0:
		skeleton.set_bone_pose_scale(right, Vector3.ONE)


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

	for bone in _extended:
		skeleton.set_bone_pose_position(bone, skeleton.get_bone_rest(bone).origin)
	_extended.clear()
	reach_extended_right = 0.0
	reach_extended_left = 0.0

	var targets := wrist_targets(_grip)
	var right_target: Vector3 = targets[0]
	var support_target: Vector3 = targets[1]
	_lean(skeleton, figure, right_target, support_target)

	var to_skeleton := skeleton.global_transform.affine_inverse()
	var out := to_skeleton.basis * (figure.global_transform.basis * elbow_pole)
	var drawn: Array = []
	hand_gap_right = 0.0
	hand_gap_left = 0.0

	arm_depth_right = 0.0
	arm_depth_left = 0.0

	if not _right.is_empty():
		reach_extended_right = _extend(skeleton, _right, right_target)
		var pole := _clear_pole(skeleton, _right, to_skeleton * right_target, out, true)
		DotHumanoidIk.two_bone(skeleton, _right, to_skeleton * right_target, pole, 1.0)
		drawn.append([_grip.grip_world(), right_target, "Middle1.R"])
		hand_gap_right = _gap(skeleton, _right, right_target)

	if not _left.is_empty() and not _left_hidden():
		var rest := figure.global_transform * (_base + LEFT_REST)
		var target := rest
		if _runs_left():
			var r := clampf(run, 0.0, 1.0)
			var swing := -sin(TAU * run_phase) if is_finite(run_phase) else 0.0
			target = global_transform * (run_left + run_left_pump * swing * r + RUN_LEFT_DROP * (1.0 - r))
		elif _grip.is_two_hand():
			reach_extended_left = _extend(skeleton, _left, support_target)
			# What the stretch could not cover slides toward the firing hand, as before it.
			target = _slide_to_reach(skeleton, _left, support_target, right_target + (support_target - _grip.support_world()))
		var left_pole := Vector3(-out.x, out.y, out.z)
		if _grip.is_two_hand():
			left_pole = _clear_pole(skeleton, _left, to_skeleton * target, left_pole, false)
		DotHumanoidIk.two_bone(skeleton, _left, to_skeleton * target, left_pole, 1.0)
		drawn.append([_grip.support_world() if _grip.is_two_hand() else rest, target, "Middle1.L"])
		hand_gap_left = _gap(skeleton, _left, target)

	if debug_pose:
		if _pose_debug == null:
			_pose_debug = DotViewArmsPoseDebug.new()
			add_child(_pose_debug)
		_pose_debug.draw(skeleton, drawn)


## The elbow direction (skeleton space) for an arm reaching [param target]: [param pole], turned about the
## shoulder-to-hand line to the least-buried of [constant CLEAR_ANGLES] when the arm would pass through the weapon.
## Eased part way each frame, so the elbow swings across rather than snapping.
func _clear_pole(skeleton: Skeleton3D, bones: Array[int], target: Vector3, pole: Vector3, right: bool) -> Vector3:
	var box := _grip.bounds_local().grow(arm_radius) if keep_arms_clear and _grip.bounds_local().has_volume() else AABB()
	var shoulder := DotHumanoidIk.global_pose(skeleton, bones[0]).origin
	var dir := (target - shoulder).normalized()
	if not box.has_volume() or not dir.is_normalized():
		return pole
	var lengths := _arm_lengths(skeleton, bones)
	var to_anchor := _grip.anchor.global_transform.affine_inverse() * skeleton.global_transform
	var up := skeleton.global_transform.basis.inverse() * (global_transform.basis * Vector3.UP)
	if not _native_tried:
		_native_tried = true
		if native_clear and ClassDB.class_exists(&"DotSimViewArms"):
			_native = ClassDB.instantiate(&"DotSimViewArms")
	var prev := _turn_right if right else _turn_left
	var r: PackedFloat64Array
	if _native != null:
		r = _native.clear_pole(shoulder, target, lengths, pole, dir, to_anchor, box, up, prev)
	else:
		r = DotViewArmsClear.scan(shoulder, target, lengths, pole, dir, to_anchor, box, up, prev)
	var turned := Vector3(r[0], r[1], r[2])
	var turn := r[3]
	var depth := r[4]
	if right:
		_turn_right = turn
		arm_depth_right = depth
	else:
		_turn_left = turn
		arm_depth_left = depth
	return turned


func _arm_lengths(skeleton: Skeleton3D, bones: Array[int]) -> Vector2:
	var upper := DotHumanoidIk.global_pose(skeleton, bones[0]).origin
	var lower := DotHumanoidIk.global_pose(skeleton, bones[1]).origin
	var wrist := DotHumanoidIk.global_pose(skeleton, bones[2]).origin
	return Vector2((lower - upper).length(), (wrist - lower).length())


## Leans the arms toward whichever hand target (firing or support) is furthest out of its arm's reach, a step at a time, by up to [member max_lean] in all.
func _lean(skeleton: Skeleton3D, figure: DotHumanoidFigure, target: Vector3, support_target: Vector3) -> void:
	if _right.is_empty() or max_lean <= 0.0 or not _fitted:
		_leaned = Vector3.ZERO
		return

	var goals: Array = [[_right, target]]

	if not _left.is_empty() and _grip.is_two_hand() and not _left_hidden() and support_target.is_finite():
		goals.append([_left, support_target])

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

	# Eased only as the lean shrinks: more lean than needed still reaches. A lean that has to grow is taken at once,
	# or the support hand slid off a two-hand grip drawn after a one-hand one (grenade_launcher draw 0.26 m for 4 frames).
	if lean.length() >= _leaned.length():
		_leaned = lean
	else:
		_leaned = _leaned.move_toward(lean, LEAN_RATE * _delta)
	figure.global_position += _leaned

## The point on the segment from [param from] to [param to] nearest [param from] that the arm can reach, or the point nearest the shoulder when none is.
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

	# A line that misses the reach ends at its nearest point to the shoulder, where the hit point would be as the line
	# grazes the reach. Answering [param to] there jumped the hand to the firing hand whenever the sway took the line
	# off the reach, and it flickered between the two from frame to frame.
	if disc < 0.0:
		return from + (to - from) * clampf(-b / (2.0 * a), 0.0, 1.0)

	return from + (to - from) * clampf((-b - sqrt(disc)) / (2.0 * a), 0.0, 1.0)


## Moves the arm's shoulder joint (the upper arm's pose position) out toward [param target] (world) by what the arm is
## still short of it, up to [member reach_extend_max]; the metres moved (figure space), 0 when it reaches already.
func _extend(skeleton: Skeleton3D, bones: Array[int], target: Vector3) -> float:
	if not extend_reach or bones.size() < 3 or not target.is_finite():
		return 0.0
	var to := skeleton.global_transform.affine_inverse() * target - DotHumanoidIk.global_pose(skeleton, bones[0]).origin
	var short := to.length() - _reach_local(skeleton, bones)
	if not (short > 0.0):
		return 0.0
	if reach_extend_max > 0.0:
		short = minf(short, reach_extend_max)
	var parent := skeleton.get_bone_parent(bones[0])
	var basis := DotHumanoidIk.global_pose(skeleton, parent).basis if parent >= 0 else Basis.IDENTITY
	skeleton.set_bone_pose_position(bones[0], skeleton.get_bone_pose_position(bones[0]) + basis.inverse() * (to.normalized() * short))
	_extended.append(bones[0])
	return short


## The firing and support hand poses for [param grip] from [member hand_poses] (the support one empty for one hand):
## its kind's, a rifle's for an unknown kind, a knife's blended toward the throw's pinch by [member throw_grip].
func _grip_hands(grip: DotViewGrip) -> Array:
	var rifle: Dictionary = hand_poses.get(DotViewHandPoses.RIFLE, {})
	var entry: Dictionary = hand_poses.get(grip.kind, rifle)
	var firing: Dictionary = entry.get(&"firing", rifle.get(&"firing", {}))
	if grip.kind == DotViewHandPoses.KNIFE and throw_grip > 0.0:
		var pinch: Dictionary = hand_poses.get(DotViewHandPoses.KNIFE_THROW, {})
		firing = DotViewHandPoses.blend(firing, pinch.get(&"firing", {}), clampf(throw_grip, 0.0, 1.0))
	var support: Dictionary = entry.get(&"support", {})
	if support.is_empty() and grip.is_two_hand():
		support = rifle.get(&"support", {})
	return [firing, support if grip.is_two_hand() else {}]


## A right-hand pose for the left hand: its directions mirrored across the weapon's vertical plane.
static func _mirrored(hand: Dictionary) -> Dictionary:
	var out := hand.duplicate()
	for key in [&"fingers", &"palm"]:
		if out.has(key):
			var v: Vector3 = out[key]
			out[key] = Vector3(-v.x, v.y, v.z)
	return out


## The real hands' world size: life size on the held arms, by [member hand_size] and [member hand_scale] over the mitts' 0.5.
func _hand_world_size() -> float:
	return held_scale * hand_size * hand_scale / 0.5 * global_transform.basis.get_scale().y


## Where each wrist (the kit's finger roots) goes on [param grip], world: [firing, support] (support INF for one hand).
## Real hands put the wrist where the hand's grip point lands on the weapon; the mitts take [member palm_offset].
func wrist_targets(grip: DotViewGrip) -> Array[Vector3]:
	var basis := global_transform.basis
	if not (real_hands and _hands.size() == 2):
		var mirrored := basis * Vector3(-palm_offset.x, palm_offset.y, palm_offset.z)
		return _kept_deep([grip.grip_world() + basis * palm_offset, grip.support_world() + mirrored if grip.is_two_hand() else Vector3.INF])
	var hands := _grip_hands(grip)
	var s := _hand_world_size()
	var forward := grip.forward_world()
	var up := grip.up_world()
	var centre: Vector3 = (hands[0] as Dictionary).get(&"centre", Vector3.ZERO)
	var right := grip.grip_world() - DotViewHandPoses.frame(hands[0], forward, up) * (centre * s)
	var left := Vector3.INF
	if grip.is_two_hand():
		var c: Vector3 = (hands[1] as Dictionary).get(&"centre", Vector3.ZERO)
		left = grip.support_world() - DotViewHandPoses.frame(hands[1], forward, up) * (Vector3(-c.x, c.y, c.z) * s)
	return _kept_deep([right, left])


## [param targets] with each finite one closer to the eye than [member hand_min_depth] moved out along the view's forward to it.
func _kept_deep(targets: Array[Vector3]) -> Array[Vector3]:
	if hand_min_depth <= 0.0:
		return targets
	var to_local := global_transform.affine_inverse()
	var ahead := -global_transform.basis.z.normalized()
	for i in targets.size():
		var p := targets[i]
		if not p.is_finite():
			continue
		var depth := -(to_local * p).z
		if depth < hand_min_depth:
			targets[i] = p + ahead * (hand_min_depth - depth)
	return targets


## Seats the real hands on the solved wrists and closes their fingers; hides them when they are not drawn.
func _place_hands(skeleton: Skeleton3D) -> void:
	if _hands.size() != 2:
		return
	var on := _real_on() and skeleton != null and not _right.is_empty()
	var left_on := on and not _left.is_empty() and not _left_hidden()
	_hands[0].visible = on
	_hands[1].visible = left_on
	if not on:
		return
	var hands := _grip_hands(_grip)
	var s := _hand_world_size()
	var rate := 1.0 if finger_rate <= 0.0 else 1.0 - exp(-finger_rate * _delta)
	var forward := _grip.forward_world()
	var up := _grip.up_world()
	_seat(_hands[0], skeleton, _right[2], hands[0], forward, up, s, rate)
	if not left_on:
		return
	var support: Dictionary = hands[1]
	if support.is_empty():
		# The free hand pumping in a sprint (or shown idle): a fist, knuckles to the view's front.
		support = _mirrored((hand_poses.get(DotViewHandPoses.FISTS, {}) as Dictionary).get(&"firing", {}))
		forward = global_transform.basis * Vector3.FORWARD
		up = global_transform.basis * Vector3.UP
	_seat(_hands[1], skeleton, _left[2], support, forward, up, s, rate)


func _seat(hand: DotViewHand, skeleton: Skeleton3D, wrist: int, pose: Dictionary, forward: Vector3, up: Vector3, s: float, rate: float) -> void:
	var at := skeleton.global_transform * DotHumanoidIk.global_pose(skeleton, wrist).origin
	hand.global_transform = Transform3D(DotViewHandPoses.frame(pose, forward, up) * s, at)
	hand.pose(pose, rate)


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


## The real hands, [firing, support] ([DotViewHand]), or empty before [method build] or for a factory's own figure.
func hands() -> Array[DotViewHand]:
	var out: Array[DotViewHand] = []
	for hand in _hands:
		out.append(hand)
	return out


## Metres from each wrist (the kit's middle-finger root) to where it goes on [param grip] (the real hands' seat, or
## the grip point plus [member palm_offset] for the mitts), the worst of the two; -1 when the arms are not shown on that grip.
func hand_error(grip: DotViewGrip) -> float:
	if not shown or grip == null or not grip.is_valid() or not (_arms is DotHumanoidFigure):
		return -1.0
	var skeleton := (_arms as DotHumanoidFigure).skeleton()
	if skeleton == null:
		return -1.0
	var targets := wrist_targets(grip)
	var pairs := [["Middle1.R", targets[0]]]
	if grip.is_two_hand():
		pairs.append(["Middle1.L", targets[1]])
	var worst := 0.0
	for pair: Array in pairs:
		var bone := skeleton.find_bone(pair[0])
		if bone < 0:
			return -1.0
		var at := skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin
		worst = maxf(worst, at.distance_to(pair[1]))
	return worst


func describe() -> Dictionary:
	return {"built": _arms != null, "shown": shown, "held": _holding(), "custom": arms_factory.is_valid(), "hidden_bones": _bones.size(),
		"overridden": _override != null, "detailed": _detail_on, "run": snappedf(run, 0.01),
		"real_hands": _real_on(), "left_arm": _arms != null and shown and not _left_hidden(), "reach_extended": snappedf(maxf(reach_extended_right, reach_extended_left), 0.001)}


func _clear() -> void:
	if _arms != null:
		remove_child(_arms)
		_arms.queue_free()
		_arms = null

	for hand in _hands:
		if is_instance_valid(hand):
			remove_child(hand)
			hand.queue_free()
	_hands.clear()
	_extended.clear()
	_two_arm_mesh = null
	_one_arm_mesh = null
	_bones.clear()
	_fingers.clear()
	_detail_on = false
