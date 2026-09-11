class_name DotPlayerModelBuilder
extends RefCounted

## Works out what goes where, and then puts it there. The two are separate.
##
## [b]This is dot-user-avatar's builder, generalised.[/b] That addon had the split
## already and it was the right one — working out which parts go in which mounts, in
## what order, with which colours is pure logic over ids, and instantiating scenes and
## reparenting nodes is not — but it was written against [code]DotAvatar[/code] and so
## only avatars could use it. Here the plan is an array of plain [Dictionary] values, so
## a character's customisation document, an avatar document, a loadout's view model and
## a game's own system all produce one and share the node work.
##
## A step is:
##
## [codeblock]
## {
##   "slot": StringName,     which mount
##   "mount": String,        the node name inside the rig
##   "part": StringName,     what was asked for
##   "scene": String,        the resolved path, or "" for nothing
##   "colours": Array,       tints, in channel order
##   "layer": int,           draw order within the mount
##   "missing": bool,        nothing resolved; show a placeholder
## }
## [/codeblock]

const CHANNEL := "player.model"


## What to build for a character's look. Touches no nodes and loads nothing.
static func plan(def: DotPlayerModelDef, look: DotPlayerCharLook) -> Array[Dictionary]:
	var steps: Array[Dictionary] = []

	if def == null:
		return steps

	var colours: Array = look.colours if look != null else []

	for slot in def.slot_names():
		var part := look.chosen(slot) if look != null else &""

		if part == &"":
			continue

		var path := def.part_path(part)
		var wrong_slot := def.has_part(part) and def.part_slot(part) != slot

		if wrong_slot:
			# Refused rather than built into the wrong mount. A part whose slot does
			# not match is a content error, and building it anyway is how a hat ends up
			# on a foot with nothing saying why.
			DotLog.warn(CHANNEL, "part is in the wrong slot", {
				"part": String(part), "asked_for": String(slot),
				"belongs_in": String(def.part_slot(part)),
			})
			path = ""

		steps.append({
			"slot": slot,
			"mount": def.mount_name(slot),
			"part": part,
			"scene": path,
			"colours": colours.duplicate(),
			"layer": def.part_layer(part),
			"missing": path == "",
		})

	# Sorted by layer so two parts in one mount stack the same way every time. Ties
	# broken by slot name, because a plan that depends on dictionary order is a plan
	# that renders differently on two machines.
	steps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["layer"]) != int(b["layer"]):
			return int(a["layer"]) < int(b["layer"])
		return String(a["slot"]) < String(b["slot"])
	)

	return steps


## Builds a plan under a rig. The only function here that touches the scene tree.
##
## Every named mount is [b]cleared and rebuilt[/b], which is what makes applying a second
## look to the same rig well defined — and that matters more than it sounds, because a
## player changing a hat in a menu does exactly that several times a second. A builder
## that appended would grow a hat per frame.
##
## Returns how many parts were actually shown.
static func apply(
	steps: Array[Dictionary],
	rig: Node3D,
	placeholder: PackedScene = null,
	tint_prefix: String = "dot_tint_"
) -> DotResult:
	if rig == null:
		return DotResult.fail(DotError.CODE_INVALID, "No rig to build on.")

	var cleared: Dictionary = {}
	var shown := 0

	for step in steps:
		var mount_name := str(step.get("mount", ""))
		var mount := rig.get_node_or_null(NodePath(mount_name))

		if mount == null:
			# A mismatch between the definition and the rig, which is a content problem
			# and worth naming rather than skipping in silence.
			DotLog.warn(CHANNEL, "the rig has no mount for a slot", {
				"slot": str(step.get("slot", "")), "expected_node": mount_name,
			})
			continue

		if not cleared.has(mount_name):
			for child in mount.get_children():
				child.queue_free()
			cleared[mount_name] = true

		var scene: PackedScene = null
		var path := str(step.get("scene", ""))

		if path != "" and ResourceLoader.exists(path):
			scene = load(path) as PackedScene

		if scene == null:
			scene = placeholder

		if scene == null:
			continue

		var instance := scene.instantiate()
		mount.add_child(instance)

		tint(instance, step.get("colours", []) as Array, tint_prefix)
		shown += 1

	return DotResult.success(shown)


## Applies tint colours to whatever a part instantiated.
##
## Per-instance shader parameters rather than material swaps, for two reasons: a part
## with one mesh and three tintable regions does not need three materials, and two
## players wearing the same part do not share a [Material] and recolour each other —
## which is what happens the moment a [Resource] loaded from disk is edited in place.
static func tint(instance: Node, colours: Array, prefix: String = "dot_tint_") -> void:
	if colours.is_empty() or instance == null:
		return

	for i in range(colours.size()):
		var colour: Variant = colours[i]

		if colour is Color:
			_tint_recursive(instance, "%s%d" % [prefix, i], colour as Color)


static func _tint_recursive(node: Node, parameter: String, colour: Color) -> void:
	var geometry := node as GeometryInstance3D

	if geometry != null:
		geometry.set_instance_shader_parameter(parameter, colour)

	for child in node.get_children():
		_tint_recursive(child, parameter, colour)


## Clears every mount a definition names, without building anything.
static func clear(def: DotPlayerModelDef, rig: Node3D) -> int:
	if def == null or rig == null:
		return 0

	var cleared := 0

	for slot in def.slot_names():
		var mount := rig.get_node_or_null(NodePath(def.mount_name(slot)))

		if mount == null:
			continue

		for child in mount.get_children():
			child.queue_free()
			cleared += 1

	return cleared


## What a plan adds up to, for a loading indicator or a bug report.
static func summarise(steps: Array[Dictionary]) -> Dictionary:
	var missing := 0

	for step in steps:
		if bool(step.get("missing", false)):
			missing += 1

	return {
		"slots": steps.size(),
		"missing": missing,
		"complete": missing == 0,
	}


## Turns dot-user-avatar's plan into this one's, without importing that addon.
##
## [b]The bridge, and it is by duck typing on purpose.[/b] dot-user-avatar produces a
## plan of its own — it has to, because its whole promise is that a server can validate
## an avatar from ids — and this addon does the node work. Neither depends on the other:
## a game with both calls this, a game with only one is unaffected.
##
## Accepts anything shaped like a plan: an [Array] of [Dictionary], or an array of
## objects with a [code]describe[/code]-able set of the same fields.
static func from_plan(rows: Array, mounts: Dictionary = {}) -> Array[Dictionary]:
	var steps: Array[Dictionary] = []

	for row: Variant in rows:
		if not (row is Dictionary):
			continue

		var d := row as Dictionary
		var slot := StringName(str(d.get("slot", "")))
		var mount := str(d.get("mount", d.get("attach_to", "")))

		if mount == "" and mounts.has(String(slot)):
			mount = str(mounts[String(slot)])

		steps.append({
			"slot": slot,
			"mount": mount,
			"part": StringName(str(d.get("part", d.get("requested", "")))),
			"scene": str(d.get("scene", d.get("scene_path", ""))),
			"colours": (d.get("colours", []) as Array).duplicate(),
			"layer": int(d.get("layer", 50)),
			"missing": bool(d.get("missing", str(d.get("scene", "")) == "")),
		})

	return steps
