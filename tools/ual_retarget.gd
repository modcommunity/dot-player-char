extends SceneTree

## Bakes clips from Quaternius' Universal Animation Library (CC0) onto the people's rig and saves
## them as one small [AnimationLibrary] the figure adds over its made clips
## (`people/people_ual.res`, see docs/people.md#real-clips-from-the-universal-animation-library).
##
## [codeblock]
## godot --headless --path . --script tools/ual_retarget.gd -- --ual=/path/UAL1_Standard.glb [--out=res://addons/dot_player_char/people/people_ual.res] [--clips=sit=Sitting_Idle_Loop]
## [/codeblock]
##
## The library is a different skeleton (65 bones, a hand and five three-joint fingers, the feet
## under the shins) from the kit's (43 bones, the feet hanging off the root for its leg IK), and
## a different size (1.8 against 1.1). Both rest in a T pose facing +Z, so a clip is carried by
## how far each bone turned from rest in skeleton space, not by its local rotation: for each
## mapped bone `turn = ual_global * ual_rest_global^-1`, and the kit's bone is `turn * its own
## rest_global`. Bone lengths stay the kit's (a key's position is its rest offset under the new
## parent), the hips' travel is scaled by the leg-length ratio, and a foot is put where its shin
## now ends. Grounded clips are then moved down (or up) until the lower foot is where the rest
## pose's feet are.
##
## The output is authored on the kit's skeleton as the library has it, right-handed: it is added
## after [method DotHumanoidClips.mirror], not before.

const MATT := "res://addons/dot_player_char/people/people_matt.glb"
const OUT := "res://addons/dot_player_char/people/people_ual.res"

## The family's clip name, the library's clip name, and what is done with the body: `grounded`
## (the lower foot put back on the floor), `free` (left where the clip has it) or `upright` (a
## prone clip stood up about the hips, for one the figure lays down itself, like the swim).
const CLIPS := {
	&"sit": ["Sitting_Idle_Loop", "grounded"],
}

## Kit bone -> library bone. The kit's `Middle1`, `Index1` and `Pinky1` all start at the wrist
## and are the palm, so they follow the hand; their second and third joints follow the fingers'
## first and second.
const MAP := {
	"Root": "root", "Body": "pelvis", "Hips": "spine_01", "Abdomen": "spine_02", "Torso": "spine_03",
	"Neck": "neck_01", "Head": "Head",
	"Shoulder.L": "clavicle_l", "UpperArm.L": "upperarm_l", "LowerArm.L": "lowerarm_l",
	"Middle1.L": "hand_l", "Middle2.L": "middle_01_l", "Middle3.L": "middle_02_l",
	"Index1.L": "hand_l", "Index2.L": "index_01_l", "Index3.L": "index_02_l",
	"Pinky1.L": "hand_l", "Pinky2.L": "pinky_01_l", "Pinky3.L": "pinky_02_l",
	"Thumb1.L": "thumb_01_l", "Thumb2.L": "thumb_02_l",
	"Shoulder.R": "clavicle_r", "UpperArm.R": "upperarm_r", "LowerArm.R": "lowerarm_r",
	"Middle1.R": "hand_r", "Middle2.R": "middle_01_r", "Middle3.R": "middle_02_r",
	"Index1.R": "hand_r", "Index2.R": "index_01_r", "Index3.R": "index_02_r",
	"Pinky1.R": "hand_r", "Pinky2.R": "pinky_01_r", "Pinky3.R": "pinky_02_r",
	"Thumb1.R": "thumb_01_r", "Thumb2.R": "thumb_02_r",
	"UpperLeg.L": "thigh_l", "LowerLeg.L": "calf_l", "Foot.L": "foot_l",
	"UpperLeg.R": "thigh_r", "LowerLeg.R": "calf_r", "Foot.R": "foot_r",
}

## Kit bones that hang off the root but belong to a shin: put at the shin's end (the foot) or
## carried with the knee (the IK pole), as the rest pose has them relative to the shin.
const ON_SHIN := {"Foot.L": "LowerLeg.L", "Foot.R": "LowerLeg.R", "PoleTarget.L": "LowerLeg.L", "PoleTarget.R": "LowerLeg.R"}

## Keys a second. The clips kept are slow (a seated idle), so this is plenty and keeps the file small.
const FPS := 15.0


func _initialize() -> void:
	var ual_path := ""
	var out := OUT
	var clips := CLIPS.duplicate()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ual="):
			ual_path = arg.trim_prefix("--ual=")
		elif arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg.begins_with("--clips="):
			clips.clear()
			for pair in arg.trim_prefix("--clips=").split(","):
				var parts := pair.split("=")
				# `name=Clip!` leaves the feet where they are; `name=Clip^` also stands a prone clip up.
				var mode := "grounded"
				if parts[1].ends_with("!"):
					mode = "free"
				elif parts[1].ends_with("^"):
					mode = "upright"
				clips[StringName(parts[0])] = [parts[1].trim_suffix("!").trim_suffix("^"), mode]
	if ual_path == "":
		printerr("--ual=<UAL1_Standard.glb> is required")
		quit(2)
		return

	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(ual_path, state) != OK:
		printerr("cannot read ", ual_path)
		quit(1)
		return
	var ual := doc.generate_scene(state)
	var ual_skeleton := ual.find_children("*", "Skeleton3D", true, false).front() as Skeleton3D
	var ual_player := ual.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var matt := (load(MATT) as PackedScene).instantiate()
	var skeleton := matt.find_children("*", "Skeleton3D", true, false).front() as Skeleton3D
	var prefix := String(matt.get_path_to(skeleton))

	var library := AnimationLibrary.new()
	for name: StringName in clips:
		var source := String(clips[name][0])
		if not ual_player.has_animation(source):
			printerr("no clip ", source)
			continue
		var made := _bake(ual_player.get_animation(source), ual_skeleton, skeleton, prefix, String(clips[name][1]))
		var _a := library.add_animation(name, made)
		print("BAKED %s from %s: %.2f s, %d tracks" % [name, source, made.length, made.get_track_count()])

	var err := ResourceSaver.save(library, out, ResourceSaver.FLAG_COMPRESS)
	print("SAVED ", out, " ", err, " ", FileAccess.get_file_as_bytes(out).size(), " bytes")
	matt.free()
	ual.free()
	quit(0 if err == OK else 1)


func _bake(source: Animation, from: Skeleton3D, to: Skeleton3D, prefix: String, mode: String) -> Animation:
	var from_rest := _rest_globals(from)
	var to_rest := _rest_globals(to)
	var from_prefix := _prefix_of(source)
	# The hips' travel at the kit's size: hip height over the floor, each rig's own.
	var ratio: float = (to_rest[to.find_bone("UpperLeg.L")].origin.y - to_rest[to.find_bone("Foot.L")].origin.y) \
		/ maxf(from_rest[from.find_bone("thigh_l")].origin.y, 0.01)
	var floor_y: float = minf(to_rest[to.find_bone("Foot.L")].origin.y, to_rest[to.find_bone("Foot.R")].origin.y)

	var made := Animation.new()
	made.length = source.length
	made.loop_mode = source.loop_mode
	var tracks := {}
	for i in to.get_bone_count():
		var path := NodePath("%s:%s" % [prefix, to.get_bone_name(i)])
		var rt := made.add_track(Animation.TYPE_ROTATION_3D)
		made.track_set_path(rt, path)
		var pt := made.add_track(Animation.TYPE_POSITION_3D)
		made.track_set_path(pt, path)
		tracks[i] = [rt, pt]

	# Standing a prone clip up: the turn that takes its first frame's spine (pelvis to neck) to
	# straight up, about the hips, the hips then put back at the rest pose's height.
	var stand := Basis.IDENTITY
	if mode == "upright":
		var first := _globals(_locals(source, from_prefix, 0.0, from), from)
		var spine: Vector3 = (first[from.find_bone("neck_01")] as Transform3D).origin - (first[from.find_bone("pelvis")] as Transform3D).origin
		stand = Basis(Quaternion(spine.normalized(), Vector3.UP))
	var body := to.find_bone("Body")

	var frames := maxi(1, roundi(source.length * FPS))
	for frame in frames + 1:
		var time := source.length * float(frame) / float(frames)
		var ual := _globals(_locals(source, from_prefix, time, from), from)
		var g := []
		g.resize(to.get_bone_count())
		for i in to.get_bone_count():
			_place(i, to, to_rest, from, from_rest, ual, ratio, g)
		if mode == "upright":
			var hips: Vector3 = (g[body] as Transform3D).origin
			var at: Vector3 = (to_rest[body] as Transform3D).origin
			for i in g.size():
				if to.get_bone_parent(i) >= 0:
					var t: Transform3D = g[i]
					g[i] = Transform3D(stand * t.basis, at + stand * (t.origin - hips))
		if mode == "grounded":
			var lowest: float = minf(g[to.find_bone("Foot.L")].origin.y, g[to.find_bone("Foot.R")].origin.y)
			var down := Vector3(0.0, floor_y - lowest, 0.0)
			for i in g.size():
				if to.get_bone_parent(i) >= 0:
					g[i] = Transform3D(g[i].basis, g[i].origin + down)
		for i in g.size():
			var parent := to.get_bone_parent(i)
			var local: Transform3D = g[i] if parent < 0 else (g[parent] as Transform3D).affine_inverse() * (g[i] as Transform3D)
			var _r := made.rotation_track_insert_key(tracks[i][0], time, local.basis.get_rotation_quaternion().normalized())
			var _p := made.position_track_insert_key(tracks[i][1], time, local.origin)
	_drop_still_keys(made)
	return made


## Bone [param i]'s new global pose, its parent's first.
func _place(i: int, to: Skeleton3D, to_rest: Array, from: Skeleton3D, from_rest: Array, ual: Array, ratio: float, g: Array) -> Transform3D:
	if g[i] != null:
		return g[i]
	var name := to.get_bone_name(i)
	var parent := to.get_bone_parent(i)
	var rest: Transform3D = to_rest[i]
	var turn := Basis.IDENTITY
	if MAP.has(name):
		var j := from.find_bone(MAP[name])
		turn = (ual[j] as Transform3D).basis.orthonormalized() * (from_rest[j] as Transform3D).basis.orthonormalized().inverse()
	var basis := turn * rest.basis
	var origin := rest.origin
	if ON_SHIN.has(name):
		var shin := to.find_bone(ON_SHIN[name])
		var shin_now := _place(shin, to, to_rest, from, from_rest, ual, ratio, g)
		origin = shin_now * ((to_rest[shin] as Transform3D).affine_inverse() * rest.origin)
		if not MAP.has(name):
			basis = rest.basis
	elif name == "Body":
		var j := from.find_bone("pelvis")
		origin = rest.origin + ((ual[j] as Transform3D).origin - (from_rest[j] as Transform3D).origin) * ratio
	elif parent >= 0:
		var p := _place(parent, to, to_rest, from, from_rest, ual, ratio, g)
		origin = p * ((to_rest[parent] as Transform3D).affine_inverse() * rest.origin)
	g[i] = Transform3D(basis, origin)
	return g[i]


## A track whose keys are all the same becomes one key: most bones of a seated idle only breathe.
func _drop_still_keys(animation: Animation) -> void:
	for t in animation.get_track_count():
		var n := animation.track_get_key_count(t)
		if n < 2:
			continue
		var first: Variant = animation.track_get_key_value(t, 0)
		var still := true
		for k in range(1, n):
			var v: Variant = animation.track_get_key_value(t, k)
			if (v is Quaternion and not (v as Quaternion).is_equal_approx(first)) or (v is Vector3 and ((v as Vector3) - (first as Vector3)).length() > 0.0005):
				still = false
				break
		if still:
			for k in range(n - 1, 0, -1):
				animation.track_remove_key(t, k)


func _rest_globals(skeleton: Skeleton3D) -> Array:
	var out := []
	for i in skeleton.get_bone_count():
		out.append(skeleton.get_bone_global_rest(i))
	return out


func _prefix_of(animation: Animation) -> String:
	for t in animation.get_track_count():
		var path := animation.track_get_path(t)
		if path.get_subname_count() > 0:
			return String(path.get_concatenated_names())
	return "Skeleton3D"


func _locals(animation: Animation, prefix: String, time: float, skeleton: Skeleton3D) -> Array:
	var out := []
	for i in skeleton.get_bone_count():
		var rest := skeleton.get_bone_rest(i)
		var path := NodePath("%s:%s" % [prefix, skeleton.get_bone_name(i)])
		var rt := animation.find_track(path, Animation.TYPE_ROTATION_3D)
		var pt := animation.find_track(path, Animation.TYPE_POSITION_3D)
		var q := rest.basis.get_rotation_quaternion() if rt < 0 else animation.rotation_track_interpolate(rt, time)
		var p := rest.origin if pt < 0 else animation.position_track_interpolate(pt, time)
		out.append(Transform3D(Basis(q), p))
	return out


func _globals(locals: Array, skeleton: Skeleton3D) -> Array:
	var out := []
	for i in locals.size():
		var parent := skeleton.get_bone_parent(i)
		out.append(locals[i] if parent < 0 else (out[parent] as Transform3D) * (locals[i] as Transform3D))
	return out
