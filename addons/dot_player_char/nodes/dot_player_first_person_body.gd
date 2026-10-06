class_name DotPlayerFirstPersonBody
extends RefCounted

## Lets a first-person player see their own body when they look down: the head is not
## drawn (it still casts its shadow), and the body sits a little behind the eye.
##
## [b]The head stops drawing, it does not disappear[/b] — [code]SHADOW_CASTING_SETTING_SHADOWS_ONLY[/code]
## — because the camera is inside it, and a head drawn from the inside is a wall of
## back-faces across the screen; but a player's shadow with no head on it is a stranger.
##
## [b]Behind the eye, by a few centimetres[/b]: a body whose chest is level with the camera
## puts the camera inside the chest, and looking down shows its inside. [member back_offset]
## pulls it back far enough that looking down shows the torso and the legs and the feet
## land where the player's own feet are, give or take.
##
## [b]A game's choice per server[/b] (the game exposes it as a setting); off, the game hides
## its own body in first person exactly as it did before. Presentation only, local player
## only: everybody else always sees the whole body.

## Name fragments that make a mesh part of the head, matched like
## [member DotPlayerBreakRules.limb_names] against the mesh and its ancestors. Hats and
## faces hang off the head mount, so they go with it.
var head_names: PackedStringArray = PackedStringArray(["head", "face", "hat", "hair", "eye"])

## Metres the body is pulled back behind the eye, along the body's own facing.
var back_offset: float = 0.22

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
		if _is_head(body, mesh):
			_hidden.append(mesh)
			_was.append(mesh.cast_shadow)
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY

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
	return {"applied": _body != null, "head_meshes": _hidden.size(), "back_offset": back_offset}
