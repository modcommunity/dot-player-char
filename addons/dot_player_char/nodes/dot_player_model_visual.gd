class_name DotPlayerModelVisual
extends DotPlayerCharVisual

## The 3D implementation of dot-player-char's visual seam.
##
## [b]Four methods, and almost all of the work is somewhere else.[/b] The planning is
## [DotPlayerModelBuilder]'s, the node lookup is [DotPlayerModelRig]'s, and what this
## adds is the part only a visual can know: when to rebuild and when not to.
##
## Rebuilding is the expensive thing and the easy thing to get wrong in both directions.
## Rebuild too eagerly — on every stance change, say — and a player who crouches
## re-instantiates their whole wardrobe; rebuild too lazily and a hat changed in a menu
## does not appear until the next respawn.

## Not [code]CHANNEL[/code]: the parent chain already has one.
const MODEL_CHANNEL := "player.model"

## The model was rebuilt. Carries how many parts were shown.
signal rebuilt(shown: int)

@export var catalogue: DotPlayerModelCatalogue = null

## Shown when a part's content is missing. Optional; nothing is shown without one.
@export var placeholder: PackedScene = null

## Whether to hide the whole rig when [method set_shown] is given false.
@export var hide_when_not_shown: bool = true

var rig: DotPlayerModelRig = null

var _def: DotPlayerModelDef = null
var _last_plan: Array[Dictionary] = []
var _last_signature: String = ""


func _ready() -> void:
	if rig == null:
		rig = DotPlayerModelRig.new()
		rig.name = "Rig"
		add_child(rig)


func apply_char(def: DotPlayerCharDef, look: DotPlayerCharLook) -> void:
	if catalogue == null:
		return

	var wanted := def.model_id if def != null else &""
	var model: DotPlayerModelDef = null

	if wanted != &"" and catalogue.has_model(wanted):
		model = catalogue.get_model(wanted)
	else:
		model = catalogue.fallback()

	if model == null:
		DotLog.warn(MODEL_CHANNEL, "no model to build", {"wanted": String(wanted)})
		return

	if model != _def:
		_def = model
		var res := rig.build_from(model)

		if not res.ok:
			DotLog.error(MODEL_CHANNEL, "rig not built", {"why": res.error.message})
			return

		# A new rig has empty mounts, so the signature from the previous model must not
		# suppress the rebuild below. Without this line, changing character to one that
		# happens to be wearing the same parts shows an empty body.
		_last_signature = ""

	var plan := DotPlayerModelBuilder.plan(model, look)
	var signature := _signature(plan)

	if signature == _last_signature:
		# The menu case: a player dragging a colour slider calls this several times a
		# second and the plan is identical every time. Rebuilding forty parts per frame
		# for a change that is not a change is the cost this comparison exists to avoid.
		_retint(plan)
		return

	_last_signature = signature
	_last_plan = plan

	var built := DotPlayerModelBuilder.apply(
		plan, _root(), placeholder, model.tint_parameter
	)

	if built.ok:
		rebuilt.emit(int(built.value))


func set_stance(crouched: bool) -> void:
	# Deliberately not a rebuild. A stance is an animation's business — see
	# dot-player-char-animations — and re-instantiating a wardrobe every time somebody
	# ducks is the eager half of the mistake this class's documentation names.
	if rig != null:
		rig.set_meta("crouched", crouched)


func set_shown(shown: bool) -> void:
	if hide_when_not_shown and rig != null:
		rig.visible = shown


func eye_offset() -> float:
	return rig.eye_height() if rig != null else -1.0


func attachment(point: StringName) -> Node:
	return rig.mount(point) if rig != null else null


func attachment_names() -> Array[StringName]:
	return rig.mount_names() if rig != null else []


## The mount a weapon should be attached to.
func weapon_mount() -> Node3D:
	return rig.weapon_mount() if rig != null else null


## Forces a rebuild, ignoring the signature. For content that arrived late.
##
## Needed because dot-cloud can deliver a part after the model was first built: the plan
## is identical, the signature matches, and without this the player wears a placeholder
## until something else changes.
func rebuild() -> void:
	_last_signature = ""

	if _def != null and not _last_plan.is_empty():
		var built := DotPlayerModelBuilder.apply(
			_last_plan, _root(), placeholder, _def.tint_parameter
		)
		if built.ok:
			rebuilt.emit(int(built.value))


func plan() -> Array[Dictionary]:
	return _last_plan


func summary() -> Dictionary:
	return DotPlayerModelBuilder.summarise(_last_plan)


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()
	var s := summary()
	out.append("model visual: %s, %d slots, %d missing%s" % [
		String(_def.id) if _def != null else "<none>",
		int(s.get("slots", 0)),
		int(s.get("missing", 0)),
		"" if visual_enabled else " (disabled)",
	])

	if rig != null:
		out.append_array(rig.describe_lines())

	return out


func _root() -> Node3D:
	if rig == null:
		return null

	return rig.instance if rig.instance != null else rig


## What makes two plans the same build.
##
## Colours are deliberately excluded: a tint is applied to an existing instance, so a
## colour change never needs a rebuild, and including it here would put the menu case
## back.
func _signature(steps: Array[Dictionary]) -> String:
	var parts := PackedStringArray()

	for step in steps:
		parts.append("%s=%s" % [str(step.get("slot", "")), str(step.get("scene", ""))])

	return "|".join(parts)


func _retint(steps: Array[Dictionary]) -> void:
	if _def == null or rig == null:
		return

	for step in steps:
		var mount := rig.mount(StringName(str(step.get("slot", ""))))

		if mount == null:
			continue

		for child in mount.get_children():
			DotPlayerModelBuilder.tint(
				child, step.get("colours", []) as Array, _def.tint_parameter
			)
