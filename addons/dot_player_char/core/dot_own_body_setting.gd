class_name DotOwnBodySetting
extends RefCounted
## The client-only `cl_legs` option: whether you see your own legs and body when you look down.
## Never server-enforced; a game lists [method def] in its settings schema and calls [method follow].

const KEY := &"cl_legs"
const DEFAULT := true


## The setting's definition (a DotSettingsDef, device scope), or null when dot-settings is not in the project: this addon does not require it.
static func def() -> Variant:
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		if entry.get("class") == &"DotSettingsDef":
			var script: GDScript = load(entry["path"])
			var d: Object = script.call("boolean", KEY, DEFAULT, &"video")
			d.call("with_description", "Show your own legs and body when you look down.")
			return d
	return null


## Puts the setting's value on [param figure]. [param settings] is a DotSettingsManager or anything with `get_bool(key, fallback)`.
static func apply(figure: DotHumanoidFigure, settings: Object) -> void:
	if figure != null:
		figure.own_body_shown = settings == null or bool(settings.call("get_bool", KEY, DEFAULT))


## Keeps [param figure] on the setting as it changes; call once after the figure is built.
static func follow(figure: DotHumanoidFigure, settings: Object) -> void:
	if settings == null or not settings.has_signal("changed"):
		return
	apply(figure, settings)
	# A weak reference: a lambda holding the settings that hold the lambda would never be freed.
	var weak := weakref(settings)
	settings.connect("changed", func(key: StringName, _v: Variant, _r: StringName) -> void:
		var live: Object = weak.get_ref()
		if key == KEY and live != null and is_instance_valid(figure):
			apply(figure, live))
