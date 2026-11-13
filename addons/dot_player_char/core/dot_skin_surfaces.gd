class_name DotSkinSurfaces
extends RefCounted

## A skinned mesh's arrays as a dead body reads them, read once per mesh and kept (main thread only).
## [method Mesh.surface_get_arrays] copies a whole surface, and every broken limb and built body read it
## again: 8 ms a limb on a 31-bot kill frame. A mesh edited after its first death needs [method forget].

const CHANNEL := "player.ragdoll"

## Meshes kept before the cache starts over: a game has a handful of bodies, not hundreds.
const MAX_KEPT := 64

static var _kept: Dictionary = {}


## The readable surfaces of [param mesh] (skinned: vertices, bones and weights present), each a
## Dictionary with [code]verts normals uvs index bones weights per strongest by_bind samples[/code].
## [code]by_bind[b][/code] holds the first index (into [code]index[/code]) of every triangle whose first
## corner [code]b[/code] moves most; [code]samples[b][/code] every third vertex [code]b[/code] moves most.
static func of(mesh: Mesh) -> Array:
	if mesh == null:
		return []
	var key := mesh.get_instance_id()
	if _kept.has(key):
		return _kept[key]
	if _kept.size() >= MAX_KEPT:
		_kept.clear()
	var out: Array = []
	for surface in mesh.get_surface_count():
		var read := _read(mesh, surface)
		if not read.is_empty():
			out.append(read)
	_kept[key] = out
	DotLog.debug(CHANNEL, "skin arrays read", {"mesh": mesh.resource_name, "surfaces": out.size()})
	return out


## Reads [param figure]'s skinned meshes now (under a loading cover), so its first death does not.
## Returns the surfaces read.
static func warm(figure: Node) -> int:
	var n := 0
	for mesh in DotPlayerRagdoll.skinned_meshes(figure):
		n += of(mesh.mesh).size()
	return n


## Drops what was kept for [param mesh] (every mesh when null).
static func forget(mesh: Mesh = null) -> void:
	if mesh == null:
		_kept.clear()
	else:
		var _e := _kept.erase(mesh.get_instance_id())


static func _read(mesh: Mesh, surface: int) -> Dictionary:
	var arrays := mesh.surface_get_arrays(surface)
	if arrays.size() <= Mesh.ARRAY_WEIGHTS or arrays[Mesh.ARRAY_VERTEX] == null or arrays[Mesh.ARRAY_BONES] == null:
		return {}
	if arrays[Mesh.ARRAY_WEIGHTS] == null:
		return {}
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	if verts.is_empty() or bones.is_empty():
		return {}
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var per := bones.size() / verts.size()
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(verts.size()))

	var strongest := PackedInt32Array()
	var _r := strongest.resize(verts.size())
	var top := -1
	for v in verts.size():
		var best := 0
		for k in per:
			if weights[v * per + k] > weights[v * per + best]:
				best = k
		strongest[v] = bones[v * per + best]
		top = maxi(top, strongest[v])

	# Plain Arrays while filling: a packed array read out of an Array is a copy, and appends to it are lost.
	var tris: Array = []
	var picks: Array = []
	for b in top + 1:
		tris.append([])
		picks.append([])
	for t in range(0, index.size() - 2, 3):
		var bind := strongest[index[t]]
		if bind >= 0:
			(tris[bind] as Array).append(t)
	for v in range(0, verts.size(), 3):
		var bind := strongest[v]
		if bind >= 0:
			(picks[bind] as Array).append(verts[v])
	var by_bind: Array[PackedInt32Array] = []
	var samples: Array[PackedVector3Array] = []
	for b in top + 1:
		by_bind.append(PackedInt32Array(tris[b]))
		samples.append(PackedVector3Array(picks[b]))

	return {
		"verts": verts,
		"normals": arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array(),
		"uvs": arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array(),
		"index": index,
		"bones": bones,
		"weights": weights,
		"per": per,
		"strongest": strongest,
		"by_bind": by_bind,
		"samples": samples,
	}
