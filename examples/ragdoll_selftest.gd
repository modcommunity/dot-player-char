extends Node

## Exercises dead bodies: the reaction rule, the server's cvars, the death that travels, and real
## ragdolls falling onto a real floor in a physics world (headless; no renderer needed).
##
## [b]The rule is checked by counting[/b], over a thousand seeds, because a weighted draw that is
## wrong by a factor of two still "picks a reaction" every time. [b]The bodies are checked where
## they end up[/b] (lying down, not through the floor, frozen), because a body that is built
## correctly and then stands there, or falls through the world, passes every check that only
## asks what was built. What a fall LOOKS like is not here: that is the contact sheets.
##
## [codeblock]
## godot --headless --path . res://examples/ragdoll_selftest.tscn
## [/codeblock]

const SECTIONS := 11
const CHECKS := 105

var _passed := 0
var _failed := 0
var _section_count := 0
var _world: Node3D = null


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run()


func _run() -> void:
	_line("dot-player-char ragdoll self-test")
	_line("")

	_test_reactions()
	_test_weights()
	_test_death()
	_test_rules()
	_test_roles()
	_build_world()
	await _test_ragdoll_falls()
	await _test_styles()
	await _test_cap_and_life()
	await _test_skinned()
	await _test_faceplant_sweep()
	await _test_weight_and_weapon()

	_line("")
	_line("%d sections, %d passed, %d failed" % [_section_count, _passed, _failed])

	if _section_count != SECTIONS:
		_line("ERROR: %d of %d sections ran." % [_section_count, SECTIONS])
		get_tree().quit(1)
		return

	if _passed + _failed != CHECKS:
		_line("ERROR: %d checks ran, %d expected. A section aborted part-way." % [_passed + _failed, CHECKS])
		get_tree().quit(1)
		return

	get_tree().quit(1 if _failed > 0 else 0)


# --- The rule ----------------------------------------------------------------

func _count(reactions: DotPlayerDeathReactions, headshot: bool, power: float, damage: float, named: StringName, n: int) -> Dictionary:
	var out := {}
	for i in range(n):
		var id := reactions.pick(headshot, power, damage, named, DotPlayerDeath.seed_of(i, 1000 + i))
		out[id] = int(out.get(id, 0)) + 1
	return out


func _test_reactions() -> void:
	_section("which reaction a death picks")
	var r := DotPlayerDeathReactions.stock()
	_check(r.size() == 5 and r.has(&"limp") and r.has(&"headshot_launch") and r.has(&"power_launch")
		and r.has(&"face_plant") and r.has(&"crumple"), "the stock set is limp, two launches, face plant and crumple")

	var plain := _count(r, false, 0.0, 50.0, &"", 1000)
	_check(not plain.has(&"headshot_launch") and not plain.has(&"power_launch"),
		"an ordinary kill never launches (%s)" % str(plain))
	# limp 4, face_plant 1.5, crumple 2.5 of 8: half, three-sixteenths, five-sixteenths.
	var limp_share := float(plain.get(&"limp", 0)) / 1000.0
	var plant_share := float(plain.get(&"face_plant", 0)) / 1000.0
	_check(absf(limp_share - 0.5) < 0.06 and absf(plant_share - 0.1875) < 0.05,
		"by weight: limp %.2f of 0.50, face plant %.2f of 0.19" % [limp_share, plant_share])

	var heads := _count(r, true, 0.0, 50.0, &"", 1000)
	var launch_share := float(heads.get(&"headshot_launch", 0)) / 1000.0
	_check(absf(launch_share - 6.0 / 14.0) < 0.06, "a headshot launches about 6 times in 14 (%.2f)" % launch_share)

	var heavy := _count(r, false, 0.8, 120.0, &"", 1000)
	_check(heavy.has(&"power_launch") and not heavy.has(&"headshot_launch"),
		"a powerful weapon may launch, and a body shot never headshot-launches")
	var weak := _count(r, false, 0.3, 120.0, &"", 500)
	_check(not weak.has(&"power_launch"), "a weapon under min_power never power-launches")

	var named := _count(r, false, 0.0, 10.0, &"power_launch", 200)
	_check(named.get(&"power_launch", 0) == 200, "a weapon that names a reaction gets it every time")
	var unknown := _count(r, false, 0.0, 10.0, &"no_such", 200)
	_check(not unknown.has(&"no_such"), "a weapon naming an unknown reaction falls through to the draw")

	_check(r.pick(true, 0.0, 50.0, &"", 777) == r.pick(true, 0.0, 50.0, &"", 777),
		"the same seed picks the same reaction")


func _test_weights() -> void:
	_section("weights a server sets")
	var r := DotPlayerDeathReactions.stock()
	_check(r.apply_weights("face_plant=0, crumple=0") == 2, "two weights read")
	var counted := _count(r, false, 0.0, 50.0, &"", 500)
	_check(counted.get(&"limp", 0) == 500, "with face plant and crumple at 0, every ordinary death is limp")

	r.apply_weights("limp=0")
	_check(r.pick(false, 0.0, 50.0, &"", 5) == &"limp", "nothing left to draw is still a limp fall")

	var r2 := DotPlayerDeathReactions.stock()
	_check(r2.apply_weights("bogus=3,face_plant=x,limp:2") == 1, "an unknown id and a non-number are skipped; id:weight is read")
	_check(r2.find(&"limp").weight == 2.0, "and the one it read took")

	r2.apply_weights("power_launch=0")
	_check(r2.pick(false, 0.0, 10.0, &"power_launch", 1) != &"power_launch",
		"a weapon cannot force a reaction the server turned off")

	var def := RefCounted.new()
	_check(DotPlayerDeathReactions.weapon_reaction(def) == &"" and DotPlayerDeathReactions.weapon_power(null) == 0.0,
		"an object with no params names nothing and has no power")
	var with_params := _FakeWeapon.new()
	with_params.params = {&"death_reaction": &"power_launch", &"death_power": 0.9}
	_check(DotPlayerDeathReactions.weapon_reaction(with_params) == &"power_launch"
		and is_equal_approx(DotPlayerDeathReactions.weapon_power(with_params), 0.9),
		"a weapon def's params.death_reaction and death_power are read")


class _FakeWeapon:
	extends RefCounted
	var params: Dictionary = {}


func _test_death() -> void:
	_section("the death that travels with a kill")
	var r := DotPlayerDeathReactions.stock()
	var w := _FakeWeapon.new()
	w.params = {&"death_power": 1.0}
	var d := DotPlayerDeath.decide(r, false, 150.0, Vector3(2, 0, 0), 4242, w)
	_check(d.direction.is_equal_approx(Vector3.RIGHT), "the direction is normalised")
	var back := DotPlayerDeath.from_dict(d.to_dict())
	_check(back.reaction == d.reaction and back.roll_seed == d.roll_seed and back.direction == d.direction
		and back.damage == d.damage and back.headshot == d.headshot, "to_dict and from_dict round-trip (%s)" % d.reaction)
	var old := DotPlayerDeath.from_dict({"killer_id": 1})
	_check(old.reaction == &"limp" and old.direction == Vector3.ZERO, "a kill from an older server is a plain fall")
	_check(DotPlayerDeath.seed_of(3, 100) == DotPlayerDeath.seed_of(3, 100)
		and DotPlayerDeath.seed_of(3, 100) != DotPlayerDeath.seed_of(3, 101), "seed_of is stable and spreads")
	var twice := DotPlayerDeath.decide(r, false, 150.0, Vector3.RIGHT, 4242, w)
	_check(twice.reaction == d.reaction, "the server deciding the same kill twice decides the same")
	_check(DotPlayerDeath.decide(r, false, 10.0, Vector3.RIGHT, 1, null, -1.0, &"face_plant").reaction == &"face_plant",
		"a game whose killer is no weapon names the reaction itself")

	var wire := _FakeWire.new()
	d.headshot = true
	d.write_to(wire)
	var read := DotPlayerDeath.read_from(wire)
	_check(read.reaction == d.reaction and read.roll_seed == d.roll_seed and read.damage == 150.0
		and read.direction == d.direction and read.headshot, "write_to and read_from carry it over a writer and a reader")


## Stands in for dot-net's writer and reader, which this addon does not depend on: what is
## written comes back in order.
class _FakeWire:
	extends RefCounted
	var _q: Array = []
	func write_string(v: String, _n: int) -> void: _q.append(v)
	func write_varint(v: int) -> void: _q.append(v)
	func write_bool(v: bool) -> void: _q.append(v)
	func write_direction(v: Vector3, _bits: int) -> void: _q.append(v)
	func read_string(_n: int) -> String: return _q.pop_front()
	func read_varint() -> int: return _q.pop_front()
	func read_bool() -> bool: return _q.pop_front()
	func read_direction(_bits: int) -> Vector3: return _q.pop_front()


# --- Rules and cvars -------------------------------------------------------------

class _FakeCvar:
	extends RefCounted
	signal changed(old: String, new_value: String)
	var value := ""
	func get_string() -> String:
		return value
	func set_string(v: String) -> void:
		var old := value
		value = v
		changed.emit(old, v)


class _FakeLink:
	extends RefCounted
	signal replicated_cvar_changed(cvar_name: String, value: String)
	var held := {}
	func replicated_cvar(cvar_name: String, fallback: String) -> String:
		return str(held.get(cvar_name, fallback))


var _made_cvars := {}


func _add_cvar(cvar_name: String, default: String, _description: String, _flags: int) -> Object:
	var cv := _FakeCvar.new()
	cv.value = default if cvar_name != "sv_ragdoll_max" else "5"
	_made_cvars[cvar_name] = cv
	return cv


func _test_rules() -> void:
	_section("the server's rules")
	var rules := DotPlayerRagdollRules.new()
	_check(rules.effective_style() == DotPlayerRagdollRules.Style.RAGDOLL, "ragdolls by default")
	var made := rules.bind_cvars(_add_cvar)
	_check(made.size() == 11, "eleven sv_ragdoll cvars")
	_check(rules.max_count == 5, "a value the cvar already held is read back (sv_ragdoll_max 5)")
	(_made_cvars["sv_ragdoll"] as _FakeCvar).set_string("0")
	_check(not rules.enabled and rules.effective_style() == DotPlayerRagdollRules.Style.TOPPLE,
		"sv_ragdoll 0 falls back to the no-physics topple")
	(_made_cvars["sv_ragdoll_style"] as _FakeCvar).set_string("hide")
	_check(rules.effective_style() == DotPlayerRagdollRules.Style.HIDE, "sv_ragdoll_style hide hides, on or off")
	(_made_cvars["sv_ragdoll_style"] as _FakeCvar).set_string("cartwheel")
	_check(rules.style == DotPlayerRagdollRules.Style.HIDE, "a style it does not know is refused")
	(_made_cvars["sv_ragdoll_time"] as _FakeCvar).set_string("3.5")
	(_made_cvars["sv_ragdoll_reactions"] as _FakeCvar).set_string("face_plant=9")
	_check(rules.lifetime == 3.5 and rules.reactions().find(&"face_plant").weight == 9.0,
		"lifetime and reaction weights follow their cvars")

	var client := DotPlayerRagdollRules.new()
	var link := _FakeLink.new()
	link.held = {"sv_ragdoll_style": "stiff", "sv_ragdoll_max": "3"}
	_check(client.follow_cvars(link) and client.style == DotPlayerRagdollRules.Style.STIFF and client.max_count == 3,
		"a client follows the server's replicated values")
	link.replicated_cvar_changed.emit("sv_ragdoll", "0")
	_check(not client.enabled, "and every change after")
	_check(not client.follow_cvars(RefCounted.new()), "a link that cannot replicate is refused")


# --- Roles -------------------------------------------------------------------

func _test_roles() -> void:
	_section("which part is which")
	var R := DotPlayerRagdoll.Role
	_check(DotPlayerRagdoll.role_of_name("leg-left") == R.LEG_L and DotPlayerRagdoll.role_of_name("arm-right") == R.ARM_R
		and DotPlayerRagdoll.role_of_name("torso") == R.TORSO and DotPlayerRagdoll.role_of_name("head") == R.HEAD,
		"the block characters' names")
	_check(DotPlayerRagdoll.role_of_name("LeftHand") == R.ARM_L and DotPlayerRagdoll.role_of_name("RightFoot") == R.LEG_R
		and DotPlayerRagdoll.role_of_name("Chest") == R.TORSO, "the humanoid mount names")
	_check(DotPlayerRagdoll.role_of_name("arm") == R.OTHER and DotPlayerRagdoll.role_of_name("crest") == R.OTHER,
		"an arm with no side, and a crest, are not a limb")


# --- Bodies --------------------------------------------------------------------

func _build_world() -> void:
	_world = Node3D.new()
	add_child(_world)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	shape.shape = box
	shape.position = Vector3(0, -0.5, 0)
	floor_body.add_child(shape)
	_world.add_child(floor_body)


## A block figure in the kit's shape, 1.8 m tall, feet at [param at], facing -Z.
func _figure(at: Vector3, named := true) -> Node3D:
	var fig := Node3D.new()
	fig.name = "Figure"
	_world.add_child(fig)
	fig.global_position = at
	var k := 1.8 / 2.7
	# name, centre (kit units), size (kit units)
	for spec: Array in [
		["leg-left", Vector3(0.2, 0.5, 0), Vector3(0.4, 1.0, 0.4)],
		["leg-right", Vector3(-0.2, 0.5, 0), Vector3(0.4, 1.0, 0.4)],
		["torso", Vector3(0, 1.45, 0), Vector3(0.8, 0.9, 0.6)],
		["arm-left", Vector3(0.6, 1.35, -0.1), Vector3(0.4, 1.1, 0.4)],
		["arm-right", Vector3(-0.6, 1.35, -0.1), Vector3(0.4, 1.1, 0.4)],
		["head", Vector3(0, 2.3, 0), Vector3(0.8, 0.8, 0.8)],
		["crest", Vector3(0, 2.8, 0), Vector3(0.2, 0.2, 0.6)],
	]:
		var mesh := MeshInstance3D.new()
		mesh.name = String(spec[0]) if named else "Part%d" % fig.get_child_count()
		var bm := BoxMesh.new()
		bm.size = spec[2] * k
		mesh.mesh = bm
		mesh.position = spec[1] * k
		fig.add_child(mesh)
	return fig


func _settle(body: DotPlayerRagdoll, seconds: float) -> void:
	var waited := 0.0
	while waited < seconds and is_instance_valid(body) and not body.settled:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()


func _death(reaction: StringName, dir := Vector3(0, 0, 1), headshot := false, damage := 100.0) -> DotPlayerDeath:
	var d := DotPlayerDeath.new()
	d.reaction = reaction
	d.roll_seed = 99
	d.direction = dir
	d.headshot = headshot
	d.damage = damage
	return d


func _test_ragdoll_falls() -> void:
	_section("a ragdoll falls, lies down and stops")
	var yard := DotPlayerRagdolls.new()
	yard.rules.lifetime = 60.0
	_world.add_child(yard)
	var heard: Array[StringName] = []
	yard.sound.connect(func(id: StringName, _at: Vector3, _v: float) -> void: heard.append(id))

	var fig := _figure(Vector3(0, 0, 0))
	var body := yard.spawn(fig, _death(&"limp"))
	_check(body != null and body.part_count() == 6 and body.joint_count() == 5,
		"six parts (the crest rides on the head), five joints")
	_check(not fig.visible, "the figure is hidden")
	var parts := body.part_nodes()
	_check(parts.all(func(p: Node3D) -> bool: return p is RigidBody3D and (p as RigidBody3D).collision_layer == 0),
		"every part is a rigid body nothing collides with")
	await _settle(body, 8.0)
	_check(body.settled, "it settles and freezes (%s)" % str(body.describe()))
	_check(body.lowest_point() > -0.12, "nothing is through the floor (lowest %.2f m)" % body.lowest_point())
	_check(body.centre().y < 0.6, "it is lying down (torso at %.2f m)" % body.centre().y)
	_check(heard.has(&"ragdoll.thud"), "and it thudded once it hit the floor")

	heard.clear()
	var plant := yard.spawn(_figure(Vector3(4, 0, 0)), _death(&"face_plant"))
	var forward := Vector3(0, 0, -1)
	await _settle(plant, 8.0)
	_check(plant.settled and plant.landed, "a face plant lands and settles")
	_check((plant.centre() - Vector3(4, 0, 0)).dot(forward) > 0.3, "forward, onto its face (%.2f m ahead)" % (plant.centre() - Vector3(4, 0, 0)).dot(forward))
	_check(heard.count(&"ragdoll.face_plant") == 1, "with exactly one face-plant smack")

	heard.clear()
	yard.rules.exaggerate = true
	var launched := yard.spawn(_figure(Vector3(-4, 0, 0)), _death(&"headshot_launch", Vector3(0, 0, 1), true, 100.0))
	var top := 0.0
	for i in range(40):
		await get_tree().physics_frame
		if is_instance_valid(launched):
			top = maxf(top, launched.centre().y)
	_check(top > 2.0, "a headshot launch throws the body up (torso reached %.1f m)" % top)
	yard.rules.exaggerate = false
	await get_tree().process_frame
	_check(heard.has(&"ragdoll.whoosh"), "with a whoosh")
	await _settle(launched, 8.0)
	_check(launched.lowest_point() > -0.12, "and it lands on the floor, not through it (%.2f)" % launched.lowest_point())

	var crumple := yard.spawn(_figure(Vector3(8, 0, 0)), _death(&"crumple"))
	await _settle(crumple, 8.0)
	_check(crumple.settled and crumple.centre().y < 0.6 and (crumple.centre() - Vector3(8, 0, 0)).length() < 1.5,
		"a crumple goes down where it stood (%.2f m away)" % (crumple.centre() - Vector3(8, 0, 0)).length())
	yard.clear()


func _test_styles() -> void:
	_section("the other styles, and figures with no limbs")
	var yard := DotPlayerRagdolls.new()
	_world.add_child(yard)

	yard.rules.style = DotPlayerRagdollRules.Style.STIFF
	var stiff := yard.spawn(_figure(Vector3(0, 0, 10)), _death(&"limp"))
	_check(stiff.part_count() == 1 and stiff.joint_count() == 0 and stiff.part_nodes()[0] is RigidBody3D, "stiff is one rigid piece")
	await _settle(stiff, 8.0)
	_check(stiff.centre().y < 0.6 and stiff.lowest_point() > -0.12, "and it falls over onto the floor (%.2f)" % stiff.centre().y)

	yard.rules.style = DotPlayerRagdollRules.Style.RAGDOLL
	yard.rules.enabled = false
	var topple := yard.spawn(_figure(Vector3(4, 0, 10)), _death(&"limp", Vector3(1, 0, 0)))
	_check(topple.style == DotPlayerRagdollRules.Style.TOPPLE and not (topple.part_nodes()[0] is RigidBody3D),
		"sv_ragdoll 0: a topple, with no physics body at all")
	for i in range(90):
		await get_tree().physics_frame
	_check(topple.settled and topple.landed, "it goes over and lands")
	_check(absf(topple.lowest_point()) < 0.05, "lying on the floor, not in it (%.3f)" % topple.lowest_point())

	yard.rules.enabled = true
	yard.rules.style = DotPlayerRagdollRules.Style.HIDE
	var gone_fig := _figure(Vector3(8, 0, 10))
	_check(yard.spawn(gone_fig, _death(&"limp")) == null and not gone_fig.visible, "hide builds nothing and hides the figure")

	yard.rules.style = DotPlayerRagdollRules.Style.RAGDOLL
	var blob := _figure(Vector3(12, 0, 10), false)
	var blob_body := yard.spawn(blob, _death(&"limp"))
	_check(blob_body.style == DotPlayerRagdollRules.Style.STIFF, "a figure with no named torso falls as one piece")

	# The local player's body is hidden in first person (set_drawn(false) on the model); dying then still leaves a corpse.
	var first_person := _figure(Vector3(16, 0, 10))
	var model := Node3D.new()
	first_person.add_child(model)
	for mesh in first_person.get_children().filter(func(n: Node) -> bool: return n is MeshInstance3D):
		mesh.reparent(model, false)
	model.visible = false
	_check(yard.spawn(first_person, _death(&"limp")) != null, "a figure whose body is hidden for first person still falls")
	yard.clear()


func _test_cap_and_life() -> void:
	_section("the cap, and a body's life")
	var yard := DotPlayerRagdolls.new()
	yard.rules.max_count = 3
	yard.rules.lifetime = 1.0
	yard.rules.fade = 0.3
	yard.local_cap = 64
	_world.add_child(yard)

	var first: DotPlayerRagdoll = null
	for i in range(5):
		var b := yard.spawn(_figure(Vector3(i * 3.0, 0, 20)), _death(&"limp"))
		if i == 0:
			first = b
	_check(yard.standing_count() == 3, "five deaths, three bodies standing (cap 3)")
	_check(first.expiring, "the oldest made room")
	yard.local_cap = 2
	_check(yard.cap() == 2, "this machine's lower cap wins")
	var _b := yard.spawn(_figure(Vector3(20, 0, 20)), _death(&"limp"))
	_check(yard.standing_count() == 2, "and is held to")

	var waited := 0.0
	while waited < 3.0 and not yard.live().is_empty():
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	_check(yard.live().is_empty(), "every body fades and is gone after its lifetime (%.1f s)" % waited)
	var fps := DotPlayerRagdolls.default_local_cap()
	_check(fps >= 4, "a machine's own cap is never below four (%d)" % fps)


func _test_weight_and_weapon() -> void:
	_section("the heavy drop, the cvar defaults and the dropped weapon")
	var r := DotPlayerRagdollRules.new()
	_check(not r.exaggerate and not r.shootable, "exaggerate and shootable are off by default")
	_check(is_equal_approx(r.torque_scale, 1.0) and r.weapon_drop, "torque 1, weapon drop on by default")
	_check(r.reactions().find(&"headshot_launch").weight == 0.0, "launch reactions are not drawn by default")
	_check(r.reactions().pick(true, 1.0, 100.0, &"power_launch", 7) != &"power_launch", "a weapon naming a launch falls through")
	var specs := r.cvar_specs().map(func(d: Dictionary) -> String: return String(d["name"]))
	for name in ["sv_ragdoll_torque", "sv_ragdoll_exaggerate", "sv_ragdoll_shootable", "sv_ragdoll_weapon_drop", "sv_ragdoll_weapon_time"]:
		_check(specs.has(name), "%s is a cvar" % name)
	_check(r.set_cvar("sv_ragdoll_exaggerate", "1") and r.reactions().find(&"headshot_launch").weight > 0.0, "exaggerate brings the launches back")
	_check(r.set_cvar("sv_ragdoll_max", "200") and r.max_count == 200, "the body cap goes past 64")

	var yard := DotPlayerRagdolls.new()
	yard.local_cap = 64
	_world.add_child(yard)
	var launch := DotPlayerDeathReactions.stock().find(&"headshot_launch")
	var made := DotPlayerRagdoll.build(_figure(Vector3(0, 0, 40)), yard, yard.rules, launch, _death(&"headshot_launch", Vector3(0, 0, 1), true), Vector3.ZERO)
	var top := 0.0
	for node in made.part_nodes():
		top = maxf(top, (node as RigidBody3D).linear_velocity.y)
	_check(top < 1.0, "a launch reaction does not throw the body up by default (%.2f m/s)" % top)
	_check((made.part_nodes()[0] as RigidBody3D).gravity_scale > 1.0, "a falling body is heavier than gravity alone")

	var gun := Node3D.new()
	var gun_mesh := MeshInstance3D.new()
	gun_mesh.mesh = BoxMesh.new()
	gun.add_child(gun_mesh)
	_world.add_child(gun)
	gun.global_position = Vector3(0, 3, 40)
	var dropped := yard.drop_prop(gun)
	_check(dropped != null and dropped.get_child_count() >= 2, "the weapon drops as a physics prop with its mesh")
	for i in range(90):
		await get_tree().physics_frame
	_check(dropped != null and dropped.global_position.y < 3.0, "and falls (y %.2f)" % (dropped.global_position.y if dropped != null else 0.0))
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
	_check(with_flash != null and with_flash.get_child_count() == 2 and span < 2.0, "a muzzle flash under the gun is left out of the prop (collider %.2f m)" % span)
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
	_check(with_marks != null and with_marks.get_child_count() == 2 and span < 2.0, "shot marks in world space under the gun are left out of the prop (collider %.2f m)" % span)
	var person := _figure(Vector3(-6, 0, 40))
	var stray := MeshInstance3D.new()
	stray.mesh = BoxMesh.new()
	stray.top_level = true
	person.add_child(stray)
	stray.global_position = Vector3(-6, 9, 40)
	_check(not DotPlayerRagdoll.meshes_of(person).has(stray), "a body copies no world-space effect hung under its figure")
	person.queue_free()
	fx_root.queue_free()
	yard.rules.weapon_drop = false
	_check(yard.drop_prop(gun) == null, "weapon_drop off drops nothing")
	_check(not yard.shoot(Vector3(0, 1, 40), Vector3.FORWARD), "shooting a body does nothing by default")
	yard.rules.shootable = true
	var lying := yard.spawn(_figure(Vector3(6, 0, 40)), _death(&"limp"))
	var shot := yard.shoot(lying.centre(), Vector3.FORWARD)
	_check(shot, "with shootable on, a shot finds a part")
	yard.clear()
	# A dropped weapon freed by clear() before its timer fires must not raise on the timeout.
	yard.rules.weapon_drop = true
	yard.rules.weapon_lifetime = 0.5
	var fleeting := yard.drop_prop(gun)
	yard.clear()
	if is_instance_valid(fleeting):
		fleeting.queue_free()
	await get_tree().create_timer(0.8).timeout
	_check(true, "a weapon freed before its timer fires expires without an error")


func _person(at: Vector3) -> DotHumanoidFigure:
	var person := DotHumanoidFigure.new()
	_world.add_child(person)
	person.global_position = at
	person.build(DotHumanoidLook.stock(5), 1.8)
	person.animate(0.0, 0.2)
	return person


## A skinned person (dot-player-char's people) falls by its bones: the same parts and joints as a
## block figure, carrying the copied skeleton's bones, so it is the skin that ends up on the floor.
func _test_skinned() -> void:
	_section("a skinned body falls by its bones")
	var yard := DotPlayerRagdolls.new()
	yard.rules.lifetime = 60.0
	_world.add_child(yard)

	var person := _person(Vector3(0, 0, 40))
	var gun := MeshInstance3D.new()
	var gun_mesh := BoxMesh.new()
	gun_mesh.size = Vector3(0.06, 0.12, 0.4)
	gun.mesh = gun_mesh
	person.attachment(&"right_hand").add_child(gun)
	var body := yard.spawn(person, _death(&"limp", Vector3(1, 0, 0)))
	_check(body != null and bool(body.describe()["skinned"]) and body.part_count() == 6 and body.joint_count() == 5,
		"six parts, five joints, from the skeleton (%s)" % (str(body.describe()) if body != null else "none"))
	_check(not person.visible and body.skeleton_copy() != null and body.skeleton_copy().get_child_count() >= 1,
		"the figure is hidden and its skinned mesh is drawn on a copied skeleton")
	var copies := 0
	for part in body.part_nodes():
		for child in part.get_children():
			if child is MeshInstance3D:
				copies += 1
	_check(copies == 1, "the gun in the hand is copied onto a part (%d)" % copies)
	var skel := body.skeleton_copy()
	var head := skel.find_bone("Head")
	var head_before := (skel.global_transform * skel.get_bone_global_pose(head)).origin.y
	await _settle(body, 8.0)
	var head_after := (skel.global_transform * skel.get_bone_global_pose(head)).origin.y
	_check(body.settled, "it settles and freezes (%s)" % str(body.describe()))
	_check(body.lowest_point() > -0.15 and body.centre().y < 0.6,
		"lying on the floor, not through it (lowest %.2f, torso %.2f)" % [body.lowest_point(), body.centre().y])
	_check(head_before > 0.8 and head_after < 0.5, "and the bones went with it: the head bone from %.2f m to %.2f m" % [head_before, head_after])

	var plant := yard.spawn(_person(Vector3(4, 0, 40)), _death(&"face_plant"))
	_check(plant.part_count() == 1, "a face plant starts as one piece")
	await _settle(plant, 8.0)
	_check(plant.landed and plant.part_count() == 6 and plant.joint_count() == 5,
		"and goes jointed when it lands (%s)" % str(plant.describe()))
	_check((plant.centre() - Vector3(4, 0, 40)).dot(Vector3(0, 0, -1)) > 0.3, "forward, onto its face")

	# Held out in front, a gun and the arms made the one piece as deep as it was wide, and the
	# plank stood back up: the column is the head, the body and the legs.
	var armed := _person(Vector3(16, 0, 40))
	armed.set_hold(DotHumanoidFigure.Hold.GUN)
	armed.animate(0.0, 0.3)
	var long_gun := MeshInstance3D.new()
	var long_mesh := BoxMesh.new()
	long_mesh.size = Vector3(0.08, 0.14, 0.9)
	long_gun.mesh = long_mesh
	armed.attachment(&"right_hand").add_child(long_gun)
	var armed_plant := yard.spawn(armed, _death(&"face_plant"))
	for i in range(150):
		await get_tree().physics_frame
	# And limp: boxed round the pistol in its hand, an arm propped a dead person up on their
	# knees for good. What a hand holds is drawn on its part, never collided.
	var armed_limp := _person(Vector3(20, 0, 40))
	armed_limp.set_hold(DotHumanoidFigure.Hold.GUN)
	armed_limp.animate(0.0, 0.3)
	var pistol := MeshInstance3D.new()
	var pistol_mesh := BoxMesh.new()
	pistol_mesh.size = Vector3(0.1, 0.25, 0.7)
	pistol.mesh = pistol_mesh
	armed_limp.attachment(&"right_hand").add_child(pistol)
	var limp_body := yard.spawn(armed_limp, _death(&"limp", Vector3(-0.75, 0, -0.67)))
	_check(armed_plant.landed and armed_plant.centre().y < 0.6,
		"a person holding a long gun out goes over too, inside two and a half seconds (%s, torso %.2f)" % [
			str(armed_plant.describe()), armed_plant.centre().y])
	await _settle(limp_body, 8.0)
	_check(limp_body.centre().y < 0.35, "and one holding a gun falls limp onto the floor, not propped on it (torso %.2f; 0.42 when the gun was collided)" % limp_body.centre().y)

	yard.rules.enabled = false
	var topple := yard.spawn(_person(Vector3(8, 0, 40)), _death(&"limp", Vector3(1, 0, 0)))
	for i in range(90):
		await get_tree().physics_frame
	var tskel := topple.skeleton_copy()
	var thead := (tskel.global_transform * tskel.get_bone_global_pose(tskel.find_bone("Head"))).origin.y
	_check(topple.style == DotPlayerRagdollRules.Style.TOPPLE and topple.settled and thead < 0.7,
		"sv_ragdoll 0: the skinned body topples with no physics (head bone at %.2f m)" % thead)
	_check(absf(topple.lowest_point()) < 0.15, "onto the floor (%.2f)" % topple.lowest_point())

	yard.rules.enabled = true
	yard.rules.lifetime = 0.5
	yard.rules.fade = 0.5
	var fading := yard.spawn(_person(Vector3(12, 0, 40)), _death(&"crumple"))
	var fskel := fading.skeleton_copy()
	var smallest := 1.0
	var waited := 0.0
	while waited < 3.0 and is_instance_valid(fading):
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
		if is_instance_valid(fskel):
			smallest = minf(smallest, fskel.global_basis.get_scale().x / maxf(person.body_node().global_basis.get_scale().x, 0.0001))
	_check(smallest < 0.5, "the fade shrinks the skeleton, so the skin shrinks with it (to %.2f)" % smallest)
	_check(not is_instance_valid(fading), "and the body is gone after its lifetime")
	yard.clear()


## A face plant onto open floor always ends lying down. The skinned figure's one piece is a flush
## box (about 0.42 x 1.59 x 0.8 m) on the floor, and at the games' 20 m/s2 gravity (the default 9.8
## never showed it) floor contact ate the 1.6 rad/s spin before the top passed the toes, so a third
## of the falls (12 of 36 here) stood back up, by pose and not by seed (nightly
## ragdoll-faceplant-upright-1). Without the fix this check fails listing those falls.
func _test_faceplant_sweep() -> void:
	_section("a skinned face plant onto open floor always lies down")
	var yard := DotPlayerRagdolls.new()
	yard.rules.lifetime = 60.0
	_world.add_child(yard)
	# The games tune movement against about 20 m/s2, not 9.8; a heavier fall asks more of the spin.
	var space := get_viewport().find_world_3d().space
	var gravity_before: float = PhysicsServer3D.area_get_param(space, PhysicsServer3D.AREA_PARAM_GRAVITY)
	PhysicsServer3D.area_set_param(space, PhysicsServer3D.AREA_PARAM_GRAVITY, 20.0)
	var upright: Array[String] = []
	var falls := 0
	for s in range(36):
		var person := _person(Vector3(0, [0.0, -0.05, -0.1, 0.03][s % 4], 80))
		person.rotation.y = deg_to_rad(float(s % 4) * 45.0 + 7.0 * float(s / 4))
		person.set_hold(s % 3)
		person.aim([0.0, 0.6, -0.6, 0.3][(s / 3) % 4])
		for k in range(1 + (s * 5) % 13):
			person.animate([0.0, 2.0, 3.5, 5.0][s % 4], 0.11)
		await get_tree().physics_frame
		var forward := -person.global_basis.z
		var body := yard.spawn(person, _death(&"face_plant"))
		await _settle(body, 6.0)
		falls += 1
		var c := body.centre()
		if not (c.y < 0.6 and body.lowest_point() > -0.25):
			upright.append("%d: centre.y=%.2f lowest=%.2f" % [s, c.y, body.lowest_point()])
		elif (c - Vector3(0, 0, 80)).dot(forward) < 0.3:
			upright.append("%d: not forward (%.2f)" % [s, (c - Vector3(0, 0, 80)).dot(forward)])
		yard.clear()
	# A table edge just ahead, at the height of a person's hips: the plank tips onto it and stops
	# at about 30 degrees with its weight on the edge, still on its feet. Seen against a house
	# map's furniture on game-murder-mystery's CI (nightly ragdoll-faceplant-upright-1, second half): the
	# spin is not the problem there, so no amount of pushing fixes it, and a frozen plank leaning
	# on furniture is a dead body standing. It has to let go and slump.
	var table := StaticBody3D.new()
	var slab := CollisionShape3D.new()
	var slab_box := BoxShape3D.new()
	slab_box.size = Vector3(1.6, 0.05, 0.8)
	slab.shape = slab_box
	table.add_child(slab)
	_world.add_child(table)
	var leaning: Array[String] = []
	var tried := 0
	for s in range(8):
		var gap: float = [0.3, 0.38, 0.45, 0.55][s % 4]
		var top: float = [0.8, 0.72][s / 4]
		table.global_position = Vector3(40, top - 0.025, 80 - gap - 0.4)
		var person := _person(Vector3(40, 0, 80))
		person.set_hold(s % 3)
		await get_tree().physics_frame
		var body := yard.spawn(person, _death(&"face_plant"))
		await _settle(body, 6.0)
		tried += 1
		var pieces := body.part_count()
		var standing := false
		for node in body.part_nodes():
			standing = standing or (pieces == 1 and node.global_basis.y.dot(Vector3.UP) > 0.55)
		if pieces == 1 or standing:
			leaning.append("%d (gap %.2f, top %.2f): %d piece(s), centre.y=%.2f" % [s, gap, top, pieces, body.centre().y])
		yard.clear()
	table.queue_free()
	PhysicsServer3D.area_set_param(space, PhysicsServer3D.AREA_PARAM_GRAVITY, gravity_before)
	_check(falls == 36 and tried == 8, "36 falls onto open floor and 8 onto a table edge ran")
	_check(upright.is_empty(), "none stayed up or fell backward: %s" % str(upright))
	_check(leaning.is_empty(), "a plank stopped by a table edge lets go and slumps, never left leaning on its feet: %s" % str(leaning))


# --- Plumbing --------------------------------------------------------------------

func _section(title: String) -> void:
	_section_count += 1
	_line("")
	_line("-- %s" % title)


func _check(condition: bool, what: String) -> void:
	if condition:
		_passed += 1
		_line("   ok   %s" % what)
	else:
		_failed += 1
		_line("  FAIL  %s" % what)


func _line(text: String) -> void:
	print(text)


class _FlashStub extends Node3D:
	func fire() -> bool:
		return true

	func is_showing() -> bool:
		return true
