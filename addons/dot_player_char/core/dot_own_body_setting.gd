class_name DotOwnBodySetting
extends RefCounted
## The client-only `cl_legs` option: whether you see your own legs and body when you look down.
## Never server-enforced; a game lists [method def] in its settings schema and calls [method follow].

const KEY := &"cl_legs"
const DEFAULT := true
const META := &"dot_own_body_follow"


## The setting's definition (a DotSettingsDef, device scope), or null when dot-settings is not in the project: this addon does not require it.
static func def() -> Variant:
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		if entry.get("class") == &"DotSettingsDef":
			var script: GDScript = load(entry["path"])
			var d: Object = script.call("boolean", KEY, DEFAULT, &"video")
			d.call("with_description", "Show your own legs and body when you look down.")
			return d
	return null


## Puts the setting's value on [param target]: a [DotHumanoidFigure] or a [DotPlayerFirstPersonBody] (anything with `own_body_shown`). [param settings] is a DotSettingsManager or anything with `get_bool(key, fallback)`.
static func apply(target: Object, settings: Object) -> void:
	if target != null:
		target.set("own_body_shown", settings == null or bool(settings.call("get_bool", KEY, DEFAULT)))


## Keeps [param target] on the setting as it changes; call once after it is built. Applies at once even when [param settings] has no `changed` signal; calling again for the same pair does not connect twice.
static func follow(target: Object, settings: Object) -> void:
	apply(target, settings)
	if target == null or settings == null or not settings.has_signal("changed"):
		return
	var old: Dictionary = target.get_meta(META, {})
	if not old.is_empty():
		var prev: Object = old["settings"].get_ref()
		if prev == settings:
			return
		if prev != null and prev.is_connected("changed", old["call"]):
			prev.disconnect("changed", old["call"])
	# Weak references: a lambda holding the settings (or a target that holds the lambda) would never be freed.
	var weak := weakref(settings)
	var weak_target := weakref(target)
	var on_change := func(key: StringName, _v: Variant, _r: StringName) -> void:
		var live: Object = weak.get_ref()
		var t: Object = weak_target.get_ref()
		if key == KEY and live != null and t != null:
			apply(t, live)
	settings.connect("changed", on_change)
	target.set_meta(META, {"settings": weak, "call": on_change})
