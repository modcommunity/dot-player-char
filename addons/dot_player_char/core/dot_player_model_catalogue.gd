@tool
class_name DotPlayerModelCatalogue
extends Resource

## Every 3D model a session has, by id.

const CHANNEL := "player.model"

@export var id: StringName = &""

@export var models: Array[DotPlayerModelDef] = []

@export var default_model: StringName = &""

var _by_id: Dictionary = {}
var _built: bool = false


func build() -> DotResult:
	_by_id.clear()

	if models.is_empty():
		return DotResult.fail(DotError.CODE_INVALID, "A catalogue with no models.")

	for m in models:
		if m == null:
			return DotResult.fail(DotError.CODE_INVALID, "A null model.")

		var valid := m.validate()

		if not valid.ok:
			return valid.wrap("This model catalogue was not built")

		if _by_id.has(m.id):
			return DotResult.fail(
				DotError.CODE_INVALID, "Two models are called '%s'." % String(m.id)
			)

		_by_id[m.id] = m

	if default_model != &"" and not _by_id.has(default_model):
		return DotResult.fail(
			DotError.CODE_INVALID,
			"The default model '%s' is not in the catalogue." % String(default_model)
		)

	_built = true
	return DotResult.success(null)


func _ensure_built() -> void:
	if not _built or _by_id.size() != models.size():
		var res := build()
		if not res.ok:
			DotLog.error(CHANNEL, "model catalogue unusable", {"why": res.error.message})


func has_model(model_id: StringName) -> bool:
	_ensure_built()
	return _by_id.has(model_id)


func get_model(model_id: StringName) -> DotPlayerModelDef:
	_ensure_built()
	return _by_id.get(model_id, null)


func ids() -> Array[StringName]:
	_ensure_built()
	var out: Array[StringName] = []

	for m in models:
		if m != null:
			out.append(m.id)

	return out


func fallback() -> DotPlayerModelDef:
	_ensure_built()

	if default_model != &"" and _by_id.has(default_model):
		return _by_id[default_model]

	for m in models:
		if m != null:
			return m

	return null


## Every scene path this catalogue can possibly need.
##
## What a preloader, a dot-cloud manifest builder or a packaging check asks for. Here
## rather than in a game because the catalogue is the only thing that knows the full
## set, and a game listing them by hand is a game that ships a model with a part missing.
func content_paths() -> PackedStringArray:
	_ensure_built()
	var out := PackedStringArray()

	for m in models:
		if m == null:
			continue

		if m.rig_scene != "" and not out.has(m.rig_scene):
			out.append(m.rig_scene)

		for part_id: Variant in m.parts.keys():
			var path := str(m.parts[part_id])
			if path != "" and not out.has(path):
				out.append(path)

	return out


func describe_lines() -> PackedStringArray:
	_ensure_built()
	var out := PackedStringArray()
	out.append("models (%s): %d" % [String(id), models.size()])

	for m in models:
		if m != null:
			out.append("  " + m.describe())

	return out


func describe() -> String:
	return "DotPlayerModelCatalogue(%s, %d)" % [String(id), models.size()]


func _to_string() -> String:
	return describe()


## A catalogue with the mount names a humanoid rig is expected to have.
##
## [b]The names are the useful part.[/b] Every character rig anybody builds has these
## attachment points under different spellings, and a family that agrees on one spelling
## is a family where a weapon written for one game attaches in another. No scene paths:
## the rig is the game's.
static func humanoid(p_id: StringName = &"humanoid") -> DotPlayerModelCatalogue:
	var cat := DotPlayerModelCatalogue.new()
	cat.id = p_id

	var m := DotPlayerModelDef.make(p_id)
	m.mounts = {
		"head": "Rig/Head",
		"face": "Rig/Head/Face",
		"chest": "Rig/Chest",
		"back": "Rig/Chest/Back",
		"waist": "Rig/Waist",
		"left_hand": "Rig/LeftHand",
		"right_hand": "Rig/RightHand",
		"left_foot": "Rig/LeftFoot",
		"right_foot": "Rig/RightFoot",
	}
	m.weapon_mount = &"right_hand"
	m.eye_mount = &"head"
	m.tint_channels = 2

	cat.models = [m]
	cat.default_model = p_id
	var _res := cat.build()
	return cat
