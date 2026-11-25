extends Node
## Visual check of the story-style course: map, several lesson stages mid-story, Read more,
## quiz feedback. Saves PNGs to _webcheck/story_<name>.png.

const OUT: String = "res://_webcheck/story_%s.png"

var v: Node


func _ready() -> void:
	v = (load("res://ds_main.tscn") as PackedScene).instantiate()
	add_child(v)
	await get_tree().create_timer(1.2).timeout
	v.intro.begin_leave()
	await get_tree().create_timer(1.0).timeout
	v.menu_panel.visible = false
	v.demo_voice = false
	v._toggle_course()
	var cv: CourseView = v.course_view
	cv.chapter_i = 1
	cv.show_map()
	await get_tree().create_timer(0.8).timeout
	await _shot("map")
	for spec in [["2.4", 1, 3], ["2.2", 0, 2], ["3.3", 1, 3], ["6.2", 1, 2], ["7.4", 2, 3], ["4.5", 0, 2]]:
		cv.open_lesson(String(spec[0]))
		cv.card_i = int(spec[1])
		cv._show_card()
		cv._halt()
		cv._play_beat(int(spec[2]))
		cv.playing = false
		await get_tree().create_timer(1.6).timeout
		await _shot("L%s_c%d" % [spec[0], spec[1]])
	cv._toggle_read()
	await get_tree().create_timer(0.4).timeout
	await _shot("readmore")
	cv._toggle_read()
	cv._start_quiz()
	await get_tree().create_timer(0.4).timeout
	var q: Dictionary = cv._lesson_quiz()[0]
	cv._answer(String(q["answer"]), q)
	await get_tree().create_timer(0.35).timeout
	await _shot("quiz")
	get_tree().quit()


func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT % n))
	print("saved ", n)
