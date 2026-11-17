extends Node3D

## [DotHumanoidFigure]'s distance tuning and bone names, at the bottom of its chain: the frame and aim helpers read
## them here (by path) instead of naming DotHumanoidFigure, which named them back, a parser cycle Godot 4.7 never
## frees. Read them through DotHumanoidFigure as before.

## Within this distance of the camera the clip is advanced every frame; then every second frame
## to [constant ANIM_FAR], and every fourth beyond.
const ANIM_NEAR := 22.0
const ANIM_FAR := 45.0

## Out of the camera's view or hidden, the frame step is this many times its distance's: only a shadow and a kill-cam
## recording see the pose. Hit zones are not bones, so they never lag.
const OFFSCREEN_STEP := 2

## Frames apart a figure is posed when nothing of it is drawn: hidden, or out of view past [member shadow_range]
## (no shadow either). It is redrawn the frame it comes back into view.
const UNSEEN_STEP := 8

## Past this distance a figure in view draws no support hand on the foregrip, and past [constant ANIM_FAR] no carry
## pose on the gun arm (the clip's own arm is drawn). Out of view only its shadow is drawn: no aim, carry or support,
## and the feet are not kept out of the floor. With no camera (a server, a suite) every layer is drawn.
const SUPPORT_RANGE := ANIM_NEAR

## Seconds an [member auto_animate] body may stand still between moves before it counts as stopped: longer than a
## physics tick or a snapshot gap, short enough that a stop shows at once.
const AUTO_HOLD := 0.1

## Shortest span [member auto_animate] measures a speed over: several ticks, so the frames that fall between a stepped
## body's moves (two or three a tick at a few hundred frames a second) shake the measure by a few percent, not a third.
const AUTO_WINDOW := 0.05

## Longest an [member auto_animate] body keeps one pose while it stands between steps (its idle still breathes).
const AUTO_POSE_GAP := 1.0 / 60.0

## Below 1, the mesh switches to its simpler levels sooner; a person is small on screen past a few metres.
const LOD_BIAS := 0.4

## Past this distance from the camera a person casts no shadow: the shadow pass was over half of a crowd's triangles.
const SHADOW_RANGE := 28.0

## Nothing drawn past this.
const DRAW_RANGE := 140.0

## The ranges a client uses, defaulting to the constants above and read live (a game binds its cvars to them). 0 is
## no limit. A negative, infinite or NaN value is refused with an error and the last good value kept, never clamped.
## Past [member shadow_range] a figure casts no shadow (0: at every distance).
static var shadow_range: float = SHADOW_RANGE:
	set(value):
		if _range_ok("shadow_range", value):
			shadow_range = value
## Past [member draw_range] a figure is not drawn (0: drawn at every distance).
static var draw_range: float = DRAW_RANGE:
	set(value):
		if _range_ok("draw_range", value):
			draw_range = value
## Past [member lift_range] from the camera, or out of its view, a figure stands on the floor under it only on the
## frames its clip steps, not on every frame between (one floor ray each). 0: every frame at every distance.
static var lift_range: float = 0.0:
	set(value):
		if _range_ok("lift_range", value):
			lift_range = value
## The mesh's [member GeometryInstance3D.lod_bias]; under 1 its simpler levels come sooner. Must be above 0.
static var lod_bias: float = LOD_BIAS:
	set(value):
		if is_finite(value) and value > 0.0:
			lod_bias = value
		else:
			push_error("DotHumanoidFigure.lod_bias must be a finite number above 0, got %s" % value)


static func _range_ok(what: String, value: float) -> bool:
	if is_finite(value) and value >= 0.0:
		return true
	push_error("DotHumanoidFigure.%s must be a finite number of metres, 0 or more (0: no limit), got %s" % [what, value])
	return false

## The bone a weapon is held in. The kit's people are left-handed, so the clip set is mirrored once
## on load ([method DotHumanoidClips.mirror]) and others see the gun in the hand first person holds it in.
const HAND_BONE := "Middle1.R"

## The head bone, which the crown mounts hang from.
const HEAD_BONE := "Head"

## Where a weapon's grip sits from that bone at the held-gun pose, in metres.
const HAND_OFFSET := Vector3(0.0, 0.03, -0.02)

## How far the gun arm drops at a full sprint carry, in radians, on top of the view's pitch.
const SPRINT_DROP := 0.6
