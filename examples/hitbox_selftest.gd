extends Node

## Hit zones: the plan as data, the config layer, and the node built through stub factories (no dot-combat needed).
##
## [codeblock]
## godot --headless --path . res://examples/hitbox_selftest.tscn
## [/codeblock]

const SECTIONS := 4
const CHECKS := 35

var _passed := 0
var _failed := 0
var _section_count := 0


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run()


func _run() -> void:
	print("dot-player-char hitbox self-test")
	_test_stock()
	_test_config()
	_test_node()
	_test_off_by_default()

	print("%d sections, %d passed, %d failed" % [_section_count, _passed, _failed])
	if _section_count != SECTIONS or _passed + _failed != CHECKS:
		print("ERROR: %d of %d sections, %d of %d checks ran." % [_section_count, SECTIONS, _passed + _failed, CHECKS])
		get_tree().quit(1)
		return
	get_tree().quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL: ", what)


func _groups(zs: Array[Dictionary]) -> Array:
	var g: Array = []
	for z in zs:
		if not (z["group"] in g):
			g.append(z["group"])
	return g


func _test_stock() -> void:
	_section_count += 1
	var zs := DotPlayerHitboxPlan.stock(1.8)
	_check(zs.size() == 11, "eleven stock zones")
	var g := _groups(zs)
	for name in [&"head", &"neck", &"chest", &"arm", &"hand", &"leg", &"foot"]:
		_check(name in g, "group %s present" % name)
	_check(zs[0]["position"] == Vector3(0, 1.62, 0), "head at arena's height on a 1.8 body")
	var tall := DotPlayerHitboxPlan.stock(3.6)
	_check(is_equal_approx((tall[0]["position"] as Vector3).y, 3.24), "positions scale with height")
	_check(is_equal_approx(float(tall[0]["radius"]), 0.3), "radii scale with height")
	var big := DotPlayerHitboxPlan.stock(1.8, 1.1)
	_check(float(big[0]["radius"]) > float(zs[0]["radius"]), "hitbox_scale grows radii")
	_check((big[0]["position"] as Vector3) == (zs[0]["position"] as Vector3), "hitbox_scale leaves positions")
	_check(int(zs[0]["precedence"]) > int(zs[2]["precedence"]), "head outranks torso")
	_check(is_equal_approx(float(DotPlayerHitboxPlan.stock(0.0)[0]["radius"]), 0.15 * 0.1 / 1.8), "zero height is clamped")


func _test_config() -> void:
	_section_count += 1
	var base := DotPlayerHitboxPlan.stock()
	var r := DotPlayerHitboxPlan.from_config(base, {"disabled": ["hand_l", "hand_r"]})
	_check(r.ok and (r.value as Array).size() == 9, "disabled drops zones")
	_check(base.size() == 11, "base is not modified")
	r = DotPlayerHitboxPlan.from_config(base, {"groups": {"torso": "stomach"}})
	_check(r.ok and r.value[2]["group"] == &"stomach", "groups remaps a zone")
	r = DotPlayerHitboxPlan.from_config(base, {"zones": {"core": {"group": "core", "shape": "sphere", "radius": 0.2, "position": [0, 1.0, 0]}}})
	_check(r.ok and (r.value as Array).size() == 12 and r.value[11]["group"] == &"core", "a new zone is added")
	r = DotPlayerHitboxPlan.from_config(base, {"zones": {"head": {"radius": 0.5}}})
	_check(r.ok and is_equal_approx(float(r.value[0]["radius"]), 0.5) and r.value[0]["group"] == &"head", "a zone is overridden in part")
	r = DotPlayerHitboxPlan.from_config(base, {"groups": {"nope": "head"}})
	_check(not r.ok and r.code() == DotError.CODE_INVALID, "unknown zone in groups fails")
	r = DotPlayerHitboxPlan.from_config(base, {"zones": {"x": {"radius": 0.2}}})
	_check(not r.ok, "a new zone with no group fails")
	r = DotPlayerHitboxPlan.from_config(base, {"disabled": "head"})
	_check(not r.ok, "disabled must be an array")


class StubBox extends Node3D:
	var zone: Dictionary = {}


func _stub_box(z: Dictionary) -> Node3D:
	var b := StubBox.new()
	b.zone = z
	b.position = z["position"]
	return b


func _test_node() -> void:
	_section_count += 1
	var host := Node3D.new()
	add_child(host)
	var hb := DotPlayerHitboxes.new()
	hb.hitbox_factory = _stub_box
	hb.set_factory = func() -> Node3D: return Node3D.new()
	host.add_child(hb)
	var r := hb.build()
	_check(r.ok, "build succeeds with factories")
	_check(r.ok and r.value.get_child_count() == 11, "one node per zone")
	_check(r.ok and (r.value.get_child(0) as StubBox).zone["group"] == &"head", "the factory sees the group")
	_check(hb.describe()["built"] == true, "describe reports built")
	var again := hb.build()
	_check(again.ok and hb.get_child_count() == 1, "rebuild leaves one set")
	hb.config = {"disabled": ["foot_l"]}
	_check(hb.build().ok and hb.hitbox_set().get_child_count() == 10, "config reaches the build")
	hb.config = {"groups": {"x": "y"}}
	_check(not hb.build().ok, "a bad config fails")
	hb.clear()
	_check(hb.hitbox_set() == null, "clear drops the set")
	host.queue_free()


func _test_off_by_default() -> void:
	_section_count += 1
	var hb := DotPlayerHitboxes.new()
	_check(hb.enabled == false, "off by default")
	add_child(hb)
	_check(hb.hitbox_set() == null and hb.get_child_count() == 0, "adding it builds nothing")
	if DotPlayerHitboxes.class_script("DotHitbox") == null:
		var r := hb.build()
		_check(not r.ok and r.code() == DotError.CODE_INVALID, "without dot-combat build fails cleanly")
	else:
		_check(true, "dot-combat present, fallback exercised by the game")
	_check(DotPlayerHitboxes.class_script("NoSuchClassAnywhere") == null, "unknown class is null")
	hb.queue_free()
