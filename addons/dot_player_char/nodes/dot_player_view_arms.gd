class_name DotPlayerViewArms
extends Node3D

## Your own arms in first person while downed: put it under the camera's yaw pivot (not its pitch, or the arms swing with the look) and call [method set_downed]. Plays the
## figure's crawl clip with the head, neck and legs shrunk away so only the reaching arms and a little
## torso are in view; a game's own arms come from [member arms_factory].

const CHANNEL := "player.view_arms"
## Bones shrunk to nothing; the arms hang off the chest, so they stay.
const HIDDEN_BONES: Array[String] = ["Head", "Neck", "UpperLeg.L", "UpperLeg.R"]

## Extension point: `func(look: DotHumanoidLook, height: float) -> Node3D`. The node it returns is parented here and
## drawn as is, in place of the person; if it has `set_motion` and `animate` (a [DotHumanoidFigure]) they are driven.
var arms_factory: Callable = Callable()
## Where the camera sits relative to the crawling figure's head bone, in the figure's own frame (the clip lies the
## person along Z; the eye is measured from the posed head, not assumed, so a game's own figure fits too).
var eye_from_head: Vector3 = Vector3(0.0, 0.3, -0.4)
var look: DotHumanoidLook = null
var height: float = 1.8
var shown: bool = false

var _arms: Node3D = null
var _bones: Array[int] = []
var _fitted := false
var _ticks := 0
var _head: int = -1


## Builds the arms (once; a new [param p_look] rebuilds). Hidden until [method set_downed] says otherwise.
func build(p_look: DotHumanoidLook = null, p_height: float = 1.8) -> void:
	look = p_look if p_look != null else DotHumanoidLook.stock(0)
	height = p_height
	_clear()

	if arms_factory.is_valid():
		_arms = arms_factory.call(look, height) as Node3D

	if _arms == null:
		var figure := DotHumanoidFigure.new()
		figure.name = "Arms"
		add_child(figure)
		figure.build(look, height)
		_arms = figure
		var skeleton := figure.skeleton()

		if skeleton != null:
			_head = skeleton.find_bone("Head")

			for bone in HIDDEN_BONES:
				var i := skeleton.find_bone(bone)
				if i >= 0:
					_bones.append(i)
	else:
		add_child(_arms)

	_fitted = false
	_ticks = 0
	_arms.visible = shown


## Shows the arms while [param on]. Always the prone crawl: a player propped on their back sees the held weapon, not arms.
func set_downed(on: bool) -> void:
	shown = on

	if _arms == null:
		return

	_arms.visible = on

	if _arms.has_method("set_motion"):
		_arms.call("set_motion", {"downed": on, "propped": false})


## Advances the arms; [param speed] is the player's ground speed, which drives the crawl.
func tick(speed: float, delta: float) -> void:
	if _arms == null or not shown:
		return

	if _arms.has_method("animate"):
		_arms.call("animate", speed, delta)

	_ticks += 1

	if not _fitted and _ticks >= 3 and is_inside_tree():
		_fit()

	var skeleton: Skeleton3D = (_arms as DotHumanoidFigure).skeleton() if _arms is DotHumanoidFigure else null

	if skeleton != null:
		for i in _bones:
			skeleton.set_bone_pose_scale(i, Vector3.ONE * 0.001)


## Seats the posed head bone at this node's origin; the clip already lies the person head toward -Z.
func _fit() -> void:
	_fitted = true
	var skeleton: Skeleton3D = (_arms as DotHumanoidFigure).skeleton() if _arms is DotHumanoidFigure else null

	if skeleton == null or _head < 0:
		return

	_arms.transform = Transform3D.IDENTITY
	var head := _arms.global_transform.affine_inverse() * (skeleton.global_transform * skeleton.get_bone_global_pose(_head)).origin
	_arms.transform = Transform3D(Basis.IDENTITY, -(head + eye_from_head))


## The arms node, or null before [method build].
func arms() -> Node3D:
	return _arms


func describe() -> Dictionary:
	return {"built": _arms != null, "shown": shown, "custom": arms_factory.is_valid(), "hidden_bones": _bones.size()}


func _clear() -> void:
	if _arms != null:
		remove_child(_arms)
		_arms.queue_free()
		_arms = null

	_bones.clear()
