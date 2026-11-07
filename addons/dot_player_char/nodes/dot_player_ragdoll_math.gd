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


## [param v], or [param fallback] when any component is NaN or infinite.
static func finite_or(v: Vector3, fallback: Vector3 = Vector3.ZERO) -> Vector3:
	return v if is_finite(v.x) and is_finite(v.y) and is_finite(v.z) else fallback


## [param v] as a unit vector, or [param fallback] when it is non-finite, near zero, or so large that its length overflows.
static func unit(v: Vector3, fallback: Vector3) -> Vector3:
	if not (is_finite(v.x) and is_finite(v.y) and is_finite(v.z)):
		return fallback
	var big := maxf(absf(v.x), maxf(absf(v.y), absf(v.z)))
	if big < 0.01:
		return fallback
	return (v / big).normalized()


## [param b] orthonormalised, or the identity when it is non-finite or has collapsed (a zero-scaled node gives NaN).
static func ortho(b: Basis) -> Basis:
	for v: Vector3 in [b.x, b.y, b.z]:
		if not (is_finite(v.x) and is_finite(v.y) and is_finite(v.z)):
			return Basis.IDENTITY
	if b.x.length_squared() < 0.000001 or b.y.length_squared() < 0.000001 or b.z.length_squared() < 0.000001 or absf(b.determinant()) < 0.000001:
		return Basis.IDENTITY
	return b.orthonormalized()


## A basis whose Y runs along [param along], with Z as near [param forward] as that allows.
static func basis_along(along: Vector3, forward: Vector3) -> Basis:
	var y := along.normalized() if along.length_squared() > 0.0001 else Vector3.DOWN
	var z := forward - y * forward.dot(y)
	if z.length_squared() < 0.0001:
		z = Vector3.RIGHT.cross(y)
	z = z.normalized()
	var x := y.cross(z).normalized()
	return Basis(x, y, z)


## [param x], or [param fallback] when it is NaN or infinite.
static func finite_float(x: float, fallback: float = 0.0) -> float:
	return x if is_finite(x) else fallback


## The value [param q] (0 to 1) of the way up the sorted [param values].
static func quantile(values: Array[float], q: float) -> float:
	values.sort()
	return values[clampi(int(q * float(values.size() - 1)), 0, values.size() - 1)]
