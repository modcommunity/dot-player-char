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

## How far a swimmer is laid forward about the hips, in radians (about 80 degrees): the swim clip
## is drawn upright, and a front crawl is nearly flat with the head a little up.
const SWIM_LEAN := 1.4

## What the hand holds, which decides the arms: nothing, a gun (the kit's gun clips and the
## held-gun overlay), or a melee weapon (ordinary arms, a slash to swing).
enum Hold { NONE, GUN, MELEE }

## The atlas colours each body wears, by role, measured by `tools/people_palette.gd`; the shader
## swaps them for the look's colours. Several swatches of one role all take its colour.
const WEARS := {
	&"matt": {"skin": ["7c4e26"], "hair": ["312515"], "top": ["af6c1c"], "bottom": ["4e694b"]},
	&"lis": {"skin": ["c09264"], "hair": ["225385"], "top": ["bd8e30"], "bottom": ["466469"]},
	&"sam": {"skin": ["7c4e26"], "hair": ["4c3a21"], "top": ["504c43"], "bottom": ["333333"]},
	&"shaun": {"skin": ["c09264"], "hair": ["923c12"], "top": ["5f4009"], "bottom": ["466469"]},
}

## The body whose file carries the clip set; the others play it through [method DotHumanoidClips.retarget].
const CLIP_BODY := &"matt"

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

const SWAPS := 8
const SHADER := """
shader_type spatial;
render_mode cull_back, specular_disabled;
uniform sampler2D atlas : source_color, filter_nearest, repeat_disable;
uniform vec4 from_colour[8];
uniform vec4 to_colour[8];
uniform vec4 from_linear[8];
uniform vec4 to_linear[8];
uniform int swaps = 0;
uniform float tolerance = 0.002;
uniform float flash = 0.0;

void fragment() {
	// Sampled as a StandardMaterial3D samples its albedo (source_color), so a person is lit like
	// the walls beside them. What comes back differs by renderer (the compatibility one hands back
	// the stored sRGB values), so a swap is matched in both spaces and answered in the space it
	// matched; game-zombie-zone's first version converted by hand and drew everybody near black.
	vec3 c = texture(atlas, UV).rgb;
	for (int i = 0; i < swaps; i++) {
		vec3 d = c - from_colour[i].rgb;
		if (dot(d, d) < tolerance) {
			c = to_colour[i].rgb;
			break;
		}
		vec3 e = c - from_linear[i].rgb;
		if (dot(e, e) < tolerance * 0.25) {
			c = to_linear[i].rgb;
			break;
		}
	}
	ALBEDO = c;
	ROUGHNESS = 0.85;
	EMISSION = vec3(flash * 0.35, flash * 0.05, flash * 0.03);
}
"""

## The look drawn, the height it was built to, and whether the art loaded (or a capsule stands in).
var look: DotHumanoidLook = null
var height: float = 1.8
var from_art: bool = false

## The locomotion state and the clip playing, for a suite and [method describe].
var state: StringName = DotPlayerAnimState.IDLE
var clip: StringName = &""

## What the hand holds; see [enum Hold].
var hold: int = Hold.NONE

## Down: crawling on the floor, whatever the legs would otherwise do.
var downed: bool = false

## The overlay playing on the upper body, or empty.
var overlay: StringName = &""

## Where the player looks, up (+) or down (-), in radians: the upper body, the arms and the gun
## in the hand follow it. See [method aim].
var aim_pitch: float = 0.0

## Sitting ([constant DotHumanoidClips.SIT]): set by `seated` in [method set_motion].
var seated: bool = false

## Moves itself: every frame the figure measures how far it moved and animates from that, for a
## body something else carries (an NPC on a physics body, a prop with a person on it) where no
## code knows its speed. Off for a player, whose game says how it moves ([method pose]).
var auto_animate: bool = false:
	set(value):
		auto_animate = value
		set_process(value)
		_auto_last = Vector3.INF

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
var _crown: Node3D = null
var _machine := DotPlayerAnimState.new()
var _motion: Dictionary = {}
var _speed: float = 0.0
var _overlay_time: float = 0.0
var _overlay_rate: float = 1.0
var _owed: float = 0.0
var _frame: int = 0
var _posed_usec: int = -1
var _upper: Dictionary = {}
var _swim_pitch: float = 0.0
var _head_hidden: bool = false
var _auto_last: Vector3 = Vector3.INF
var _model_basis: Basis = Basis.IDENTITY
var _model_origin: Vector3 = Vector3.ZERO

static var _scenes: Dictionary = {}
static var _libraries: Dictionary = {}
static var _materials: Dictionary = {}
static var _shader: Shader = null
static var _atlas: Texture2D = null


## The directory the people's files are in, found from this script so a pack mounted under
## another root still finds them.
static func directory() -> String:
	var here: String = (DotHumanoidFigure as Script).resource_path
	return here.get_base_dir().get_base_dir().path_join("people")


## Every file a figure may load, for a preloader or a pack manifest.
static func content_paths() -> PackedStringArray:
	var out := PackedStringArray()
	for id in DotHumanoidLook.BODIES:
		out.append(body_path(id))
	out.append(directory().path_join("atlas_people.png"))
	out.append(real_clips_path())
	return out


## The clips baked from the Universal Animation Library ([method DotHumanoidClips.adopt]); a
## figure without the file plays the made ones.
static func real_clips_path() -> String:
	return directory().path_join("people_ual.res")


static func body_path(id: StringName) -> String:
	return directory().path_join("people_%s.glb" % id)


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
	_machine.forget_state()

	if _model != null:
		remove_child(_model)
		_model.queue_free()
		_model = null
		_skeleton = null
		_mesh = null
		_anim = null

	var scene := _scene(body_path(look.body))
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

	var library := _library_for(look.body, _skeleton)
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
	animate(Vector2(moved.x, moved.z).length(), delta)


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

	if _anim == null:
		return

	var wanted := _clip_for(state, speed)
	_play(wanted[0], wanted[1])

	if overlay != &"":
		_overlay_time += delta * _overlay_rate

	# The clip is advanced less often far from the camera, with the skipped time carried.
	_owed += delta
	_frame += 1
	anim_step = _step_for_distance()
	if _frame % anim_step != 0:
		return
	_anim.advance(_owed)
	_owed = 0.0
	_apply_overlays()
	_apply_aim()
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
## `on_floor`, `vertical`, `crouched`, `swimming`, `climbing`, `alive`; plus `downed` here.
## `seated` draws the person sitting ([method seat_height] says where their hips are), and `aim`
## (radians, up positive) is [method aim]; left out, the aim stays where it was.
func set_motion(motion: Dictionary) -> void:
	_motion = motion
	downed = bool(motion.get("downed", false))
	seated = bool(motion.get("seated", false))
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
	var base: float = _libraries.get(&"sit_height", 0.0)
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


## A hit: the kit's flinch on the upper body, quick.
func flinch() -> void:
	_start_overlay(DotHumanoidClips.HIT, 1.6)


## A gesture over the upper body: wave, yes, no.
func emote(which: StringName) -> void:
	_start_overlay(which, 1.0)


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
	_hand.transform = _hand_frame()
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
	if downed:
		return [DotHumanoidClips.CRAWL, clampf(speed / 1.2, 0.0, 1.6)]
	# A rider is carried: whatever speed the seat moves at, the legs stay sat.
	if seated and p_state != DotPlayerAnimState.DEAD:
		return [DotHumanoidClips.SIT, 1.0]
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
			return [DotHumanoidClips.WALK_GUN if gun else DotHumanoidClips.WALK, clampf(speed / 1.9, 0.6, 1.6)]
		DotPlayerAnimState.RUN:
			return [DotHumanoidClips.RUN_GUN if gun else DotHumanoidClips.RUN, clampf(speed / 5.0, 0.7, 1.5)]
		DotPlayerAnimState.CLIMB:
			return [DotHumanoidClips.CLIMB, clampf(absf(float(_motion.get("vertical", 0.0))) / 2.5, 0.0, 1.2)]
	return [DotHumanoidClips.IDLE_GUN if gun else DotHumanoidClips.IDLE, 1.0]


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
	clip = wanted
	_anim.play(wanted, 0.15)


func _start_overlay(which: StringName, rate: float) -> void:
	if _anim == null or not _anim.has_animation(which):
		return
	overlay = which
	_overlay_time = 0.0
	_overlay_rate = rate


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
		if source == null or _overlay_time >= source.length:
			overlay = &""
			source = null
		else:
			t = _overlay_time
			weight = minf(1.0, _overlay_time / BLEND_IN) * minf(1.0, (source.length - _overlay_time) / BLEND_OUT)
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
		_skeleton.set_bone_pose_rotation(index, now.slerp(q, clampf(weight, 0.0, 1.0)))


## Bends the waist and chest by [member aim_pitch] about the figure's own left-to-right axis,
## after the clip and the overlays, so whatever the arms are doing points up or down with the
## view. Not while down, dead, swimming or climbing (the body is not upright to bend), and only
## on a bone the playing clip keys: a bone no track writes keeps last frame's pose, and the bend
## would add up frame after frame.
func _apply_aim() -> void:
	if _skeleton == null or is_zero_approx(aim_pitch) or downed:
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
			parents[i] = _chain_rotation(_skeleton.get_bone_parent(i))
	for bone: String in shares:
		var i := _skeleton.find_bone(bone)
		if i < 0 or animation.find_track(NodePath("%s:%s" % [prefix, bone]), Animation.TYPE_ROTATION_3D) < 0:
			continue
		var share: float = shares[bone]
		var p: Quaternion = parents[i]
		var turn := Quaternion(axis, aim_pitch * share)
		_skeleton.set_bone_pose_rotation(i, (p.inverse() * turn * p * _skeleton.get_bone_pose_rotation(i)).normalized())


## Bone [param bone]'s rotation in skeleton space from the local poses as they are now.
func _chain_rotation(bone: int) -> Quaternion:
	var q := Quaternion.IDENTITY
	while bone >= 0:
		q = _skeleton.get_bone_pose_rotation(bone) * q
		bone = _skeleton.get_bone_parent(bone)
	return q


## Swimming lays the whole body forward, about the hips, and eases back out of it. The swim clip
## is drawn upright ([method DotHumanoidClips._swimming]); this is what makes it horizontal.
func _apply_swim(delta: float) -> void:
	if _model == null:
		return
	var wanted := SWIM_LEAN if state == DotPlayerAnimState.SWIM and not downed else 0.0
	var before := _swim_pitch
	_swim_pitch = move_toward(_swim_pitch, wanted, delta * 3.0)
	if is_equal_approx(before, _swim_pitch) and _swim_pitch == 0.0:
		return
	var hips := Vector3(0.0, height * 0.55, 0.0)
	var tilt := Transform3D(Basis(Vector3.RIGHT, -_swim_pitch), Vector3.ZERO)
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


static func _scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load_model(path)
	return _scenes[path]


## A model by path, imported or not: [code]load()[/code] when the project has imported it, and
## otherwise the source file read at run time through [GLTFDocument], packed as a scene.
##
## The fallback is not a nicety. A project only imports a file when the editor (or
## [code]--import[/code]) scans it, and a game started straight from a clone or a fresh addon
## copy, with an import cache from before the file arrived, has the [code].glb[/code] and
## its [code].import[/code] and no imported scene: [code]load()[/code] fails, and every person
## was a capsule in three games on a machine that pulled the people and played without opening
## the editor. The run-time read builds the same skeleton, skin, mesh and clips as the importer
## does with this addon's import settings (compared bone for bone), so nothing downstream can
## tell. An exported build has no source file, and there the import is always present.
static func load_model(path: String) -> PackedScene:
	if ResourceLoader.exists(path):
		var imported := load(path) as PackedScene
		if imported != null:
			return imported
	if not FileAccess.file_exists(path):
		return null
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(path, state)
	var root := doc.generate_scene(state, 30.0, false, true) if err == OK else null
	if root == null:
		DotLog.warn(CHANNEL, "model is neither imported nor readable", {"path": path, "error": error_string(err)})
		return null
	var packed := PackedScene.new()
	var packed_err := packed.pack(root)
	root.free()
	if packed_err != OK:
		return null
	DotLog.warn(CHANNEL, "model was never imported; read from the source file instead (run the project's import once)", {"path": path})
	return packed


## A texture by path, imported or not; the image fallback is [method load_model]'s reasoning.
static func load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var imported := load(path) as Texture2D
		if imported != null:
			return imported
	if not FileAccess.file_exists(path):
		return null
	# From the bytes rather than Image.load_from_file, which prints an export warning for any
	# res:// path even where, as here, there is nothing to export.
	var image := Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
		return null
	return ImageTexture.create_from_image(image)


## The clip set for [param id]'s body: the clip body's own (with the made clips), carried onto
## this body's rest by [method DotHumanoidClips.retarget], once per body and shared.
##
## Mirrored first (the kit is left-handed; [constant HAND_BONE]), then the made clips added, then
## the real ones from [method real_clips_path] put over the made ones they replace.
static func _library_for(id: StringName, skeleton: Skeleton3D) -> AnimationLibrary:
	var base_key := StringName("base")
	if not _libraries.has(base_key):
		var scene := _scene(body_path(CLIP_BODY))
		var probe := scene.instantiate() if scene != null else null
		var bones: Array = probe.find_children("*", "Skeleton3D", true, false) if probe != null else []
		var clip_skeleton: Skeleton3D = bones.front() as Skeleton3D if not bones.is_empty() else null
		var library := DotHumanoidClips.mirror(DotHumanoidClips.library_of(scene))
		_libraries[base_key] = DotHumanoidClips.synthesise(library, clip_skeleton)
		var real_path := real_clips_path()
		var real: AnimationLibrary = load(real_path) as AnimationLibrary if ResourceLoader.exists(real_path) else null
		var _adopted := DotHumanoidClips.adopt(library, real)
		_libraries[&"rests"] = DotHumanoidClips.rests_of(clip_skeleton)
		_libraries[&"sit_height"] = DotHumanoidClips.sit_height(library, clip_skeleton)
		if probe != null:
			probe.free()
	if id == CLIP_BODY or skeleton == null:
		return _libraries[base_key]
	if not _libraries.has(id):
		_libraries[id] = DotHumanoidClips.retarget(_libraries[base_key], _libraries[&"rests"], skeleton)
	return _libraries[id]


## One material per look: people with the same colours share it.
static func material_for(p_look: DotHumanoidLook) -> ShaderMaterial:
	var key := p_look.key()
	if _materials.has(key):
		return _materials[key]
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	if _atlas == null:
		var path := directory().path_join("atlas_people.png")
		_atlas = load_texture(path)

	var wears: Dictionary = WEARS.get(p_look.body, {})
	var colours := {"skin": p_look.skin, "hair": p_look.hair, "top": p_look.top, "bottom": p_look.bottom}
	# vec4, not vec3: a vec3 array is padded on the GPU and a PackedVector3Array set into one is
	# read skewed.
	var from := PackedVector4Array()
	var to := PackedVector4Array()
	var from_lin := PackedVector4Array()
	var to_lin := PackedVector4Array()
	for role: String in ["skin", "hair", "top", "bottom"]:
		for hex: String in wears.get(role, []):
			if from.size() >= SWAPS:
				break
			var a := Color(hex)
			var b: Color = colours[role]
			from.append(Vector4(a.r, a.g, a.b, 1.0))
			to.append(Vector4(b.r, b.g, b.b, 1.0))
			var al := a.srgb_to_linear()
			var bl := b.srgb_to_linear()
			from_lin.append(Vector4(al.r, al.g, al.b, 1.0))
			to_lin.append(Vector4(bl.r, bl.g, bl.b, 1.0))
	var used := from.size()
	while from.size() < SWAPS:
		from.append(Vector4(-9.0, -9.0, -9.0, 0.0))
		to.append(Vector4.ZERO)
		from_lin.append(Vector4(-9.0, -9.0, -9.0, 0.0))
		to_lin.append(Vector4.ZERO)

	var material := ShaderMaterial.new()
	material.shader = _shader
	material.set_shader_parameter(&"atlas", _atlas)
	material.set_shader_parameter(&"from_colour", from)
	material.set_shader_parameter(&"to_colour", to)
	material.set_shader_parameter(&"from_linear", from_lin)
	material.set_shader_parameter(&"to_linear", to_lin)
	material.set_shader_parameter(&"swaps", used)
	_materials[key] = material
	return material


## How many distinct materials the looks drawn so far made: a crowd's draw-state cost.
static func material_count() -> int:
	return _materials.size()


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
		"hold": hold,
		"downed": downed,
		"anim_step": anim_step,
		"visible": visible,
	}
