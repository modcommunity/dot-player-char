class_name DotRagdollPoseNativeChecks
extends RefCounted

## The ragdoll suite's native pose section: dot-sim's [code]DotSimRagdollPose[/code] against
## [method DotPlayerRagdoll._pose_bones_script] on falling skinned bodies, every bone to the bit,
## and what each costs per call. With no library it says the native half was skipped and passes;
## [code]DOT_SIM_REQUIRE_NATIVE=1[/code] (CI) fails instead. Always two checks, so the suite's count
## holds either way.

const FRAMES := 90
const BENCH_CALLS := 2000

var suite: Node


func _init(host: Node) -> void:
	suite = host


func run() -> void:
	suite._section("the native bone pose is the script's, to the bit")
	var native := DotPlayerRagdoll.native_pose_available()
	var required := OS.get_environment("DOT_SIM_REQUIRE_NATIVE") == "1"
	if not native:
		suite._line("  dot-sim's ragdoll module is not loaded: the native half is skipped")
	var yard := DotPlayerRagdolls.new()
	yard.rules.lifetime = 60.0
	yard.rules.max_count = 8
	yard.local_cap = 8
	suite._world.add_child(yard)

	# Falls that hit every path: limp, a launch, a crumple, and a face plant that turns jointed on
	# landing (its parts, and so the native plan, are rebuilt mid-fall).
	var bodies: Array[DotPlayerRagdoll] = []
	var deaths := [
		suite._death(&"limp", Vector3(1, 0, 0)),
		suite._death(&"headshot_launch", Vector3(0, 0, -1), true, 150.0),
		suite._death(&"crumple", Vector3(-1, 0, 0.3)),
		suite._death(&"face_plant", Vector3(0, 0, 1)),
	]
	for i in deaths.size():
		var person: DotHumanoidFigure = suite._person(Vector3(-20 - 4 * i, 0, 60))
		var body := yard.spawn(person, deaths[i])
		if body != null:
			bodies.append(body)
	var compared := 0
	var differ := 0
	var moved := 0
	var bones := 0
	if native:
		for f in FRAMES:
			await suite.get_tree().physics_frame
			for body in bodies:
				if not is_instance_valid(body) or body.skeleton_copy() == null:
					continue
				var skel := body.skeleton_copy()
				skel.reset_bone_poses()
				var rest := _poses(skel)
				body._pose_bones_script()
				var by_script := _poses(skel)
				skel.reset_bone_poses()
				body._pose_bones_native()
				var by_native := _poses(skel)
				compared += 1
				bones = skel.get_bone_count()
				if by_script != by_native:
					differ += 1
				if by_script != rest:
					moved += 1
	suite._check((native and bodies.size() == 4 and compared >= FRAMES * 4 and differ == 0 and moved == compared)
			or (not native and not required),
		"%d falling skinned bodies, %d poses of %d bones: every bone's position, rotation and scale the same bytes (%d differ%s)"
			% [bodies.size(), compared, bones, differ, "" if native else "; skipped, no library"])

	if native and not bodies.is_empty() and is_instance_valid(bodies[0]):
		var body := bodies[0]
		var t0 := Time.get_ticks_usec()
		for i in BENCH_CALLS:
			body._pose_bones_script()
		var t1 := Time.get_ticks_usec()
		for i in BENCH_CALLS:
			body._pose_bones_native()
		var t2 := Time.get_ticks_usec()
		suite._line("  per pose: script %.1f us, native %.1f us (%d calls each, %d bones)"
			% [float(t1 - t0) / BENCH_CALLS, float(t2 - t1) / BENCH_CALLS, BENCH_CALLS, body.skeleton_copy().get_bone_count()])
	# The switch: off keeps the script and makes no native poser.
	var was := DotPlayerRagdoll.native_pose
	DotPlayerRagdoll.native_pose = false
	var person: DotHumanoidFigure = suite._person(Vector3(-40, 0, 60))
	var plain := yard.spawn(person, suite._death(&"limp"))
	await suite.get_tree().physics_frame
	var stayed_script := plain != null and plain.get(&"_poser") == null
	DotPlayerRagdoll.native_pose = was
	var planned := false
	if plain != null:
		plain._pose_bones()
		planned = plain.get(&"_poser") != null
	suite._check(stayed_script and planned == native,
		"native_pose off keeps the script path, on plans the native poser when the library has it (%s, %s)"
			% [stayed_script, planned])

	yard.clear()


## Every bone's pose as bytes: position, rotation and scale.
static func _poses(skel: Skeleton3D) -> PackedByteArray:
	var out := []
	for b in skel.get_bone_count():
		out.append(skel.get_bone_pose_position(b))
		out.append(skel.get_bone_pose_rotation(b))
		out.append(skel.get_bone_pose_scale(b))
	return var_to_bytes(out)
