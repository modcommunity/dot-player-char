class_name DotPlayerHitboxPlan
extends RefCounted

## The hit zones of a standing person as plain data, scaled from one height. Pure: no node, no dot-combat.

const SPHERE := &"sphere"
const CAPSULE := &"capsule"
const BOX := &"box"

## Zone ids a config may name; the group is the hit_group dot-combat's resolver and DotStatsHitzones read.
const STOCK_IDS: Array[StringName] = [
	&"head", &"neck", &"torso", &"arm_l", &"arm_r", &"hand_l", &"hand_r",
	&"leg_l", &"leg_r", &"foot_l", &"foot_r",
]

## Proportions of a 1.8 m body (y, x and sizes are metres at that height, scaled by height / 1.8).
const REFERENCE_HEIGHT := 1.8


## One zone: `id`, `group`, `shape`, `position`, `radius`, `height`, `precedence`.
static func zone(id: StringName, group: StringName, shape: StringName, position: Vector3, radius: float, height: float = 0.0, precedence: int = 0) -> Dictionary:
	return {
		"id": id, "group": group, "shape": shape, "position": position,
		"radius": radius, "height": height, "precedence": precedence,
	}


## The stock set for a body of [param height] metres; [param scale] is DotPlayerCharDef.hitbox_scale.
static func stock(height: float = REFERENCE_HEIGHT, scale: float = 1.0) -> Array[Dictionary]:
	var k := maxf(height, 0.1) / REFERENCE_HEIGHT
	var r := k * maxf(scale, 0.1)
	var out: Array[Dictionary] = []
	# Small zones outrank the torso and legs they sit inside, so a shared surface always resolves the same way.
	out.append(zone(&"head", &"head", SPHERE, Vector3(0, 1.62 * k, 0), 0.15 * r, 0.0, 10))
	out.append(zone(&"neck", &"neck", SPHERE, Vector3(0, 1.46 * k, 0), 0.09 * r, 0.0, 5))
	out.append(zone(&"torso", &"chest", CAPSULE, Vector3(0, 1.08 * k, 0), 0.26 * r, 0.8 * k * r, 0))
	for s in [[&"_l", -1.0], [&"_r", 1.0]]:
		var x: float = s[1]
		var sfx: String = s[0]
		out.append(zone(StringName("arm" + sfx), &"arm", CAPSULE, Vector3(x * 0.37 * k, 1.12 * k, 0), 0.07 * r, 0.55 * k * r, 3))
		out.append(zone(StringName("hand" + sfx), &"hand", SPHERE, Vector3(x * 0.38 * k, 0.80 * k, 0), 0.07 * r, 0.0, 4))
		out.append(zone(StringName("leg" + sfx), &"leg", CAPSULE, Vector3(x * 0.11 * k, 0.46 * k, 0), 0.10 * r, 0.82 * k * r, 1))
		out.append(zone(StringName("foot" + sfx), &"foot", SPHERE, Vector3(x * 0.11 * k, 0.07 * k, 0), 0.10 * r, 0.0, 5))
	return out


## [param base] with a config applied. Keys: `disabled` (ids dropped), `groups` ({id: group}), `zones` (extra or replacing
## zone dicts keyed by id with any of the zone fields). A bad entry fails the whole config, nothing is half applied.
static func from_config(base: Array[Dictionary], config: Dictionary) -> DotResult:
	var out: Array[Dictionary] = []
	for z in base:
		out.append(z.duplicate())
	var disabled: Variant = config.get("disabled", [])
	if not (disabled is Array):
		return DotResult.fail(DotError.CODE_INVALID, "hitbox config: disabled must be an array")
	var groups: Variant = config.get("groups", {})
	if not (groups is Dictionary):
		return DotResult.fail(DotError.CODE_INVALID, "hitbox config: groups must be a dictionary")
	var extra: Variant = config.get("zones", {})
	if not (extra is Dictionary):
		return DotResult.fail(DotError.CODE_INVALID, "hitbox config: zones must be a dictionary")
	for id in extra:
		var spec: Variant = extra[id]
		if not (spec is Dictionary):
			return DotResult.fail(DotError.CODE_INVALID, "hitbox config: zone %s must be a dictionary" % id)
		var at := _index_of(out, StringName(str(id)))
		var merged: Dictionary = out[at].duplicate() if at >= 0 else zone(StringName(str(id)), &"", SPHERE, Vector3.ZERO, 0.1)
		for key in spec:
			var v: Variant = spec[key]
			if key == "position":
				if not (v is Array) or v.size() != 3:
					return DotResult.fail(DotError.CODE_INVALID, "hitbox config: zone %s position must be [x, y, z]" % id)
				v = Vector3(float(v[0]), float(v[1]), float(v[2]))
			elif key == "group" or key == "shape":
				v = StringName(str(v))
			merged[key] = v
		if not (merged["shape"] in [SPHERE, CAPSULE, BOX]) or float(merged["radius"]) <= 0.0 or merged["group"] == &"":
			return DotResult.fail(DotError.CODE_INVALID, "hitbox config: zone %s needs a shape, a group and a radius" % id)
		if at >= 0:
			out[at] = merged
		else:
			out.append(merged)
	for id in groups:
		var at2 := _index_of(out, StringName(str(id)))
		if at2 < 0:
			return DotResult.fail(DotError.CODE_INVALID, "hitbox config: groups names unknown zone %s" % id)
		out[at2]["group"] = StringName(str(groups[id]))
	var kept: Array[Dictionary] = []
	for z in out:
		if not (String(z["id"]) in disabled):
			kept.append(z)
	return DotResult.success(kept)


static func _index_of(zones: Array[Dictionary], id: StringName) -> int:
	for i in zones.size():
		if zones[i]["id"] == id:
			return i
	return -1
