extends Node
## Opens the app with the Token Lab showing, for manual / harness click tests.

var v: Node


func _ready() -> void:
	v = (load("res://ds_main.tscn") as PackedScene).instantiate()
	add_child(v)
	await get_tree().create_timer(1.2).timeout
	v.intro.begin_leave()
	await get_tree().create_timer(1.0).timeout
	v.menu_panel.visible = false
	await get_tree().create_timer(0.3).timeout
	v._toggle_lab()
	print("token lab open: ", v.lab_panel.visible)


func _process(_d: float) -> void:
	if v != null and v.get("lab_panel") != null and Engine.get_process_frames() % 60 == 0:
		print("t=", Time.get_ticks_msec(), " lab visible=", v.lab_panel.visible)
