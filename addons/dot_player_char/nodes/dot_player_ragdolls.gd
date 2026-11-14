class_name DotPlayerRagdolls
extends Node3D

## Where a game's dead bodies lie: builds each from a death, keeps no more than the cap, passes their sounds on.
## One per world, placed by the game (no autoload). The cap is the lower of the server's and [member local_cap];
## the oldest body fades quickly. Use: `spawn(victim_figure, DotPlayerDeath.from_dict(info), victim_velocity)`.

const CHANNEL := "player.ragdoll"

## A body was built.
signal spawned(ragdoll: DotPlayerRagdoll)

var rules: DotPlayerRagdollRules = DotPlayerRagdollRules.new()

## The reactions a death's id is looked up in. The stock set unless a game adds its own; the
## weights here do not matter on a client (the server picked), only the poses and sounds.
var reactions: DotPlayerDeathReactions = DotPlayerDeathReactions.stock()

## This machine's own limit: -1 for [method default_local_cap], 0 = unlimited, else a body count.
var local_cap: int = -1

## Called as [code]sound_fn.call(id, position, volume)[/code] for each body's sound; dot-audio's
## [code]DotAudioManager.play_at[/code] fits. Unset, sounds go only to the [signal sound] signal.
var sound_fn: Callable = Callable()

## Every body's sound, for a game that would rather listen than hand over a callable.
signal sound(id: StringName, position: Vector3, volume: float)

## How long an evicted body takes to fade.
const EVICT_FADE := 0.3

var _live: Array[DotPlayerRagdoll] = []
var _props: Array[RigidBody3D] = []


## Four on a machine that simulates physics on its only thread or is a phone; 0 (unlimited,
## the server's [member DotPlayerRagdollRules.max_count] decides) otherwise.
static func default_local_cap() -> int:
	if not DotPlatform.has_threads() or DotPlatform.is_mobile():
		return 4
	return 0


## The cap in force: the rules' and this machine's, the lower, where 0 on either side is no
## limit from that side. 0 = unlimited.
func cap() -> int:
	return cap_of(rules.max_count if rules != null else 8, local_cap)


## [param server_max] ([member DotPlayerRagdollRules.max_count]) and [param machine]
## ([member local_cap]: -1 for [method default_local_cap]) combined: the lower, 0 on either side
## meaning no limit from it. 0 = unlimited. For a game keeping its own bodies (a 2D fall).
static func cap_of(server_max: int, machine: int) -> int:
	var mine := machine if machine >= 0 else default_local_cap()
	if mine <= 0:
		return maxi(server_max, 0)
	if server_max <= 0:
		return mine
	return mini(server_max, mine)


## Builds a body for [param figure] dying as [param death] says. Returns it, or null when the
## style hides bodies or there was nothing to copy (and then the figure is hidden all the same
## when the style is HIDE).
func spawn(figure: Node3D, death: DotPlayerDeath, velocity: Vector3 = Vector3.ZERO) -> DotPlayerRagdoll:
	if figure == null or rules == null:
		return null

	_reap()
	var limit := cap()
	var room := limit - 1
	# Make room: the oldest go first, quickly. Those already fading do not count. 0 = no cap.
	var standing: Array[DotPlayerRagdoll] = []
	if limit > 0:
		standing = _standing()
	while standing.size() > room and not standing.is_empty():
		standing.pop_front().expire(EVICT_FADE)
		DotLog.debug(CHANNEL, "cap reached, oldest body fading", {"cap": cap()})

	var reaction := reactions.find(death.reaction) if death != null and reactions != null else null
	var made := DotPlayerRagdoll.build(figure, self, rules, reaction, death, velocity)
	if made == null:
		DotLog.debug(CHANNEL, "no body built", {"figure": figure.name})
		return null

	var _c := made.sound.connect(_on_sound)
	_live.append(made)
	spawned.emit(made)
	return made


## Drops a copy of [param model] (a weapon's world model) as a physics prop that fades after
## [member DotPlayerRagdollRules.weapon_lifetime]. Null when off or the model has no mesh.
## Presentation only: nothing collides with it.
func drop_prop(model: Node3D, velocity: Vector3 = Vector3.ZERO) -> RigidBody3D:
	if model == null or rules == null or not rules.weapon_drop or not model.is_inside_tree():
		return null
	var meshes: Array[MeshInstance3D] = []
	for mesh in DotPlayerRagdoll.meshes_of(model):
		if not _is_effect(mesh, model):
			meshes.append(mesh)
	if meshes.is_empty():
		return null

	var frame := Transform3D(DotPlayerRagdollMath.ortho(model.global_basis), model.global_position)
	var to_local := frame.affine_inverse()
	var bounds := AABB()
	var first := true
	for mesh in meshes:
		var box := (to_local * mesh.global_transform) * mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false

	var body := RigidBody3D.new()
	body.name = "DroppedWeapon"
	body.collision_layer = 0
	body.collision_mask = rules.collision_mask
	body.mass = 4.0
	body.gravity_scale = rules.gravity_scale
	body.continuous_cd = true
	body.linear_damp = rules.linear_damp
	body.angular_damp = 0.5
	var material := PhysicsMaterial.new()
	material.friction = 0.8
	material.bounce = 0.25
	body.physics_material_override = material
	add_child(body)
	body.global_transform = frame

	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = bounds.size.max(Vector3.ONE * 0.06)
	shape.shape = box_shape
	shape.position = bounds.get_center()
	body.add_child(shape)
	for mesh in meshes:
		var copy := mesh.duplicate(0) as MeshInstance3D
		body.add_child(copy)
		copy.visible = true
		copy.global_transform = mesh.global_transform

	body.linear_velocity = velocity + Vector3.DOWN * 1.5
	body.angular_velocity = Vector3(0.0, 0.0, 2.0) * (1.0 if velocity.x >= 0.0 else -1.0)

	var prop_cap := cap()
	while prop_cap > 0 and _props.size() >= prop_cap:
		var oldest := _props.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
	_props.append(body)
	var timer := get_tree().create_timer(rules.weapon_lifetime)
	var _t := timer.timeout.connect(_expire_prop.bind(body))
	DotLog.debug(CHANNEL, "weapon dropped", {"life": rules.weapon_lifetime})
	return body


## True for a mesh under a muzzle flash (duck-typed: it can be fired and asked if it shows).
## Copied into a prop it freezes at the muzzle and inflates the collider, so the gun stood on end.
static func _is_effect(mesh: Node, root: Node) -> bool:
	var n := mesh.get_parent()
	while n != null and n != root:
		if n.has_method("is_showing") and n.has_method("fire"):
			return true
		n = n.get_parent()
	return false


func _expire_prop(prop) -> void:
	# Untyped and checked first: a freed object converts to no type, and erase() on a typed array converts.
	if not is_instance_valid(prop):
		return
	_props.erase(prop)
	var body := prop as RigidBody3D
	body.freeze = true
	var tween := body.create_tween()
	tween.tween_property(body, "scale", Vector3.ONE * 0.01, 0.4)
	tween.tween_callback(body.queue_free)


## Applies a shot's impulse to the lying part nearest [param point] (within [param radius]); false
## unless [member DotPlayerRagdollRules.shootable]. With [param from], a part behind world
## geometry is skipped: the impact point sits on the wall a body lies against.
func shoot(point: Vector3, direction: Vector3, impulse: float = 4.0, radius: float = 0.6, from: Vector3 = Vector3.INF) -> bool:
	if rules == null or not rules.shootable:
		return false
	direction = DotPlayerRagdollMath.finite_or(direction)
	if not is_finite(impulse) or not point.is_finite():

		return false

	_reap()
	var best: RigidBody3D = null
	var best_d := radius
	var hit_body: DotPlayerRagdoll = null
	for body in _live:
		for node in body.part_nodes():
			var rb := node as RigidBody3D
			if rb == null:
				continue
			var d := rb.global_position.distance_to(point)
			if d < best_d and not _covered(from, rb.global_position):
				best_d = d
				best = rb
				hit_body = body
	if best == null:
		return false
	hit_body.wake()
	best.freeze = false
	var push := DotPlayerRagdollMath.unit(direction, Vector3.ZERO) * impulse * rules.force_scale
	var lever := DotPlayerRagdollMath.finite_or(point - best.global_position)
	best.apply_impulse(DotPlayerRagdollMath.finite_or(push), lever)
	return true


## True when world geometry lies between [param from] and [param target]; false without an origin.
func _covered(from: Vector3, target: Vector3) -> bool:
	if from == Vector3.INF or not is_inside_tree():
		return false
	return not DotPlayerRagdoll.crossing(get_world_3d().direct_space_state, from, target, rules.collision_mask).is_empty()


## Bodies not yet fading, oldest first.
func _standing() -> Array[DotPlayerRagdoll]:
	var out: Array[DotPlayerRagdoll] = []
	for body in _live:
		if is_instance_valid(body) and not body.expiring:
			out.append(body)
	return out


func _reap() -> void:
	var kept: Array[DotPlayerRagdoll] = []
	for body in _live:
		if is_instance_valid(body) and not body.is_queued_for_deletion():
			kept.append(body)
	_live = kept


## Bodies lying about now, fading ones included.
func live() -> Array[DotPlayerRagdoll]:
	_reap()
	return _live.duplicate()


## Bodies not fading: the number the cap holds to.
func standing_count() -> int:
	_reap()
	return _standing().size()


## Builds one throwaway body off a stock figure, far below the world, and frees it [param frames] frames later, so the first real death does not pay for first-use work (the physics bodies and joints, the script and shape setup: a 32 ms hitch in a web build). Call it under a loading cover; it neither emits [signal spawned] nor plays a sound, and no body is left in the yard.
func prewarm(frames: int = 2) -> void:
	if rules == null or not is_inside_tree() or rules.effective_style() == DotPlayerRagdollRules.Style.HIDE:
		return
	var figure := Node3D.new()
	figure.name = "RagdollPrewarm"
	add_child(figure)
	figure.global_position = Vector3(0.0, -4000.0, 0.0)
	var box := BoxMesh.new()
	# name, centre, size: the roles the build looks for, in a human's proportions.
	for spec: Array in [
		["leg-left", Vector3(0.13, 0.4, 0), Vector3(0.2, 0.8, 0.2)], ["leg-right", Vector3(-0.13, 0.4, 0), Vector3(0.2, 0.8, 0.2)],
		["torso", Vector3(0, 1.1, 0), Vector3(0.5, 0.6, 0.3)], ["arm-left", Vector3(0.4, 1.1, 0), Vector3(0.15, 0.7, 0.15)],
		["arm-right", Vector3(-0.4, 1.1, 0), Vector3(0.15, 0.7, 0.15)], ["head", Vector3(0, 1.6, 0), Vector3(0.3, 0.3, 0.3)],
	]:
		var mesh := MeshInstance3D.new()
		mesh.name = String(spec[0])
		mesh.mesh = box
		mesh.scale = spec[2]
		mesh.position = spec[1]
		figure.add_child(mesh)
	var made := DotPlayerRagdoll.build(figure, self, rules, null, null)
	if is_inside_tree():
		for i in frames:
			await get_tree().physics_frame
	if is_instance_valid(made):
		made.queue_free()
	if is_instance_valid(figure):
		figure.queue_free()


## Removes every body at once: a map change, a round reset.
func clear() -> void:
	for body in _live:
		if is_instance_valid(body):
			body.queue_free()
	_live.clear()
	for prop in _props:
		if is_instance_valid(prop):
			prop.queue_free()
	_props.clear()


func _on_sound(id: StringName, at: Vector3, strength: float) -> void:
	sound.emit(id, at, strength)
	if sound_fn.is_valid():
		var _played: Variant = sound_fn.call(id, at, strength)


func describe() -> Dictionary:
	return {
		"bodies": live().size(),
		"standing": standing_count(),
		"cap": cap(),
		"rules": rules.describe() if rules != null else {},
	}
