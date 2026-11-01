extends Node

## The real DotHitbox / DotHitboxSet path. Needs dot-combat linked (ln -s ../../dot-combat/addons/dot_combat addons/dot_combat).
##
## [codeblock]
## godot --headless --path . res://examples/hitbox_combat_selftest.tscn
## [/codeblock]

const CHECKS := 11

var _passed := 0
var _failed := 0


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	print("dot-player-char hitbox + dot-combat self-test")
	if DotPlayerHitboxes.class_script("DotHitboxSet") == null:
		print("SKIP: dot-combat is not linked")
		get_tree().quit(0)
		return
	var host := Node3D.new()
	add_child(host)
	host.add_child(DotPlayerChar.new())
	var hb := DotPlayerHitboxes.new()
	host.add_child(hb)
	var r := hb.build()
	_check(r.ok, "build succeeds with the real classes")
	var set_node: Node = hb.hitbox_set()
	_check(set_node != null and set_node.get_class() != "", "a set exists")
	_check(set_node != null and set_node.get_child_count() == 11, "one DotHitbox per zone")
	var first: Node = set_node.get_child(0) if set_node != null and set_node.get_child_count() > 0 else null
	_check(first != null and first.get_script() == DotPlayerHitboxes.class_script("DotHitbox"), "children are DotHitbox")
	_check(first != null and first.get("group") == &"head", "first zone is the head group")
	_check(first != null and float(first.get("radius")) > 0.0, "radius carried over")
	_wall_flush(host, set_node)
	hb.clear()
	_check(hb.hitbox_set() == null, "clear drops the set")
	print("%d passed, %d failed" % [_passed, _failed])
	if _passed + _failed != CHECKS:
		print("ERROR: %d of %d checks ran." % [_passed + _failed, CHECKS])
		get_tree().quit(1)
		return
	get_tree().quit(1 if _failed > 0 else 0)


## Stands flush at a wall plane (x = capsule radius) and fires from the far side along every height.
func _wall_flush(host: Node3D, set_node: Node) -> void:
	host.rotation.y = 0.0
	var plane := 0.35
	var reach := -INF
	var far_hits := 0
	var near_hits := 0
	for side in [1.0, -1.0]:
		for i in 40:
			var y := 0.02 + i * 0.045
			var from := Vector3(side * 3.0, y, 0.0)
			for h in set_node.get_children():
				var hit: Variant = h.call("intersect_ray", from, Vector3(-side, 0, 0), 10.0)
				if hit == null or float(hit.distance) <= 0.0:
					continue
				reach = maxf(reach, absf(hit.point.x))
				# A shot from beyond the wall plane must stop at the plane: nothing is hit past it.
				if absf(hit.point.x) > plane + 0.001:
					far_hits += 1
				else:
					near_hits += 1
	_check(near_hits > 0, "a shot along the wall plane still hits the body")
	_check(far_hits == 0, "no hit point beyond the wall plane (%d past it, reach %.3f m)" % [far_hits, reach])
	var arm_l: Node = set_node.get_node("ArmL")
	var arm_r: Node = set_node.get_node("ArmR")
	_check(absf((arm_l as Node3D).position.x) + float(arm_l.get("radius")) <= plane + 0.001, "left arm inside the capsule")
	_check(absf((arm_r as Node3D).position.x) + float(arm_r.get("radius")) <= plane + 0.001, "right arm inside the capsule")


func _check(ok: bool, what: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL: %s" % what)
