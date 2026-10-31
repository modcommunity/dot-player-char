extends Node

## The real DotHitbox / DotHitboxSet path. Needs dot-combat linked (ln -s ../../dot-combat/addons/dot_combat addons/dot_combat).
##
## [codeblock]
## godot --headless --path . res://examples/hitbox_combat_selftest.tscn
## [/codeblock]

const CHECKS := 7

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
	hb.clear()
	_check(hb.hitbox_set() == null, "clear drops the set")
	print("%d passed, %d failed" % [_passed, _failed])
	if _passed + _failed != CHECKS:
		print("ERROR: %d of %d checks ran." % [_passed + _failed, CHECKS])
		get_tree().quit(1)
		return
	get_tree().quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL: %s" % what)
