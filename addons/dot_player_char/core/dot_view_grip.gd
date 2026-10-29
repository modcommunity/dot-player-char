class_name DotViewGrip
extends RefCounted

## Where the hands go on a first-person weapon: points in [member anchor]'s local space, read each frame so the hands follow the weapon wherever the host moves it. Hand one, or both.

## The weapon mesh's node (or a marker child of it); the points below are in its space.
var anchor: Node3D = null
## Where the firing hand's palm sits.
var grip: Vector3 = Vector3.ZERO
## Where the support hand sits; [constant Vector3.INF] holds the weapon with one hand.
var support: Vector3 = Vector3.INF


## A one-hand weapon (a pistol, a knife).
static func one_hand(p_anchor: Node3D, p_grip: Vector3) -> DotViewGrip:
	var g := DotViewGrip.new()
	g.anchor = p_anchor
	g.grip = p_grip
	return g


## A two-hand weapon: the support hand on the foregrip.
static func two_hand(p_anchor: Node3D, p_grip: Vector3, p_support: Vector3) -> DotViewGrip:
	var g := one_hand(p_anchor, p_grip)
	g.support = p_support
	return g


func is_two_hand() -> bool:
	return support.is_finite()


## False when the anchor is gone or outside the tree, so the arms rest instead of reaching for nothing.
func is_valid() -> bool:
	return anchor != null and is_instance_valid(anchor) and anchor.is_inside_tree() and grip.is_finite()


func grip_world() -> Vector3:
	return anchor.global_transform * grip


func support_world() -> Vector3:
	return anchor.global_transform * support
