class_name DotViewHandPoses
extends RefCounted

## How each hand holds each kind of weapon in first person: the grips [DotPlayerViewArms] closes its [DotViewHand]s
## into. A kind ([member DotViewGrip.kind]) has a `firing` hand (the right) and, for a two-hand weapon, a `support`
## one (the left).
##
## A hand is a Dictionary:
## - `fingers`, `palm`: where the fingers point and the palm faces, in the weapon's frame as Vector3(right, up,
##   forward); the thumb follows from the two and the hand's side;
## - `centre`: the point of the hand, in its own frame (metres at life size: +Y to the fingers, +Z out of the palm,
##   x toward the thumb on a right hand), that sits on the grip point; the wrist is placed from it;
## - `thumb`, `index`, `middle`, `ring`, `pinky`: each finger's three joint curls toward the palm (degrees);
## - `spread`: how far the fingers fan out (degrees).
##
## A game edits [member DotPlayerViewArms.hand_poses] (a fresh [method table]) to adjust one, or adds kinds.

const RIFLE: StringName = &"rifle"
const PISTOL: StringName = &"pistol"
const SHOTGUN: StringName = &"shotgun"
const LAUNCHER: StringName = &"launcher"
const SNIPER: StringName = &"sniper"
const GRENADE: StringName = &"grenade"
const KNIFE: StringName = &"knife"
const FISTS: StringName = &"fists"
## What a knife hand blends to as a throw winds up ([member DotPlayerViewArms.throw_grip]): the blade pinched between
## the thumb and the first two fingers, the others tucked.
const KNIFE_THROW: StringName = &"knife_throw"
## The fingers a hand pose curls, in [DotViewHand]'s order.
const FINGERS: Array[StringName] = [&"thumb", &"index", &"middle", &"ring", &"pinky"]


## The stock grips, a fresh copy each call.
static func table() -> Dictionary:
	# The firing hand on a pistol grip raked back about 20 degrees, the index finger along the trigger guard.
	var trigger := {&"fingers": Vector3(0.0, -0.34, 0.94), &"palm": Vector3(-1.0, 0.0, 0.0), &"centre": Vector3(0.0, 0.066, 0.026),
		&"thumb": Vector3(18.0, 22.0, 12.0), &"index": Vector3(22.0, 48.0, 18.0), &"middle": Vector3(72.0, 92.0, 52.0),
		&"ring": Vector3(76.0, 94.0, 54.0), &"pinky": Vector3(80.0, 92.0, 52.0), &"spread": 0.0}
	var out := {}
	out[RIFLE] = {
		&"firing": trigger.duplicate(),
		# Under the handguard, palm up, the fingers round its right side, the thumb along the left.
		&"support": {&"fingers": Vector3(0.85, 0.1, 0.5), &"palm": Vector3(-0.15, 1.0, 0.0), &"centre": Vector3(0.0, 0.07, 0.022),
			&"thumb": Vector3(12.0, 18.0, 10.0), &"index": Vector3(58.0, 68.0, 38.0), &"middle": Vector3(62.0, 72.0, 40.0),
			&"ring": Vector3(64.0, 74.0, 42.0), &"pinky": Vector3(68.0, 74.0, 42.0), &"spread": 2.0},
	}
	out[SNIPER] = {
		&"firing": trigger.duplicate(),
		# A long gun rests in a looser hand, the fingers along the stock as much as round it.
		&"support": {&"fingers": Vector3(0.55, 0.05, 0.85), &"palm": Vector3(-0.1, 1.0, 0.0), &"centre": Vector3(0.0, 0.065, 0.018),
			&"thumb": Vector3(8.0, 14.0, 8.0), &"index": Vector3(44.0, 52.0, 30.0), &"middle": Vector3(48.0, 56.0, 32.0),
			&"ring": Vector3(50.0, 58.0, 34.0), &"pinky": Vector3(54.0, 58.0, 34.0), &"spread": 3.0},
	}
	out[SHOTGUN] = {
		&"firing": trigger.duplicate(),
		# Round the pump: the fingers close up its right side.
		&"support": {&"fingers": Vector3(0.95, 0.15, 0.3), &"palm": Vector3(-0.2, 1.0, 0.0), &"centre": Vector3(0.0, 0.07, 0.026),
			&"thumb": Vector3(16.0, 22.0, 12.0), &"index": Vector3(68.0, 80.0, 46.0), &"middle": Vector3(70.0, 84.0, 48.0),
			&"ring": Vector3(72.0, 84.0, 48.0), &"pinky": Vector3(74.0, 82.0, 46.0), &"spread": 0.0},
	}
	out[LAUNCHER] = {
		&"firing": trigger.duplicate(),
		# A vertical fore grip, palm in from the left, thumb up.
		&"support": {&"fingers": Vector3(0.0, -0.25, 1.0), &"palm": Vector3(1.0, 0.0, 0.0), &"centre": Vector3(0.0, 0.066, 0.026),
			&"thumb": Vector3(16.0, 20.0, 12.0), &"index": Vector3(70.0, 88.0, 50.0), &"middle": Vector3(72.0, 92.0, 52.0),
			&"ring": Vector3(76.0, 94.0, 54.0), &"pinky": Vector3(80.0, 92.0, 52.0), &"spread": 0.0},
	}
	var pistol: Dictionary = trigger.duplicate()
	pistol[&"fingers"] = Vector3(0.0, -0.24, 0.97)
	out[PISTOL] = {
		&"firing": pistol,
		# Thumbs forward: the support hand wraps the firing fingers from the left, palm in.
		&"support": {&"fingers": Vector3(0.25, -0.75, 0.6), &"palm": Vector3(1.0, -0.1, 0.25), &"centre": Vector3(0.0, 0.06, 0.03),
			&"thumb": Vector3(10.0, 12.0, 8.0), &"index": Vector3(58.0, 70.0, 40.0), &"middle": Vector3(62.0, 74.0, 44.0),
			&"ring": Vector3(66.0, 76.0, 44.0), &"pinky": Vector3(70.0, 74.0, 44.0), &"spread": 0.0},
	}
	# A ball in the fingers, the hand under and behind it.
	out[GRENADE] = {&"firing": {&"fingers": Vector3(-0.25, 0.55, 0.8), &"palm": Vector3(-0.55, 0.55, -0.35), &"centre": Vector3(0.0, 0.088, 0.036),
		&"thumb": Vector3(26.0, 26.0, 16.0), &"index": Vector3(40.0, 46.0, 30.0), &"middle": Vector3(42.0, 48.0, 32.0),
		&"ring": Vector3(44.0, 48.0, 32.0), &"pinky": Vector3(46.0, 46.0, 30.0), &"spread": 10.0}}
	# A fist round the handle, which runs along the thumb's line to the blade: fingers down, palm in, thumb forward.
	out[KNIFE] = {&"firing": {&"fingers": Vector3(0.0, -1.0, 0.25), &"palm": Vector3(-1.0, 0.0, 0.0), &"centre": Vector3(0.0, 0.07, 0.024),
		&"thumb": Vector3(26.0, 30.0, 16.0), &"index": Vector3(78.0, 96.0, 56.0), &"middle": Vector3(80.0, 98.0, 58.0),
		&"ring": Vector3(82.0, 98.0, 58.0), &"pinky": Vector3(84.0, 96.0, 56.0), &"spread": 0.0}}
	out[KNIFE_THROW] = {&"firing": {&"fingers": Vector3(0.0, -1.0, 0.25), &"palm": Vector3(-1.0, 0.0, 0.0), &"centre": Vector3(0.0, 0.105, 0.018),
		&"thumb": Vector3(8.0, 18.0, 14.0), &"index": Vector3(30.0, 34.0, 18.0), &"middle": Vector3(36.0, 40.0, 22.0),
		&"ring": Vector3(80.0, 96.0, 56.0), &"pinky": Vector3(84.0, 94.0, 54.0), &"spread": 2.0}}
	out[FISTS] = {&"firing": {&"fingers": Vector3(0.0, 0.0, 1.0), &"palm": Vector3(-1.0, 0.0, 0.0), &"centre": Vector3(0.0, 0.07, 0.02),
		&"thumb": Vector3(32.0, 40.0, 26.0), &"index": Vector3(86.0, 100.0, 62.0), &"middle": Vector3(88.0, 102.0, 62.0),
		&"ring": Vector3(88.0, 102.0, 62.0), &"pinky": Vector3(88.0, 100.0, 60.0), &"spread": 0.0}}
	return out


## [param a] blended toward [param b] by [param t] (0 to 1): curls, centre and directions.
static func blend(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	if not (t > 0.0) or b.is_empty():
		return a
	if t >= 1.0:
		return b
	var out := a.duplicate()
	for key in b:
		if a.has(key) and a[key] is Vector3:
			out[key] = (a[key] as Vector3).lerp(b[key], t)
		elif a.has(key) and (a[key] is float or a[key] is int):
			out[key] = lerpf(float(a[key]), float(b[key]), t)
	return out


## The hand's frame (orthonormal, before its size) for [param hand] on a weapon whose forward and up are
## [param forward] and [param up] (world): x = y cross z, so a right hand's thumb is +x and a mirrored left one's -x.
static func frame(hand: Dictionary, forward: Vector3, up: Vector3) -> Basis:
	var f := forward.normalized()
	var u := up.normalized() - f * up.normalized().dot(f)
	# An up along the forward (a grenade's art forward is its own up) has no side to close round: what is left of it
	# is noise, which flipped the hand 0.13 m frame to frame. The world's up then, or its back for a forward along it.
	if u.length() < 0.1:
		var ref := Vector3.UP if absf(f.y) < 0.9 else Vector3.BACK
		u = ref - f * ref.dot(f)
	u = u.normalized()
	if not f.is_normalized() or not u.is_normalized():
		return Basis.IDENTITY
	var r := f.cross(u)
	var p: Vector3 = hand.get(&"palm", Vector3(-1.0, 0.0, 0.0))
	var palm := (r * p.x + u * p.y + f * p.z).normalized()
	var g: Vector3 = hand.get(&"fingers", Vector3(0.0, 0.0, 1.0))
	var along := r * g.x + u * g.y + f * g.z
	var fingers := (along - palm * along.dot(palm)).normalized()
	if not fingers.is_normalized():
		fingers = (f - palm * f.dot(palm)).normalized()
	return Basis(fingers.cross(palm), fingers, palm)
