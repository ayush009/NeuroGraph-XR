extends Node
## Plays lesson 2.4 card 1 with the narrator ON and logs when each beat starts, whether a
## pre-recorded voice file existed for its caption, and whether the next beat waited for it.

var v: Node


func _ready() -> void:
	v = (load("res://ds_main.tscn") as PackedScene).instantiate()
	add_child(v)
	await get_tree().create_timer(1.2).timeout
	v.intro.begin_leave()
	await get_tree().create_timer(1.0).timeout
	v.menu_panel.visible = false
	v.demo_voice = true
	v._toggle_course()
	var cv: CourseView = v.course_view
	var missing: int = 0
	var total: int = 0
	for ch in cv.course["chapters"]:
		for l in ch["lessons"]:
			for c in l["cards"]:
				for b in c["scene"]["beats"]:
					total += 1
					if not ResourceLoader.exists("res://assets/narration/%s.mp3" % v._narr_key(String(b["cap"]))):
						missing += 1
	print("beat captions with a voice file: ", total - missing, " / ", total)
	cv.open_lesson("2.4")
	var last: int = -1
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 30000 and cv.card_i == 0:
		if cv.beat_i != last:
			last = cv.beat_i
			print("t=%5.1fs  beat %d  voice playing=%s  '%s'" % [(Time.get_ticks_msec() - t0) / 1000.0, cv.beat_i,
				v.narr_player.playing, cv.stage.beat_caption(cv.beat_i).left(60)])
		if not cv.playing:
			print("t=%5.1fs  story finished, waiting for the learner (playing=false)" % ((Time.get_ticks_msec() - t0) / 1000.0))
			break
		await get_tree().process_frame
	get_tree().quit()
