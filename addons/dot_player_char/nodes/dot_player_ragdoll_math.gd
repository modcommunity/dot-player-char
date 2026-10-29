class_name DotPlayerRagdollMath
extends RefCounted

## Small pure helpers for building a ragdoll from a skeleton's points.


## The average of [param list], or [param fallback] when it is empty.
static func mean(list: Array, fallback: Vector3) -> Vector3:
	if list.is_empty():
		return fallback
	var sum := Vector3.ZERO
	for p: Vector3 in list:
		sum += p
	return sum / float(list.size())


## A basis whose Y runs along [param along], with Z as near [param forward] as that allows.
static func basis_along(along: Vector3, forward: Vector3) -> Basis:
	var y := along.normalized() if along.length_squared() > 0.0001 else Vector3.DOWN
	var z := forward - y * forward.dot(y)
	if z.length_squared() < 0.0001:
		z = Vector3.RIGHT.cross(y)
	z = z.normalized()
	var x := y.cross(z).normalized()
	return Basis(x, y, z)


## The value [param q] (0 to 1) of the way up the sorted [param values].
static func quantile(values: Array[float], q: float) -> float:
	values.sort()
	return values[clampi(int(q * float(values.size() - 1)), 0, values.size() - 1)]
