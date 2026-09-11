@tool
extends EditorPlugin

## Editor entry point for dot-player-char. Registers inspector types only.
##
## No autoloads: two players in one scene are two characters, and a character preview in
## a menu beside the player wearing it is a third.

const _ICON := "res://addons/dot_player_char/icon_placeholder.svg"

const _NODES := "res://addons/dot_player_char/nodes/"

const _TYPES := [
	["DotPlayerChar", "Node", _NODES + "dot_player_char.gd"],
	["DotPlayerCharVisual", "Node", _NODES + "dot_player_char_visual.gd"],
	["DotPlayerModelVisual", "Node", _NODES + "dot_player_model_visual.gd"],
	["DotPlayerModelRig", "Node3D", _NODES + "dot_player_model_rig.gd"],
	["DotPlayerSpriteVisual", "Node", _NODES + "dot_player_sprite_visual.gd"],
	["DotPlayerAnimDriver", "Node", _NODES + "dot_player_anim_driver.gd"],
	["DotPlayerAnimPlayerSink", "Node", _NODES + "dot_player_anim_player_sink.gd"],
	["DotPlayerAnimSpriteSink", "Node", _NODES + "dot_player_anim_sprite_sink.gd"],
]


func _enter_tree() -> void:
	var icon: Texture2D = null
	if ResourceLoader.exists(_ICON):
		icon = load(_ICON) as Texture2D

	for entry in _TYPES:
		add_custom_type(entry[0], entry[1], load(entry[2]), icon)


func _exit_tree() -> void:
	for i in range(_TYPES.size() - 1, -1, -1):
		remove_custom_type(_TYPES[i][0])
