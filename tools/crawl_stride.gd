extends Node

## Prints each stride clip's natural ground speed (lower-foot travel per clip second, figure frame)
## so a rate scale can be chosen from numbers: `hv <wt> scene res://tools/crawl_stride.tscn`.

func _ready() -> void:
	var g := DotHumanoidFigure.new()
	add_child(g)
	g.build(DotHumanoidLook.stock(9), 1.8)
	await get_tree().process_frame
	for id: StringName in [DotHumanoidClips.CRAWL, DotHumanoidClips.WALK, DotHumanoidClips.CROUCH_WALK, DotHumanoidClips.ZOMBIE_WALK, DotHumanoidClips.SPRINT]:
		var animation: Animation = g._anim.get_animation(id)
		if animation == null:
			print("STRIDE %s missing" % id)
			continue
		var table := DotHumanoidStride.table_for(animation, g._skeleton, g._model, g._to_figure())
		var total := table[-1] if table.size() > 1 else 0.0
		print("STRIDE %s length=%.3f s travel=%.3f m natural=%.3f m/s" % [id, animation.length, total, total / animation.length])
	get_tree().quit()
