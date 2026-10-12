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

const SECTIONS := 8
const CHECKS := 64

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
	_check(made.size() == 6, "six sv_ragdoll cvars")
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
	var launched := yard.spawn(_figure(Vector3(-4, 0, 0)), _death(&"headshot_launch", Vector3(0, 0, 1), true, 100.0))
	var top := 0.0
	for i in range(40):
		await get_tree().physics_frame
		if is_instance_valid(launched):
			top = maxf(top, launched.centre().y)
	_check(top > 2.0, "a headshot launch throws the body up (torso reached %.1f m)" % top)
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
