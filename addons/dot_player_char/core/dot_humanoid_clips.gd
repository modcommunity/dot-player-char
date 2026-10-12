class_name DotHumanoidClips
extends RefCounted

## The family's clip set for skinned people: which clips exist, which loop, carrying a clip set
## from one skeleton to another, and the two clips made from others (a held crouch and a crouch
## walk). Static and loads nothing itself; [DotHumanoidFigure] hands it libraries.
##
## [b]One rig.[/b] The people (`people/`) and game-zombie-zone's zombies are one artist's rig with
## the same bone names (Root, Body, Hips, Abdomen, Torso, Neck, Head, Shoulder/UpperArm/LowerArm
## .L/.R, UpperLeg/LowerLeg/Foot .L/.R, fingers), so any clip made for one plays on all of them
## once [method retarget] has moved it onto the other's rest pose. See docs/people.md.

## The clips the people carry, by the family's names. `duck` is the kit's one-shot dodge; the
## held crouch is made from its lowest frame ([method synthesise]).
const IDLE := &"idle"
const IDLE_GUN := &"idle_gun"
const WALK := &"walk"
const WALK_GUN := &"walk_gun"
const RUN := &"run"
const RUN_GUN := &"run_gun"
const CROUCH := &"crouch"
const CROUCH_WALK := &"crouch_walk"
const JUMP := &"jump"
const FALL := &"fall"
const LAND := &"land"
const SLASH := &"slash"
const STAB := &"stab"
const PUNCH := &"punch"
const HIT := &"hit"
const DEATH := &"death"
const CRAWL := &"crawl"
const WAVE := &"wave"
const YES := &"yes"
const NO := &"no"
const DUCK := &"duck"

## Every clip a figure is expected to have, for a suite and a contact sheet.
const ALL: Array[StringName] = [IDLE, IDLE_GUN, WALK, WALK_GUN, RUN, RUN_GUN, CROUCH, CROUCH_WALK,
	JUMP, FALL, LAND, SLASH, STAB, PUNCH, HIT, DEATH, CRAWL, WAVE, YES, NO, DUCK]

## Clips that loop; the rest play once and hold their last frame.
const LOOPING: Array[StringName] = [IDLE, IDLE_GUN, WALK, WALK_GUN, RUN, RUN_GUN, CROUCH, CROUCH_WALK, FALL, CRAWL]

## The bones a crouch bends: the body's height and the legs. The arms and head keep what the
## walk does with them.
const CROUCH_BONES: Array[String] = ["Body", "Hips", "Abdomen", "Torso", "UpperLeg.L", "UpperLeg.R",
	"LowerLeg.L", "LowerLeg.R", "Foot.L", "Foot.R"]

## The bones under the root that move with the body in an in-place jump.
const ROOTED_BONES: Array[String] = ["Body", "Foot.L", "Foot.R", "PoleTarget.L", "PoleTarget.R"]

## The upper body: what an overlay (a swing, a flinch, holding a gun) moves while the legs keep
## the locomotion clip.
const UPPER_BONES: Array[String] = ["Abdomen", "Torso", "Neck", "Head", "Shoulder.L", "UpperArm.L",
	"LowerArm.L", "Shoulder.R", "UpperArm.R", "LowerArm.R"]


## The rest pose of [param skeleton], bone name -> local rest transform.
static func rests_of(skeleton: Skeleton3D) -> Dictionary:
	var out := {}
	if skeleton == null:
		return out
	for i in skeleton.get_bone_count():
		out[skeleton.get_bone_name(i)] = skeleton.get_bone_rest(i)
	return out


## The clips of the first [AnimationPlayer] under [param scene], with loop modes set, as a
## library. Null when it has none.
static func library_of(scene: PackedScene) -> AnimationLibrary:
	if scene == null:
		return null
	var probe := scene.instantiate()
	var player := probe.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var library: AnimationLibrary = null
	if player != null:
		library = AnimationLibrary.new()
		for clip in player.get_animation_list():
			var animation := player.get_animation(clip).duplicate(true) as Animation
			animation.loop_mode = Animation.LOOP_LINEAR if LOOPING.has(StringName(clip)) else Animation.LOOP_NONE
			var _added := library.add_animation(StringName(clip), animation)
	probe.free()
	return library


## [param library]'s clips, moved from a skeleton with rests [param from] onto [param to].
##
## [b]A clip stores where each bone is, not how far it moved.[/b] Two bodies on one rig still
## differ in rest pose (a survivor's chest bone points up, a zombie's leans forward; even two
## survivors differ at the shoulder), and a clip played as it is on the other body bends it at
## the waist. What the animator made is the motion away from rest, so each key is taken off the
## old rest and put on the new: rotation `to * from^-1 * key`, a position by the same turn about
## the new rest. game-zombie-zone found it first (its docs/zombies.md).
static func retarget(library: AnimationLibrary, from: Dictionary, to: Skeleton3D) -> AnimationLibrary:
	if library == null or to == null:
		return library

	var out := AnimationLibrary.new()

	for clip in library.get_animation_list():
		var animation := library.get_animation(clip).duplicate(true) as Animation

		for t in animation.get_track_count():
			var bone := String(animation.track_get_path(t).get_concatenated_subnames())
			var index := to.find_bone(bone)

			if index < 0 or not from.has(bone):
				continue

			var a: Transform3D = from[bone]
			var b := to.get_bone_rest(index)
			var turn := b.basis.get_rotation_quaternion() * a.basis.get_rotation_quaternion().inverse()

			match animation.track_get_type(t):
				Animation.TYPE_ROTATION_3D:
					for k in animation.track_get_key_count(t):
						var q: Quaternion = animation.track_get_key_value(t, k)
						animation.track_set_key_value(t, k, (turn * q).normalized())
				Animation.TYPE_POSITION_3D:
					for k in animation.track_get_key_count(t):
						var p: Vector3 = animation.track_get_key_value(t, k)
						animation.track_set_key_value(t, k, b.origin + turn * (p - a.origin))

		var _added := out.add_animation(clip, animation)

	return out


## Adds the made clips to [param library] (in place) and returns it: [constant CROUCH] and
## [constant CROUCH_WALK], the idle and the walk with the kit's duck (at its lowest) added to the
## body and legs; and the air clips with the body's own rise taken out.
##
## [b]Made, not drawn,[/b] because the kit has no crouch at all: its duck is a one-shot dodge with
## both arms over the head, and held at its lowest it reads as somebody cowering, not crouching.
## The bend is added as a change from the idle pose (`key * idle^-1 * duck` on each of
## [constant CROUCH_BONES]' local rotations, the drop added to positions), so the idle's breathing
## and the walk's stride are kept above and under it.
##
## [b]The jump and the fall lift the body in the clip[/b] (an in-place jump), and a player in the
## air is already lifted by the game: drawn as it is, a falling player hung half a metre above
## their own capsule. The body's height in [constant JUMP], [constant FALL] and [constant LAND] is
## held at the idle's, and only allowed to go lower (the landing's squat).
static func synthesise(library: AnimationLibrary) -> AnimationLibrary:
	if library == null or not library.has_animation(DUCK) or not library.has_animation(IDLE):
		return library

	var duck := library.get_animation(DUCK)
	var idle := library.get_animation(IDLE)
	var low := _lowest_time(duck)

	for pair: Array in [[IDLE, CROUCH], [WALK, CROUCH_WALK]]:
		if not library.has_animation(pair[0]):
			continue
		var made := _bent(library.get_animation(pair[0]), idle, duck, low)
		if library.has_animation(pair[1]):
			library.remove_animation(pair[1])
		var _a := library.add_animation(pair[1], made)

	var rest_y := _body_height(idle, 0.0)
	for name: StringName in [JUMP, FALL, LAND]:
		if library.has_animation(name):
			_ground(library.get_animation(name), rest_y)

	return library


## [param base] with the duck's bend at [param low] added on [constant CROUCH_BONES], looping.
static func _bent(base: Animation, idle: Animation, duck: Animation, low: float) -> Animation:
	var made := base.duplicate(true) as Animation
	made.loop_mode = Animation.LOOP_LINEAR
	for t in made.get_track_count():
		var path := made.track_get_path(t)
		var bone := String(path.get_concatenated_subnames())
		if not CROUCH_BONES.has(bone):
			continue
		var type := made.track_get_type(t)
		var it := idle.find_track(path, type)
		var dt := duck.find_track(path, type)
		if it < 0 or dt < 0:
			continue
		var rest_value: Variant = _sample(idle, it, 0.0)
		var bent_value: Variant = _sample(duck, dt, low)
		for k in made.track_get_key_count(t):
			var v: Variant = made.track_get_key_value(t, k)
			if type == Animation.TYPE_ROTATION_3D:
				var change := (rest_value as Quaternion).inverse() * (bent_value as Quaternion)
				made.track_set_key_value(t, k, ((v as Quaternion) * change).normalized())
			elif type == Animation.TYPE_POSITION_3D:
				made.track_set_key_value(t, k, (v as Vector3) + ((bent_value as Vector3) - (rest_value as Vector3)))
	return made


## Takes the clip's own rise out of [param animation]: at every key, the body and the bones that
## hang off the root with it (the feet and their pole targets) come down by however far the body
## is above [param rest_y] then.
static func _ground(animation: Animation, rest_y: float) -> void:
	var body := _body_track(animation)
	if body < 0 or rest_y == INF:
		return
	for t in animation.get_track_count():
		if animation.track_get_type(t) != Animation.TYPE_POSITION_3D:
			continue
		var bone := String(animation.track_get_path(t).get_concatenated_subnames())
		if not ROOTED_BONES.has(bone):
			continue
		for k in animation.track_get_key_count(t):
			var at := animation.track_get_key_time(t, k)
			var lift := maxf(0.0, animation.position_track_interpolate(body, at).y - rest_y)
			var p: Vector3 = animation.track_get_key_value(t, k)
			animation.track_set_key_value(t, k, p - Vector3(0.0, lift, 0.0))


static func _body_track(animation: Animation) -> int:
	for t in animation.get_track_count():
		if animation.track_get_type(t) == Animation.TYPE_POSITION_3D \
				and String(animation.track_get_path(t).get_concatenated_subnames()) == "Body":
			return t
	return -1


static func _body_height(animation: Animation, time: float) -> float:
	for t in animation.get_track_count():
		if animation.track_get_type(t) == Animation.TYPE_POSITION_3D \
				and String(animation.track_get_path(t).get_concatenated_subnames()) == "Body":
			return animation.position_track_interpolate(t, time).y
	return INF


## The time in [param animation] at which the body is lowest (its `Body` bone's height), or the
## middle when it has no such track.
static func _lowest_time(animation: Animation) -> float:
	for t in animation.get_track_count():
		if animation.track_get_type(t) != Animation.TYPE_POSITION_3D:
			continue
		if String(animation.track_get_path(t).get_concatenated_subnames()) != "Body":
			continue
		var best := 0.0
		var best_y := INF
		for k in animation.track_get_key_count(t):
			var p: Vector3 = animation.track_get_key_value(t, k)
			if p.y < best_y:
				best_y = p.y
				best = animation.track_get_key_time(t, k)
		return best
	return animation.length * 0.5


static func _sample(animation: Animation, track: int, time: float) -> Variant:
	match animation.track_get_type(track):
		Animation.TYPE_ROTATION_3D:
			return animation.rotation_track_interpolate(track, time)
		Animation.TYPE_POSITION_3D:
			return animation.position_track_interpolate(track, time)
		Animation.TYPE_SCALE_3D:
			return animation.scale_track_interpolate(track, time)
	return null
