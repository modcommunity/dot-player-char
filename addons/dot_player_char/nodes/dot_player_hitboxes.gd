class_name DotPlayerHitboxes
extends Node3D

## Optional hit zones (head, neck, torso, arms, hands, legs, feet) for a player, built as dot-combat hitboxes.
##
## Off by default. dot-player-char does not depend on dot-combat, so the hitbox classes are looked up by name
## at build time; without them, or without a [member hitbox_factory], [method build] fails and builds nothing.

const CHANNEL := "player.hitboxes"

## Whether [method build] runs by itself when this enters the tree.
@export var enabled: bool = false

## Used when no [DotPlayerChar] is a sibling.
@export_range(0.5, 10.0, 0.01, "or_greater") var height: float = 1.8

## Config layered over the stock zones, see [method DotPlayerHitboxPlan.from_config].
@export var config: Dictionary = {}

## Replaces how one zone becomes a node: `func(zone: Dictionary) -> Node3D`. Null falls back to DotHitbox.
var hitbox_factory: Callable = Callable()

## Replaces how the container is made; null falls back to DotHitboxSet.
var set_factory: Callable = Callable()

var _set: Node3D = null
var _zones: Array[Dictionary] = []


func _ready() -> void:
	if enabled:
		var res := build()
		if not res.ok:
			DotLog.warn(CHANNEL, "hitboxes not built", {"code": res.code(), "why": res.error.message})


## The zones this would build; override to compute them differently.
func zones() -> DotResult:
	var h := height
	var s := 1.0
	var pc := _char()
	if pc != null:
		h = pc.height()
		s = pc.hitbox_scale()
	return DotPlayerHitboxPlan.from_config(DotPlayerHitboxPlan.stock(h, s), config)


## Builds (or rebuilds) the hitboxes under this node; the container is returned.
func build() -> DotResult:
	var planned := zones()
	if not planned.ok:
		return planned
	var zs: Array[Dictionary] = planned.value
	var box := _make_set(zs)
	if not box.ok:
		return box
	clear()
	_set = box.value
	_set.name = "Hitboxes"
	for z in zs:
		var node: Node3D = _make_box(z)
		if node == null:
			_set.free()
			_set = null
			return DotResult.fail(DotError.CODE_INVALID, "no hitbox could be made for zone %s" % z["id"])
		_set.add_child(node)
	_zones = zs
	add_child(_set)
	if _set.has_method("refresh"):
		_set.call("refresh")
	DotLog.debug(CHANNEL, "built hitboxes", {"zones": zs.size()})
	return DotResult.success(_set)


## Removes what [method build] made.
func clear() -> void:
	if _set != null:
		_set.queue_free()
		if _set.get_parent() == self:
			remove_child(_set)
		_set = null
	_zones = []


func hitbox_set() -> Node3D:
	return _set


func describe() -> Dictionary:
	var groups: Array = []
	for z in _zones:
		groups.append("%s:%s" % [z["id"], z["group"]])
	return {"enabled": enabled, "built": _set != null, "zones": groups}


func _char() -> DotPlayerChar:
	var p := get_parent()
	if p == null:
		return null
	for c in p.get_children():
		if c is DotPlayerChar:
			return c
	return null


func _make_set(zs: Array[Dictionary]) -> DotResult:
	var top := 0.0
	for z in zs:
		top = maxf(top, (z["position"] as Vector3).y + float(z["radius"]) + float(z["height"]) * 0.5)
	var node: Node3D = null
	if set_factory.is_valid():
		node = set_factory.call()
	else:
		var script := class_script("DotHitboxSet")
		if script == null:
			return DotResult.fail(DotError.CODE_INVALID, "DotHitboxSet is not available (dot-combat missing); set set_factory")
		node = script.new()
		node.set("bounds_offset", Vector3(0, top * 0.5, 0))
		node.set("bounds_radius", maxf(top, 0.5) * 0.9 + 0.2)
	if node == null:
		return DotResult.fail(DotError.CODE_INVALID, "set_factory returned null")
	return DotResult.success(node)


func _make_box(z: Dictionary) -> Node3D:
	if hitbox_factory.is_valid():
		return hitbox_factory.call(z)
	var script := class_script("DotHitbox")
	if script == null:
		return null
	var shapes: Dictionary = script.get_script_constant_map().get("Shape", {})
	var node: Node3D = script.new()
	node.name = String(z["id"]).capitalize().replace(" ", "")
	node.set("group", z["group"])
	node.set("shape", shapes.get(String(z["shape"]).to_upper(), 0))
	node.set("radius", z["radius"])
	if float(z["height"]) > 0.0:
		node.set("height", z["height"])
	node.set("precedence", z["precedence"])
	node.position = z["position"]
	return node


## A global script class by name, or null; avoids naming dot-combat in this file.
static func class_script(class_name_: String) -> Script:
	for entry in ProjectSettings.get_global_class_list():
		if entry["class"] == class_name_:
			return load(entry["path"]) as Script
	return null
