class_name DotRagdollNanChecks
extends RefCounted

## The ragdoll suite's stress section: many bodies die against walls for simulated minutes, from
## every direction, and no part may ever hold a non-finite transform or velocity. Split out of
## ragdoll_selftest to keep it under the file-size gate.

var suite: Node


func _init(host: Node) -> void:
	suite = host


static func finite(body: Node3D) -> bool:
	var t := body.global_transform
	for v: Vector3 in [t.origin, t.basis.x, t.basis.y, t.basis.z]:
		if not (is_finite(v.x) and is_finite(v.y) and is_finite(v.z)):
			return false
	if body is RigidBody3D:
		var r := body as RigidBody3D
		for v: Vector3 in [r.linear_velocity, r.angular_velocity]:
			if not (is_finite(v.x) and is_finite(v.y) and is_finite(v.z)):
				return false
	return true


func run() -> void:
	await _stress()
	await _sources()


func _stress() -> void:
	suite._section("bodies dying near walls for minutes never go non-finite")
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var mesh := ConcavePolygonShape3D.new()
	var faces := PackedVector3Array()
	for x in [1.2, -1.2]:
		faces.append_array(PackedVector3Array([
			Vector3(x, 0, -6), Vector3(x, 0, 6), Vector3(x, 5, 6),
			Vector3(x, 0, -6), Vector3(x, 5, 6), Vector3(x, 5, -6)]))
	mesh.set_faces(faces)
	shape.shape = mesh
	wall.add_child(shape)
	suite._world.add_child(wall)
	await suite.get_tree().physics_frame
	await suite.get_tree().physics_frame

	var yard := DotPlayerRagdolls.new()
	yard.rules.lifetime = 40.0
	yard.rules.max_count = 40
	yard.local_cap = 40
	suite._world.add_child(yard)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var reactions: Array[StringName] = [&"limp", &"faceplant", &"stiff", &"crumple"]
	var dirs: Array[Vector3] = [Vector3.ZERO, Vector3.UP, Vector3.DOWN, Vector3.RIGHT, Vector3.LEFT, Vector3(0.05, 1, 0.0), Vector3(1, -1, 1)]
	var bad := ""
	var frames := 0
	var kills := 0
	while frames < 60 * 45 and bad.is_empty():
		if frames % 20 == 0:
			var at := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(0.0, 0.5), rng.randf_range(-1.5, 1.5))
			var fig: Node3D = suite._figure(at)
			fig.rotate_y(rng.randf() * TAU)
			var dir: Vector3 = dirs[rng.randi() % dirs.size()]
			var speed := Vector3(rng.randf_range(-12, 12), rng.randf_range(-3, 8), rng.randf_range(-12, 12))
			var damage := rng.randf_range(10, 300)
			if kills % 5 == 4:
				# A bot whose own body went bad hands the ragdoll a bad velocity, direction or damage.
				match kills % 3:
					0: speed = Vector3(NAN, 0.0, 1.0)
					1: dir = Vector3(INF, 0.0, NAN)
					2: damage = NAN
			yard.spawn(fig, suite._death(reactions[rng.randi() % reactions.size()], dir, rng.randf() < 0.3, damage), speed)
			fig.queue_free()
			kills += 1
		await suite.get_tree().physics_frame
		frames += 1
		for body: DotPlayerRagdoll in yard.live():
			for node in body.part_nodes():
				if not finite(node):
					bad = "%s at frame %d" % [node.name, frames]
	suite._check(kills > 100, "%d bodies were killed over %d simulated seconds" % [kills, frames / 60])
	suite._check(bad.is_empty(), "no part went non-finite (%s)" % bad)
	yard.queue_free()
	wall.queue_free()


func _sources() -> void:
	suite._section("degenerate inputs are refused where the NaN would be born")
	var huge := Vector3(1e30, 0.0, 1e30)
	suite._check(finite3(DotPlayerRagdollMath.unit(huge, Vector3.UP)) and DotPlayerRagdollMath.unit(huge, Vector3.UP).is_normalized(), "a huge vector still normalises (its length overflows to inf)")
	suite._check(DotPlayerRagdollMath.unit(Vector3.ZERO, Vector3.UP) == Vector3.UP, "a zero vector gives the fallback")
	suite._check(DotPlayerRagdollMath.unit(Vector3(NAN, 1, 0), Vector3.UP) == Vector3.UP, "a NaN vector gives the fallback")
	suite._check(DotPlayerRagdollMath.ortho(Basis.from_scale(Vector3.ZERO)) == Basis.IDENTITY, "a zero-scaled basis gives the identity, not NaN")
	suite._check(DotPlayerRagdollMath.ortho(Basis.from_scale(Vector3(1, 0, 1))) == Basis.IDENTITY, "a flattened basis gives the identity")
	suite._check(finite3(DotPlayerRagdollMath.ortho(Basis.from_scale(Vector3(2, 2, 2)).rotated(Vector3.UP, 1.0)).x), "an ordinary scaled basis still orthonormalises")

	var yard := DotPlayerRagdolls.new()
	yard.rules.lifetime = 20.0
	suite._world.add_child(yard)
	var bad := ""
	var cases := [
		["huge direction", Vector3(1e30, 0, 1e30)],
		["vertical huge direction", Vector3(0, 1e38, 0)],
		["zero-scaled figure", Vector3.ZERO],
	]
	for c: Array in cases:
		for reaction: StringName in [&"limp", &"faceplant", &"stiff", &"crumple"]:
			var fig: Node3D = suite._figure(Vector3(0, 0.1, 0))
			if c[0] == "zero-scaled figure":
				fig.scale = Vector3.ZERO
			var body: DotPlayerRagdoll = yard.spawn(fig, suite._death(reaction, c[1], false, 100.0), Vector3.ZERO)
			fig.queue_free()
			if body == null:
				continue
			for i in 30:
				await suite.get_tree().physics_frame
				for node in body.part_nodes():
					if not finite(node):
						bad = "%s/%s %s" % [c[0], reaction, node.name]
			body.queue_free()
	suite._check(bad.is_empty(), "no part went non-finite from degenerate inputs (%s)" % bad)
	var fig2: Node3D = suite._figure(Vector3(0, 0.1, 0))
	var body2: DotPlayerRagdoll = yard.spawn(fig2, suite._death(&"limp"), Vector3.ZERO)
	fig2.queue_free()
	await suite.get_tree().physics_frame
	yard.rules.shootable = true
	yard.shoot(body2.global_position, Vector3(1e30, 1e30, 1e30), 4.0)
	yard.shoot(body2.global_position, Vector3.ONE, INF)
	yard.shoot(Vector3(NAN, 0, 0), Vector3.ONE, 4.0)
	for i in 5:
		await suite.get_tree().physics_frame
	var shot_bad := false
	for node in body2.part_nodes():
		shot_bad = shot_bad or not finite(node)
	suite._check(not shot_bad, "shots with a huge direction, an infinite impulse or a NaN point leave every part finite")
	yard.queue_free()


static func finite3(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)
