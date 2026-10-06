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

	if meshes.is_empty():
		return null

	var rng := RandomNumberGenerator.new()
	rng.seed = p_seed

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
		if mesh.visible and mesh.mesh != null:
			out.append(mesh)

	for child in node.get_children():
		if child is Node3D and not (child as Node3D).visible:
			continue
		_collect(child, out)


func piece_count() -> int:
	return _pieces.size()


func _add_piece(source: MeshInstance3D, centre: Vector3, along: Vector3, rng: RandomNumberGenerator) -> void:
	var at := source.global_transform

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
