class_name DotPlayerRagdolls
extends Node3D

## Where a game's dead bodies lie: builds each one from a death, keeps no more than the cap,
## and passes their sounds on. One per world, placed by the game (no autoload, so a server and
## a client in one process each have their own, or the server none).
##
## [codeblock]
## var yard := DotPlayerRagdolls.new()
## yard.rules = rules                      # a DotPlayerRagdollRules following the server's cvars
## yard.sound_fn = audio.play_at           # (id, position, volume) -> anything; optional
## world.add_child(yard)
## # on a kill message:
## yard.spawn(victim_figure, DotPlayerDeath.from_dict(info), victim_velocity)
## [/codeblock]
##
## [b]The cap is the server's ([member DotPlayerRagdollRules.max_count]) and this machine's
## ([member local_cap]), whichever is lower.[/b] A browser tab simulates on the one thread it
## has, so a machine without threads keeps fewer by default; the oldest body fades out quickly
## to make room rather than the new one not appearing, because the new one is the death
## somebody is looking at.

const CHANNEL := "player.ragdoll"

## A body was built.
signal spawned(ragdoll: DotPlayerRagdoll)

var rules: DotPlayerRagdollRules = DotPlayerRagdollRules.new()

## The reactions a death's id is looked up in. The stock set unless a game adds its own; the
## weights here do not matter on a client (the server picked), only the poses and sounds.
var reactions: DotPlayerDeathReactions = DotPlayerDeathReactions.stock()

## This machine's own limit, or -1 for [method default_local_cap].
var local_cap: int = -1

## Called as [code]sound_fn.call(id, position, volume)[/code] for each body's sound; dot-audio's
## [code]DotAudioManager.play_at[/code] fits. Unset, sounds go only to the [signal sound] signal.
var sound_fn: Callable = Callable()

## Every body's sound, for a game that would rather listen than hand over a callable.
signal sound(id: StringName, position: Vector3, volume: float)

## How long an evicted body takes to fade.
const EVICT_FADE := 0.3

var _live: Array[DotPlayerRagdoll] = []


## Fewer on a machine that simulates physics on its only thread or is a phone.
static func default_local_cap() -> int:
	if not DotPlatform.has_threads() or DotPlatform.is_mobile():
		return 4
	return 64


## The cap in force: the rules' and this machine's, the lower.
func cap() -> int:
	var mine := local_cap if local_cap > 0 else default_local_cap()
	return mini(rules.max_count if rules != null else 8, mine)


## Builds a body for [param figure] dying as [param death] says. Returns it, or null when the
## style hides bodies or there was nothing to copy (and then the figure is hidden all the same
## when the style is HIDE).
func spawn(figure: Node3D, death: DotPlayerDeath, velocity: Vector3 = Vector3.ZERO) -> DotPlayerRagdoll:
	if figure == null or rules == null:
		return null

	_reap()
	var room := cap() - 1
	# Make room: the oldest go first, quickly. Those already fading do not count.
	var standing := _standing()
	while standing.size() > room and not standing.is_empty():
		standing.pop_front().expire(EVICT_FADE)

	var reaction := reactions.find(death.reaction) if death != null and reactions != null else null
	var made := DotPlayerRagdoll.build(figure, self, rules, reaction, death, velocity)
	if made == null:
		return null

	var _c := made.sound.connect(_on_sound)
	_live.append(made)
	spawned.emit(made)
	return made


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


## Removes every body at once: a map change, a round reset.
func clear() -> void:
	for body in _live:
		if is_instance_valid(body):
			body.queue_free()
	_live.clear()


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
