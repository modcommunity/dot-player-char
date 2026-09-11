@tool
class_name DotPlayerModelRig
extends Node3D

## A built character rig: named mounts, a stance, and where the eyes are.
##
## [b]A thin node over a scene somebody else authored.[/b] It does not build the model —
## [DotPlayerModelBuilder] does — and it does not know what a character is. What it adds
## is the lookup: a mount by slot name, cached, with one warning rather than one per
## frame when the rig and the definition disagree.

const CHANNEL := "player.model"

## The definition this rig was built for.
var def: DotPlayerModelDef = null

## The instantiated rig scene, if one was loaded.
var instance: Node3D = null

var _mounts: Dictionary = {}
var _warned: Dictionary = {}


## Loads the rig scene and takes it as a child. Idempotent.
##
## Returns a failure rather than a half-built rig when the scene is missing, because a
## rig with no mounts silently shows nothing and reads as "the character is invisible",
## which is debugged in the renderer.
func build_from(p_def: DotPlayerModelDef) -> DotResult:
	def = p_def
	_mounts.clear()
	_warned.clear()

	if instance != null and is_instance_valid(instance):
		instance.queue_free()
		instance = null

	if def == null:
		return DotResult.fail(DotError.CODE_INVALID, "No model definition.")

	scale = Vector3.ONE * def.scale

	if def.rig_scene == "":
		# Legal: a game whose rig is already in the scene beside this node passes
		# nothing and uses adopt() instead.
		return DotResult.success(null)

	if not ResourceLoader.exists(def.rig_scene):
		return DotResult.fail(
			DotError.CODE_IO,
			"The rig scene for '%s' is not there: %s" % [String(def.id), def.rig_scene]
		)

	var packed := load(def.rig_scene) as PackedScene

	if packed == null:
		return DotResult.fail(
			DotError.CODE_PARSE, "%s is not a PackedScene." % def.rig_scene
		)

	instance = packed.instantiate() as Node3D

	if instance == null:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"%s does not instantiate to a Node3D." % def.rig_scene
		)

	add_child(instance)
	return DotResult.success(instance)


## Uses a rig that is already in the scene rather than loading one.
func adopt(existing: Node3D, p_def: DotPlayerModelDef) -> void:
	def = p_def
	instance = existing
	_mounts.clear()
	_warned.clear()


## The node a slot's content goes into, or null.
##
## Cached, and the warning fires once per slot rather than once per frame: a rig that
## does not match its definition would otherwise fill a log with one line per attachment
## per frame, which buries everything else.
func mount(slot: StringName) -> Node3D:
	if _mounts.has(slot):
		var cached: Variant = _mounts[slot]
		return cached if cached != null and is_instance_valid(cached) else null

	if def == null:
		return null

	# `node_name` rather than `name`: Node already has one, and a local that shadows it
	# compiles while making every later reference in the function ambiguous to read.
	var node_name := def.mount_name(slot)

	if node_name == "":
		return null

	var root: Node = instance if instance != null else self
	var found := root.get_node_or_null(NodePath(node_name)) as Node3D

	if found == null and not _warned.has(slot):
		_warned[slot] = true
		DotLog.warn(CHANNEL, "the rig has no mount", {
			"slot": String(slot), "expected": node_name, "model": String(def.id),
		})

	_mounts[slot] = found
	return found


func has_mount(slot: StringName) -> bool:
	return mount(slot) != null


func mount_names() -> Array[StringName]:
	return def.slot_names() if def != null else []


## Where a weapon goes.
func weapon_mount() -> Node3D:
	return mount(def.weapon_mount) if def != null else null


## The eye height this rig actually has, or -1 for "no opinion".
##
## Measured from the mount's position rather than declared, because a rig that has been
## scaled, or whose author put the head somewhere unexpected, is exactly the case where
## a declared number is wrong.
func eye_height() -> float:
	if def == null or def.eye_mount == &"":
		return -1.0

	var node := mount(def.eye_mount)

	if node == null:
		return -1.0

	return maxf(0.0, node.global_position.y - global_position.y)


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()
	out.append("rig %s%s" % [
		String(def.id) if def != null else "<none>",
		"" if instance != null else " (no scene)",
	])

	for slot in mount_names():
		out.append("  %-12s %s" % [
			String(slot), "ok" if has_mount(slot) else "MISSING"
		])

	return out
