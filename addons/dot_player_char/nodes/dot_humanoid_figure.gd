class_name DotHumanoidFigure
extends "dot_humanoid_figure_clips.gd"

## One of the family's people, drawn: a skinned body from `people/` wearing a [DotHumanoidLook]'s colours, playing
## [DotHumanoidClips] from how it moves, holding a weapon, and handing its skeleton to [DotPlayerRagdoll] on death.
## Client side only. The upper body is written over the locomotion pose after the clip (LOD rates in docs/people.md).

## Builds the figure for [param p_look], [param p_height] metres tall, feet at this node's origin,
## facing -Z.
func build(p_look: DotHumanoidLook, p_height: float = 1.8) -> void:
	look = p_look if p_look != null else DotHumanoidLook.stock(0)
	height = p_height
	_forget_body()

	var scene := DotHumanoidAssets.scene(body_path(look.body))
	if scene != null:
		_model = scene.instantiate() as Node3D

	if _model == null:
		# A capsule rather than nothing: an invisible player is worse than a grey one.
		DotLog.warn(CHANNEL, "no body model; drawing a capsule", {"body": String(look.body)})
		_model = DotHumanoidFrames.capsule(height, look.top)
		add_child(_model)
		from_art = false
		return

	_model.name = "Body"
	add_child(_model)
	from_art = true
	_skeleton = _model.find_children("*", "Skeleton3D", true, false).front() as Skeleton3D
	var meshes := _model.find_children("*", "MeshInstance3D", true, false)
	_mesh = meshes.front() as MeshInstance3D if not meshes.is_empty() else null
	_details.clear()
	_detail = 0
	if DotHumanoidLook.registered.has(look.body):
		_details = DotHumanoidAssets.detail_meshes(_model)
	if not _details.is_empty():
		# One instance swaps its mesh by distance, so the ragdoll, the gibs and the own view see one body, not three.
		_mesh = _model.find_child("LOD0", true, false) as MeshInstance3D
		for other: MeshInstance3D in meshes:
			if other != _mesh:
				other.get_parent().remove_child(other)
				other.free()
		# The clips' tracks name `CharacterArmature/Skeleton3D`; a body from another exporter has its own names.
		_skeleton.name = "Skeleton3D"
		if _skeleton.get_parent() != _model:
			_skeleton.get_parent().name = "CharacterArmature"
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
		_mesh.lod_bias = lod_bias
		_mesh.visibility_range_end = draw_range

	# The kit faces +Z and this family's forward is -Z; scaled to the height asked for, measured
	# from the mesh rather than assumed.
	var tall := DotHumanoidFrames.measure(_mesh, _model)
	var s := height / maxf(tall, 0.01)
	_model_basis = Basis(Vector3.UP, PI).scaled(Vector3.ONE * s)
	_model_origin = Vector3.ZERO
	_model.transform = Transform3D(_model_basis, _model_origin)
	_floor_ankles.clear()
	if _skeleton != null:
		_skel_to_model = DotHumanoidFrames.to_model(_skeleton, _model)
		for names: Array in DotHumanoidLegs.LEGS:
			var foot := _skeleton.find_bone(names[2])
			if foot >= 0:
				_floor_ankles.append((_model.transform * _skel_to_model * _skeleton.get_bone_global_rest(foot).origin).y)

	for bone in DotHumanoidClips.UPPER_BONES:
		var i := _skeleton.find_bone(bone) if _skeleton != null else -1
		if i >= 0:
			_upper[bone] = i
			_upper_paths[bone] = NodePath("%s:%s" % [String(_model.get_path_to(_skeleton)), bone])

	_play(DotHumanoidClips.IDLE, 1.0)
	_anim.advance(0.0)


## Drops the body built before and everything cached from it, for [method build] to start over.
func _forget_body() -> void:
	clip = &""
	overlay = &""
	_ease.clear()
	_turn_limit.clear()
	_hand = null
	_crown = null
	_upper.clear()
	_upper_paths.clear()
	_support_cache.clear()
	_support_chains.clear()
	_overlay_tracks.clear()
	_aim_plans.clear()
	_strides.clear()
	_machine.forget_state()
	if _model != null:
		remove_child(_model)
		_model.queue_free()
		_model = null
		_skeleton = null
		_mesh = null
		_anim = null
	_lift_at = Vector3.INF


func _ready() -> void:
	# Always: between calls to [method animate] (a far body's skipped frames) the drawn origin still moves, and
	# [method _lift_body] follows it.
	set_process(true)


func _process(delta: float) -> void:
	if not auto_animate or delta <= 0.0:
		if global_position != _lift_at and _lifts_between_steps():
			_lift_body()
		return
	# Measured over at least AUTO_WINDOW, not frame to frame: a body carried in physics ticks or snapshots stands still on the frames between, and a per-frame measure flips the clip
	# (and pays its crossfade and stride match) several times a tick. A stop shows after AUTO_HOLD seconds without a move.
	var at := global_position
	var stepped := at != _auto_seen
	_auto_since += delta
	_auto_still += delta
	_auto_pending += delta
	if _auto_last == Vector3.INF:
		_auto_last = at
		_auto_seen = at
		_auto_since = 0.0
		_auto_still = 0.0
		_auto_velocity = Vector3.ZERO
	elif stepped:
		_auto_seen = at
		_auto_still = 0.0
		if _auto_since >= AUTO_WINDOW:
			_auto_velocity = (at - _auto_last) / _auto_since
			_auto_last = at
			_auto_since = 0.0
	elif _auto_still > AUTO_HOLD:
		_auto_velocity = Vector3.ZERO
		_auto_last = at
		_auto_since = 0.0
	# Posed when the body steps, so each drawn place has its own pose and none is drawn twice; a body standing
	# between steps keeps the last pose (the skeleton untouched, so the engine skips the skin too) for at most
	# AUTO_POSE_GAP. A body moved every frame is posed every frame.
	if not stepped and _auto_pending < AUTO_POSE_GAP:
		return
	var step := _auto_pending
	_auto_pending = 0.0
	var moved := _auto_velocity
	var motion := _motion.duplicate()
	motion["vertical"] = moved.y
	motion["on_floor"] = absf(moved.y) < 1.5
	_motion = motion
	var ground := Vector2(moved.x, moved.z).length()
	if auto_smooth_time > 0.0:
		ground = lerpf(_speed, ground, 1.0 - exp(-step / auto_smooth_time))
	animate(ground, step)


# The registered body's mesh for a camera [param distance] away.
func _pick_detail(distance: float) -> void:
	var level := 0
	for far in DotHumanoidAssets.lod_distances:
		if distance > far and level + 1 < _details.size():
			level += 1
	# Swapped on a change of level only: a figure that replaced its own mesh (the view arms' stripped copy) keeps it near.
	if level != _detail:
		_detail = level
		_mesh.mesh = _details[level]


## The look changed colours only: a new material, no rebuild.
func recolour(p_look: DotHumanoidLook) -> void:
	if p_look == null:
		return
	if look == null or p_look.body != look.body or _mesh == null:
		build(p_look, height)
		return
	look = p_look
	_mesh.material_override = material_for(look)


## Puts the figure where its player is drawn, facing [param yaw_radians] at ground [param speed],
## and advances the animation by the time since the last call.
func pose(at: Vector3, yaw_radians: float, speed: float) -> void:
	global_position = at
	rotation = Vector3(0.0, yaw_radians, 0.0)
	animate(speed, frame_delta())


## Game seconds since the last call (0 on a second call in a frame), clamped to 0.1. Game time,
## not wall clock, or a slowed or recorded frame skates the feet.
func frame_delta() -> float:
	var now := Engine.get_process_frames()
	var frames := 0 if _posed_frame < 0 else now - _posed_frame
	_posed_frame = now
	var step := get_process_delta_time() if is_inside_tree() else 0.0
	return clampf(step * frames, 0.0, 0.1)


## Advances the animation by [param delta] at ground [param speed]. [method pose] calls it; a suite
## or a contact sheet calls it directly to step time exactly.
func animate(speed: float, delta: float) -> void:
	# [method _to_figure] is read several times a step and cannot change within one unless the model is moved.
	_frame_tf_on = true
	_animate_step(speed, delta)
	_frame_tf_on = false
	_frame_tf_ok = false


func _animate_step(speed: float, p_delta: float) -> void:
	_speed = speed
	if _anim != null:
		# The figure is drawn less often far from the camera or out of view. A skipped frame does nothing but carry its time: the state, the carry, the legs' turn and the clip are all worked out on the next drawn
		# frame over the whole of it, and nothing is written to the skeleton (a write marks it dirty, and the engine then redoes every bone's global pose and the skin).
		_frame += 1
		var was_step := anim_step
		anim_step = DotHumanoidFrames.step_for_distance(self, _mesh)
		_step_distance = DotHumanoidFrames.last_distance
		_step_seen = DotHumanoidFrames.last_seen
		if not _details.is_empty():
			_pick_detail(DotHumanoidFrames.last_distance)
		# A figure coming into view (or nearer) is redrawn at once, not up to seven frames later.
		if _frame % anim_step != 0 and anim_step >= was_step:
			_owed += p_delta
			# The drawn origin still moves between drawn frames: the body follows the floor under it.
			if not is_inside_tree() or (global_position != _lift_at and _lifts_between_steps()):
				_lift_body()
			return
	var delta := p_delta + _owed
	_owed = 0.0
	# The layers drawn this frame ([constant SUPPORT_RANGE]), from the step just worked out.
	var seen := DotHumanoidFrames.last_seen if _anim != null else true
	var far := DotHumanoidFrames.last_distance if _anim != null else 0.0
	state = _machine.advance(_motion, delta, speed)
	_end_action_if_moved()
	var carry_sprint := sprinting if _motion.has("sprinting") else state == DotPlayerAnimState.RUN
	_sprint = move_toward(_sprint, 1.0 if carry_sprint and hold == Hold.GUN and not downed else 0.0, delta / SPRINT_SECONDS)
	var standing := not (downed or seated or driving) and _action_full == &"" and state != DotPlayerAnimState.DEAD
	carry.step(delta, hold == Hold.GUN and standing and state != DotPlayerAnimState.SWIM and state != DotPlayerAnimState.CLIMB)
	var grip := support_point.is_finite() or carry.support_grip.is_finite()
	_support_weight = move_toward(_support_weight, 1.0 if grip and hold == Hold.GUN and not downed else 0.0, delta / 0.15)
	var pumping := carry_sprint and _motion.has("sprinting") and hold != Hold.GUN and standing and overlay == &"" \
		and (state == DotPlayerAnimState.RUN or state == DotPlayerAnimState.WALK)
	if downed or not standing:
		arms.charge = -1.0
	arms.step(delta, pumping, _speed, _stride_fraction() if _anim != null else -1.0)

	if _anim == null:
		return
	var facing := global_basis if is_inside_tree() else basis
	legs.update(facing, _motion.get("velocity", Vector3.ZERO), delta)
	var wanted := _clip_for(state, speed)

	if overlay != &"":
		_overlay_time += delta * _overlay_rate
		if _overlay_stopping:
			_stop_time += delta

	var up := _skeleton_up()
	# Undone in the reverse of the order they were written: the turn limit last, so first.
	_turn_limit.restore(_skeleton)
	legs.restore(_skeleton)
	_play(wanted[0], wanted[1])
	var matched := _matched_rate(legs.along_speed if _motion.has("velocity") else speed, delta)
	if not is_nan(matched):
		_anim.speed_scale = matched
	_anim.advance(delta)
	_apply_overlays()
	if seen:
		_apply_aim()
	_ease.step(_skeleton, delta)
	legs.apply(_skeleton, up)
	if seen and far <= ANIM_FAR:
		_apply_carry()
	if seen and far <= SUPPORT_RANGE:
		_apply_support()
	if seen and far <= ANIM_FAR and hold != Hold.GUN:
		arms.apply(_skeleton, _model, _anim.get_animation(clip), _to_figure())
	_apply_swim(delta)
	# After the body's tilt: a plant is a world point, so the model must already be where it is drawn.
	_apply_crawl_feet(speed, delta)
	legs.on_wall(_skeleton, _motion.get("wall", Plane()), facing.y.normalized(), 1.0 if bool(_motion.get("wall_running", false)) and is_inside_tree() else 0.0)
	var planted := _apply_floor(seen)
	# On the pose as drawn: a floor IK let go on landing turns no faster than a clip.
	_turn_limit.step(_skeleton, deg_to_rad(limb_turn_rate) if seen else 0.0, delta)
	# A leg held back can carry its ankle under the floor again; the lift only lifts, so a foot already up is left.
	if planted and _turn_limit.turned():
		legs.on_floor(_skeleton, _model.transform * _skel_to_model, _floor_ankles, floor_lift)
	_own.cap_colour = look.top
	_own.apply(_skeleton, _mesh)


## Whether the body follows the floor on a frame its clip does not step: always near and in view; past [member lift_range]
## or out of view it waits for the next step (a few dozen pixels a frame or two above a stair's riser is not seen).
func _lifts_between_steps() -> bool:
	return lift_range <= 0.0 or (_step_seen and _step_distance <= lift_range)


## Stands the drawn body on the floor its origin is drawn inside ([member floor_mask]). Whatever the clip: a body interpolated across a riser is often drawn mid-hop (its drawn state is in the air) while its sim stands on the tread.
## Raised at once, never eased: an eased rise is a body sunk into the step it just climbed. Not seated, swimming, climbing or dead.
func _lift_body() -> void:
	var at := global_position if is_inside_tree() else Vector3.INF
	if _model == null:
		_lift_at = at
		return
	var allowed := _skeleton != null and not (seated or driving) and not state in NO_LIFT_STATES
	# Unmoved, with the same mask, reach and state: the floor under it is the one already found (the world is
	# taken as still under a still body, as between drawn frames), so no ray is cast again.
	if at == _lift_at and at.is_finite() and allowed == _lift_allowed and floor_mask == _lift_mask \
			and floor_reach == _lift_reach:
		return
	_lift_at = at
	_lift_allowed = allowed
	_lift_mask = floor_mask
	_lift_reach = floor_reach
	var lift := legs.floor_lift(self, floor_mask, floor_reach) if allowed else 0.0
	if lift != floor_lift:
		floor_lift = lift
		_model.transform = _model_transform()
		_frame_tf_ok = false


## Keeps a standing body's drawn feet out of the floor its origin stands on ([method DotHumanoidLegs.on_floor]):
## a clip's stride can carry an ankle under it; first the body is stood on the floor under its origin ([member floor_mask]).
## Not in the air, on a wall, a ladder, a seat or the ground.
## Stands the body on the floor and lifts drawn ankles out of it; returns whether the feet were kept out of the floor.
func _apply_floor(feet: bool = true) -> bool:
	_lift_body()
	var grounded := feet and _skeleton != null and not (downed or seated or driving) and bool(_motion.get("on_floor", true)) \
		and not bool(_motion.get("wall_running", false)) and not state in OFF_FLOOR_STATES
	if grounded:
		legs.on_floor(_skeleton, _model.transform * _skel_to_model, _floor_ankles, floor_lift)
	return grounded


func _skeleton_up() -> Vector3:
	return (_to_figure().basis.inverse() * Vector3.UP).normalized()


func _apply_crawl_feet(speed: float, dt: float) -> void:
	var id := StringName(downed_clips.get(&"crawl", DotHumanoidClips.CRAWL))
	_crawl.step(self, _skeleton, downed and not propped and clip == id and _anim.current_animation == String(id), speed, dt)


## Puts back whatever a death took off: every bone at its own size again. For a respawn.
func mend() -> void:
	_turn_limit.clear()
	_own.mend(_skeleton, _mesh)


## Everything else about how the player moves, as [method DotPlayerAnimState.advance] reads it, plus `downed`,
## `wall_running`, `sliding`, `velocity` (world; turns the legs), `wall` (a world [Plane]), `seated`
## ([method seat_height]), `driving` and `aim` (radians, up positive; left out, it stays).
func set_motion(motion: Dictionary) -> void:
	_motion = motion
	sprinting = bool(motion.get("sprinting", false))
	downed = bool(motion.get("downed", false))
	propped = downed and bool(motion.get("propped", false))
	seated = bool(motion.get("seated", false))
	driving = bool(motion.get("driving", false))
	if motion.has("aim"):
		aim(float(motion["aim"]))


## Where the player looks, up or down, in radians (up positive; `deg_to_rad` a controller's
## `state.pitch`). Drawn on the next [method animate]: waist and chest bend by it, held to
## [constant AIM_LIMIT].
func aim(pitch_radians: float) -> void:
	aim_pitch = clampf(pitch_radians, -AIM_LIMIT, AIM_LIMIT) if is_finite(pitch_radians) else 0.0
	_view_pitch = pitch_radians if is_finite(pitch_radians) else 0.0


## How high above the feet the hips are when sitting, in metres at this figure's height: a game
## puts the figure's origin this far under the seat.
func seat_height() -> float:
	var base: float = DotHumanoidAssets.sit_height()
	if _skeleton == null or base <= 0.0:
		return height * 0.25
	return base * height / maxf(DotHumanoidFrames.measure(_mesh, _model), 0.01)


## What the hand holds: [enum Hold].
func set_hold(kind: int) -> void:
	hold = kind


## A melee swing over whatever the legs are doing: [constant DotHumanoidClips.SLASH] by default,
## [constant DotHumanoidClips.STAB] or [constant DotHumanoidClips.PUNCH] for empty hands.
func swing(which: StringName = &"") -> void:
	if which == &"":
		which = DotHumanoidClips.PUNCH if hold == Hold.NONE else DotHumanoidClips.SLASH
	_start_overlay(which, 1.4)


## The knife throw's meter as the game reports it (0 to 1 while winding up, below 0 when not): the throwing arm
## cocks back over the head and the chest turns with it, further the fuller the meter.
func set_throw_charge(fraction: float) -> void:
	arms.charge = fraction if is_finite(fraction) else -1.0


## The throw itself: the arm whips forward from wherever the windup had it, and the chest turns through.
func throw_release() -> void:
	arms.charge = -1.0
	arms.release()


## A hit: the kit's flinch on the upper body, pushed past its authored pose so a third-person view reads it.
func flinch() -> void:
	_start_overlay(DotHumanoidClips.HIT, 1.0)
	_overlay_gain = FLINCH_GAIN


## A gesture over the upper body: wave, yes, no.
func emote(which: StringName) -> void:
	_start_overlay(which, 1.0)


## Plays the avatar action [param id] that began [param elapsed] seconds ago, so a late joiner lands
## in step. Upper body over the legs, except [constant DotHumanoidActions.FULL_BODY] ids. A looping
## action holds until [method stop_action] or the player moves. False when the body has no clip.
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


## Adds the uploaded action [param id] from [param scene] (a built GLB) so [method play_action] can
## play it; the library is shared by every figure of the body. Success is false when already there.
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


## The node a held weapon hangs from: "right_hand" or "hand" ([constant HAND_BONE]), turned so its
## -Z is the way the figure faces holding a gun, +Y up, at metre scale. "head_top", "crest" or
## "hat" is the crown of the head, upright, following the head bone (hidden by [member hide_head]).
func attachment(point: StringName) -> Node3D:
	if HEAD_MOUNTS.has(point):
		return _crown_mount()
	if point != &"right_hand" and point != &"hand":
		return null
	if _hand != null and is_instance_valid(_hand):
		return _hand
	_hand = _bone_mount("Hand", HAND_BONE, Vector3(0.26, height * 0.62, -0.34))
	if _hand.get_parent() != self:
		_hand.transform = DotHumanoidFrames.hand_frame(_skeleton, _anim, _model, _to_figure()) * Transform3D(Basis.from_scale(Vector3.ONE * held_scale), Vector3.ZERO)
	return _hand


func _crown_mount() -> Node3D:
	if _crown != null and is_instance_valid(_crown):
		return _crown
	_crown = _bone_mount("Crown", HEAD_BONE, Vector3(0.0, height, 0.0))
	if _crown.get_parent() != self:
		_crown.transform = DotHumanoidFrames.crown_local(_skeleton, _to_figure(), height)
	return _crown


## A node under a bone attachment, or under the figure at [param fallback] when there is no such bone.
func _bone_mount(node_name: String, bone_name: String, fallback: Vector3) -> Node3D:
	var node := Node3D.new()
	node.name = node_name
	if _skeleton == null or _skeleton.find_bone(bone_name) < 0:
		node.position = fallback
		add_child(node)
		return node
	var bone := BoneAttachment3D.new()
	bone.name = node_name + "Bone"
	bone.bone_name = bone_name
	_skeleton.add_child(bone)
	bone.add_child(node)
	return node


## The drawn model, for [DotPlayerRagdoll] (it finds the skeleton and the skinned mesh under it).
func body_node() -> Node3D:
	return _model


func skeleton() -> Skeleton3D:
	return _skeleton


func mesh() -> MeshInstance3D:
	return _mesh


## The pose as drawn now, for a replay (overlays, aim and swim tilt included); [method pose_apply]
## puts it back. See [DotHumanoidPoseRecord] for the layout.
func pose_record() -> PackedFloat32Array:
	return DotHumanoidPoseRecord.record(_skeleton, _model)


## Draws the pose between two [method pose_record]s, [param alpha] of the way to [param b]. False
## (and nothing changed) when either is from another skeleton.
func pose_apply(a: PackedFloat32Array, b: PackedFloat32Array, alpha: float) -> bool:
	if not DotHumanoidPoseRecord.apply(_skeleton, _model, a, b, alpha):
		return false
	# Two recorded rows apart the blend can carry a foot under the floor; every leg bone was just written, so the lift does not add up.
	_apply_floor()
	return true


## Shows or hides the body (the local player's own, in first person). The hand stays where it
## is: a weapon model hung there hides with it.
func set_drawn(on: bool) -> void:
	if _model != null:
		_model.visible = on


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
		"carry": carry.describe(),
		"arms": arms.describe(),
		"downed": downed,
		"anim_step": anim_step,
		"visible": visible,
	}


## Writes the upper body over the locomotion pose: a playing overlay (swing, flinch, gesture),
## else the held-gun arms in a clip that is not a gun clip (nor a full-body action such as a dance). Not while swimming, where the
## stroke is the arms.
func _apply_overlays() -> void:
	if _skeleton == null:
		return
	var source: Animation = null
	var t := 0.0
	var weight := 0.0
	_overlay_weight = 0.0
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
	if source != null:
		_overlay_weight = clampf(weight, 0.0, 1.0)
	if source == null and hold == Hold.GUN and not downed and _action_full == &"" and not String(clip).ends_with("_gun") and clip != DotHumanoidClips.DEATH and clip != DotHumanoidClips.SWIM:
		source = _anim.get_animation(DotHumanoidClips.IDLE_GUN)
		t = 0.0
		weight = 1.0
	if source == null or weight <= 0.0:
		return
	var pairs: PackedInt32Array = _overlay_tracks.get(source, PackedInt32Array())
	if not _overlay_tracks.has(source):
		for bone: String in _upper:
			var track := source.find_track(_upper_paths[bone], Animation.TYPE_ROTATION_3D)
			if track >= 0:
				pairs.append_array([_upper[bone], track])
		_overlay_tracks[source] = pairs
	var w := clampf(weight, 0.0, 1.0)
	for k in range(0, pairs.size(), 2):
		var index := pairs[k]
		var q := source.rotation_track_interpolate(pairs[k + 1], t)
		_skeleton.set_bone_pose_rotation(index, DotHumanoidBlend.toward(_skeleton.get_bone_pose_rotation(index), q, w, _overlay_gain))
