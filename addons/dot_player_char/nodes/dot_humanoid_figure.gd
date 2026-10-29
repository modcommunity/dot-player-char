class_name DotHumanoidFigure
extends Node3D

## One of the family's people, drawn: a skinned body from `people/`, wearing a [DotHumanoidLook]'s
## colours, playing the family clip set ([DotHumanoidClips]) from how it moves, holding a weapon
## in its hand, and handing its skeleton to [DotPlayerRagdoll] when it dies. Client side only.
##
## [b]The game places it and says how it moves; this picks the clip.[/b] [method pose] takes where
## the player is drawn this frame, the yaw and the ground speed; [method set_motion] the rest (on
## the floor, vertical speed, crouched, swimming, downed, alive). A [DotPlayerAnimState] turns that
## into a state with hysteresis, so a player at the run threshold does not flicker.
##
## [b]Legs from the locomotion clip, arms from an overlay.[/b] Holding a gun while crouched or in
## the air, a melee swing while running, a flinch: the upper body ([constant DotHumanoidClips.UPPER_BONES])
## is written over the locomotion pose after the clip is applied, blended in and out, so the legs
## never stop for a swing. The clip is advanced here, manually, for that reason: left to the
## engine, the overlay and the clip run in an order nothing controls.
##
## [b]Cheap enough for a browser crowd:[/b] one surface and one material per look (a palette
## shader shared by everybody dressed alike, no per-instance uniforms), the import's LODs,
## and the clip advanced every frame within [constant ANIM_NEAR] of the camera, every second frame
## to [constant ANIM_FAR] and every fourth beyond (docs/people.md has the numbers).

const CHANNEL := "player.humanoid"

## Within this distance of the camera the clip is advanced every frame; then every second frame
## to [constant ANIM_FAR], and every fourth beyond.
const ANIM_NEAR := 22.0
const ANIM_FAR := 45.0

## Below 1, the mesh switches to its simpler levels sooner. A person is small on screen past a
## few metres; 0.4 is game-zombie-zone's crowd number too.
const LOD_BIAS := 0.4

## Past this distance from the camera a person casts no shadow. The shadow pass drew every person
## at full detail and was more than half of a crowd's triangles (docs/people.md), for shadows too
## far away to read.
const SHADOW_RANGE := 28.0

## Nothing drawn past this.
const DRAW_RANGE := 140.0

## How long an overlay blends in and out, in seconds.
const BLEND_IN := 0.08
const BLEND_OUT := 0.14

## A held pose or an emote eases in slower than a swing.
const ACTION_BLEND_IN := 0.25
const ACTION_BLEND_OUT := 0.3

## How far a swimmer is laid forward about the hips, in radians (about 80 degrees): the swim clip
## is drawn upright, and a front crawl is nearly flat with the head a little up.
const SWIM_LEAN := 1.4

## How far back a propped, downed body leans about the hips, in radians (about 70 degrees from upright).
const PROP_LEAN := 1.2

## The clip a downed pose plays; a game with better clips assigns its own names.
var downed_clips: Dictionary = {&"propped": &"", &"crawl": DotHumanoidClips.CRAWL}

## Whether the person is sprinting (from [method set_motion]; a game that never sends the key gets the run state instead); the carry eases in and out in [member sprint_blend].
var sprinting: bool = false

## What the hand holds, which decides the arms: nothing, a gun (the kit's gun clips and the
## held-gun overlay), or a melee weapon (ordinary arms, a slash to swing).
enum Hold { NONE, GUN, MELEE }

## The body whose file carries the clip set; the others play it through [method DotHumanoidClips.retarget].
const CLIP_BODY := DotHumanoidAssets.CLIP_BODY
## How far past the clip's pose a flinch turns the upper body (1 is the clip as authored).
const FLINCH_GAIN := 1.4
var _overlay_gain := 1.0

## The bone a weapon is held in: the right hand. The kit's people are left-handed (every weapon
## in it hangs off `Middle1.L`), so the clip set is mirrored once when it is loaded
## ([method DotHumanoidClips.mirror]) and a player seen by anybody else holds the gun in the
## hand their own first-person view holds it in.
const HAND_BONE := "Middle1.R"

## Where a hat or a crest sits: on the crown, from the head bone, so it nods and bobs with the
## head. "head_top", "crest" and "hat" are all this mount.
const HEAD_BONE := "Head"
const HEAD_MOUNTS: Array[StringName] = [&"head_top", &"crest", &"hat"]

## How far up and down the upper body follows the view, in radians: past this a person would
## fold in half at the waist.
const AIM_LIMIT := 1.15

## Where a weapon's grip sits from that bone at the held-gun pose, in metres in the figure's frame.
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

## While [member downed]: true lies on the back, propped, weapon out; false crawls on the stomach.
## Set from the `propped` motion key ([DotDownedRules]).
var propped: bool = false

## The overlay playing on the upper body, or empty.
var overlay: StringName = &""

## The avatar action (emote, pose or gesture id) playing, or empty. See [method play_action].
var action: StringName = &""

## Where the player looks, up (+) or down (-), in radians: the upper body, the arms and the gun
## in the hand follow it. See [method aim].
var aim_pitch: float = 0.0

## Sitting ([constant DotHumanoidClips.SIT]): set by `seated` in [method set_motion].
var seated: bool = false

## Seated with the hands on a wheel ([constant DotHumanoidClips.DRIVE]): set by `driving` in [method set_motion]. Needs `seated` too; a figure without the clip just sits.
var driving: bool = false

## Moves itself: every frame the figure measures how far it moved and animates from that, for a
## body something else carries (an NPC on a physics body, a prop with a person on it) where no
## code knows its speed. Off for a player, whose game says how it moves ([method pose]).
var auto_animate: bool = false:
	set(value):
		auto_animate = value
		set_process(value)
		_auto_last = Vector3.INF

## Seconds over which [member auto_animate]'s measured speed is averaged. A body carried in physics ticks or on network snapshots moves in steps, so its per-frame speed alternates between zero and double and the clip flips between idle, walk and run. 0 keeps the raw measure.
var auto_smooth_time: float = 0.0

## The clips whose rate follows the planted foot ([method _matched_rate]), and the fastest they play.
const STRIDE_CLIPS: Array[StringName] = [DotHumanoidClips.WALK, DotHumanoidClips.WALK_GUN, DotHumanoidClips.RUN,
	DotHumanoidClips.RUN_GUN, DotHumanoidClips.CROUCH_WALK, DotHumanoidClips.SPRINT]
const STRIDE_SAMPLES := 48
const STRIDE_MAX_RATE := 4.0
## How far above the clip's lowest foot the lower foot is in flight (a run's both-feet-up stretch).
const STRIDE_AIRBORNE_M := 0.06

## Ground speed from which a runner plays the sprint clip when the game sends no `sprinting` key (0 picks 1.6 times the run speed), and how far below it the run clip returns.
var sprint_speed: float = 0.0
const SPRINT_EXIT := 0.8
var _sprint_clip: bool = false

## Ground speed above which the figure runs, and below which a runner walks again ([member DotPlayerAnimState.run_speed], [member DotPlayerAnimState.run_exit_speed]). A game whose walking pace is near the default 4.0 raises them so a walk does not play the hunched run clip.
func set_run_speeds(run_speed: float, run_exit_speed: float) -> void:
	_machine.run_speed = run_speed
	_machine.run_exit_speed = run_exit_speed


## Frames per advance of the clip: 1, 2 or 4, by distance from the camera.
var anim_step: int = 1

## The head (and the neck under it) shrunk to nothing after the clip: your own body seen in first
## person, where the camera is inside the head. The rest still draws and casts its shadow.
var hide_head: bool = false:
	set(value):
		hide_head = value
		_apply_head()

var _model: Node3D = null
var _skeleton: Skeleton3D = null
var _mesh: MeshInstance3D = null
var _anim: AnimationPlayer = null
var _hand: Node3D = null

## How far the sprint carry is blended in, 0 to 1: set by `sprinting` in [method set_motion], eased over
## [constant SPRINT_SECONDS]. A held weapon ([code]ZeeWorldModel[/code]) reads it to swing to the side.
var sprint_blend: float = 0.0

## Where the support hand goes, in world space, while a long gun is held with two hands; INF for none.
## Set every frame by the weapon (see [method set_support_grip]).
var support_point := Vector3.INF
var _support_weight: float = 0.0
var _support_cache: Dictionary = {}
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
var _frame: int = 0
var _posed_usec: int = -1
var _upper: Dictionary = {}
var _swim_pitch: float = 0.0
var _prop_pitch: float = 0.0
var _head_hidden: bool = false
var _auto_last: Vector3 = Vector3.INF
var _model_basis: Basis = Basis.IDENTITY
var _strides: Dictionary = {}
var _model_origin: Vector3 = Vector3.ZERO

## Builds the figure for [param p_look], [param p_height] metres tall, feet at this node's origin,
## facing -Z.
func build(p_look: DotHumanoidLook, p_height: float = 1.8) -> void:
	look = p_look if p_look != null else DotHumanoidLook.stock(0)
	height = p_height
	clip = &""
	overlay = &""
	_hand = null
	_crown = null
	_upper.clear()
	_support_cache.clear()
	_strides.clear()
	_machine.forget_state()

	if _model != null:
		remove_child(_model)
		_model.queue_free()
		_model = null
		_skeleton = null
		_mesh = null
		_anim = null

	var scene := DotHumanoidAssets.scene(body_path(look.body))
	if scene != null:
		_model = scene.instantiate() as Node3D

	if _model == null:
		# A capsule rather than nothing: an invisible player is worse than a grey one.
		DotLog.warn(CHANNEL, "no body model; drawing a capsule", {"body": String(look.body)})
		_model = _capsule(height, look.top)
		add_child(_model)
		from_art = false
		return

	_model.name = "Body"
	add_child(_model)
	from_art = true
	_skeleton = _model.find_children("*", "Skeleton3D", true, false).front() as Skeleton3D
	var meshes := _model.find_children("*", "MeshInstance3D", true, false)
	_mesh = meshes.front() as MeshInstance3D if not meshes.is_empty() else null
	_anim = _model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim == null:
		_anim = AnimationPlayer.new()
		_anim.name = "AnimationPlayer"
		_model.add_child(_anim)
	# Advanced here, not by the engine: see the class note.
	_anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL

	var library := DotHumanoidAssets.library_for(look.body, _skeleton)
	if library != null:
		for name in _anim.get_animation_library_list():
			_anim.remove_animation_library(name)
		var _err := _anim.add_animation_library(&"", library)

	if _mesh != null:
		_mesh.material_override = material_for(look)
		_mesh.lod_bias = LOD_BIAS
		_mesh.visibility_range_end = DRAW_RANGE

	# The kit faces +Z and this family's forward is -Z; scaled to the height asked for, measured
	# from the mesh rather than assumed.
	var tall := _measure()
	var s := height / maxf(tall, 0.01)
	_model_basis = Basis(Vector3.UP, PI).scaled(Vector3.ONE * s)
	_model_origin = Vector3.ZERO
	_model.transform = Transform3D(_model_basis, _model_origin)

	for bone in DotHumanoidClips.UPPER_BONES:
		var i := _skeleton.find_bone(bone) if _skeleton != null else -1
		if i >= 0:
			_upper[bone] = i

	_play(DotHumanoidClips.IDLE, 1.0)
	_anim.advance(0.0)


func _ready() -> void:
	set_process(auto_animate)


func _process(delta: float) -> void:
	if not auto_animate or delta <= 0.0:
		return
	var at := global_position
	var moved := Vector3.ZERO if _auto_last == Vector3.INF else (at - _auto_last) / delta
	_auto_last = at
	var motion := _motion.duplicate()
	motion["vertical"] = moved.y
	motion["on_floor"] = absf(moved.y) < 1.5
	_motion = motion
	var ground := Vector2(moved.x, moved.z).length()
	if auto_smooth_time > 0.0:
		ground = lerpf(_speed, ground, 1.0 - exp(-delta / auto_smooth_time))
	animate(ground, delta)


## The look changed colours only: a new material, no rebuild.
func recolour(p_look: DotHumanoidLook) -> void:
	if p_look == null:
		return
	if look == null or p_look.body != look.body or _mesh == null:
		build(p_look, height)
		return
	look = p_look
	_mesh.material_override = material_for(look)


## Puts the figure where this frame draws its player, facing [param yaw_radians], moving at
## [param speed] metres a second over the ground, and advances its animation by the time since
## the last call (clamped, so a figure hidden for a minute picks up where it was).
func pose(at: Vector3, yaw_radians: float, speed: float) -> void:
	global_position = at
	rotation = Vector3(0.0, yaw_radians, 0.0)
	var now := Time.get_ticks_usec()
	var delta := 0.0 if _posed_usec < 0 else clampf((now - _posed_usec) / 1e6, 0.0, 0.1)
	_posed_usec = now
	animate(speed, delta)


## Advances the animation by [param delta] at ground [param speed]. [method pose] calls it; a suite
## or a contact sheet calls it directly to step time exactly.
func animate(speed: float, delta: float) -> void:
	_speed = speed
	var motion := _motion.duplicate()
	motion["speed"] = speed
	state = _machine.advance(motion, delta)
	_end_action_if_moved()
	var carry_sprint := sprinting if _motion.has("sprinting") else state == DotPlayerAnimState.RUN
	sprint_blend = move_toward(sprint_blend, 1.0 if carry_sprint and hold == Hold.GUN and not downed else 0.0, delta / SPRINT_SECONDS)
	_support_weight = move_toward(_support_weight, 1.0 if support_point.is_finite() and hold == Hold.GUN and not downed else 0.0, delta / 0.15)

	if _anim == null:
		return

	var wanted := _clip_for(state, speed)
	_play(wanted[0], wanted[1])

	if overlay != &"":
		_overlay_time += delta * _overlay_rate
		if _overlay_stopping:
			_stop_time += delta

	# The clip is advanced less often far from the camera, with the skipped time carried.
	_owed += delta
	_frame += 1
	anim_step = _step_for_distance()
	if _frame % anim_step != 0:
		return
	var matched := _matched_rate(speed, _owed)
	if matched >= 0.0:
		_anim.speed_scale = matched
	_anim.advance(_owed)
	_owed = 0.0
	_apply_overlays()
	_apply_aim()
	_apply_support()
	_apply_head()
	_apply_swim(delta * anim_step)


func _apply_head() -> void:
	if _skeleton == null:
		return
	var head := _skeleton.find_bone("Head")
	if head < 0:
		return
	# A pose scale carries to every child (the eyes, the hair), so the one bone is enough. Written
	# while hidden (a clip may key the scale) and once when shown again, not every frame: a head
	# a critical took off (DotPlayerBodyBreak) stays off until [method mend].
	if hide_head:
		_skeleton.set_bone_pose_scale(head, Vector3.ONE * 0.001)
		_head_hidden = true
	elif _head_hidden:
		_skeleton.set_bone_pose_scale(head, Vector3.ONE)
		_head_hidden = false


## Puts back whatever a death took off: every bone at its own size again. For a respawn.
func mend() -> void:
	if _skeleton == null:
		return
	for i in _skeleton.get_bone_count():
		_skeleton.set_bone_pose_scale(i, Vector3.ONE)
	_head_hidden = false
	if hide_head:
		_apply_head()


## Everything else about how the player moves, as [method DotPlayerAnimState.advance] reads it:
## `on_floor`, `vertical`, `crouched`, `swimming`, `climbing`, `alive`; plus `downed` here, and
## `wall_running` (the run clip plays in the air).
## `seated` draws the person sitting ([method seat_height] says where their hips are), `driving`
## (with `seated`) puts the hands on a wheel, and `aim`
## (radians, up positive) is [method aim]; left out, the aim stays where it was.
func set_motion(motion: Dictionary) -> void:
	_motion = motion
	sprinting = bool(motion.get("sprinting", false))
	downed = bool(motion.get("downed", false))
	propped = downed and bool(motion.get("propped", false))
	seated = bool(motion.get("seated", false))
	driving = bool(motion.get("driving", false))
	if motion.has("aim"):
		aim(float(motion["aim"]))


## Where the player looks, up or down, in radians (up is positive; a first-person controller's
## `state.pitch` is in degrees, so `deg_to_rad` it). Drawn on the next [method animate]: the waist
## and chest bend by it, so the arms, the gun and the head point where the player aims, which is
## how anybody else reads where somebody is looking. Held to [constant AIM_LIMIT].
func aim(pitch_radians: float) -> void:
	aim_pitch = clampf(pitch_radians, -AIM_LIMIT, AIM_LIMIT) if is_finite(pitch_radians) else 0.0


## How high above the feet the hips are when sitting, in metres at this figure's height: a game
## puts the figure's origin this far under the seat.
func seat_height() -> float:
	var base: float = DotHumanoidAssets.sit_height()
	if _skeleton == null or base <= 0.0:
		return height * 0.25
	return base * height / maxf(_measure(), 0.01)


## What the hand holds: [enum Hold].
func set_hold(kind: int) -> void:
	hold = kind


## A melee swing over whatever the legs are doing: [constant DotHumanoidClips.SLASH] by default,
## [constant DotHumanoidClips.STAB] or [constant DotHumanoidClips.PUNCH] for empty hands.
func swing(which: StringName = &"") -> void:
	if which == &"":
		which = DotHumanoidClips.PUNCH if hold == Hold.NONE else DotHumanoidClips.SLASH
	_start_overlay(which, 1.4)


## A hit: the kit's flinch on the upper body, pushed past its authored pose so a third-person view reads it.
func flinch() -> void:
	_start_overlay(DotHumanoidClips.HIT, 1.0)
	_overlay_gain = FLINCH_GAIN


## A gesture over the upper body: wave, yes, no.
func emote(which: StringName) -> void:
	_start_overlay(which, 1.0)


## Plays the avatar action [param id] (a [DotHumanoidActions] id) that began [param elapsed]
## seconds ago, so a late joiner or a replicated start lands in step. Upper body over the legs,
## except [constant DotHumanoidActions.FULL_BODY] ids, which take the legs while standing still.
## A looping action holds until [method stop_action] or the player moves off. False when this
## body has no clip for it.
func play_action(id: StringName, loop: bool = false, elapsed: float = 0.0) -> bool:
	var wanted := DotHumanoidActions.clip_name(id)
	if _anim == null or not _anim.has_animation(wanted):
		return false
	stop_action()
	if DotHumanoidActions.is_full_body(id):
		action = id
		_action_full = wanted
		return true
	var length := _anim.get_animation(wanted).length
	if not loop and elapsed >= length:
		return true
	_start_overlay(wanted, 1.0)
	action = id
	_overlay_loop = loop
	_overlay_blend = ACTION_BLEND_IN
	_overlay_time = maxf(elapsed, 0.0)
	return true


## Adds the uploaded action [param id] (a content id) from [param scene], an uploaded clip's
## built GLB, so [method play_action] can play it. Its clip [param clip] is moved onto this body
## ([method DotHumanoidActions.from_upload]); the body's library is shared, so every figure of the
## same body gets it. Success is false when it was already there.
func add_action_scene(id: StringName, scene: Node, clip: String, loop: bool = false) -> DotResult:
	if _anim == null or _skeleton == null or not _anim.has_animation(DotHumanoidClips.IDLE):
		return DotResult.fail(DotError.CODE_STATE, "this figure has no skinned body to play a clip on")
	var wanted := DotHumanoidActions.clip_name(id)
	if _anim.has_animation(wanted):
		return DotResult.success(false)
	var prefix := DotHumanoidClips._skeleton_prefix(_anim.get_animation(DotHumanoidClips.IDLE))
	var made := DotHumanoidActions.from_upload(scene, clip, _skeleton, prefix, loop)
	if not made.ok:
		return made
	var err := _anim.get_animation_library(&"").add_animation(wanted, made.value)
	if err != OK:
		return DotResult.failure(DotError.from_engine(err, "adding an uploaded action"))
	return DotResult.success(true)


## Ends the playing action, easing out.
func stop_action() -> void:
	_action_full = &""
	if overlay != &"" and _overlay_loop and not _overlay_stopping:
		_overlay_stopping = true
		_stop_time = 0.0
	action = &""


## The node a held weapon hangs from, by the name [code]ZeeWorldModel[/code] asks for:
## "right_hand" or "hand" (see [constant HAND_BONE] for which hand that is). Turned so its -Z is
## the way the figure faces when holding a gun, its +Y up, and at metre scale whatever the body's.
##
## "head_top" (or "crest", "hat") is the crown of the head, upright, at metre scale, and it
## follows the head bone, so a hat nods with the head and goes with it in first person
## ([member hide_head]).
func attachment(point: StringName) -> Node3D:
	if HEAD_MOUNTS.has(point):
		return _crown_mount()
	if point != &"right_hand" and point != &"hand":
		return null
	if _hand != null and is_instance_valid(_hand):
		return _hand
	_hand = Node3D.new()
	_hand.name = "Hand"
	if _skeleton == null or _skeleton.find_bone(HAND_BONE) < 0:
		_hand.position = Vector3(0.26, height * 0.62, -0.34)
		add_child(_hand)
		return _hand

	var bone := BoneAttachment3D.new()
	bone.name = "HandBone"
	bone.bone_name = HAND_BONE
	_skeleton.add_child(bone)
	bone.add_child(_hand)
	_hand.transform = _hand_frame() * Transform3D(Basis.from_scale(Vector3.ONE * held_scale), Vector3.ZERO)
	return _hand


func _crown_mount() -> Node3D:
	if _crown != null and is_instance_valid(_crown):
		return _crown
	_crown = Node3D.new()
	_crown.name = "Crown"
	if _skeleton == null or _skeleton.find_bone(HEAD_BONE) < 0:
		_crown.position = Vector3(0.0, height, 0.0)
		add_child(_crown)
		return _crown
	var bone := BoneAttachment3D.new()
	bone.name = "HeadBone"
	bone.bone_name = HEAD_BONE
	_skeleton.add_child(bone)
	bone.add_child(_crown)
	# The crown is the mesh's top, straight over the head bone at rest; upright and metre scale
	# in the figure's frame, as the hand is.
	var head := _skeleton.find_bone(HEAD_BONE)
	var head_in_figure := _to_figure() * _skeleton.get_bone_global_rest(head)
	var top := Vector3(head_in_figure.origin.x, height, head_in_figure.origin.z)
	_crown.transform = head_in_figure.affine_inverse() * Transform3D(Basis.IDENTITY, top)
	return _crown


## Skeleton space to the figure's frame: the skeleton's own transform under the model, then the
## model's turn and scale.
func _to_figure() -> Transform3D:
	var skel_to_model := _model.global_transform.affine_inverse() * _skeleton.global_transform if _model.is_inside_tree() else Transform3D.IDENTITY
	return Transform3D(_model_basis, _model_origin) * skel_to_model


## The hand's frame in its bone's, from the held-gun pose: forward is the figure's forward and up
## is up there, so a weapon model made pointing down -Z points where the gun clips aim.
func _hand_frame() -> Transform3D:
	var bone := _skeleton.find_bone(HAND_BONE)
	var library := _anim.get_animation_library(&"")
	var gun := library.get_animation(DotHumanoidClips.IDLE_GUN) if library != null and library.has_animation(DotHumanoidClips.IDLE_GUN) else null
	# The bone's pose in skeleton space at the held-gun pose, computed from the clip's keys.
	var poses: Dictionary = {}
	var chain: Array[int] = []
	var i := bone
	while i >= 0:
		chain.push_front(i)
		i = _skeleton.get_bone_parent(i)
	var global := Transform3D.IDENTITY
	for b in chain:
		var local := _skeleton.get_bone_rest(b)
		if gun != null:
			var path := NodePath("%s:%s" % [_model.get_path_to(_skeleton), _skeleton.get_bone_name(b)])
			var rt := gun.find_track(path, Animation.TYPE_ROTATION_3D)
			var pt := gun.find_track(path, Animation.TYPE_POSITION_3D)
			var q := local.basis.get_rotation_quaternion() if rt < 0 else gun.rotation_track_interpolate(rt, 0.0)
			var p := local.origin if pt < 0 else gun.position_track_interpolate(pt, 0.0)
			local = Transform3D(Basis(q).scaled(local.basis.get_scale()), p)
		global = global * local
		poses[b] = global
	var bone_global: Transform3D = poses[bone]
	var bone_in_figure := _to_figure() * bone_global
	# Wanted: in the figure's frame, -Z forward, +Y up, metres; at the bone plus the grip offset.
	var wanted := Transform3D(Basis.IDENTITY, bone_in_figure.origin + HAND_OFFSET)
	return bone_in_figure.affine_inverse() * wanted


## The drawn model, for [DotPlayerRagdoll] (it finds the skeleton and the skinned mesh under it).
func body_node() -> Node3D:
	return _model


func skeleton() -> Skeleton3D:
	return _skeleton


func mesh() -> MeshInstance3D:
	return _mesh


## Shows or hides the body (the local player's own, in first person). The hand stays where it
## is: a weapon model hung there hides with it.
func set_drawn(on: bool) -> void:
	if _model != null:
		_model.visible = on


func _clip_for(p_state: StringName, speed: float) -> Array:
	var gun := hold == Hold.GUN
	if downed and propped:
		var named := StringName(downed_clips.get(&"propped", &""))
		if named == &"":
			named = DotHumanoidClips.IDLE_GUN if gun else DotHumanoidClips.IDLE
		return [named, 1.0]
	if downed:
		return [StringName(downed_clips.get(&"crawl", DotHumanoidClips.CRAWL)), clampf(speed / 1.2, 0.0, 1.6)]
	if _action_full != &"":
		return [_action_full, 1.0]
	# A rider is carried: whatever speed the seat moves at, the legs stay sat.
	if seated and p_state != DotPlayerAnimState.DEAD:
		if driving and _anim != null and _anim.has_animation(DotHumanoidClips.DRIVE):
			return [DotHumanoidClips.DRIVE, 1.0]
		return [DotHumanoidClips.SIT, 1.0]
	# Running along a wall: the legs run in the air (the body is rolled onto the wall by the game).
	if bool(_motion.get("wall_running", false)) and p_state in [
			DotPlayerAnimState.JUMP, DotPlayerAnimState.FALL, DotPlayerAnimState.LAND]:
		return [DotHumanoidClips.RUN_GUN if gun else DotHumanoidClips.RUN, clampf(speed / 5.0, 0.7, 1.5)]
	match p_state:
		DotPlayerAnimState.DEAD:
			return [DotHumanoidClips.DEATH, 1.0]
		DotPlayerAnimState.SWIM:
			return [DotHumanoidClips.SWIM, clampf(speed / 2.5, 0.45, 1.3)]
		DotPlayerAnimState.JUMP:
			return [DotHumanoidClips.JUMP, 1.0]
		DotPlayerAnimState.FALL:
			return [DotHumanoidClips.FALL, 1.0]
		DotPlayerAnimState.LAND:
			return [DotHumanoidClips.LAND, 1.4]
		DotPlayerAnimState.CROUCH_IDLE:
			return [DotHumanoidClips.CROUCH, 1.0]
		DotPlayerAnimState.CROUCH_WALK:
			return [DotHumanoidClips.CROUCH_WALK, clampf(speed / 1.6, 0.5, 1.6)]
		DotPlayerAnimState.WALK:
			# A game whose run threshold sits above its sprint speed would walk at a sprinter's pace.
			if sprint_speed > 0.0 and speed >= sprint_speed and _sprint_clip_for(speed):
				return [DotHumanoidClips.SPRINT, 1.0]
			return [DotHumanoidClips.WALK_GUN if gun else DotHumanoidClips.WALK, clampf(speed / 1.9, 0.6, 1.6)]
		DotPlayerAnimState.RUN:
			if _sprint_clip_for(speed):
				return [DotHumanoidClips.SPRINT, 1.0]
			return [DotHumanoidClips.RUN_GUN if gun else DotHumanoidClips.RUN, clampf(speed / 5.0, 0.7, 1.5)]
		DotPlayerAnimState.CLIMB:
			return [DotHumanoidClips.CLIMB, clampf(absf(float(_motion.get("vertical", 0.0))) / 2.5, 0.0, 1.2)]
	return [DotHumanoidClips.IDLE_GUN if gun else DotHumanoidClips.IDLE, 1.0]


## Whether a runner at [param speed] plays the sprint clip: the game's `sprinting` key when it sends one, else the speed, with a gap so it does not flicker.
func _sprint_clip_for(speed: float) -> bool:
	if _anim == null or not _anim.has_animation(DotHumanoidClips.SPRINT):
		return false
	if _motion.has("sprinting"):
		_sprint_clip = sprinting
	else:
		var from := sprint_speed if sprint_speed > 0.0 else _machine.run_speed * 1.6
		_sprint_clip = speed >= from - (SPRINT_EXIT if _sprint_clip else 0.0)
	return _sprint_clip


## The rate that moves the lower foot back exactly as far as the body goes this step, or -1 when the
## clip is not a stride. The clips have no root motion and sweep the planted foot back unevenly, so
## any constant rate skates it; the rate is read off the clip's distance table instead.
func _matched_rate(speed: float, dt: float) -> float:
	if dt <= 0.0 or not state in [DotPlayerAnimState.WALK, DotPlayerAnimState.RUN, DotPlayerAnimState.CROUCH_WALK]:
		return -1.0
	if not clip in STRIDE_CLIPS or _anim.current_animation != String(clip):
		return -1.0
	var table := _stride_for(clip)
	if table.size() < 2 or table[-1] <= 0.0:
		return -1.0
	var length := _anim.current_animation_length
	var phase := fposmod(_anim.current_animation_position, length) / length
	var want := _distance_at(table, phase) + speed * dt
	var laps := floorf(want / table[-1])
	var to := _phase_at(table, want - laps * table[-1]) + laps
	return clampf((to - phase) * length / dt, 0.0, STRIDE_MAX_RATE)


## Metres over the ground at each of [constant STRIDE_SAMPLES] steps through [param clip_id]: the
## lower foot's backward travel in the figure's frame, never under a third of the mean so the
## clip does not race through a moment the foot stands still in it, and in flight no less than
## a stance step, so a run's swing plays at the clip's own pace. Cached per clip.
func _stride_for(clip_id: StringName) -> PackedFloat32Array:
	if _strides.has(clip_id):
		return _strides[clip_id]
	var table := PackedFloat32Array()
	_strides[clip_id] = table
	var animation := _anim.get_animation(clip_id)
	var feet := [_skeleton.find_bone("Foot.L"), _skeleton.find_bone("Foot.R")]
	if animation == null or feet.has(-1) or animation.length <= 0.0:
		return table
	var prefix := String(_model.get_path_to(_skeleton))
	var to_figure := _to_figure()
	var points: Array = []
	for i in STRIDE_SAMPLES + 1:
		var t := animation.length * i / STRIDE_SAMPLES
		points.append(feet.map(func(b: int) -> Vector3: return to_figure * _bone_at(animation, prefix, b, t).origin))
	var steps := PackedFloat32Array()
	var airborne: Array[bool] = []
	var total := 0.0
	var floor_y := INF
	for p: Array in points:
		floor_y = minf(floor_y, minf(p[0].y, p[1].y))
	var stance := 0.0
	var stance_steps := 0
	for i in range(1, points.size()):
		var k := 0 if points[i][0].y + points[i - 1][0].y < points[i][1].y + points[i - 1][1].y else 1
		var back: float = maxf(0.0, points[i][k].z - points[i - 1][k].z)
		steps.append(back)
		total += back
		airborne.append(minf(points[i][k].y, points[i - 1][k].y) > floor_y + STRIDE_AIRBORNE_M)
		if not airborne[-1] and back > 0.0:
			stance += back
			stance_steps += 1
	var least := total / STRIDE_SAMPLES / 3.0
	# Both feet up: the body flies on at the pace the clip's stance sets, so a run's flight is not raced through.
	var flight := stance / stance_steps if stance_steps > 0 else least
	table.append(0.0)
	for i in steps.size():
		table.append(table[-1] + (maxf(steps[i], flight) if airborne[i] else maxf(steps[i], least)))
	_strides[clip_id] = table
	return table


## [param bone]'s skeleton-space transform in [param animation] at [param t], from its tracks or its rest.
func _bone_at(animation: Animation, prefix: String, bone: int, t: float) -> Transform3D:
	var path := NodePath("%s:%s" % [prefix, _skeleton.get_bone_name(bone)])
	var rest := _skeleton.get_bone_rest(bone)
	var at := rest.origin
	var turn := rest.basis.get_rotation_quaternion()
	var track := animation.find_track(path, Animation.TYPE_POSITION_3D)
	if track >= 0:
		at = animation.position_track_interpolate(track, t)
	track = animation.find_track(path, Animation.TYPE_ROTATION_3D)
	if track >= 0:
		turn = animation.rotation_track_interpolate(track, t)
	var local := Transform3D(Basis(turn).scaled(rest.basis.get_scale()), at)
	var parent := _skeleton.get_bone_parent(bone)
	return local if parent < 0 else _bone_at(animation, prefix, parent, t) * local


static func _distance_at(table: PackedFloat32Array, phase: float) -> float:
	var x := clampf(phase, 0.0, 1.0) * (table.size() - 1)
	var i := mini(int(x), table.size() - 2)
	return lerpf(table[i], table[i + 1], x - i)


static func _phase_at(table: PackedFloat32Array, distance: float) -> float:
	var hi := table.bsearch(distance)
	hi = clampi(hi, 1, table.size() - 1)
	var span := table[hi] - table[hi - 1]
	var x := float(hi - 1) + (clampf((distance - table[hi - 1]) / span, 0.0, 1.0) if span > 0.0 else 0.0)
	return x / (table.size() - 1)


func _play(wanted: StringName, rate: float) -> void:
	if _anim == null:
		return
	if not _anim.has_animation(wanted):
		wanted = DotHumanoidClips.IDLE
		if not _anim.has_animation(wanted):
			return
	_anim.speed_scale = rate
	if clip == wanted:
		return
	var from := _stride_fraction()
	clip = wanted
	var cross := from >= 0.0 and wanted in STRIDE_CLIPS
	var feet := _feet_now() if cross else PackedVector3Array()
	_anim.play(wanted, 0.0 if cross else 0.15)
	if cross and not feet.is_empty():
		_anim.seek(_matching_time(wanted, feet), true)


## The feet's figure-frame positions in the pose on screen now.
func _feet_now() -> PackedVector3Array:
	var out := PackedVector3Array()
	var to_figure := _to_figure()
	for foot in [&"Foot.L", &"Foot.R"]:
		var b := _skeleton.find_bone(foot)
		if b < 0:
			return PackedVector3Array()
		out.append(to_figure * (_skeleton.get_bone_global_pose(b).origin))
	return out


## The time in [param clip_id] whose feet sit closest to [param feet], so a clip entered there carries the planted (lower) foot on as it was.
func _matching_time(clip_id: StringName, feet: PackedVector3Array) -> float:
	var animation := _anim.get_animation(clip_id)
	var prefix := String(_model.get_path_to(_skeleton))
	var ids := [_skeleton.find_bone("Foot.L"), _skeleton.find_bone("Foot.R")]
	var to_figure := _to_figure()
	var low := 0 if feet[0].y <= feet[1].y else 1
	var best := 0.0
	var least := INF
	for i in STRIDE_SAMPLES * 2:
		var t := animation.length * i / (STRIDE_SAMPLES * 2)
		var cost := 0.0
		for k in 2:
			cost += (to_figure * _bone_at(animation, prefix, ids[k], t).origin).distance_squared_to(feet[k]) * (6.0 if k == low else 1.0)
		if cost < least:
			least = cost
			best = t
	return best


## How far through its stride the playing clip's planted foot is, 0 to 1, or -1 when it is not a stride clip. A clip entered at this fraction keeps the foot it stands on travelling with the ground.
func _stride_fraction() -> float:
	if not clip in STRIDE_CLIPS or _anim.current_animation != String(clip):
		return -1.0
	var table := _stride_for(clip)
	if table.size() < 2 or table[-1] <= 0.0:
		return -1.0
	var length := _anim.current_animation_length
	return _distance_at(table, fposmod(_anim.current_animation_position, length) / length) / table[-1]


## Ends a looping or full-body action when the player leaves the spot: a pose is for standing.
func _end_action_if_moved() -> void:
	if action == &"" and not _overlay_loop:
		return
	var still := state == DotPlayerAnimState.IDLE or state == DotPlayerAnimState.CROUCH_IDLE
	if _action_full != &"" and not still:
		stop_action()
	elif _overlay_loop and (downed or state in [DotPlayerAnimState.DEAD, DotPlayerAnimState.SWIM,
			DotPlayerAnimState.CLIMB, DotPlayerAnimState.JUMP, DotPlayerAnimState.FALL, DotPlayerAnimState.RUN]):
		stop_action()


func _start_overlay(which: StringName, rate: float) -> void:
	if _anim == null or not _anim.has_animation(which):
		return
	_overlay_loop = false
	_overlay_stopping = false
	_stop_time = 0.0
	_overlay_blend = BLEND_IN
	action = &""
	overlay = which
	_overlay_time = 0.0
	_overlay_rate = rate
	_overlay_gain = 1.0


## Writes the upper body over the locomotion pose: a playing overlay (swing, flinch, gesture),
## else, holding a gun in a clip that is not a gun clip (crouch, air), the held-gun arms. Not while
## swimming: the stroke is the arms, and a swimmer drawn holding the gun level was the leaned run
## again from the waist up.
func _apply_overlays() -> void:
	if _skeleton == null:
		return
	var source: Animation = null
	var t := 0.0
	var weight := 0.0
	if overlay != &"":
		source = _anim.get_animation(overlay)
		if source == null or (not _overlay_loop and _overlay_time >= source.length):
			overlay = &""
			action = &""
			_overlay_loop = false
			source = null
		elif _overlay_loop:
			t = fposmod(_overlay_time, source.length)
			weight = minf(1.0, _overlay_time / _overlay_blend)
			if _overlay_stopping:
				weight *= 1.0 - minf(1.0, _stop_time / ACTION_BLEND_OUT)
				if _stop_time >= ACTION_BLEND_OUT:
					overlay = &""
					_overlay_loop = false
					_overlay_stopping = false
					_stop_time = 0.0
					source = null
		else:
			t = _overlay_time
			weight = minf(1.0, _overlay_time / _overlay_blend) * minf(1.0, (source.length - _overlay_time) / BLEND_OUT)
	if source == null and hold == Hold.GUN and not downed and not String(clip).ends_with("_gun") and clip != DotHumanoidClips.DEATH and clip != DotHumanoidClips.SWIM:
		source = _anim.get_animation(DotHumanoidClips.IDLE_GUN)
		t = 0.0
		weight = 1.0
	if source == null or weight <= 0.0:
		return
	var prefix := String(_model.get_path_to(_skeleton))
	for bone: String in _upper:
		var index: int = _upper[bone]
		var track := source.find_track(NodePath("%s:%s" % [prefix, bone]), Animation.TYPE_ROTATION_3D)
		if track < 0:
			continue
		var q := source.rotation_track_interpolate(track, t)
		var now := _skeleton.get_bone_pose_rotation(index)
		_skeleton.set_bone_pose_rotation(index, _toward(now, q, clampf(weight, 0.0, 1.0), _overlay_gain))


## [param from] turned [param weight] of the way to [param to], the angle then multiplied by [param gain]; a slerp past 1 flips the long way round and pops.
static func _toward(from: Quaternion, to: Quaternion, weight: float, gain: float) -> Quaternion:
	if gain == 1.0:
		return from.slerp(to, weight)
	var d := from.inverse() * to
	if d.w < 0.0:
		d = -d
	var angle := d.get_angle()
	if angle < 0.0001:
		return from
	return from * Quaternion(d.get_axis(), angle * weight * gain)


## Bends the waist and chest by [member aim_pitch] about the figure's own left-to-right axis,
## after the clip and the overlays, so whatever the arms are doing points up or down with the
## view. Not while down, dead, swimming or climbing (the body is not upright to bend), and only
## on a bone the playing clip keys: a bone no track writes keeps last frame's pose, and the bend
## would add up frame after frame.
func _apply_aim() -> void:
	if _skeleton == null or (is_zero_approx(aim_pitch) and sprint_blend <= 0.0) or downed:
		return
	if state == DotPlayerAnimState.DEAD or state == DotPlayerAnimState.SWIM or state == DotPlayerAnimState.CLIMB:
		return
	var animation := _anim.get_animation(clip)
	if animation == null:
		return
	# Figure right, in skeleton space: the axis a nod turns about.
	var axis := (_to_figure().basis.inverse() * Vector3.RIGHT).normalized()
	var prefix := String(_model.get_path_to(_skeleton))
	# Every parent's pose is read before any bone is turned. Turns about one axis commute, so each
	# bone's share goes on through its parent's unturned frame: local' = P^-1 * turn * P * local.
	# Read from the local poses up the chain, not get_bone_global_pose: the skeleton updates its
	# global poses later in the frame, so that is last frame's (with last frame's bend in it).
	var shares: Dictionary = DotHumanoidClips.AIM_BONES
	if hold != Hold.NONE:
		shares = shares.merged(DotHumanoidClips.AIM_ARM)
	var parents := {}
	for bone: String in shares:
		var i := _skeleton.find_bone(bone)
		if i >= 0:
			parents[i] = DotHumanoidIk.chain_rotation(_skeleton, _skeleton.get_bone_parent(i))
	for bone: String in shares:
		var i := _skeleton.find_bone(bone)
		if i < 0 or animation.find_track(NodePath("%s:%s" % [prefix, bone]), Animation.TYPE_ROTATION_3D) < 0:
			continue
		var share: float = shares[bone]
		var p: Quaternion = parents[i]
		var drop := -SPRINT_DROP * sprint_blend if DotHumanoidClips.AIM_ARM.has(bone) else 0.0
		var turn := Quaternion(axis, aim_pitch * share + drop)
		_skeleton.set_bone_pose_rotation(i, (p.inverse() * turn * p * _skeleton.get_bone_pose_rotation(i)).normalized())


## Where the support hand goes: the weapon's foregrip, [constant Vector3.INF] when the gun is held with one
## hand or none. In world space; called every frame by the held weapon, since it moves with the gun.
func set_support_grip(point: Vector3) -> void:
	support_point = point


## Two-bone IK on the left arm toward [member support_point], blended by the support weight, after the clip,
## the overlays and the aim so it lands on the gun wherever they put it. Only on bones the clip keys (a bone no
## track writes keeps last frame's pose, and the turn would add up).
func _apply_support() -> void:
	if _skeleton == null or _support_weight <= 0.0 or not support_point.is_finite() or downed:
		return
	var bones := _support_bones_for(clip)
	if bones.is_empty():
		return
	DotHumanoidIk.two_bone(_skeleton, bones, _skeleton.global_transform.affine_inverse() * support_point, _to_figure().basis.inverse() * SUPPORT_POLE, _support_weight)


## The support arm's bone indices if [param clip_id] keys them (a bone no track writes keeps last frame's pose), else empty; cached per clip.
func _support_bones_for(clip_id: StringName) -> Array[int]:
	if _support_cache.has(clip_id):
		return _support_cache[clip_id]
	var bones := DotHumanoidIk.keyed_bones(_skeleton, _model, _anim.get_animation(clip_id), SUPPORT_BONES)
	_support_cache[clip_id] = bones
	return bones


## Swimming lays the whole body forward, about the hips, and eases back out of it. The swim clip
## is drawn upright ([method DotHumanoidClips._swimming]); this is what makes it horizontal.
func _apply_swim(delta: float) -> void:
	if _model == null:
		return
	var wanted := SWIM_LEAN if state == DotPlayerAnimState.SWIM and not downed else 0.0
	var before := _swim_pitch + _prop_pitch
	_swim_pitch = move_toward(_swim_pitch, wanted, delta * 3.0)
	_prop_pitch = move_toward(_prop_pitch, -PROP_LEAN if downed and propped else 0.0, delta * 3.0)
	var total := _swim_pitch + _prop_pitch
	if is_equal_approx(before, total) and total == 0.0:
		return
	var hips := Vector3(0.0, height * 0.55, 0.0)
	var tilt := Transform3D(Basis(Vector3.RIGHT, -total), Vector3.ZERO)
	var about := Transform3D(Basis.IDENTITY, hips) * tilt * Transform3D(Basis.IDENTITY, -hips)
	_model.transform = about * Transform3D(_model_basis, _model_origin)


func _step_for_distance() -> int:
	var viewport := get_viewport() if is_inside_tree() else null
	var camera := viewport.get_camera_3d() if viewport != null else null
	if camera == null:
		return 1
	var d := camera.global_position.distance_to(global_position)
	if _mesh != null:
		var shadow := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if d <= SHADOW_RANGE else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if _mesh.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY and _mesh.cast_shadow != shadow:
			_mesh.cast_shadow = shadow
	if d <= ANIM_NEAR:
		return 1
	return 2 if d <= ANIM_FAR else 4


## The body's height at rest, from its mesh (the unposed bind shape, which is standing).
func _measure() -> float:
	if _mesh == null or _mesh.mesh == null:
		return 1.8
	var aabb := _mesh.mesh.get_aabb()
	# The mesh's own transform under the model (the importer may scale the armature).
	var to_model := Transform3D.IDENTITY
	var node: Node = _mesh
	while node != null and node != _model:
		if node is Node3D:
			to_model = (node as Node3D).transform * to_model
		node = node.get_parent()
	return (to_model * aabb).size.y


## The directory the people's files are in.
static func directory() -> String:
	return DotHumanoidAssets.directory()


## Every file a figure may load, for a preloader or a pack manifest.
static func content_paths() -> PackedStringArray:
	return DotHumanoidAssets.content_paths()


## The baked real clips' path; a figure without the file plays the made ones.
static func real_clips_path() -> String:
	return DotHumanoidAssets.real_clips_path()


static func body_path(id: StringName) -> String:
	return DotHumanoidAssets.body_path(id)


## A model by path, imported or not (see [method DotHumanoidAssets.load_model]).
static func load_model(path: String) -> PackedScene:
	return DotHumanoidAssets.load_model(path)


## A texture by path, imported or not.
static func load_texture(path: String) -> Texture2D:
	return DotHumanoidAssets.load_texture(path)


## One material per look: people with the same colours share it.
static func material_for(p_look: DotHumanoidLook) -> ShaderMaterial:
	return DotHumanoidAssets.material_for(p_look)


## How many distinct materials the looks drawn so far made: a crowd's draw-state cost.
static func material_count() -> int:
	return DotHumanoidAssets.material_count()


## Drops every shared scene, library, material, shader and atlas so a process can exit without leaking them.
static func clear_cache() -> void:
	DotHumanoidAssets.clear_cache()


static func _capsule(p_height: float, colour: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "Capsule"
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	var trunk := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.32
	capsule.height = p_height
	trunk.mesh = capsule
	trunk.material_override = material
	trunk.position = Vector3(0.0, p_height * 0.5, 0.0)
	trunk.name = "torso"
	root.add_child(trunk)
	return root


func describe() -> Dictionary:
	return {
		"art": from_art,
		"body": String(look.body) if look != null else "",
		"look": look.to_dict() if look != null else {},
		"state": String(state),
		"clip": String(clip),
		"overlay": String(overlay),
		"aim": snappedf(rad_to_deg(aim_pitch), 0.1),
		"seated": seated,
		"driving": driving,
		"hold": hold,
		"downed": downed,
		"anim_step": anim_step,
		"visible": visible,
	}
