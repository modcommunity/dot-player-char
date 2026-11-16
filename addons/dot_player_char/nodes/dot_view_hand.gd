class_name DotViewHand
extends Node3D

## A first-person hand with five jointed fingers: one skinned mesh (palm, thumb and four fingers, three joints each) on
## its own small skeleton, built from tapered capsules at life size. [DotPlayerViewArms] puts one on each wrist and
## closes it on the weapon with a [DotViewHandPoses] grip. Made here, so it is free to use (CC0, like the people kit).
##
## The hand's frame: origin at the wrist, +Y toward the fingers, +Z out of the palm, +X toward the thumb (a left hand
## is the right one mirrored, so its thumb is at -X). A finger's curl turns each joint toward the palm.

## The fingers in pose order; a pose gives each three joint curls (degrees).
const FINGERS: Array[StringName] = [&"thumb", &"index", &"middle", &"ring", &"pinky"]
## Each finger's knuckle in the hand frame (metres, a right hand) and its three segment lengths, base to tip.
const KNUCKLES: Array[Vector3] = [Vector3(0.024, 0.022, 0.006), Vector3(0.029, 0.088, 0.0), Vector3(0.009, 0.092, 0.0),
	Vector3(-0.011, 0.088, 0.0), Vector3(-0.029, 0.079, 0.0)]
const SEGMENTS: Array[Vector3] = [Vector3(0.042, 0.032, 0.026), Vector3(0.042, 0.025, 0.021), Vector3(0.046, 0.029, 0.022),
	Vector3(0.043, 0.027, 0.021), Vector3(0.034, 0.021, 0.019)]
## Segment radius at the knuckle and at the tip, per finger.
const RADII: Array[Vector2] = [Vector2(0.0125, 0.0085), Vector2(0.0098, 0.0076), Vector2(0.0102, 0.0078),
	Vector2(0.0096, 0.0074), Vector2(0.0086, 0.0066)]
## How the fingers fan out at rest (degrees about the palm normal; + toward the thumb).
const SPLAY: Array[float] = [0.0, 4.0, 0.0, -4.0, -9.0]
## The thumb's rest direction from its base, and the way its joints bend (across the palm).
const THUMB_DIR := Vector3(0.62, 0.72, 0.3)
const THUMB_BEND := Vector3(-0.55, 0.15, 0.82)
## The palm's cross sections from the wrist to the knuckles: y, half width, half thickness (metres).
const PALM: Array[Vector3] = [Vector3(-0.03, 0.026, 0.019), Vector3(0.0, 0.029, 0.018), Vector3(0.03, 0.039, 0.017),
	Vector3(0.065, 0.043, 0.015), Vector3(0.088, 0.041, 0.012), Vector3(0.097, 0.036, 0.01)]
## Vertices around each ring of a capsule or the palm, and rings in each rounded end.
const AROUND := 12
const CAP_RINGS := 3

## Right hand (false mirrors it to a left one); set before the node enters the tree, or call [method build].
var right: bool = true
## Uniform size against life size: [DotPlayerViewArms] sets it to its held arms' scale.
var size: float = 1.0:
	set(value):
		size = value
		scale = Vector3.ONE * size
## The material the mesh draws with (the arms' own, so the hand shares their skin and the team avatars' family).
var material: Material = null:
	set(value):
		material = value
		if _mesh != null:
			_mesh.material_override = value
## Where on the arms' atlas the skin is read, so the swap and the painted bodies colour the hand as they do the arms.
var skin_uv: Vector2 = Vector2.ZERO

var _skeleton: Skeleton3D = null
var _mesh: MeshInstance3D = null
## Bone index of each finger's three joints, in [constant FINGERS] order.
var _joints: Array = []
## The pose drawn, eased toward the target each [method pose] call.
var _curls: Array[Vector3] = []
var _spread: float = 0.0
# The mesh being built. Packed arrays are values, so they live in members: one read out of a Dictionary is a copy.
var _v := PackedVector3Array()
var _n := PackedVector3Array()
var _b := PackedInt32Array()
var _w := PackedFloat32Array()
var _i := PackedInt32Array()


func _ready() -> void:
	if _skeleton == null:
		build()


## Makes the skeleton and the mesh (again, when [member right] or [member skin_uv] changed).
func build() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_skeleton = Skeleton3D.new()
	_skeleton.name = "Skeleton"
	add_child(_skeleton)
	var wrist := _skeleton.get_bone_count()
	_skeleton.add_bone("Wrist")
	_joints.clear()
	_curls.clear()
	for f in FINGERS.size():
		var chain: Array[int] = []
		var parent := wrist
		for j in 3:
			var bone := _skeleton.get_bone_count()
			_skeleton.add_bone("%s%d" % [FINGERS[f], j + 1])
			_skeleton.set_bone_parent(bone, parent)
			_skeleton.set_bone_rest(bone, _rest(f, j))
			chain.append(bone)
			parent = bone
		_joints.append(chain)
		_curls.append(Vector3.ZERO)
	_skeleton.reset_bone_poses()
	_mesh = MeshInstance3D.new()
	_mesh.name = "Mesh"
	_skeleton.add_child(_mesh)
	_mesh.mesh = _build_mesh()
	_mesh.skin = _build_skin()
	_mesh.skeleton = _mesh.get_path_to(_skeleton)
	_mesh.material_override = material


## A joint's rest in its parent's space: the base at the knuckle turned to the finger's direction, the rest along +Y.
func _rest(f: int, j: int) -> Transform3D:
	var lengths: Vector3 = SEGMENTS[f]
	if j > 0:
		return Transform3D(Basis.IDENTITY, Vector3(0.0, lengths[j - 1], 0.0))
	var basis := Basis(Vector3.BACK, deg_to_rad(SPLAY[f]))
	if f == 0:
		var y := THUMB_DIR.normalized()
		var z := (THUMB_BEND - y * THUMB_BEND.dot(y)).normalized()
		basis = Basis(y.cross(z), y, z)
	return _mirror(Transform3D(basis, KNUCKLES[f]))


## A right-hand frame as the left hand's: x flipped, which keeps the basis right-handed (two axes flip).
func _mirror(t: Transform3D) -> Transform3D:
	if right:
		return t
	var m := Basis.from_scale(Vector3(-1, 1, 1))
	return Transform3D(m * t.basis * m, m * t.origin)


func _build_skin() -> Skin:
	var skin := Skin.new()
	for bone in _skeleton.get_bone_count():
		skin.add_named_bind(_skeleton.get_bone_name(bone), _skeleton.get_bone_global_rest(bone).affine_inverse())
	return skin


func _build_mesh() -> ArrayMesh:
	_v = PackedVector3Array()
	_n = PackedVector3Array()
	_b = PackedInt32Array()
	_w = PackedFloat32Array()
	_i = PackedInt32Array()
	_palm()
	for f in FINGERS.size():
		var lengths: Vector3 = SEGMENTS[f]
		var radii: Vector2 = RADII[f]
		var total := lengths.x + lengths.y + lengths.z
		var along := 0.0
		for j in 3:
			var bone: int = _joints[f][j]
			var r0 := lerpf(radii.x, radii.y, along / total)
			along += lengths[j]
			var r1 := lerpf(radii.x, radii.y, along / total)
			_capsule(_skeleton.get_bone_global_rest(bone), lengths[j], r0, r1, bone)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _v
	arrays[Mesh.ARRAY_NORMAL] = _n
	arrays[Mesh.ARRAY_BONES] = _b
	arrays[Mesh.ARRAY_WEIGHTS] = _w
	arrays[Mesh.ARRAY_INDEX] = _i
	var uv := PackedVector2Array()
	uv.resize(_v.size())
	uv.fill(skin_uv)
	arrays[Mesh.ARRAY_TEX_UV] = uv
	var rest := PackedFloat32Array()
	for p: Vector3 in _v:
		rest.append_array([p.x, p.y, p.z, 1.0])
	arrays[Mesh.ARRAY_CUSTOM0] = rest
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, DotViewArmsMaterial.REST_FORMAT)
	return mesh


## One vertex, rigidly on [param bone].
func _vertex(p: Vector3, n: Vector3, bone: int) -> int:
	var at := _v.size()
	_v.append(p)
	_n.append(n.normalized())
	_b.append_array([bone, 0, 0, 0])
	_w.append_array([1.0, 0.0, 0.0, 0.0])
	return at


## Triangles of a grid of rings ([param rings] of [constant AROUND] vertices from [param first]), facing outward.
func _rings(first: int, rings: int) -> void:
	for r in rings - 1:
		for a in AROUND:
			var p := first + r * AROUND + a
			var q := first + r * AROUND + (a + 1) % AROUND
			_tri(p, q, p + AROUND)
			_tri(q, q + AROUND, p + AROUND)


func _tri(a: int, b: int, c: int) -> void:
	# (a, b, a + AROUND) runs clockwise seen from outside, Godot's front face. Both hands wind the same: the bones are
	# turned, not mirrored, and the palm is symmetric about x.
	_i.append_array([a, b, c])


## A capsule from the bone's origin along its +Y for [param length], radius [param r0] to [param r1], round both ends.
func _capsule(frame: Transform3D, length: float, r0: float, r1: float, bone: int) -> void:
	var first := _v.size()
	var rings: Array[Vector3] = []  # (y, radius, normal tilt toward +Y)
	for k in CAP_RINGS:
		var t := float(CAP_RINGS - k) / CAP_RINGS * PI * 0.5
		rings.append(Vector3(-sin(t) * r0 * 0.9, cos(t) * r0, -sin(t)))
	rings.append(Vector3(0.0, r0, 0.0))
	rings.append(Vector3(length, r1, 0.0))
	for k in range(1, CAP_RINGS + 1):
		var t := float(k) / CAP_RINGS * PI * 0.5
		rings.append(Vector3(length + sin(t) * r1 * 0.9, maxf(cos(t) * r1, r1 * 0.12), sin(t)))
	for ring in rings:
		for a in AROUND:
			var angle := TAU * a / AROUND
			var dir := Vector3(cos(angle), 0.0, sin(angle))
			# Fingers are a little flatter front to back than side to side.
			var local := Vector3(dir.x * ring.y, ring.x, dir.z * ring.y * 0.88)
			var normal := dir * sqrt(maxf(1.0 - ring.z * ring.z, 0.0)) + Vector3.UP * ring.z
			_vertex(frame * local, frame.basis * normal, bone)
	_rings(first, rings.size())
	_close(first, frame * Vector3(0.0, -r0 * 0.9, 0.0), -(frame.basis * Vector3.UP), bone, false)
	_close(first + (rings.size() - 1) * AROUND, frame * Vector3(0.0, length + r1 * 0.9, 0.0), frame.basis * Vector3.UP, bone, true)


## A fan closing the ring at [param ring_first] on a pole.
func _close(ring_first: int, pole: Vector3, normal: Vector3, bone: int, top: bool) -> void:
	var c := _vertex(pole, normal, bone)
	for a in AROUND:
		var p := ring_first + a
		var q := ring_first + (a + 1) % AROUND
		if top:
			_tri(p, q, c)
		else:
			_tri(q, p, c)


## The palm: rounded-rectangle rings from the wrist to the knuckles, on the wrist bone.
func _palm() -> void:
	var first := _v.size()
	for section in PALM:
		for a in AROUND:
			var angle := TAU * a / AROUND
			var c := cos(angle)
			var s := sin(angle)
			# A superellipse: flat on the palm and the back, round at the edges.
			var x := signf(c) * pow(absf(c), 0.6) * section.y
			var z := signf(s) * pow(absf(s), 0.6) * section.z
			_vertex(Vector3(x, section.x, z), Vector3(c / section.y, 0.0, s / section.z), 0)
	_rings(first, PALM.size())
	var low: Vector3 = PALM[0]
	var high: Vector3 = PALM[PALM.size() - 1]
	_close(first, Vector3(0.0, low.x - 0.004, 0.0), Vector3.DOWN, 0, false)
	_close(first + (PALM.size() - 1) * AROUND, Vector3(0.0, high.x + 0.004, 0.0), Vector3.UP, 0, true)


## Closes the fingers to [param curls] (a [DotViewHandPoses] hand: finger name to Vector3 joint degrees, `spread` in
## degrees), easing at [param rate] (1 = at once) so a new grip folds in rather than snaps.
func pose(curls: Dictionary, rate: float = 1.0) -> void:
	if _skeleton == null:
		build()
	_spread = lerpf(_spread, float(curls.get(&"spread", 0.0)), clampf(rate, 0.0, 1.0))
	for f in FINGERS.size():
		var want: Vector3 = curls.get(FINGERS[f], Vector3.ZERO)
		_curls[f] = _curls[f].lerp(want, clampf(rate, 0.0, 1.0))
		var chain: Array = _joints[f]
		for j in 3:
			var bone: int = chain[j]
			var bend := Basis(Vector3.RIGHT, deg_to_rad(_curls[f][j]))
			if j == 0 and f > 0:
				# Index toward the thumb, pinky away: a turn about the palm normal, + toward -x.
				var fan := _spread * (f - 2.0) / 2.0
				bend = Basis(Vector3.BACK, deg_to_rad(fan if right else -fan)) * bend
			var rest := _skeleton.get_bone_rest(bone)
			_skeleton.set_bone_pose_rotation(bone, (rest.basis * bend).get_rotation_quaternion())


## The current joint curls, finger name to Vector3 degrees (what [method pose] has eased to).
func curls() -> Dictionary:
	var out := {&"spread": _spread}
	for f in FINGERS.size():
		out[FINGERS[f]] = _curls[f]
	return out


## Where a finger's tip is, in this node's space (for tests and the pose debug).
func tip(finger: StringName) -> Vector3:
	var f := FINGERS.find(finger)
	if f < 0 or _skeleton == null:
		return Vector3.INF
	var bone: int = _joints[f][2]
	return _skeleton.transform * (_skeleton.get_bone_global_pose(bone) * Vector3(0.0, (SEGMENTS[f] as Vector3).z, 0.0))


func mesh_instance() -> MeshInstance3D:
	return _mesh
