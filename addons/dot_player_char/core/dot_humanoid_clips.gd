class_name DotHumanoidClips
extends RefCounted

## The family's clip set for skinned people: which clips exist, which loop, carrying a clip set
## from one skeleton to another, and the clips made from others (a held crouch, a crouch
## walk, sitting, climbing and a swim stroke). Static and loads nothing itself; [DotHumanoidFigure]
## hands it libraries.
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
const SIT := &"sit"
## Seated with the hands on a wheel: only from `people/people_ual.res` (the library's `Driving_Loop`), no made one; a figure without it sits.
const DRIVE := &"drive"
const CLIMB := &"climb"
const SWIM := &"swim"

## Every clip a figure is expected to have, for a suite and a contact sheet.
const ALL: Array[StringName] = [IDLE, IDLE_GUN, WALK, WALK_GUN, RUN, RUN_GUN, CROUCH, CROUCH_WALK,
	JUMP, FALL, LAND, SLASH, STAB, PUNCH, HIT, DEATH, CRAWL, WAVE, YES, NO, DUCK, SIT, DRIVE, CLIMB, SWIM]

## Clips that loop; the rest play once and hold their last frame.
const LOOPING: Array[StringName] = [IDLE, IDLE_GUN, WALK, WALK_GUN, RUN, RUN_GUN, CROUCH, CROUCH_WALK, FALL, CRAWL, SIT, DRIVE, CLIMB, SWIM]

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

## The bones an aim pitch bends, and each one's share of it. The waist and chest take a little
## under a quarter (much more folds a cartoon-proportioned person in half: the first try gave them
## two thirds and a player looking down was bowing), and the neck enough again for the head to
## read as looking there. The hips and legs take none.
const AIM_BONES := {"Abdomen": 0.1, "Torso": 0.12, "Neck": 0.25}

## The weapon arm's share, at the shoulder, when the hand holds something: with the chest's, the
## whole pitch, so the gun points where the player aims. The other arm hangs as the clip has it.
const AIM_ARM := {"UpperArm.R": 0.78}


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


## [param library] (in place) turned left for right: every track of a `.L` bone becomes the
## `.R` bone's and the other way round, and every key is reflected across the body's middle.
## Returns it.
##
## [b]The kit's people are left-handed[/b]: every weapon in it hangs off the left hand, and its
## gun and melee clips hold them there. The family's first-person view models are right-handed,
## so a player seen by anybody else held the gun in the other hand from the one they saw it in.
## Mirroring the whole set (not only the gun clips) keeps every clip one person: a right-handed
## swing, wave and punch to go with the right-handed gun, and a walk is a walk either way.
##
## The rig is symmetric (each `.R` bone's rest is the `.L` bone's reflected across x = 0 in the
## skeleton's space, to the thousandth), so a local pose mirrors on its own: with the reflection
## `M`, `L'(b) = M L(mirror b) M`, a rotation's y and z negated and a position's x.
static func mirror(library: AnimationLibrary) -> AnimationLibrary:
	if library == null:
		return library
	for clip in library.get_animation_list():
		var animation := library.get_animation(clip)
		for t in animation.get_track_count():
			var path := animation.track_get_path(t)
			var bone := String(path.get_concatenated_subnames())
			var other := mirrored_bone(bone)
			if other != bone:
				animation.track_set_path(t, NodePath("%s:%s" % [String(path.get_concatenated_names()), other]))
			match animation.track_get_type(t):
				Animation.TYPE_ROTATION_3D:
					for k in animation.track_get_key_count(t):
						var q: Quaternion = animation.track_get_key_value(t, k)
						animation.track_set_key_value(t, k, Quaternion(q.x, -q.y, -q.z, q.w))
				Animation.TYPE_POSITION_3D:
					for k in animation.track_get_key_count(t):
						var p: Vector3 = animation.track_get_key_value(t, k)
						animation.track_set_key_value(t, k, Vector3(-p.x, p.y, p.z))
	return library


## The bone on the other side: `Hand.L` for `Hand.R` and back; a middle bone is its own.
static func mirrored_bone(bone: String) -> String:
	if bone.ends_with(".L"):
		return bone.trim_suffix(".L") + ".R"
	if bone.ends_with(".R"):
		return bone.trim_suffix(".R") + ".L"
	return bone


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
##
## With [param skeleton] (the clip body's), also [constant SIT], [constant CLIMB] and
## [constant SWIM], which need the bone hierarchy to pose: see [method _sat], [method _climbing]
## and [method _swimming].
static func synthesise(library: AnimationLibrary, skeleton: Skeleton3D = null) -> AnimationLibrary:
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

	if skeleton != null:
		if library.has_animation(SIT):
			library.remove_animation(SIT)
		var _s := library.add_animation(SIT, _sat(idle, skeleton))
		if library.has_animation(CLIMB):
			library.remove_animation(CLIMB)
		var _c := library.add_animation(CLIMB, _climbing(idle, skeleton))
		if library.has_animation(SWIM):
			library.remove_animation(SWIM)
		var _w := library.add_animation(SWIM, _swimming(idle, skeleton))
		var _actions := DotHumanoidActions.add_to(library, idle, skeleton)

	return library


## [param library] (in place) with each clip of [param real] put in place of the one of the same
## name, loop mode set from [constant LOOPING]. Returns it.
##
## [param real] is `people/people_ual.res`: clips from Quaternius' Universal Animation Library,
## baked onto the clip body's skeleton by `tools/ual_retarget.gd` and already right-handed, so
## this runs after [method mirror] and [method synthesise]. Only a clip that reads better than
## the made one is in the file (docs/people.md, "Real clips").
static func adopt(library: AnimationLibrary, real: AnimationLibrary) -> AnimationLibrary:
	if library == null or real == null:
		return library
	for clip in real.get_animation_list():
		var animation := real.get_animation(clip).duplicate(true) as Animation
		animation.loop_mode = Animation.LOOP_LINEAR if LOOPING.has(StringName(clip)) else Animation.LOOP_NONE
		if library.has_animation(clip):
			library.remove_animation(clip)
		var _a := library.add_animation(clip, animation)
	return library


## How high the hips are above the feet in [constant SIT], in the clip body's units (the kit is
## about 1.1 tall): [method DotHumanoidFigure.seat_height] scales it.
static func sit_height(library: AnimationLibrary, skeleton: Skeleton3D) -> float:
	if library == null or skeleton == null or not library.has_animation(SIT):
		return 0.0
	var globals := _globals(_locals(library.get_animation(SIT), 0.0, skeleton), skeleton)
	var hips := skeleton.find_bone("UpperLeg.L")
	var foot := skeleton.find_bone("Foot.L")
	if hips < 0 or foot < 0:
		return 0.0
	return globals[hips].origin.y - globals[foot].origin.y


## Sitting, made from the idle's first frame: the thighs laid forward level, the shins hanging
## straight down with the feet flat on the floor under the knees, and the body dropped until they
## are. The hips end at knee height. The kit has no seat; a rider drawn crouching was somebody
## squatting over the cushion.
##
## The feet are not the shins' children on this rig (they hang off the root, for the kit's own
## leg IK, which nothing here runs), so each is put where its shin now ends, and the knee pole
## targets move with the knees.
static func _sat(idle: Animation, skeleton: Skeleton3D) -> Animation:
	var g := _globals(_locals(idle, 0.0, skeleton), skeleton)
	var body := skeleton.find_bone("Body")
	var thigh_l := skeleton.find_bone("UpperLeg.L")
	var knee_l := skeleton.find_bone("LowerLeg.L")
	var foot_l := skeleton.find_bone("Foot.L")
	if body < 0 or thigh_l < 0 or knee_l < 0 or foot_l < 0:
		return idle.duplicate(true) as Animation
	# The shin's length is taken before the drop: the foot is not under the body, so it stays put
	# while the knee comes down.
	var shins := {}
	for side in [".L", ".R"]:
		var k := skeleton.find_bone("LowerLeg" + side)
		var f := skeleton.find_bone("Foot" + side)
		shins[side] = (g[f].origin - g[k].origin).length() if k >= 0 and f >= 0 else 0.0
	var drop: float = g[thigh_l].origin.y - (g[foot_l].origin.y + float(shins[".L"]))
	_move_subtree(g, skeleton, body, Transform3D(Basis.IDENTITY, Vector3(0.0, -drop, 0.0)))
	for side: String in [".L", ".R"]:
		# This rig faces +Z in its own space.
		_place_leg(g, skeleton, side, Vector3(0.0, -0.05, 1.0), Vector3(0.0, -1.0, 0.08), shins[side])
	var made := Animation.new()
	made.length = 1.0
	made.loop_mode = Animation.LOOP_LINEAR
	_write_pose(made, idle, _back_to_locals(g, skeleton), skeleton, 0.0)
	return made


## Climbing a ladder, made from the idle (its breathing kept): one knee lifted to the next rung
## while the other leg straightens, and the arms reaching up over the head, the hand on the side
## of the straight leg the higher (people climb with opposite hand and foot). One second a cycle;
## the figure plays it as fast as the player climbs. The kit has none; the crawl it played before
## was a body lying on its front, drawn upright on a ladder.
static func _climbing(idle: Animation, skeleton: Skeleton3D) -> Animation:
	var made := Animation.new()
	made.length = 1.0
	made.loop_mode = Animation.LOOP_LINEAR
	var prefix := _skeleton_prefix(idle)
	var tracks := {}
	for i in skeleton.get_bone_count():
		var path := NodePath("%s:%s" % [prefix, skeleton.get_bone_name(i)])
		var rt := made.add_track(Animation.TYPE_ROTATION_3D)
		made.track_set_path(rt, path)
		var pt := made.add_track(Animation.TYPE_POSITION_3D)
		made.track_set_path(pt, path)
		tracks[i] = [rt, pt]
	var frames := 24
	for frame in frames + 1:
		var time := float(frame) / float(frames)
		var phase := TAU * time
		var g := _globals(_locals(idle, fmod(time, maxf(idle.length, 0.001)), skeleton), skeleton)
		var floor_y := INF
		for side: String in [".L", ".R"]:
			var f := skeleton.find_bone("Foot" + side)
			if f >= 0:
				floor_y = minf(floor_y, (g[f] as Transform3D).origin.y)
		for side: String in [".L", ".R"]:
			var lift := 0.5 + 0.5 * sin(phase if side == ".L" else phase + PI)
			var thigh_angle := deg_to_rad(8.0 + 62.0 * lift)
			_place_leg(g, skeleton, side, Vector3(0.0, -cos(thigh_angle), sin(thigh_angle)), Vector3(0.0, -1.0, 0.1))
			# The hand on the side of the lifted knee is the lower one.
			var reach := deg_to_rad(6.0 + 34.0 * lift)
			var out := 0.18 if side == ".L" else -0.18
			_point_bone(g, skeleton, "UpperArm" + side, "LowerArm" + side, Vector3(out, cos(reach), sin(reach)).normalized())
			# The forearm nearly straight on up: a hand on a rung over the head.
			_point_bone(g, skeleton, "LowerArm" + side, "Middle1" + side, Vector3(out * 0.4, cos(reach * 0.6), sin(reach * 0.6) + 0.15).normalized())
		# The idle stands on bent knees; a straight leg on the rung below would put its foot through
		# the figure's origin, so the climber is pushed up until the lower foot is where the feet
		# stood. That is also the pull-up: the body rises as a leg straightens.
		var lowest := INF
		for side: String in [".L", ".R"]:
			var f := skeleton.find_bone("Foot" + side)
			if f >= 0:
				lowest = minf(lowest, (g[f] as Transform3D).origin.y)
		if lowest < floor_y and floor_y != INF:
			var up := Transform3D(Basis.IDENTITY, Vector3(0.0, floor_y - lowest, 0.0))
			for name: String in ["Body", "Foot.L", "Foot.R", "PoleTarget.L", "PoleTarget.R"]:
				var i := skeleton.find_bone(name)
				if i >= 0:
					_move_subtree(g, skeleton, i, up)
		var locals := _back_to_locals(g, skeleton)
		for i in locals.size():
			var local: Transform3D = locals[i]
			var _r := made.rotation_track_insert_key(tracks[i][0], time, local.basis.get_rotation_quaternion().normalized())
			var _p := made.position_track_insert_key(tracks[i][1], time, local.origin)
	return made


## One stroke of [constant SWIM], in seconds at rate 1.
const SWIM_CYCLE := 1.6


## A front crawl, made from the idle and drawn UPRIGHT: [DotHumanoidFigure] lays the whole figure
## forward about the hips ([constant DotHumanoidFigure.SWIM_LEAN]), so this clip's "up" is ahead
## of the swimmer, its "front" is down into the water and its "back" is up out of it.
##
## In that frame a crawl is a windmill: each arm goes round the body's side, up (the reach),
## front (the catch and pull, under the chest, elbow bent), down to the thigh (the finish) and
## back (the recovery over the water, elbow high and wide), the two arms half a turn apart. The
## body rolls about the spine towards the pulling arm and the head turns with it to breathe on
## one side. The legs flutter from the hip, three kicks per arm, knees a little bent and toes
## pointed. One stroke cycle is [constant SWIM_CYCLE] seconds; the figure plays it faster with
## speed. The kit has no swim; the stand-in before was the run, slowed and leaned forward.
static func _swimming(idle: Animation, skeleton: Skeleton3D) -> Animation:
	var made := Animation.new()
	made.length = SWIM_CYCLE
	made.loop_mode = Animation.LOOP_LINEAR
	var prefix := _skeleton_prefix(idle)
	var tracks := {}
	for i in skeleton.get_bone_count():
		var path := NodePath("%s:%s" % [prefix, skeleton.get_bone_name(i)])
		var rt := made.add_track(Animation.TYPE_ROTATION_3D)
		made.track_set_path(rt, path)
		var pt := made.add_track(Animation.TYPE_POSITION_3D)
		made.track_set_path(pt, path)
		tracks[i] = [rt, pt]
	var abdomen := skeleton.find_bone("Abdomen")
	var neck := skeleton.find_bone("Neck")
	var frames := 32
	for frame in frames + 1:
		var time := SWIM_CYCLE * float(frame) / float(frames)
		var phase := TAU * float(frame) / float(frames)
		var g := _globals(_locals(idle, 0.0, skeleton), skeleton)
		# The roll, about the spine (this frame's Y), towards the arm that is pulling: the left
		# arm pulls while sin(phase) > 0, and that shoulder goes down (+Z, into the water).
		var roll := -0.45 * sin(phase)
		if abdomen >= 0:
			_move_subtree(g, skeleton, abdomen, _about(g[abdomen].origin, Basis(Vector3.UP, roll)))
		# Breathing to the right, once a cycle: the head turns further with the roll while the
		# right arm recovers, and is face down again before it reaches.
		if neck >= 0:
			var breathe := -0.7 * pow(maxf(0.0, sin(phase)), 2.0)
			_move_subtree(g, skeleton, neck, _about(g[neck].origin, Basis(Vector3.UP, breathe)))
		for side: String in [".L", ".R"]:
			var away := 1.0 if side == ".L" else -1.0
			var theta := phase if side == ".L" else phase + PI
			var pulling := maxf(0.0, sin(theta))
			var recovering := maxf(0.0, -sin(theta))
			# Close under the body on the pull; on the recovery swung round wide and low over the
			# water rather than straight up out of it (the first try was a windmill in the plane
			# of the body, and a recovering arm stood up like a mast).
			var out := away * (0.1 + 0.9 * recovering)
			var upper := Vector3(out, cos(theta), sin(theta) * (1.0 - 0.5 * recovering)).normalized()
			_point_bone(g, skeleton, "UpperArm" + side, "LowerArm" + side, upper)
			# The forearm runs ahead of the elbow on the pull (a bent-elbow catch); on the recovery
			# the elbow leads and the hand hangs towards the water (+Z here) as it travels forward.
			var fore := theta + 0.75 * pulling
			var catch := Vector3(out * 0.7, cos(fore), sin(fore)).normalized()
			var hang := Vector3(out * 0.5, cos(theta) * 0.6, 0.7).normalized()
			_point_bone(g, skeleton, "LowerArm" + side, "Middle1" + side, catch.lerp(hang, recovering).normalized())
		for side: String in [".L", ".R"]:
			var kick := 0.24 * sin(3.0 * phase + (0.0 if side == ".L" else PI))
			# The knee gives a little on the down-kick (towards +Z, the water) and straightens on
			# the way back up; a shin only ever bends behind its thigh.
			var knee := 0.12 + 0.22 * maxf(0.0, sin(3.0 * phase + (0.0 if side == ".L" else PI) + 0.8))
			_place_leg(g, skeleton, side, Vector3(0.0, -cos(kick), sin(kick)), Vector3(0.0, -cos(kick - knee), sin(kick - knee)))
			# Toes pointed: the foot turned down along the shin.
			var foot := skeleton.find_bone("Foot" + side)
			if foot >= 0:
				_move_subtree(g, skeleton, foot, _about(g[foot].origin, Basis(Vector3.RIGHT, 1.2)))
		var locals := _back_to_locals(g, skeleton)
		for i in locals.size():
			var local: Transform3D = locals[i]
			var _r := made.rotation_track_insert_key(tracks[i][0], time, local.basis.get_rotation_quaternion().normalized())
			var _p := made.position_track_insert_key(tracks[i][1], time, local.origin)
	return made


## Lays one leg along [param thigh_dir] from the hip and [param shin_dir] from the knee (both in
## skeleton space), and puts the foot (and the knee's pole target) where the shin now ends,
## [param shin] from the knee (measured from the pose when 0).
static func _place_leg(g: Array, skeleton: Skeleton3D, side: String, thigh_dir: Vector3, shin_dir: Vector3, shin: float = 0.0) -> void:
	var thigh := skeleton.find_bone("UpperLeg" + side)
	var knee := skeleton.find_bone("LowerLeg" + side)
	var foot := skeleton.find_bone("Foot" + side)
	if thigh < 0 or knee < 0 or foot < 0:
		return
	var shin_was: Vector3 = g[foot].origin - g[knee].origin
	if shin <= 0.0:
		shin = shin_was.length()
	var knee_was: Vector3 = g[knee].origin
	var foot_was: Vector3 = g[foot].origin
	# The foot does not follow the leg on this rig, so where the shin points is carried by hand:
	# the thigh's turn swings it round with the knee.
	var turned := _turn_subtree(g, skeleton, thigh, g[knee].origin - g[thigh].origin, thigh_dir)
	var _k := _turn_subtree(g, skeleton, knee, turned * shin_was, shin_dir)
	var ankle: Vector3 = g[knee].origin + shin_dir.normalized() * shin
	_move_subtree(g, skeleton, foot, Transform3D(Basis.IDENTITY, ankle - foot_was))
	var pole := skeleton.find_bone("PoleTarget" + side)
	if pole >= 0:
		_move_subtree(g, skeleton, pole, Transform3D(Basis.IDENTITY, g[knee].origin - knee_was))


## Turns bone [param bone] (and everything under it) about its own origin so that
## [param from_dir] points along [param to_dir]: the shortest turn, in skeleton space. Returns it.
static func _turn_subtree(g: Array, skeleton: Skeleton3D, bone: int, from_dir: Vector3, to_dir: Vector3) -> Basis:
	var a := from_dir.normalized()
	var b := to_dir.normalized()
	if a.is_zero_approx() or b.is_zero_approx() or a.is_equal_approx(b):
		return Basis.IDENTITY
	var turn := Basis(Quaternion(a, b))
	_move_subtree(g, skeleton, bone, _about(g[bone].origin, turn))
	return turn


## Points bone [param bone] at its child [param child] along [param to_dir].
static func _point_bone(g: Array, skeleton: Skeleton3D, bone: String, child: String, to_dir: Vector3) -> void:
	var i := skeleton.find_bone(bone)
	var j := skeleton.find_bone(child)
	if i < 0 or j < 0:
		return
	var _t := _turn_subtree(g, skeleton, i, g[j].origin - g[i].origin, to_dir)


## The local pose of every bone of [param skeleton] in [param animation] at [param time]: the
## clip's keys where it has them, the rest where it does not. Indexed by bone.
static func _locals(animation: Animation, time: float, skeleton: Skeleton3D) -> Array:
	var prefix := _skeleton_prefix(animation)
	var out := []
	for i in skeleton.get_bone_count():
		var rest := skeleton.get_bone_rest(i)
		var path := NodePath("%s:%s" % [prefix, skeleton.get_bone_name(i)])
		var rt := animation.find_track(path, Animation.TYPE_ROTATION_3D)
		var pt := animation.find_track(path, Animation.TYPE_POSITION_3D)
		var st := animation.find_track(path, Animation.TYPE_SCALE_3D)
		var q := rest.basis.get_rotation_quaternion() if rt < 0 else animation.rotation_track_interpolate(rt, time)
		var p := rest.origin if pt < 0 else animation.position_track_interpolate(pt, time)
		var s := rest.basis.get_scale() if st < 0 else animation.scale_track_interpolate(st, time)
		out.append(Transform3D(Basis(q).scaled(s), p))
	return out


static func _globals(locals: Array, skeleton: Skeleton3D) -> Array:
	var out := []
	out.resize(locals.size())
	for i in locals.size():
		_global_of(i, locals, skeleton, out)
	return out


static func _global_of(i: int, locals: Array, skeleton: Skeleton3D, out: Array) -> Transform3D:
	if out[i] != null:
		return out[i]
	var parent := skeleton.get_bone_parent(i)
	var g: Transform3D = locals[i] if parent < 0 else _global_of(parent, locals, skeleton, out) * (locals[i] as Transform3D)
	out[i] = g
	return g


static func _back_to_locals(globals: Array, skeleton: Skeleton3D) -> Array:
	var out := []
	for i in globals.size():
		var parent := skeleton.get_bone_parent(i)
		out.append(globals[i] if parent < 0 else (globals[parent] as Transform3D).affine_inverse() * (globals[i] as Transform3D))
	return out


## [param by] applied to bone [param bone] and everything under it, in skeleton space.
static func _move_subtree(globals: Array, skeleton: Skeleton3D, bone: int, by: Transform3D) -> void:
	for i in globals.size():
		var j := i
		while j >= 0 and j != bone:
			j = skeleton.get_bone_parent(j)
		if j == bone:
			globals[i] = by * (globals[i] as Transform3D)


## A turn [param basis] about the point [param at].
static func _about(at: Vector3, basis: Basis) -> Transform3D:
	return Transform3D(Basis.IDENTITY, at) * Transform3D(basis, Vector3.ZERO) * Transform3D(Basis.IDENTITY, -at)


## One key per bone at [param time]: rotation and position from [param locals], on the tracks
## [param like] uses (same node path), so the made clip binds where the kit's do.
static func _write_pose(made: Animation, like: Animation, locals: Array, skeleton: Skeleton3D, time: float) -> void:
	var prefix := _skeleton_prefix(like)
	for i in locals.size():
		var path := NodePath("%s:%s" % [prefix, skeleton.get_bone_name(i)])
		var local: Transform3D = locals[i]
		var rt := made.add_track(Animation.TYPE_ROTATION_3D)
		made.track_set_path(rt, path)
		var _r := made.rotation_track_insert_key(rt, time, local.basis.get_rotation_quaternion().normalized())
		var pt := made.add_track(Animation.TYPE_POSITION_3D)
		made.track_set_path(pt, path)
		var _p := made.position_track_insert_key(pt, time, local.origin)


## The node path in front of the bone names in [param animation]'s tracks
## (`CharacterArmature/Skeleton3D`).
static func _skeleton_prefix(animation: Animation) -> String:
	for t in animation.get_track_count():
		var path := animation.track_get_path(t)
		if path.get_subname_count() > 0:
			return String(path.get_concatenated_names())
	return "Skeleton3D"


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
