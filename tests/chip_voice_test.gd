extends Node
## Clicking a suggested question must be answered in text AND voice; a new click stops the old voice.

var v: Node


func _ready() -> void:
	v = (load("res://ds_main.tscn") as PackedScene).instantiate()
	v.preview_vr_ui = true
	add_child(v)
	await get_tree().create_timer(1.0).timeout
	v.intro.begin_leave()
	await get_tree().create_timer(1.0).timeout
	v.menu_panel.visible = false
	v.ask_on = true
	await get_tree().create_timer(0.5).timeout
	var chips: Array = v.chips_row.get_children()
	_log("suggestion buttons: ", chips.map(func(b): return (b as Button).text))
	(chips[0] as Button).pressed.emit()   # same as clicking it
	var t0: int = Time.get_ticks_msec()
	while v._ai_busy:
		await get_tree().process_frame
	_log("text answer after ", Time.get_ticks_msec() - t0, " ms: ", v.answer_label.text.substr(0, 90), "...")
	var t1: int = Time.get_ticks_msec()
	while not v.answer_player.playing and Time.get_ticks_msec() - t1 < 10000:
		await get_tree().process_frame
	_log("VOICE for the clicked suggestion: playing=", v.answer_player.playing, "  started ", Time.get_ticks_msec() - t1, " ms after the text")
	await get_tree().create_timer(1.5).timeout
	(chips[1] as Button).pressed.emit()   # click another one while the first is still speaking
	await get_tree().process_frame
	_log("2nd click: old voice stopped=", not v.answer_player.playing)
	while v._ai_busy:
		await get_tree().process_frame
	var t2: int = Time.get_ticks_msec()
	while not v.answer_player.playing and Time.get_ticks_msec() - t2 < 10000:
		await get_tree().process_frame
	_log("2nd suggestion spoken: ", v.answer_player.playing, "   answer: ", v.answer_label.text.substr(0, 80), "...")


func _log(a: Variant = "", b: Variant = "", c: Variant = "", d: Variant = "", e: Variant = "", f: Variant = "") -> void:
	var line: String = str(a) + str(b) + str(c) + str(d) + str(e) + str(f)
	var fa: FileAccess = FileAccess.open("user://chip_voice_test.txt", FileAccess.READ_WRITE if FileAccess.file_exists("user://chip_voice_test.txt") else FileAccess.WRITE)
	fa.seek_end()
	fa.store_line(line)
	fa.close()
