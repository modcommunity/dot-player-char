extends "res://tools/ual_retarget.gd"

## Bakes the family's clips onto Kenney's Animated Characters rig (`people/kenney/kenney_character.glb`) into one [AnimationLibrary] (`people/kenney/kenney_clips.res`, docs/kenney-characters.md). Run:
## godot --headless --path . --script tools/kenney_retarget.gd [-- --out=res://...kenney_clips.res]
## Kenney ships three clips (idle, run, jump); the rest of the family's set comes from the kit's own clips, mirrored (right-handed gun) and made as the game makes them, then carried onto
## this rig bone by bone by its turn from rest in skeleton space (the shared `ual_retarget.gd` method). Both rigs rest in a T-pose, legs and spine straight, so the turns line up.
## The kit's body travel moves the rig's `HipsCtrl` by the leg-length ratio; bone lengths stay Kenney's.

const KENNEY := "res://addons/dot_player_char/people/kenney/kenney_character.glb"
const KENNEY_OUT := "res://addons/dot_player_char/people/kenney/kenney_clips.res"

## Family clip name -> body treatment: `grounded` (lower foot on the floor each frame), `lifted` (moved once so the loop's lowest foot is on it; a run keeps its flight),
## `free` (the kit's hip travel, scaled), `floor` (moved once so the lowest bone of the clip rests just above the floor: a body lying down).
const FAMILY := {
	&"walk": "grounded", &"walk_gun": "grounded", &"idle_gun": "grounded", &"run_gun": "lifted",
	&"crouch": "grounded", &"crouch_walk": "grounded",
	&"fall": "free", &"land": "grounded", &"death": "floor", &"crawl": "floor",
}

## Kenney bone -> kit bone whose turn it takes. The kit's pelvis is `Body` and its spine starts at `Hips`; its palm is `Middle1`
## (the wrist), its fingers' first joints `Index2`/`Pinky2`. Bones not listed (the foot, knee and roll controls) stay at rest.
const KMAP := {
	"Hips": "Body", "Spine": "Hips", "Chest": "Abdomen", "UpperChest": "Torso", "Neck": "Neck", "Head": "Head",
	"LeftShoulder": "Shoulder.L", "LeftArm": "UpperArm.L", "LeftForeArm": "LowerArm.L", "LeftHand": "Middle1.L",
	"LeftHandIndex1": "Index2.L", "LeftHandIndex2": "Index3.L", "LeftHandIndex3": "Index3.L",
	"LeftHandThumb1": "Thumb1.L", "LeftHandThumb2": "Thumb2.L",
	"RightShoulder": "Shoulder.R", "RightArm": "UpperArm.R", "RightForeArm": "LowerArm.R", "RightHand": "Middle1.R",
	"RightHandIndex1": "Index2.R", "RightHandIndex2": "Index3.R", "RightHandIndex3": "Index3.R",
	"RightHandThumb1": "Thumb1.R", "RightHandThumb2": "Thumb2.R",
	"LeftUpLeg": "UpperLeg.L", "LeftLeg": "LowerLeg.L", "LeftFoot": "Foot.L", "LeftToes": "Foot.L",
	"RightUpLeg": "UpperLeg.R", "RightLeg": "LowerLeg.R", "RightFoot": "Foot.R", "RightToes": "Foot.R",
}

## Bones the clips key: the body and everything under it. The controls are not deform bones.
const DEFORM_ROOT := "HipsCtrl"

## How far above the floor a lying body's lowest bone sits, in the rig's own units (the body is 3.77 tall; a lying body is about 0.3 thick).
const FLOOR_CLEARANCE := 0.12

const KENNEY_FPS := 30.0

var _to_rest: Array = []


func _initialize() -> void:
	var out := KENNEY_OUT
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	var kenney := (load(KENNEY) as PackedScene).instantiate()
	var to := kenney.find_children("*", "Skeleton3D", true, false).front() as Skeleton3D
	var prefix := String(kenney.get_path_to(to))
	var matt := (load(MATT) as PackedScene).instantiate()
	var from := matt.find_children("*", "Skeleton3D", true, false).front() as Skeleton3D
	# The kit's clips as the game builds them: mirrored so the gun is in the right hand, then the crouch and the rest made.
	var library := DotHumanoidClips.synthesise(DotHumanoidClips.mirror(DotHumanoidClips.library_from(DotHumanoidClips.clips_of(matt))), from)

	var result := AnimationLibrary.new()
	var native := kenney.find_child("AnimationPlayer", true, false) as AnimationPlayer
	for clip in native.get_animation_list():
		var kept := native.get_animation(clip).duplicate(true) as Animation
		kept.loop_mode = Animation.LOOP_LINEAR if DotHumanoidClips.LOOPING.has(StringName(clip)) else Animation.LOOP_NONE
		var _n := result.add_animation(clip, kept)
		print("NATIVE ", clip, " ", kept.length, " s, ", kept.get_track_count(), " tracks")
	var failed := false
	for name: StringName in FAMILY:
		if not library.has_animation(name):
			printerr("the kit has no clip ", name)
			failed = true
			continue
		var made := _bake_kenney(library.get_animation(name), from, to, prefix, String(FAMILY[name]))
		made.loop_mode = Animation.LOOP_LINEAR if DotHumanoidClips.LOOPING.has(name) else Animation.LOOP_NONE
		var _a := result.add_animation(name, made)
		print("BAKED %s: %.2f s, %d tracks, mode %s" % [name, made.length, made.get_track_count(), FAMILY[name]])
	var err := ResourceSaver.save(result, out, ResourceSaver.FLAG_COMPRESS)
	print("SAVED ", out, " ", err, " ", FileAccess.get_file_as_bytes(out).size(), " bytes")
	kenney.free()
	matt.free()
	quit(1 if failed or err != OK else 0)


func _bake_kenney(source: Animation, from: Skeleton3D, to: Skeleton3D, prefix: String, mode: String) -> Animation:
	var from_rest := _rest_globals(from)
	var to_rest := _rest_globals(to)
	_to_rest = to_rest
	var from_prefix := _prefix_of(source)
	var thigh_to := (to_rest[to.find_bone("LeftUpLeg")] as Transform3D).origin.y - (to_rest[to.find_bone("LeftFoot")] as Transform3D).origin.y
	var thigh_from := (from_rest[from.find_bone("UpperLeg.L")] as Transform3D).origin.y - (from_rest[from.find_bone("Foot.L")] as Transform3D).origin.y
	var ratio := thigh_to / maxf(thigh_from, 0.01)
	var feet := [to.find_bone("LeftFoot"), to.find_bone("RightFoot")]
	var floor_y := minf((to_rest[feet[0]] as Transform3D).origin.y, (to_rest[feet[1]] as Transform3D).origin.y)
	var root := to.find_bone(DEFORM_ROOT)

	# The bones that move: the deform root and its descendants.
	var moving: Array[int] = []
	for i in to.get_bone_count():
		var cursor := i
		while cursor >= 0 and cursor != root:
			cursor = to.get_bone_parent(cursor)
		if cursor == root:
			moving.append(i)

	var made := Animation.new()
	made.length = source.length
	var tracks := {}
	for i in moving:
		var path := NodePath("%s:%s" % [prefix, to.get_bone_name(i)])
		var rt := made.add_track(Animation.TYPE_ROTATION_3D)
		made.track_set_path(rt, path)
		var pt := made.add_track(Animation.TYPE_POSITION_3D)
		made.track_set_path(pt, path)
		tracks[i] = [rt, pt]

	var frames := maxi(1, roundi(source.length * KENNEY_FPS))
	var poses: Array = []
	for frame in frames + 1:
		var kit := _globals(_locals(source, from_prefix, source.length * float(frame) / float(frames), from), from)
		var g := []
		g.resize(to.get_bone_count())
		for i in to.get_bone_count():
			_place_kenney(i, to, to_rest, from, from_rest, kit, ratio, g)
		poses.append(g)

	var shift := 0.0
	if mode == "lifted":
		var lowest := INF
		for g: Array in poses:
			lowest = minf(lowest, minf((g[feet[0]] as Transform3D).origin.y, (g[feet[1]] as Transform3D).origin.y))
		shift = floor_y - lowest
	elif mode == "floor":
		var lowest := INF
		for g: Array in poses:
			for i in moving:
				lowest = minf(lowest, (g[i] as Transform3D).origin.y)
		shift = FLOOR_CLEARANCE - lowest

	for frame in frames + 1:
		var g: Array = poses[frame]
		var down := shift
		if mode == "grounded":
			down = floor_y - minf((g[feet[0]] as Transform3D).origin.y, (g[feet[1]] as Transform3D).origin.y)
		for i in g.size():
			if to.get_bone_parent(i) < 0 or moving.has(i):
				g[i] = Transform3D((g[i] as Transform3D).basis, (g[i] as Transform3D).origin + Vector3(0.0, down, 0.0))
		var time := source.length * float(frame) / float(frames)
		for i in moving:
			var parent := to.get_bone_parent(i)
			var local: Transform3D = g[i] if parent < 0 else (g[parent] as Transform3D).affine_inverse() * (g[i] as Transform3D)
			var _r := made.rotation_track_insert_key(tracks[i][0], time, local.basis.get_rotation_quaternion().normalized())
			var _p := made.position_track_insert_key(tracks[i][1], time, local.origin)
	_drop_still_keys(made)
	return made


## Bone [param i]'s global pose in the kit's pose [param kit]: its rest hung off its parent's new pose, turned as the kit's bone is.
## The deform root also moves by the kit's body travel.
func _place_kenney(i: int, to: Skeleton3D, to_rest: Array, from: Skeleton3D, from_rest: Array, kit: Array, ratio: float, g: Array) -> Transform3D:
	if g[i] != null:
		return g[i]
	var name := to.get_bone_name(i)
	var parent := to.get_bone_parent(i)
	var rest: Transform3D = to_rest[i]
	var turn := Basis.IDENTITY
	if KMAP.has(name):
		var j := from.find_bone(KMAP[name])
		if j < 0:
			printerr("the kit has no bone ", KMAP[name])
		else:
			turn = (kit[j] as Transform3D).basis.orthonormalized() * (from_rest[j] as Transform3D).basis.orthonormalized().inverse()
	var origin := rest.origin
	if name == DEFORM_ROOT:
		var body := from.find_bone("Body")
		origin = rest.origin + ((kit[body] as Transform3D).origin - (from_rest[body] as Transform3D).origin) * ratio
	elif parent >= 0:
		var p := _place_kenney(parent, to, to_rest, from, from_rest, kit, ratio, g)
		origin = p * ((to_rest[parent] as Transform3D).affine_inverse() * rest.origin)
	g[i] = Transform3D(turn * rest.basis, origin)
	return g[i]
