extends Node3D

## [DotHumanoidFigure]'s constants and state, split out to keep each file small.

const CHANNEL := "player.humanoid"

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

## How long an overlay blends in and out, in seconds.
const BLEND_IN := 0.08
const BLEND_OUT := 0.14

## A held pose or an emote eases in slower than a swing.
const ACTION_BLEND_IN := 0.25
const ACTION_BLEND_OUT := 0.3

## How far a swimmer is laid forward about the hips, in radians: the swim clip is drawn upright.
const SWIM_LEAN := 1.4

## Metres the slide clip is raised: its hips sit below the floor otherwise (for a 1.8 m figure).
const SLIDE_LIFT := 0.1

## Seconds to fall into and rise out of a slide.
const SLIDE_BLEND := 0.35

## How far back a propped, downed body leans about the hips, in radians.
const PROP_LEAN := 1.2

## The clip a downed pose plays; a game with better clips assigns its own names.
var downed_clips: Dictionary = {&"propped": &"", &"crawl": DotHumanoidClips.CRAWL}

## Whether the person is sprinting (from [method set_motion]); the carry eases into it over [constant SPRINT_SECONDS].
var sprinting: bool = false

## What the hand holds, which decides the arms: nothing, a gun (gun clips and overlay) or a melee weapon.
enum Hold { NONE, GUN, MELEE }

## The body whose file carries the clip set; the others play it through [method DotHumanoidClips.retarget].
const CLIP_BODY := DotHumanoidAssets.CLIP_BODY
## How far past the clip's pose a flinch turns the upper body (1 is the clip as authored).
const FLINCH_GAIN := 1.4
var _overlay_gain := 1.0

## The bone a weapon is held in. The kit's people are left-handed, so the clip set is mirrored once
## on load ([method DotHumanoidClips.mirror]) and others see the gun in the hand first person holds it in.
const HAND_BONE := "Middle1.R"

## "head_top", "crest" and "hat" are all the crown mount, from the head bone.
const HEAD_BONE := "Head"
const HEAD_MOUNTS: Array[StringName] = [&"head_top", &"crest", &"hat"]

## How far up and down the upper body follows the view, in radians.
const AIM_LIMIT := 1.15

## Where a weapon's grip sits from that bone at the held-gun pose, in metres.
const HAND_OFFSET := Vector3(0.0, 0.03, -0.02)

## Seconds to ease the sprint carry in or out.
const SPRINT_SECONDS := 0.2

## How far the gun arm drops at a full sprint carry, in radians, on top of the view's pitch.
const SPRINT_DROP := 0.6

## The support arm's bones, and where its elbow points (figure space: left, down, a little back).
const SUPPORT_BONES: Array[String] = ["UpperArm.L", "LowerArm.L", "Middle1.L"]
const SUPPORT_POLE := Vector3(-0.5, -1.0, 0.4)

## The look drawn, the height it was built to, and whether the art loaded (or a capsule stands in).
var look: DotHumanoidLook = null
var height: float = 1.8

## How much a held weapon is scaled up: the people have chibi hands and a real pistol is lost in a fist.
## Set before the first weapon is held.
var held_scale: float = 1.7
var from_art: bool = false

## The locomotion state and the clip playing, for a suite and [method describe].
var state: StringName = DotPlayerAnimState.IDLE
var clip: StringName = &""

## What the hand holds; see [enum Hold].
var hold: int = Hold.NONE

## Down: crawling on the floor, whatever the legs would otherwise do.
var downed: bool = false

## While [member downed]: true lies propped on the back, weapon out; false crawls (`propped` key, [DotDownedRules]).
var propped: bool = false

## The overlay playing on the upper body, or empty.
var overlay: StringName = &""

## The avatar action (emote, pose or gesture id) playing, or empty. See [method play_action].
var action: StringName = &""

## Where the player looks, up (+) or down (-), in radians; the upper body follows ([method aim]).
var aim_pitch: float = 0.0

## Sitting ([constant DotHumanoidClips.SIT]): set by `seated` in [method set_motion].
var seated: bool = false

## Seated with the hands on a wheel ([constant DotHumanoidClips.DRIVE]): set by `driving` in [method set_motion]. Needs `seated` too; a figure without the clip just sits.
var driving: bool = false

## Measures its own movement every frame and animates from that, for a body something else
## carries where no code knows its speed. Off for a player ([method pose]).
var auto_animate: bool = false:
	set(value):
		auto_animate = value
		_auto_last = Vector3.INF
		_auto_seen = Vector3.INF
		_auto_pending = 0.0

## Idles, walks and runs as a zombie does: the library's shuffling walk ([constant DotHumanoidClips.ZOMBIE_WALK]), its idle, and the real sprint for a run. Every other state is the person's own. A figure without the real clips ignores it.
var zombie_gait: bool = false

## Seconds over which [member auto_animate]'s measured speed is averaged. The measure already spans the frames between a stepped body's moves (physics ticks, snapshots); this smooths what is left. 0 keeps the raw measure.
var auto_smooth_time: float = 0.0

## The clips whose rate follows the planted foot ([method _matched_rate]), and the fastest they play.
const STRIDE_CLIPS: Array[StringName] = [DotHumanoidClips.WALK, DotHumanoidClips.WALK_GUN, DotHumanoidClips.RUN,
	DotHumanoidClips.RUN_GUN, DotHumanoidClips.CROUCH_WALK, DotHumanoidClips.SPRINT]
const STRIDE_MAX_RATE := 4.0
## Most the matched rate runs ahead of the clip's mean pace at the ground speed (a multiple of it); 0 (the default) leaves only [member stride_max_rate]. Lower trades a
## little foot slide where the clip stands a foot still for a swing that does not snap through in a frame or two.
var stride_rate_span: float = 0.0:
	set(value):
		if _rate_ok("stride_rate_span", value):
			stride_rate_span = value
## Most the matched rate plays a stride clip at, a multiple of its own pace; 0 no limit. Starts at [constant STRIDE_MAX_RATE].
var stride_max_rate: float = STRIDE_MAX_RATE:
	set(value):
		if _rate_ok("stride_max_rate", value):
			stride_max_rate = value
## Fastest a limb bone (upper and lower legs, feet, upper and lower arms) turns on screen, degrees a second; 0 draws every pose as posed.
## A clip run well past its own pace, a cut between clips or a foot let go by the floor IK otherwise swings a knee through 100 degrees in a frame or
## two. 1300 keeps the worst limb under the 90 degrees in 1/15 s a pop is judged by, and above a sprinter's knee, so the clips play as made. Drawing only ([DotHumanoidTurnLimit]).
var limb_turn_rate: float = 1300.0:
	set(value):
		if _rate_ok("limb_turn_rate", value):
			limb_turn_rate = value


## Farthest a planted foot of a stride is held off where its clip draws it, metres ([method DotHumanoidLegs.hold_feet]): the clip, played at the matched rate,
## still sweeps a planted foot back a little faster or slower than the ground goes by, and the hold pins it where it came down instead. Past this it drags
## (a sharp turn, a teleport). 0 draws the clip's feet as they are. Drawing only.
var foot_hold_reach: float = FOOT_HOLD_REACH:
	set(value):
		if _rate_ok("foot_hold_reach", value, "0: off"):
			foot_hold_reach = value
const FOOT_HOLD_REACH := 0.15
## A stride's foot within this of its rest height (metres) and moving slower than [constant FOOT_HOLD_SETTLE] m/s in the world as the clip draws it is planted;
## a lifted foot eases back onto the clip's over [constant FOOT_HOLD_RELEASE] seconds.
const FOOT_HOLD_HEIGHT := 0.04
const FOOT_HOLD_SETTLE := 1.0
const FOOT_HOLD_RELEASE := 0.12


static func _rate_ok(what: String, value: float, zero := "0: no limit") -> bool:
	if is_finite(value) and value >= 0.0:
		return true
	push_error("DotHumanoidFigure.%s must be a finite number, 0 or more (%s), got %s" % [what, zero, value])
	return false

## The states whose clip is a stride (its rate is matched to the ground), no floor lift, off the floor.
const STRIDE_STATES: Array[StringName] = [DotPlayerAnimState.WALK, DotPlayerAnimState.RUN, DotPlayerAnimState.CROUCH_WALK]
const NO_LIFT_STATES: Array[StringName] = [DotPlayerAnimState.SWIM, DotPlayerAnimState.CLIMB, DotPlayerAnimState.DEAD]
const OFF_FLOOR_STATES: Array[StringName] = [DotPlayerAnimState.SWIM, DotPlayerAnimState.CLIMB, DotPlayerAnimState.DEAD,
	DotPlayerAnimState.JUMP, DotPlayerAnimState.FALL]

## The zombie walk's and the sprint's own ground speeds (m/s), for the rate at other speeds.
const ZOMBIE_WALK_NATURAL := 1.3
const ZOMBIE_SPRINT_NATURAL := 6.0

## Ground speed from which a runner plays the sprint clip when the game sends no `sprinting` key (0 picks 1.6 times the run speed), and how far below it the run clip returns.
var sprint_speed: float = 0.0
const SPRINT_EXIT := 0.8

## Fastest a runner plays the run clip; faster plays the grounded sprint clip, since the run clip's flight hovers.
const RUN_CLIP_MAX_SPEED := 5.5
var _sprint_clip: bool = false

## Ground speed above which the figure runs, and below which a runner walks again ([member DotPlayerAnimState.run_speed], [member DotPlayerAnimState.run_exit_speed]). A game whose walking pace is near the default 4.0 raises them so a walk does not play the hunched run clip.
func set_run_speeds(run_speed: float, run_exit_speed: float) -> void:
	_machine.run_speed = run_speed
	_machine.run_exit_speed = run_exit_speed


## Frames per advance of the clip: 1, 2 or 4 by distance from the camera, twice that out of view.
var anim_step: int = 1

## The head (and neck) shrunk to nothing after the clip, for your own body in first person.
var hide_head: bool = false:
	set(value):
		hide_head = value
		_own.hide_head = value
		_own.apply(_skeleton, _mesh)

## Seen by its own player from inside the head ([DotHumanoidOwnView]: THIRD, LEGS or BODY).
var first_person: int = DotHumanoidOwnView.THIRD:
	set(value):
		first_person = value
		_own.mode = value
		_own.apply(_skeleton, _mesh)

## False hides your own legs and body in first person (the `cl_legs` setting, see [DotOwnBodySetting]); the shadow stays.
var own_body_shown: bool = true:
	set(value):
		own_body_shown = value
		_own.shown = value
		_own.apply(_skeleton, _mesh)

## Metres your own body trails behind the eye looking straight down in first person ([member DotHumanoidOwnView.look_down_back]); 0 when the game places the body itself.
var own_look_down_back: float:
	get:
		return _own.look_down_back
	set(value):
		_own.look_down_back = maxf(value, 0.0)

var _model: Node3D = null
var _skeleton: Skeleton3D = null
var _mesh: MeshInstance3D = null
# A registered body's meshes by detail, drawn one at a time in _mesh ([member DotHumanoidAssets.lod_distances]).
var _details: Array[Mesh] = []
var _detail := 0
var _anim: AnimationPlayer = null
var _hand: Node3D = null

## How far a held weapon should add its own sprint carry, 0 to 1: set by `sprinting` in [method set_motion], eased
## over [constant SPRINT_SECONDS]. A held weapon ([code]ZeeWorldModel[/code]) reads it to swing to the side. While
## the figure draws the carry itself ([member carry]) the sprint is in the arms and this falls to 0.
var sprint_blend: float:
	get:
		return _sprint * (1.0 - carry.weight)
var _sprint: float = 0.0
## The gun as others see it carried: [method DotHumanoidCarryPose.set_class], [method DotHumanoidCarryPose.fired],
## and its raised / reloading / switching flags. A rifle unless set; drawn only, never the hit zones.
var carry := DotHumanoidCarryPose.new()
## A knife throw's windup and release and a sprint's pumping arms, for a blade or empty hands: [method set_throw_charge],
## [method throw_release]. Drawn only.
var arms := preload("dot_humanoid_arm_pose.gd").new()
var _overlay_weight := 0.0
var _slide_lift := 0.0

## Physics layers the drawn body is stood on (0 = off; the default is the shooter layout's `world`). A body whose origin is drawn under the floor beneath it, as one interpolated between ticks is across a step's riser or a
## slope's crest, is raised onto it by up to [member floor_reach] metres ([method DotHumanoidLegs.floor_lift]). Drawing only: the origin, the hull and the hit zones are not moved.
var floor_mask: int = 1
var floor_reach: float = 0.45
## How far the body is drawn above its origin now to stand on the floor under it, metres.
var floor_lift: float = 0.0
var _lift_at := Vector3.INF
## The camera distance and whether it may be in view at the last clip step, for [member lift_range].
var _step_distance := 0.0
var _step_seen := true
var _lift_allowed := false
var _lift_mask := -1
var _lift_reach := -1.0

## Where the support hand goes, in world space, with a two-handed gun; INF for none ([method set_support_grip]).
var support_point := Vector3.INF
var _support_weight: float = 0.0
var _support_cache: Dictionary = {}
## The bones from the root to the support arm's parent, per upper-arm bone, for [method DotHumanoidIk.chain_pose].
var _support_chains: Dictionary = {}
## Per Animation (a clip can be replaced under its name): the upper-body bones it rotates as [index, track] pairs, flat.
var _overlay_tracks: Dictionary = {}
## Per Animation: [DotHumanoidAim.plan] without and with the arm.
var _aim_plans: Dictionary = {}
var _crown: Node3D = null
var _machine := DotPlayerAnimState.new()
var _motion: Dictionary = {}
var _speed: float = 0.0
var _overlay_time: float = 0.0
var _overlay_rate: float = 1.0
var _overlay_loop: bool = false
var _overlay_stopping: bool = false
var _stop_time: float = 0.0
var _overlay_blend: float = BLEND_IN
var _action_full: StringName = &""
var _owed: float = 0.0
var _crawl := DotHumanoidCrawl.new()
var _frame: int = 0
var _posed_frame: int = -1
var _upper: Dictionary = {}
# Each upper-body bone's rotation-track path from the model, built once per body so the overlay
# lookup in the frame path formats no strings.
var _upper_paths: Dictionary = {}
var _ease := DotHumanoidBlend.new()
var _turn_limit := DotHumanoidTurnLimit.new()
var _swim_pitch: float = 0.0
var _prop_pitch: float = 0.0
var _view_pitch: float = 0.0
var _own_back: float = 0.0
var _own := DotHumanoidOwnView.new()
var legs := DotHumanoidLegs.new()
var _auto_last: Vector3 = Vector3.INF
var _auto_since: float = 0.0
var _auto_seen: Vector3 = Vector3.INF
var _auto_still: float = 0.0
var _auto_pending: float = 0.0
var _auto_velocity: Vector3 = Vector3.ZERO
var _model_basis: Basis = Basis.IDENTITY
var _strides: Dictionary = {}
var _model_origin: Vector3 = Vector3.ZERO
# The skeleton's frame under the model, and each leg's drawn ankle at rest in the figure's frame (the lowest it is drawn).
var _skel_to_model: Transform3D = Transform3D.IDENTITY
## [method _to_figure] held for the rest of one [method animate] (cleared when the model moves).
var _frame_tf := Transform3D.IDENTITY
var _frame_tf_on := false
var _frame_tf_ok := false
var _floor_ankles: PackedFloat32Array = PackedFloat32Array()
