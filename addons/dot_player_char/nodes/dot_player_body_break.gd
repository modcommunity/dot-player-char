class_name DotPlayerBodyBreak
extends Node3D

## A body coming apart: the chosen meshes, copied into tumbling pieces that land, lie a
## while, and shrink away. See [DotPlayerBreakRules] for what decides how much.
##
## [b]Copies, then hides the originals[/b], rather than reparenting them: the body belongs
## to the player node, which a game frees or respawns on its own schedule, and a piece that
## was still the player's child would vanish with it mid-flight or come back on respawn.
## The pieces hang off [param world] (usually the player's parent) and free themselves.
##
## [b]Not for a server.[/b] Nothing here is simulated; a dedicated server never calls it.
## A headless client can, and the suite does — the pieces are real [RigidBody3D]s and need
## a physics world, not a renderer.

const CHANNEL := "player.break"

var rules: DotPlayerBreakRules = null

var _pieces: Array[RigidBody3D] = []
var _age: float = 0.0
var _sizes: Array[Vector3] = []


## Breaks [param body] apart under [param world]. Returns the node holding the pieces, or
## null when the rules say this death breaks nothing.
##
## [param origin] is where the hit landed, [param direction] the way it was travelling;
## [param p_seed] should be a function of the death (victim id and tick) so every viewer
## agrees. [param lethal] and [param critical] are the [DotDamage]'s.
static func break_apart(
	body: Node3D,
	world: Node,
	p_rules: DotPlayerBreakRules,
	origin: Vector3,
	direction: Vector3,
	p_seed: int,
	lethal: bool = true,
	critical: bool = true
) -> DotPlayerBodyBreak:
	if body == null or world == null or p_rules == null:
		return null

	if not p_rules.breaks(lethal, critical):
		return null

	var meshes := visible_meshes(body)
	var skinned := DotPlayerRagdoll.skinned_meshes(body)

	if meshes.is_empty() and skinned.is_empty():
		return null

	var rng := RandomNumberGenerator.new()
	rng.seed = p_seed

	if not skinned.is_empty():
		return _break_skinned(body, world, p_rules, skinned, direction, rng)

	var chosen: Array[MeshInstance3D] = []

	if p_rules.mode == DotPlayerBreakRules.Mode.EXPLODE:
		chosen = meshes
	else:
		var limbs := limbs_of(body, meshes, p_rules.limb_names)
		# Shuffled with the seeded stream, never with shuffle(): Array.shuffle uses the
		# global generator, which no two viewers share.
		for i in range(limbs.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var swap := limbs[i]
			limbs[i] = limbs[j]
			limbs[j] = swap
		for i in range(mini(p_rules.limbs, limbs.size())):
			chosen.append(limbs[i])

	if chosen.is_empty():
		return null

	var made := DotPlayerBodyBreak.new()
	made.name = "BodyBreak"
	made.rules = p_rules
	world.add_child(made)

	var centre := body.global_position + Vector3(0.0, 1.0, 0.0)
	var along := direction.normalized() if direction.length_squared() > 0.0001 else Vector3.ZERO

	for mesh in chosen:
		made._add_piece(mesh, centre, along, rng)
		mesh.visible = false

	if p_rules.mode == DotPlayerBreakRules.Mode.EXPLODE:
		body.visible = false

	DotLog.debug(CHANNEL, "body broke", {
		"mode": DotPlayerBreakRules.Mode.keys()[p_rules.mode],
		"pieces": made.piece_count(),
	})

	return made


## A skinned body comes apart by its bones: a limb (every bone of one role, and what hangs off
## them) is baked out of the skin where it is posed into a mesh of its own, which tumbles like any
## piece, and the limb's top bones are shrunk to nothing on the body, so the stump is where it
## joined. EXPLODE takes every limb and the head; the torso stays, as the ragdoll's.
##
## [b]Baked, not copied[/b]: a skinned mesh copied without its skeleton draws its bind pose, the
## whole standing body, which is what a critical threw across the room before this.
static func _break_skinned(
	body: Node3D, world: Node, p_rules: DotPlayerBreakRules, skinned: Array[MeshInstance3D],
	direction: Vector3, rng: RandomNumberGenerator
) -> DotPlayerBodyBreak:
	var skeleton := skinned[0].get_node(skinned[0].skeleton) as Skeleton3D
	var R := DotPlayerRagdoll.Role
	var named := {R.HEAD: "head", R.ARM_L: "arm", R.ARM_R: "arm", R.LEG_L: "leg", R.LEG_R: "leg"}
	var roles: Array[int] = []
	for role: int in [R.HEAD, R.ARM_L, R.ARM_R, R.LEG_L, R.LEG_R]:
		if p_rules.limb_names.has(named[role]) and not bones_of_role(skeleton, role).is_empty():
			roles.append(role)
	for i in range(roles.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap := roles[i]
		roles[i] = roles[j]
		roles[j] = swap
	var count := roles.size() if p_rules.mode == DotPlayerBreakRules.Mode.EXPLODE else mini(p_rules.limbs, roles.size())
	if count == 0:
		return null

	var made := DotPlayerBodyBreak.new()
	made.name = "BodyBreak"
	made.rules = p_rules
	world.add_child(made)
	var centre := body.global_position + Vector3(0.0, 1.0, 0.0)
	var along := direction.normalized() if direction.length_squared() > 0.0001 else Vector3.ZERO

	for k in range(count):
		var bones := bones_of_role(skeleton, roles[k])
		for mesh in skinned:
			var baked := bake_bones(mesh, skeleton, bones)
			if baked != null:
				made._add_piece(baked, centre, along, rng)
				baked.free()
		for bone in bones:
			var parent := skeleton.get_bone_parent(bone)
			if parent < 0 or not bones.has(parent):
				skeleton.set_bone_pose_scale(bone, Vector3.ONE * 0.001)

	DotLog.debug(CHANNEL, "skinned body broke", {"pieces": made.piece_count()})
	return made


## Every bone of [param role] on [param skeleton] (by [method DotPlayerRagdoll.role_of_name]) and
## every bone under them: an arm's fingers, a leg's foot.
static func bones_of_role(skeleton: Skeleton3D, role: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in skeleton.get_bone_count():
		var mine := DotPlayerRagdoll.role_of_name(skeleton.get_bone_name(i)) == role
		var p := skeleton.get_bone_parent(i)
		while not mine and p >= 0:
			if out.has(p):
				mine = true
			p = skeleton.get_bone_parent(p)
		if mine:
			out.append(i)
	# A bone listed before its parent: once more, now that the parents are in.
	for i in skeleton.get_bone_count():
		if out.has(i):
			continue
		var p := skeleton.get_bone_parent(i)
		while p >= 0:
			if out.has(p):
				out.append(i)
				break
			p = skeleton.get_bone_parent(p)
	return out


## The triangles of [param mesh] that [param bones] move (every corner's strongest bone among
## them), baked where they are posed now into a plain mesh in world space. Null when there are
## none, or the mesh's arrays cannot be read.
static func bake_bones(mesh: MeshInstance3D, skeleton: Skeleton3D, bones: PackedInt32Array) -> MeshInstance3D:
	var skin := mesh.skin
	if mesh.mesh == null or skin == null:
		return null
	var bind_bone := PackedInt32Array()
	for b in skin.get_bind_count():
		var bone := skin.get_bind_bone(b)
		bind_bone.append(bone if bone >= 0 else skeleton.find_bone(skin.get_bind_name(b)))
	var to_world := skeleton.global_transform
	var out_v := PackedVector3Array()
	var out_n := PackedVector3Array()
	var out_uv := PackedVector2Array()
	for surface in mesh.mesh.get_surface_count():
		var arrays := mesh.mesh.surface_get_arrays(surface)
		if arrays.size() <= Mesh.ARRAY_WEIGHTS or arrays[Mesh.ARRAY_VERTEX] == null or arrays[Mesh.ARRAY_BONES] == null:
			continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		var vb: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var vw: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(verts.size()))
		if verts.is_empty() or vb.is_empty():
			continue
		var per := vb.size() / verts.size()
		var poses := {}
		for t in range(0, index.size() - 2, 3):
			var corners := [index[t], index[t + 1], index[t + 2]]
			var keep := true
			for v: int in corners:
				var best := 0
				for k in per:
					if vw[v * per + k] > vw[v * per + best]:
						best = k
				var bind := vb[v * per + best]
				if bind < 0 or bind >= bind_bone.size() or not bones.has(bind_bone[bind]):
					keep = false
					break
			if not keep:
				continue
			for v: int in corners:
				var skinned_at := _skinning(v, per, vb, vw, bind_bone, skin, skeleton, poses)
				out_v.append(to_world * (skinned_at * verts[v]))
				out_n.append(((to_world.basis * skinned_at.basis) * (normals[v] if v < normals.size() else Vector3.UP)).normalized())
				out_uv.append(uvs[v] if v < uvs.size() else Vector2.ZERO)
	if out_v.is_empty():
		return null
	var arrays_out := []
	arrays_out.resize(Mesh.ARRAY_MAX)
	arrays_out[Mesh.ARRAY_VERTEX] = out_v
	arrays_out[Mesh.ARRAY_NORMAL] = out_n
	arrays_out[Mesh.ARRAY_TEX_UV] = out_uv
	# Centred on its own middle, placed there: a piece spins about where it is, not the origin.
	var middle := Vector3.ZERO
	for p in out_v:
		middle += p
	middle /= float(out_v.size())
	for i in out_v.size():
		out_v[i] -= middle
	arrays_out[Mesh.ARRAY_VERTEX] = out_v
	var baked := ArrayMesh.new()
	baked.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays_out)
	var piece := MeshInstance3D.new()
	piece.mesh = baked
	piece.position = middle
	piece.material_override = mesh.material_override if mesh.material_override != null else mesh.get_active_material(0)
	# Not in the tree: [method _add_piece] takes its transform as the world one.
	return piece


## A vertex's skinning transform (weighted bone poses times bind poses), in skeleton space.
static func _skinning(v: int, per: int, vb: PackedInt32Array, vw: PackedFloat32Array, bind_bone: PackedInt32Array,
		skin: Skin, skeleton: Skeleton3D, poses: Dictionary) -> Transform3D:
	var sum_basis := Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
	var sum_origin := Vector3.ZERO
	var total := 0.0
	for k in per:
		var w := vw[v * per + k]
		if w <= 0.0:
			continue
		var bind := vb[v * per + k]
		if bind < 0 or bind >= bind_bone.size() or bind_bone[bind] < 0:
			continue
		if not poses.has(bind):
			poses[bind] = skeleton.get_bone_global_pose(bind_bone[bind]) * skin.get_bind_pose(bind)
		var t: Transform3D = poses[bind]
		sum_basis = Basis(sum_basis.x + t.basis.x * w, sum_basis.y + t.basis.y * w, sum_basis.z + t.basis.z * w)
		sum_origin += t.origin * w
		total += w
	if total <= 0.0:
		return Transform3D.IDENTITY
	return Transform3D(Basis(sum_basis.x / total, sum_basis.y / total, sum_basis.z / total), sum_origin / total)


## Every visible mesh under [param body], in tree order.
static func visible_meshes(body: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	_collect(body, out)
	return out


## The meshes in [param meshes] whose own name or an ancestor's (up to [param body]) holds
## one of [param names].
static func limbs_of(
	body: Node, meshes: Array[MeshInstance3D], names: PackedStringArray
) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []

	for mesh in meshes:
		var node: Node = mesh
		var found := false

		while node != null and not found:
			var lower := String(node.name).to_lower()
			for fragment in names:
				if fragment != "" and lower.contains(fragment.to_lower()):
					found = true
					break
			if node == body:
				break
			node = node.get_parent()

		if found:
			out.append(mesh)

	return out


static func _collect(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		var mesh := node as MeshInstance3D
		# Not a skinned mesh: copied without its skeleton it draws its bind pose, so a critical
		# on a skinned person threw a whole standing body across the room as one "limb". A
		# skinned body has no separate limbs to take off; its death is the ragdoll's.
		if mesh.visible and mesh.mesh != null and mesh.skin == null:
			out.append(mesh)

	for child in node.get_children():
		# A top_level child (shot effects in world space) does not move with the body.
		if child is Node3D and (not (child as Node3D).visible or (child as Node3D).top_level):
			continue
		_collect(child, out)


func piece_count() -> int:
	return _pieces.size()


func _add_piece(source: MeshInstance3D, centre: Vector3, along: Vector3, rng: RandomNumberGenerator) -> void:
	# A baked limb is not in the tree, and its own transform is the world one.
	var at := source.global_transform if source.is_inside_tree() else source.transform

	var piece := RigidBody3D.new()
	piece.collision_layer = 0
	piece.collision_mask = rules.collision_mask
	add_child(piece)
	piece.global_transform = Transform3D(at.basis.orthonormalized(), at.origin)

	var copy := MeshInstance3D.new()
	copy.mesh = source.mesh
	copy.material_override = source.material_override
	for i in range(source.get_surface_override_material_count()):
		copy.set_surface_override_material(i, source.get_surface_override_material(i))
	# The scale stays on the copy, not the body: a RigidBody3D's own scale is reset by the
	# physics server every step.
	copy.scale = at.basis.get_scale()
	piece.add_child(copy)

	var bounds := source.mesh.get_aabb()
	var size := (bounds.size * at.basis.get_scale()).abs()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(maxf(size.x, 0.05), maxf(size.y, 0.05), maxf(size.z, 0.05))
	shape.shape = box
	shape.position = bounds.get_center() * at.basis.get_scale()
	piece.add_child(shape)

	var outward := at.origin - centre
	outward = outward.normalized() if outward.length_squared() > 0.0001 else Vector3.UP
	var jitter := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.5, 1.0), rng.randf_range(-1.0, 1.0))
	piece.linear_velocity = (
		(outward + jitter * 0.4).normalized() * rules.force
		+ along * rules.push
		+ Vector3.UP * rules.lift
	)
	piece.angular_velocity = Vector3(
		rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)
	) * rules.spin

	_pieces.append(piece)
	_sizes.append(copy.scale)


func _process(delta: float) -> void:
	advance(delta)


## Ages the pieces; public so a suite can drive it without waiting.
func advance(delta: float) -> void:
	_age += delta

	if rules == null or _age < rules.lifetime:
		return

	var left := 1.0 - clampf((_age - rules.lifetime) / maxf(rules.fade, 0.01), 0.0, 1.0)

	if left <= 0.0:
		queue_free()
		return

	for i in range(_pieces.size()):
		var piece := _pieces[i]
		if is_instance_valid(piece) and piece.get_child_count() > 0:
			(piece.get_child(0) as Node3D).scale = _sizes[i] * left


func describe() -> Dictionary:
	return {"pieces": _pieces.size(), "age": _age}
