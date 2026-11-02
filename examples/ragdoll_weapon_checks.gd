class_name DotRagdollWeaponChecks
extends RefCounted

## The ragdoll suite's heavy-drop, cvar-default and dropped-weapon section, split out to keep
## ragdoll_selftest under the file-size gate. Reports through the suite's `_check` and `_section`.

var suite: Node


func _init(host: Node) -> void:
	suite = host


func run() -> void:
	suite._section("the heavy drop, the cvar defaults and the dropped weapon")
	var r := DotPlayerRagdollRules.new()
	suite._check(not r.exaggerate and not r.shootable, "exaggerate and shootable are off by default")
	suite._check(is_equal_approx(r.torque_scale, 1.0) and r.weapon_drop, "torque 1, weapon drop on by default")
	suite._check(r.reactions().find(&"headshot_launch").weight == 0.0, "launch reactions are not drawn by default")
	suite._check(r.reactions().pick(true, 1.0, 100.0, &"power_launch", 7) != &"power_launch", "a weapon naming a launch falls through")
	var specs := r.cvar_specs().map(func(d: Dictionary) -> String: return String(d["name"]))
	for name in ["sv_ragdoll_torque", "sv_ragdoll_exaggerate", "sv_ragdoll_shootable", "sv_ragdoll_weapon_drop", "sv_ragdoll_weapon_time"]:
		suite._check(specs.has(name), "%s is a cvar" % name)
	suite._check(r.set_cvar("sv_ragdoll_exaggerate", "1") and r.reactions().find(&"headshot_launch").weight > 0.0, "exaggerate brings the launches back")
	suite._check(r.set_cvar("sv_ragdoll_max", "200") and r.max_count == 200, "the body cap goes past 64")

	var yard := DotPlayerRagdolls.new()
	yard.local_cap = 64
	suite._world.add_child(yard)
	var launch := DotPlayerDeathReactions.stock().find(&"headshot_launch")
	var made := DotPlayerRagdoll.build(suite._figure(Vector3(0, 0, 40)), yard, yard.rules, launch, suite._death(&"headshot_launch", Vector3(0, 0, 1), true), Vector3.ZERO)
	var top := 0.0
	for node in made.part_nodes():
		top = maxf(top, (node as RigidBody3D).linear_velocity.y)
	suite._check(top < 1.0, "a launch reaction does not throw the body up by default (%.2f m/s)" % top)
	suite._check((made.part_nodes()[0] as RigidBody3D).gravity_scale > 1.0, "a falling body is heavier than gravity alone")

	await _check_weapon_drop(yard)


## The dropped weapon prop: its mesh, what it leaves out, and shooting a lying body.
func _check_weapon_drop(yard: DotPlayerRagdolls) -> void:
	var gun := Node3D.new()
	var gun_mesh := MeshInstance3D.new()
	gun_mesh.mesh = BoxMesh.new()
	gun.add_child(gun_mesh)
	suite._world.add_child(gun)
	gun.global_position = Vector3(0, 3, 40)
	var dropped := yard.drop_prop(gun)
	suite._check(dropped != null and dropped.get_child_count() >= 2, "the weapon drops as a physics prop with its mesh")
	for i in range(90):
		await suite.get_tree().physics_frame
	suite._check(dropped != null and dropped.global_position.y < 3.0, "and falls (y %.2f)" % (dropped.global_position.y if dropped != null else 0.0))
	var flash := _FlashStub.new()
	var flash_mesh := MeshInstance3D.new()
	var big := BoxMesh.new()
	big.size = Vector3(1, 1, 6)
	flash_mesh.mesh = big
	flash.add_child(flash_mesh)
	gun.add_child(flash)
	var with_flash := yard.drop_prop(gun)
	var span := 0.0
	if with_flash != null:
		span = ((with_flash.get_child(0) as CollisionShape3D).shape as BoxShape3D).size.z
	suite._check(with_flash != null and with_flash.get_child_count() == 2 and span < 2.0, "a muzzle flash under the gun is left out of the prop (collider %.2f m)" % span)
	flash.queue_free()
	var fx_root := Node3D.new()
	fx_root.top_level = true
	gun.add_child(fx_root)
	var mark := MeshInstance3D.new()
	mark.mesh = BoxMesh.new()
	fx_root.add_child(mark)
	mark.global_position = Vector3(20, 3, 40)
	var with_marks := yard.drop_prop(gun)
	span = 0.0
	if with_marks != null:
		span = ((with_marks.get_child(0) as CollisionShape3D).shape as BoxShape3D).size.x
	suite._check(with_marks != null and with_marks.get_child_count() == 2 and span < 2.0, "shot marks in world space under the gun are left out of the prop (collider %.2f m)" % span)
	var person: Node3D = suite._figure(Vector3(-6, 0, 40))
	var stray := MeshInstance3D.new()
	stray.mesh = BoxMesh.new()
	stray.top_level = true
	person.add_child(stray)
	stray.global_position = Vector3(-6, 9, 40)
	suite._check(not DotPlayerRagdoll.meshes_of(person).has(stray), "a body copies no world-space effect hung under its figure")
	person.queue_free()
	fx_root.queue_free()
	yard.rules.weapon_drop = false
	suite._check(yard.drop_prop(gun) == null, "weapon_drop off drops nothing")
	suite._check(not yard.shoot(Vector3(0, 1, 40), Vector3.FORWARD), "shooting a body does nothing by default")
	yard.rules.shootable = true
	var lying := yard.spawn(suite._figure(Vector3(6, 0, 40)), suite._death(&"limp"))
	var shot := yard.shoot(lying.centre(), Vector3.FORWARD)
	suite._check(shot, "with shootable on, a shot finds a part")
	yard.clear()
	# A dropped weapon freed by clear() before its timer fires must not raise on the timeout.
	yard.rules.weapon_drop = true
	yard.rules.weapon_lifetime = 0.5
	var fleeting := yard.drop_prop(gun)
	yard.clear()
	if is_instance_valid(fleeting):
		fleeting.queue_free()
	await suite.get_tree().create_timer(0.8).timeout
	suite._check(true, "a weapon freed before its timer fires expires without an error")


class _FlashStub extends Node3D:
	func fire() -> bool:
		return true

	func is_showing() -> bool:
		return true
