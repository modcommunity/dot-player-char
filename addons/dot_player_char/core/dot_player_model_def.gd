@tool
class_name DotPlayerModelDef
extends Resource

## A 3D character model: which rig, which mounts, and how a slot maps onto one.
##
## [b]A definition names content; it does not hold it.[/b] [member rig_scene] is a
## path, every part is an id, and nothing here is a [PackedScene] — so a dedicated
## server can carry a catalogue of these and answer questions about them without
## loading a single mesh. The resolution from a path to an actual scene happens on a
## client, in [DotPlayerModelBuilder], and only there.

## The name everything else uses. Usually the same as a [DotPlayerCharDef]'s.
@export var id: StringName = &""

@export var display_name: String = ""

## The rig scene: a [Node3D] with a child per mount.
##
## A path rather than a [PackedScene] export, because a `PackedScene` export is loaded
## the moment the resource is, and a server holding forty of these would load forty
## character rigs it has no use for.
@export_file("*.tscn", "*.scn") var rig_scene: String = ""

## Uniform scale applied to the built rig.
@export_range(0.01, 100.0, 0.01) var scale: float = 1.0

@export_group("Mounts")

## slot id -> node name inside the rig.
##
## [code]{"head": "Skeleton3D/HeadAttachment", "back": "Skeleton3D/BackAttachment"}[/code].
## Names rather than [NodePath]s so the table survives being written in JSON, which is
## how a catalogue delivered through dot-cloud arrives.
@export var mounts: Dictionary = {}

## The mount a weapon goes in.
@export var weapon_mount: StringName = &"right_hand"

## The node whose position is the eyes, if the rig has one.
##
## What lets [method DotPlayerCharVisual.eye_offset] answer properly. Empty means the
## rig has no opinion and the character definition's number is used.
@export var eye_mount: StringName = &""

@export_group("Parts")

## part id -> scene path. The content this model can put in its mounts.
##
## Flat and by id, the way dot-user-avatar's catalogue is, because the id is what a
## server validates against and the path is what only a client ever needs.
@export var parts: Dictionary = {}

## part id -> the slot it belongs in. A part in the wrong mount is a hat on a foot.
@export var part_slots: Dictionary = {}

## Draw order within a mount, part id -> layer. Higher is later.
@export var part_layers: Dictionary = {}

@export_group("Tinting")

## The shader parameter prefix used for per-instance tints.
##
## Written with [method GeometryInstance3D.set_instance_shader_parameter], which is
## per-instance and therefore cannot leak between two players wearing the same part —
## the trap a shared [Material] falls into, and the one dot-user-avatar's builder
## documents having avoided.
@export var tint_parameter: String = "dot_tint_"

## How many channels this model's materials actually read.
@export_range(0, 8, 1) var tint_channels: int = 2

@export_group("Anything else")

@export var attributes: Dictionary = {}


static func make(p_id: StringName, p_rig: String = "") -> DotPlayerModelDef:
	var m := DotPlayerModelDef.new()
	m.id = p_id
	m.display_name = String(p_id).capitalize()
	m.rig_scene = p_rig
	return m


func validate() -> DotResult:
	if id == &"":
		return DotResult.fail(DotError.CODE_INVALID, "A model with no id.")

	for part_id: Variant in parts.keys():
		if not part_slots.has(part_id):
			return DotResult.fail(
				DotError.CODE_INVALID,
				"Part '%s' has no slot." % str(part_id),
				"It would be built into whichever mount happened to be asked for it, "
				+ "which is how a hat ends up on a foot."
			)

		var slot := str(part_slots[part_id])

		if not mounts.has(slot):
			return DotResult.fail(
				DotError.CODE_INVALID,
				"Part '%s' goes in slot '%s', which this rig has no mount for."
				% [str(part_id), slot]
			)

	return DotResult.success(null)


func mount_name(slot: StringName) -> String:
	return str(mounts.get(String(slot), ""))


func has_mount(slot: StringName) -> bool:
	return mounts.has(String(slot))


func slot_names() -> Array[StringName]:
	var out: Array[StringName] = []

	for key: Variant in mounts.keys():
		out.append(StringName(str(key)))

	out.sort()
	return out


func part_path(part_id: StringName) -> String:
	return str(parts.get(String(part_id), ""))


func has_part(part_id: StringName) -> bool:
	return parts.has(String(part_id))


func part_slot(part_id: StringName) -> StringName:
	return StringName(str(part_slots.get(String(part_id), "")))


func part_layer(part_id: StringName) -> int:
	return int(part_layers.get(String(part_id), 50))


func describe() -> String:
	return "%s: %d mounts, %d parts%s" % [
		String(id), mounts.size(), parts.size(),
		"" if rig_scene == "" else ", rig %s" % rig_scene.get_file(),
	]


func _to_string() -> String:
	return "DotPlayerModelDef(%s)" % describe()
