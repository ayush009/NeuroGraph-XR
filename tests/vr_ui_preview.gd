extends Node
## Test scene: runs the real game with the VR screen shown on the desktop monitor
## (same floating 1280x720 screen as in the headset, steered with the mouse).


func _ready() -> void:
	var viewer: Node = (load("res://ds_main.tscn") as PackedScene).instantiate()
	viewer.preview_vr_ui = true
	add_child(viewer)
