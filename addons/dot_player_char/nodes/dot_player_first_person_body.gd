class_name DotPlayerFirstPersonBody
extends RefCounted

## Lets a first-person player see their own body when they look down. Local player only; presentation only.
## The head casts its shadow but is not drawn (the camera is inside it and would see back-faces), and the body
## sits [member back_offset] behind the eye, else the camera is in the chest.

## Name fragments that make a mesh part of the head, matched like
## [member DotPlayerBreakRules.limb_names] against the mesh and its ancestors. Hats and
## faces hang off the head mount, so they go with it.
var head_names: PackedStringArray = PackedStringArray(["head", "face", "hat", "hair", "eye"])

## When not empty, only meshes whose names (or an ancestor's) contain one of these stay drawn; the rest cast
## their shadow only, like the head. Empty is the old behaviour (everything but the head).
## Set the legs (["leg", "foot", "shoe", "boot"]) for a box body, whose torso an eye-height camera looks into.
var shown_names: PackedStringArray = PackedStringArray()

## Metres the body is pulled back behind the eye, along the body's own facing.
var back_offset: float = 0.22

## False (the `cl_legs` setting, see [DotOwnBodySetting]): nothing of the body is drawn, only its shadow, and it is not pulled back.
var own_body_shown: bool = true:
	set(value):
		if value == own_body_shown:
			return
		own_body_shown = value
		var body := _body
		if body != null and is_instance_valid(body):
			restore()
			apply(body)

var _hidden: Array[MeshInstance3D] = []
var _was: Array[int] = []
var _body: Node3D = null
var _moved: Vector3 = Vector3.ZERO


## Shows [param body] in first person. Idempotent; [method restore] undoes it.
func apply(body: Node3D) -> void:
	if body == null:
		return

	if _body == body:
		return

	restore()
	_body = body

	for mesh in DotPlayerBodyBreak.visible_meshes(body):
		if not own_body_shown or _is_head(body, mesh) or not _is_shown(body, mesh):
			_hidden.append(mesh)
			_was.append(mesh.cast_shadow)
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY

	if not own_body_shown:
		return
	# Godot's forward is -Z, so "behind" is +Z in the body's own frame.
	_moved = Vector3(0.0, 0.0, back_offset)
	body.position += body.basis * _moved


## Puts the body back the way it was drawn: the head drawn, the body where it stood.
func restore() -> void:
	for i in range(_hidden.size()):
		if is_instance_valid(_hidden[i]):
			_hidden[i].cast_shadow = _was[i]

	if _body != null and is_instance_valid(_body):
		_body.position -= _body.basis * _moved

	_hidden.clear()
	_was.clear()
	_body = null
	_moved = Vector3.ZERO


## The meshes it stopped drawing. For a suite and for describe().
func hidden_count() -> int:
	return _hidden.size()


func _is_shown(body: Node, mesh: MeshInstance3D) -> bool:
	if shown_names.is_empty():
		return true

	return _named(body, mesh, shown_names)


func _named(body: Node, mesh: MeshInstance3D, fragments: PackedStringArray) -> bool:
	var node: Node = mesh

	while node != null:
		var lower := String(node.name).to_lower()

		for fragment in fragments:
			if fragment != "" and lower.contains(fragment):
				return true

		if node == body:
			break

		node = node.get_parent()

	return false


func _is_head(body: Node, mesh: MeshInstance3D) -> bool:
	var node: Node = mesh

	while node != null:
		var lower := String(node.name).to_lower()
		for fragment in head_names:
			if fragment != "" and lower.contains(fragment):
				return true
		if node == body:
			break
		node = node.get_parent()

	return false


func describe() -> Dictionary:
	return {"applied": _body != null, "head_meshes": _hidden.size(), "back_offset": back_offset, "shown": shown_names}
