extends Node
## Captures the README screenshots of course mode straight out of the running app.

const OUT_DIR: String = "C:/Users/aayus/Documents/NeuroGraph_XR/docs/media/"

var v: Node


func _ready() -> void:
	v = (load("res://ds_main.tscn") as PackedScene).instantiate()
	add_child(v)
	await get_tree().create_timer(1.2).timeout
	v.intro.begin_leave()
	await get_tree().create_timer(1.0).timeout
	v.menu_panel.visible = false
	await get_tree().create_timer(0.4).timeout
	v.demo_voice = false
	# 1) chapter story path (with two lessons finished, so stars + the waiting robot show)
	v._toggle_course()
	var cv: CourseView = v.course_view
	var saved: Dictionary = cv.progress.duplicate(true)
	cv.progress = {"3.1": {"done": true, "quiz_best": 5}, "3.2": {"done": true, "quiz_best": 4}}
	cv.chapter_i = 2
	cv.show_map()
	await get_tree().create_timer(0.8).timeout
	await _shot("09_course_chapters")
	# 2) an animated story scene (attention arcs, mid-story)
	cv.open_lesson("3.3")
	cv.card_i = 1
	cv._show_card()
	cv._halt()
	cv._play_beat(3)
	cv.playing = false
	await get_tree().create_timer(1.6).timeout
	await _shot("10_course_lesson")
	# 3) the lesson quiz
	cv._start_quiz()
	await get_tree().create_timer(0.5).timeout
	cv._answer(String(cv._lesson_quiz()[0]["answer"]), cv._lesson_quiz()[0])
	await get_tree().create_timer(0.35).timeout
	await _shot("11_course_quiz")
	cv.progress = saved
	cv._save_progress()
	print("screenshots written to ", OUT_DIR)
	await get_tree().create_timer(0.4).timeout
	get_tree().quit()


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)      # JPG saving needs a 3-channel image
	var err: int = img.save_jpg(OUT_DIR + shot_name + ".jpg", 0.92)
	print("saved ", shot_name, "  size=", img.get_size(), "  err=", err)