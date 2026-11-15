extends "dot_humanoid_figure_state.gd"

## [DotHumanoidFigure]'s clip choice, overlays, aim, support hand and swim lean, split out to keep each file small.

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
	# A slide on the ground: leant back, legs forward. The game's `sliding` key; in the air it is a fall.
	if bool(_motion.get("sliding", false)) and p_state in [
			DotPlayerAnimState.CROUCH_IDLE, DotPlayerAnimState.CROUCH_WALK, DotPlayerAnimState.RUN,
			DotPlayerAnimState.WALK, DotPlayerAnimState.IDLE] and _anim != null and _anim.has_animation(DotHumanoidClips.SLIDE):
		return [DotHumanoidClips.SLIDE, 1.0]
	if zombie_gait and not gun and _anim != null:
		var zombie := _zombie_clip_for(p_state, speed)
		if not zombie.is_empty():
			return zombie
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


## The zombie gait's clip and rate for a ground state, or empty. The rates are the clips' own ground speeds (metres a second).
func _zombie_clip_for(p_state: StringName, speed: float) -> Array:
	match p_state:
		DotPlayerAnimState.IDLE:
			if _anim.has_animation(DotHumanoidClips.ZOMBIE_IDLE):
				return [DotHumanoidClips.ZOMBIE_IDLE, 1.0]
		DotPlayerAnimState.WALK:
			if _anim.has_animation(DotHumanoidClips.ZOMBIE_WALK):
				return [DotHumanoidClips.ZOMBIE_WALK, clampf(speed / ZOMBIE_WALK_NATURAL, 0.6, 1.8)]
		DotPlayerAnimState.RUN:
			if _anim.has_animation(DotHumanoidClips.SPRINT):
				return [DotHumanoidClips.SPRINT, clampf(speed / ZOMBIE_SPRINT_NATURAL, 0.7, 1.5)]
	return []


## Whether a runner at [param speed] plays the sprint clip: the game's `sprinting` key when it sends one, else the speed, with a gap so it does not flicker.
func _sprint_clip_for(speed: float) -> bool:
	if _anim == null or not _anim.has_animation(DotHumanoidClips.SPRINT):
		return false
	var from := sprint_speed if sprint_speed > 0.0 else _machine.run_speed * 1.6
	# The run clip hovers (both feet up) above its own pace, whoever says sprinting; the sprint clip stays grounded.
	from = minf(from, RUN_CLIP_MAX_SPEED)
	var fast := speed >= from - (SPRINT_EXIT if _sprint_clip else 0.0)
	_sprint_clip = (sprinting or fast) if _motion.has("sprinting") else fast
	return _sprint_clip


## The rate that moves the lower foot back exactly as far as the body goes this step (negative walking backward), or NAN when the
## clip is not a stride. The clips have no root motion and sweep the planted foot back unevenly, so
## any constant rate skates it; the rate is read off the clip's distance table instead.
func _matched_rate(speed: float, dt: float) -> float:
	if dt <= 0.0 or not state in STRIDE_STATES:
		return NAN
	if not clip in STRIDE_CLIPS or _anim.current_animation != String(clip):
		return NAN
	var table := _stride_for(clip)
	if table.size() < 2 or table[-1] <= 0.0:
		return NAN
	var length := _anim.current_animation_length
	var phase := fposmod(_anim.current_animation_position, length) / length
	var back := -1.0 if legs.backward else 1.0
	var want := DotHumanoidStride.distance_at(table, phase) + back * speed * dt
	var laps := floorf(want / table[-1])
	var to := DotHumanoidStride.phase_at(table, want - laps * table[-1]) + laps
	return clampf((to - phase) * length / dt * back, 0.0, STRIDE_MAX_RATE) * back


func _stride_for(clip_id: StringName) -> PackedFloat32Array:
	if not _strides.has(clip_id):
		_strides[clip_id] = DotHumanoidStride.table_for(_anim.get_animation(clip_id), _skeleton, _model, _to_figure())
	return _strides[clip_id]


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
	var blend := SLIDE_BLEND if wanted == DotHumanoidClips.SLIDE or clip == DotHumanoidClips.SLIDE else 0.15
	clip = wanted
	var cross := from >= 0.0 and wanted in STRIDE_CLIPS
	# A stride cut keeps the feet planted but would snap the arms, and the gun in the hand with them.
	if cross:
		_ease.begin(_skeleton, _upper, HAND_BONE)
	var feet := DotHumanoidStride.feet_now(_skeleton, _to_figure()) if cross else PackedVector3Array()
	_anim.play(wanted, 0.0 if cross else blend)
	if cross and not feet.is_empty():
		_anim.seek(DotHumanoidStride.matching_time(_anim.get_animation(wanted), _skeleton, _model, _to_figure(), feet), true)


## How far through its stride the playing clip's planted foot is, 0 to 1, or -1 when it is not a stride clip. A clip entered at this fraction keeps the foot it stands on travelling with the ground.
func _stride_fraction() -> float:
	if not clip in STRIDE_CLIPS or _anim.current_animation != String(clip):
		return -1.0
	var table := _stride_for(clip)
	if table.size() < 2 or table[-1] <= 0.0:
		return -1.0
	var length := _anim.current_animation_length
	return DotHumanoidStride.distance_at(table, fposmod(_anim.current_animation_position, length) / length) / table[-1]


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


## Bends the waist and chest by [member aim_pitch] after the clip and the overlays, so what the arms
## do points up or down with the view; not while down, dead, swimming or climbing, and only on a
## bone the playing clip keys (see [DotHumanoidAim]).
func _apply_aim() -> void:
	if _skeleton == null or (is_zero_approx(aim_pitch) and sprint_blend <= 0.0) or downed:
		return
	if state == DotPlayerAnimState.DEAD or state == DotPlayerAnimState.SWIM or state == DotPlayerAnimState.CLIMB:
		return
	var animation := _anim.get_animation(clip)
	if animation == null:
		return
	var arm := 1 if hold != Hold.NONE else 0
	var plans: Variant = _aim_plans.get(animation)
	if plans == null:
		plans = [null, null]
	if plans[arm] == null:
		plans[arm] = DotHumanoidAim.plan(_skeleton, _model, animation, arm == 1)
		_aim_plans[animation] = plans
	DotHumanoidAim.apply_plan(_skeleton, plans[arm], _to_figure(), aim_pitch, sprint_blend)


## Where the support hand goes: the weapon's foregrip, [constant Vector3.INF] when the gun is held with one
## hand or none. In world space; called every frame by the held weapon, since it moves with the gun.
func set_support_grip(point: Vector3) -> void:
	support_point = point


## Two-bone IK on the left arm toward [member support_point], blended by the support weight, after the clip,
## the overlays and the aim so it lands on the gun wherever they put it. Only on bones the clip keys (a bone no
## track writes keeps last frame's pose, and the turn would add up).
func _apply_support() -> void:
	if _skeleton == null or _support_weight <= 0.0 or downed:
		return
	var target := carry.support_grip
	if support_point.is_finite():
		target = _skeleton.global_transform.affine_inverse() * support_point
	if not target.is_finite():
		return
	var bones := _support_bones_for(clip)
	if bones.is_empty():
		return
	var chain: Variant = _support_chains.get(bones[0])
	if chain == null:
		chain = DotHumanoidIk.chain_to(_skeleton, _skeleton.get_bone_parent(bones[0]))
		_support_chains[bones[0]] = chain
	DotHumanoidIk.two_bone_under(_skeleton, bones, DotHumanoidIk.chain_pose(_skeleton, chain), target,
		_to_figure().basis.inverse() * SUPPORT_POLE, _support_weight)


func _apply_carry() -> void:
	if _skeleton == null or clip == DotHumanoidClips.DEATH or clip == DotHumanoidClips.SWIM:
		carry.support_grip = Vector3.INF
		return
	carry.apply(_skeleton, _model, _anim, _to_figure(), _anim.get_animation(clip), _stride_fraction(), aim_pitch,
		height / 1.8, _sprint, _speed, _overlay_weight)


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
	var before := _swim_pitch + _prop_pitch + _slide_lift + _own_back
	var sliding := state != DotPlayerAnimState.SWIM and clip == DotHumanoidClips.SLIDE
	_slide_lift = move_toward(_slide_lift, SLIDE_LIFT * height / 1.8 if sliding else 0.0, delta * 0.6)
	_swim_pitch = move_toward(_swim_pitch, wanted, delta * 3.0)
	_prop_pitch = move_toward(_prop_pitch, -PROP_LEAN if downed and propped else 0.0, delta * 3.0)
	_own_back = _own.back_for(_view_pitch) * height / 1.8
	var total := _swim_pitch + _prop_pitch
	if is_equal_approx(before, total + _slide_lift + _own_back) and total == 0.0 and _slide_lift == 0.0 and _own_back == 0.0:
		return
	_model.transform = _model_transform()
	_frame_tf_ok = false


## The model under the figure: laid forward or back about the hips, raised by a slide and onto the floor, set back for its own view.
func _model_transform() -> Transform3D:
	var hips := Vector3(0.0, height * 0.55, 0.0)
	var tilt := Transform3D(Basis(Vector3.RIGHT, -(_swim_pitch + _prop_pitch)), Vector3.ZERO)
	var about := Transform3D(Basis.IDENTITY, hips) * tilt * Transform3D(Basis.IDENTITY, -hips)
	return Transform3D(Basis.IDENTITY, Vector3(0.0, _slide_lift + floor_lift, _own_back)) * about * Transform3D(_model_basis, _model_origin)


## Ends the playing action, easing out.
func stop_action() -> void:
	_action_full = &""
	if overlay != &"" and _overlay_loop and not _overlay_stopping:
		_overlay_stopping = true
		_stop_time = 0.0
	action = &""


## Skeleton space to the figure's frame: the skeleton's own transform under the model, then the
## model's turn and scale.
func _to_figure() -> Transform3D:
	if _frame_tf_ok:
		return _frame_tf
	var skel_to_model := _model.global_transform.affine_inverse() * _skeleton.global_transform if _model.is_inside_tree() and absf(_model.global_basis.determinant()) > 1e-9 else Transform3D.IDENTITY
	var out := Transform3D(_model_basis, _model_origin) * skel_to_model
	if _frame_tf_on:
		_frame_tf = out
		_frame_tf_ok = true
	return out
