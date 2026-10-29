class_name DotDownedRules
extends RefCounted

## What a downed player holds, whether they may crawl with it, and how the body lies. The
## `sv_downed_*` cvars; REPLICATED, because a client predicts its own crawl and draws the others.
## Every method is a pure function of these rules and its arguments, so server and clients agree.

signal changed

const CVAR_WEAPON := "sv_downed_weapon"
const CVAR_CRAWL_PISTOL := "sv_downed_crawl_pistol"
const CVAR_CRAWL_PRIMARY := "sv_downed_crawl_primary"
const CVAR_HOLSTER := "sv_downed_holster_crawl"

## `sv_downed_weapon` modes.
const MODE_SECONDARY := &"secondary"
const MODE_PRIMARY_IN_PLACE := &"primary_in_place"
const MODE_PISTOL_ONLY := &"pistol_only"
const MODES: Array[StringName] = [MODE_SECONDARY, MODE_PRIMARY_IN_PLACE, MODE_PISTOL_ONLY]

## What the downed player ends up holding.
const KIND_PISTOL := &"pistol"
const KIND_SECONDARY := &"secondary"
const KIND_PRIMARY := &"primary"

## Body poses: on the back with the weapon out, or on the stomach crawling.
const POSE_PROPPED := &"propped"
const POSE_CRAWL := &"crawl"

## Pose to clip name; a clip library that has better ones overrides an entry.
const CLIPS := {
	POSE_PROPPED: &"idle_gun",
	POSE_CRAWL: &"crawl",
}

var weapon_mode: StringName = MODE_SECONDARY:
	set(value):
		if value != weapon_mode and MODES.has(value):
			weapon_mode = value
			changed.emit()

var crawl_pistol: bool = true:
	set(value):
		if value != crawl_pistol:
			crawl_pistol = value
			changed.emit()

var crawl_primary: bool = false:
	set(value):
		if value != crawl_primary:
			crawl_primary = value
			changed.emit()

var holster_crawl: bool = true:
	set(value):
		if value != holster_crawl:
			holster_crawl = value
			changed.emit()


## The kind of weapon taken out on going down, from what the player carries.
func choose_weapon(has_secondary: bool, has_primary: bool) -> StringName:
	match weapon_mode:
		MODE_PRIMARY_IN_PLACE:
			if has_primary:
				return KIND_PRIMARY
			return KIND_SECONDARY if has_secondary else KIND_PISTOL
		MODE_PISTOL_ONLY:
			return KIND_PISTOL
		_:
			return KIND_SECONDARY if has_secondary else KIND_PISTOL


## Whether a downed player holding [param kind] may crawl.
func can_crawl(kind: StringName) -> bool:
	return crawl_primary if kind == KIND_PRIMARY else crawl_pistol


## Propped (on the back, shooting) while still, crawling (on the stomach) while moving and allowed to.
func pose_for(moving: bool, kind: StringName) -> StringName:
	return POSE_CRAWL if moving and can_crawl(kind) else POSE_PROPPED


## The weapon is put away in the crawl pose, and out again in the propped one.
func holstered(pose: StringName) -> bool:
	return holster_crawl and pose == POSE_CRAWL


func clip_for(pose: StringName) -> StringName:
	return CLIPS.get(pose, CLIPS[POSE_CRAWL])


## The kind a weapon tier counts as (`sidearm`, `primary`, `heavy`...).
static func kind_of_tier(tier: StringName) -> StringName:
	return KIND_PRIMARY if tier == &"primary" or tier == &"heavy" else KIND_PISTOL


func bind_cvars(add: Callable, flags: int = 0) -> Array:
	var made: Array = []
	for spec in _specs():
		var made_cvar: Variant = add.call(spec[0], spec[1], spec[2], flags)
		if not (made_cvar is Object):
			continue
		var cv := made_cvar as Object
		if cv.has_signal(&"changed"):
			cv.connect(&"changed", _on_cvar_changed.bind(spec[0]))
		if cv.has_method(&"get_string"):
			var _applied := set_cvar(spec[0], String(cv.call(&"get_string")))
		made.append(cv)
	return made


## Follows a server's values through its link; false for an older shell's link.
func follow_cvars(source: Object) -> bool:
	if source == null or not is_instance_valid(source):
		return false
	if not source.has_method(&"replicated_cvar") or not source.has_signal(&"replicated_cvar_changed"):
		return false
	for spec in _specs():
		var held := String(source.call(&"replicated_cvar", spec[0], ""))
		if held != "":
			var _applied := set_cvar(spec[0], held)
	if not source.is_connected(&"replicated_cvar_changed", _on_replicated):
		source.connect(&"replicated_cvar_changed", _on_replicated)
	return true


## Applies one cvar by name; false for an unknown name or a value that does not parse.
func set_cvar(cvar_name: String, value: String) -> bool:
	var text := value.strip_edges().to_lower()
	match cvar_name:
		CVAR_WEAPON:
			if not MODES.has(StringName(text)):
				return false
			weapon_mode = StringName(text)
		CVAR_CRAWL_PISTOL, CVAR_CRAWL_PRIMARY, CVAR_HOLSTER:
			if not text.is_valid_int():
				return false
			var on := text.to_int() != 0
			match cvar_name:
				CVAR_CRAWL_PISTOL: crawl_pistol = on
				CVAR_CRAWL_PRIMARY: crawl_primary = on
				_: holster_crawl = on
		_:
			return false
	return true


func describe() -> Dictionary:
	return {"weapon": String(weapon_mode), "crawl_pistol": crawl_pistol,
		"crawl_primary": crawl_primary, "holster_crawl": holster_crawl}


func _specs() -> Array:
	return [
		[CVAR_WEAPON, String(weapon_mode), "What a downed player holds: secondary (the secondary, else the default pistol), primary_in_place (keep the primary) or pistol_only"],
		[CVAR_CRAWL_PISTOL, "1" if crawl_pistol else "0", "1 lets a downed player holding a pistol crawl"],
		[CVAR_CRAWL_PRIMARY, "1" if crawl_primary else "0", "1 lets a downed player holding a primary crawl"],
		[CVAR_HOLSTER, "1" if holster_crawl else "0", "1 puts the weapon away while crawling and brings it out when they stop"],
	]


func _on_cvar_changed(_old: Variant, new_value: Variant, cvar_name: String) -> void:
	var _applied := set_cvar(cvar_name, str(new_value))


func _on_replicated(cvar_name: String, value: String) -> void:
	if cvar_name.begins_with("sv_downed_"):
		var _applied := set_cvar(cvar_name, value)
