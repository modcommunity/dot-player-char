class_name DotHumanoidActions
extends RefCounted

## The starter emotes, poses and gestures of dot-user-avatar (the site's BUILTIN_AVATAR_ACTIONS ids)
## as clips on the people's rig, and the path an uploaded humanoid clip takes onto it.
##
## Made like the sit and the climb: each pose is bone directions worked out on the idle's first
## frame in skeleton space (+X the figure's left, +Y up, +Z forward), keyed at 20 frames a second.
## No art is downloaded or vendored: the kit's own wave and yes are the `wave` and `nod`, the sit
## is the Universal Animation Library's (both CC0, credited in README.md), the rest is geometry.

## Ids with a clip made here. `wave` and `nod` are the kit's, `sit` the real sit.
const MADE: Array[StringName] = [&"point", &"thumbs_up", &"shrug", &"cheer", &"dance", &"clap", &"bow",
	&"salute", &"arms_crossed", &"hands_on_hips"]

## Ids played as the whole body (the legs too), only while standing still; the rest are the upper
## body over whatever the legs are doing.
const FULL_BODY: Array[StringName] = [&"sit", &"dance"]

## Seconds of each made clip. A looping one is a cycle, a held pose one second of the same pose.
const LENGTHS := {
	&"point": 1.4, &"thumbs_up": 1.5, &"shrug": 1.3, &"cheer": 1.8, &"dance": 1.6, &"clap": 1.0,
	&"bow": 2.0, &"salute": 1.0, &"arms_crossed": 1.0, &"hands_on_hips": 1.0,
}

const FPS := 20.0

## Which kit bone a humanoid profile bone is, for [method rename_humanoid]. The kit has no hand
## bone and hangs its feet off the root, so neither is mapped.
const KIT_BONES := {
	"Hips": "Hips", "Spine": "Abdomen", "Chest": "Torso", "Neck": "Neck", "Head": "Head",
	"LeftShoulder": "Shoulder.L", "LeftUpperArm": "UpperArm.L", "LeftLowerArm": "LowerArm.L",
	"LeftUpperLeg": "UpperLeg.L", "LeftLowerLeg": "LowerLeg.L",
	"RightShoulder": "Shoulder.R", "RightUpperArm": "UpperArm.R", "RightLowerArm": "LowerArm.R",
	"RightUpperLeg": "UpperLeg.R", "RightLowerLeg": "LowerLeg.R",
}


## The clip name an action id plays: the kit's `wave` and `yes` (nod), the made sit, else `act_<id>`.
static func clip_name(id: StringName) -> StringName:
	match id:
		&"wave":
			return DotHumanoidClips.WAVE
		&"nod":
			return DotHumanoidClips.YES
		&"sit":
			return DotHumanoidClips.SIT
	return StringName("act_" + String(id))


## Whether [param id] replaces the legs' clip while it plays.
static func is_full_body(id: StringName) -> bool:
	return FULL_BODY.has(id)


## [param library] (in place) with a clip for each of [constant MADE], built from [param idle] on
## [param skeleton] (the clip body's). Returns it.
static func add_to(library: AnimationLibrary, idle: Animation, skeleton: Skeleton3D) -> AnimationLibrary:
	if library == null or idle == null or skeleton == null:
		return library
	for id in MADE:
		var name := clip_name(id)
		if library.has_animation(name):
			library.remove_animation(name)
		var _a := library.add_animation(name, _build(id, idle, skeleton))
	return library


## [param animation]'s tracks renamed from [param bone_map]'s bones to the kit's, rotation only,
## each with its source rest in the result's second element, ready for
## [method DotHumanoidClips.retarget]. For a clip a member uploaded on a humanoid rig: the
## [BoneMap] says which of its bones is the hips, spine and so on, and nothing else is trusted.
##
## Returns {"animation": Animation, "rests": Dictionary} with rests keyed by kit bone name, from
## [param source_rests] (source bone name to local rest, [method DotHumanoidClips.rests_of]).
## Retargeting moves each key off the source rest and onto the kit's, so it needs the two rigs to
## rest in the same stance; an upload in a T-pose against the kit's A-pose bends the arms by the
## difference, which is why the upload path asks for the clip's own rest.
static func rename_humanoid(animation: Animation, bone_map: BoneMap, source_rests: Dictionary) -> Dictionary:
	var out := Animation.new()
	out.length = animation.length
	out.loop_mode = animation.loop_mode
	var rests := {}
	if bone_map == null:
		return {"animation": out, "rests": rests}
	var prefix := DotHumanoidClips._skeleton_prefix(animation)
	for t in animation.get_track_count():
		if animation.track_get_type(t) != Animation.TYPE_ROTATION_3D:
			continue
		var source := String(animation.track_get_path(t).get_concatenated_subnames())
		var profile := String(bone_map.find_profile_bone_name(StringName(source)))
		if not KIT_BONES.has(profile):
			continue
		var kit: String = KIT_BONES[profile]
		var nt := out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(nt, NodePath("%s:%s" % [prefix, kit]))
		for k in animation.track_get_key_count(t):
			var _i := out.rotation_track_insert_key(nt, animation.track_get_key_time(t, k), animation.track_get_key_value(t, k))
		if source_rests.has(source):
			rests[kit] = source_rests[source]
	return {"animation": out, "rests": rests}


static func _build(id: StringName, idle: Animation, skeleton: Skeleton3D) -> Animation:
	var length: float = LENGTHS[id]
	var made := Animation.new()
	made.length = length
	made.loop_mode = Animation.LOOP_LINEAR if id == &"dance" else Animation.LOOP_NONE
	var prefix := DotHumanoidClips._skeleton_prefix(idle)
	var tracks := {}
	for i in skeleton.get_bone_count():
		var path := NodePath("%s:%s" % [prefix, skeleton.get_bone_name(i)])
		var rt := made.add_track(Animation.TYPE_ROTATION_3D)
		made.track_set_path(rt, path)
		var pt := made.add_track(Animation.TYPE_POSITION_3D)
		made.track_set_path(pt, path)
		tracks[i] = [rt, pt]
	var frames := int(ceil(length * FPS))
	for frame in frames + 1:
		var time := length * float(frame) / float(frames)
		var g := DotHumanoidClips._globals(DotHumanoidClips._locals(idle, 0.0, skeleton), skeleton)
		_pose(id, g, skeleton, time, length)
		var locals := DotHumanoidClips._back_to_locals(g, skeleton)
		for i in locals.size():
			var local: Transform3D = locals[i]
			var _r := made.rotation_track_insert_key(tracks[i][0], time, local.basis.get_rotation_quaternion().normalized())
			var _p := made.position_track_insert_key(tracks[i][1], time, local.origin)
	return made


## Bones moved into [param id]'s pose at [param t] seconds. [param k] eases a one-shot in and out
## so its ends are the idle; a held pose and a loop are at full strength throughout.
static func _pose(id: StringName, g: Array, sk: Skeleton3D, t: float, length: float) -> void:
	var held := id == &"salute" or id == &"arms_crossed" or id == &"hands_on_hips" or id == &"clap" or id == &"dance"
	var k := 1.0 if held else minf(smoothstep(0.0, 0.25, t), smoothstep(0.0, 0.25, length - t))
	var phase := TAU * t / length
	match id:
		&"point":
			_arm(g, sk, ".R", Vector3(0.12, 0.08, 1.0), Vector3(0.08, 0.1, 1.0), k)
		&"thumbs_up":
			_arm(g, sk, ".R", Vector3(0.3, -0.2, 0.9), Vector3(0.05, 1.0, 0.3 + 0.1 * sin(phase * 2.0)), k)
		&"shrug":
			for side: String in [".L", ".R"]:
				_lift_shoulder(g, sk, side, 0.4 * k)
				_arm(g, sk, side, Vector3(0.6, -0.75, 0.05), Vector3(0.55, 0.4, 0.75), k)
		&"cheer":
			var pump := sin(phase * 3.0)
			for side: String in [".L", ".R"]:
				_arm(g, sk, side, Vector3(0.4 + 0.1 * pump, 0.85, 0.1), Vector3(0.25, 1.0 + 0.2 * pump, 0.1), k)
		&"clap":
			var c := 0.5 + 0.5 * cos(phase * 2.0)
			for side: String in [".L", ".R"]:
				_arm(g, sk, side, Vector3(0.3, -0.45, 0.9), Vector3(0.25 - 0.8 * c, 0.25, 0.8))
		&"bow":
			var bend := smoothstep(0.0, 0.35, t) * smoothstep(0.0, 0.35, length - t)
			_bend(g, sk, "Abdomen", deg_to_rad(28.0) * bend)
			_bend(g, sk, "Torso", deg_to_rad(30.0) * bend)
			_bend(g, sk, "Neck", deg_to_rad(10.0) * bend)
		&"salute":
			_arm(g, sk, ".R", Vector3(0.75, 0.2, 0.1), Vector3(-0.65, 0.75, 0.35))
		&"arms_crossed":
			for side: String in [".L", ".R"]:
				_arm(g, sk, side, Vector3(0.1, -0.9, 0.35), Vector3(-0.95, 0.15, 0.3))
		&"hands_on_hips":
			for side: String in [".L", ".R"]:
				_arm(g, sk, side, Vector3(0.6, -0.7, -0.15), Vector3(-0.5, -0.6, 0.6))
		&"dance":
			_dance(g, sk, phase)


static func _dance(g: Array, sk: Skeleton3D, phase: float) -> void:
	var torso := sk.find_bone("Torso")
	if torso >= 0:
		DotHumanoidClips._move_subtree(g, sk, torso, DotHumanoidClips._about(g[torso].origin, Basis(Vector3.UP, 0.25 * sin(phase))))
	_bend(g, sk, "Neck", deg_to_rad(6.0) * sin(phase * 2.0))
	for side: String in [".L", ".R"]:
		var offset := 0.0 if side == ".L" else PI
		var lift := 0.5 + 0.5 * sin(phase + offset)
		_arm(g, sk, side, Vector3(0.6, -0.3 + 1.1 * lift, 0.1), Vector3(0.4, 0.2 + 0.7 * lift, 0.35))
		var step := 0.5 + 0.5 * sin(phase * 2.0 + offset)
		var angle := deg_to_rad(4.0 + 32.0 * step)
		DotHumanoidClips._place_leg(g, sk, side, Vector3(0.0, -cos(angle), sin(angle)), Vector3(0.0, -1.0, 0.1))


## Both [param upper] and [param fore] are written for the left arm (X outward): the right arm
## flips X. Each moves from where the bone points now to the wanted direction by [param k].
static func _arm(g: Array, sk: Skeleton3D, side: String, upper: Vector3, fore: Vector3, k: float = 1.0) -> void:
	var u := sk.find_bone("UpperArm" + side)
	var l := sk.find_bone("LowerArm" + side)
	var h := sk.find_bone("Middle1" + side)
	if u < 0 or l < 0 or h < 0:
		return
	var o := 1.0 if side == ".L" else -1.0
	var now: Vector3 = (g[l].origin - g[u].origin).normalized()
	var want := Vector3(upper.x * o, upper.y, upper.z).normalized()
	var _a := DotHumanoidClips._turn_subtree(g, sk, u, now, now.slerp(want, k))
	now = (g[h].origin - g[l].origin).normalized()
	want = Vector3(fore.x * o, fore.y, fore.z).normalized()
	var _b := DotHumanoidClips._turn_subtree(g, sk, l, now, now.slerp(want, k))


static func _lift_shoulder(g: Array, sk: Skeleton3D, side: String, amount: float) -> void:
	var s := sk.find_bone("Shoulder" + side)
	var u := sk.find_bone("UpperArm" + side)
	if s < 0 or u < 0:
		return
	var now: Vector3 = g[u].origin - g[s].origin
	var _t := DotHumanoidClips._turn_subtree(g, sk, s, now, now + Vector3(0.0, now.length() * amount, 0.0))


## [param bone] and everything under it bent forward by [param angle] about the figure's left-right axis.
static func _bend(g: Array, sk: Skeleton3D, bone: String, angle: float) -> void:
	var i := sk.find_bone(bone)
	if i >= 0:
		DotHumanoidClips._move_subtree(g, sk, i, DotHumanoidClips._about(g[i].origin, Basis(Vector3.RIGHT, angle)))
