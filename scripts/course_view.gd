class_name CourseView
extends CanvasLayer
## "AI Engineering" course mode: chapter map, lesson player with narration, mini labs and a quiz.
## Built from data/aie_course.json (277 cards over 43 lessons in 7 chapters).

signal closed
signal open_lab_requested(lab_id: String)
signal show_concept_requested(node_id: String)
signal narration_requested(text: String)

const PROGRESS_PATH: String = "user://course_progress.json"

var course: Dictionary = {}
var progress: Dictionary = {}
var ap_theme: Theme

var panel: PanelContainer
var chapter_box: VBoxContainer
var lesson_box: VBoxContainer
var card_box: VBoxContainer
var head_title: Label
var head_sub: Label
var bar: ProgressBar

var chapter_i: int = 0
var lesson: Dictionary = {}
var card_i: int = 0
var quiz_i: int = 0
var quiz_score: int = 0
var in_quiz: bool = false
var quiz_opts: VBoxContainer
var _answered: bool = false


func setup(theme_in: Theme, course_data: Dictionary) -> void:
	ap_theme = theme_in
	course = course_data
	_load_progress()
	layer = 40
	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.008, 0.014, 0.035, 0.97)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)
	# header
	var head: HBoxContainer = HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	root.add_child(head)
	var t: Label = Label.new()
	t.text = "AI ENGINEERING"
	t.add_theme_font_size_override("font_size", 30)
	t.add_theme_color_override("font_color", Color(0.6, 0.88, 1.0))
	head.add_child(t)
	head_sub = Label.new()
	head_sub.add_theme_font_size_override("font_size", 15)
	head_sub.modulate = Color(0.8, 0.88, 1.0, 0.85)
	head.add_child(head_sub)
	var gap: Control = Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(gap)
	bar = ProgressBar.new()
	bar.custom_minimum_size = Vector2(240, 10)
	bar.show_percentage = false
	head.add_child(bar)
	var close_btn: Button = Button.new()
	close_btn.text = "✕  Close"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(func() -> void: closed.emit())
	head.add_child(close_btn)
	# 3 columns
	var cols: HBoxContainer = HBoxContainer.new()
	cols.add_theme_constant_override("separation", 12)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)
	chapter_box = _column(cols, 230)
	lesson_box = _column(cols, 330)
	card_box = _column(cols, 320, true)
	panel = PanelContainer.new()


func _column(parent: Node, width: int, expand: bool = false) -> VBoxContainer:
	var p: PanelContainer = PanelContainer.new()
	if width > 0:
		p.custom_minimum_size = Vector2(width, 0)
	if expand:
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.clip_contents = true
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.05, 0.1, 0.92)
	sb.border_color = Color(0.25, 0.5, 0.85, 0.5)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(10)
	p.add_theme_stylebox_override("panel", sb)
	parent.add_child(p)
	var sc: ScrollContainer = ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p.add_child(sc)
	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(vb)
	return vb


func _load_progress() -> void:
	if FileAccess.file_exists(PROGRESS_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROGRESS_PATH))
		if parsed is Dictionary:
			progress = parsed


func _save_progress() -> void:
	var f: FileAccess = FileAccess.open(PROGRESS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(progress))


func lesson_progress(id: String) -> Dictionary:
	return progress.get(id, {})


func open() -> void:
	visible = true
	_refresh_header()
	_show_chapters()


func _refresh_header() -> void:
	var done: int = 0
	var total: int = 0
	for ch in course["chapters"]:
		for l in ch["lessons"]:
			total += 1
			if progress.has(l["id"]):
				done += 1
	head_sub.text = "%d of %d lessons finished" % [done, total]
	bar.max_value = maxf(float(total), 1.0)
	bar.value = float(done)


func _clear(box: VBoxContainer) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


func _label(box: Node, text: String, size: int, col: Color) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(l)
	return l


func _btn(box: Node, text: String, cb: Callable, accent: bool = false, wrap_text: bool = true) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	# list buttons wrap to the column width; buttons placed side by side must not wrap,
	# or their minimum width collapses and every character lands on its own line
	if wrap_text:
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	else:
		b.autowrap_mode = TextServer.AUTOWRAP_OFF
	b.custom_minimum_size = Vector2(0, 0)
	b.pressed.connect(cb)
	if accent:
		var sb: StyleBoxFlat = StyleBoxFlat.new()
		sb.bg_color = Color(0.13, 0.4, 0.75, 0.85)
		sb.set_corner_radius_all(8)
		sb.set_content_margin_all(8)
		b.add_theme_stylebox_override("normal", sb)
	box.add_child(b)
	return b


func _show_chapters() -> void:
	_clear(chapter_box)
	_clear(lesson_box)
	_clear(card_box)
	_label(chapter_box, "Chapters", 20, Color(1.0, 0.85, 0.35))
	for i in course["chapters"].size():
		var ch: Dictionary = course["chapters"][i]
		var n: int = ch["lessons"].size()
		var done: int = 0
		for l in ch["lessons"]:
			if progress.has(l["id"]):
				done += 1
		var col: Color = Color.html(ch.get("colour", "#3fa7ff"))
		var b: Button = _btn(chapter_box, "%d.  %s\n      %d/%d lessons" % [ch["n"], ch["title"], done, n],
			func() -> void: _open_chapter(i))
		b.add_theme_color_override("font_color", col.lightened(0.25))
		if done == n:
			b.text += "   ✓"
	_open_chapter(chapter_i)


func _open_chapter(i: int) -> void:
	chapter_i = i
	var ch: Dictionary = course["chapters"][i]
	_clear(lesson_box)
	_label(lesson_box, ch["title"], 20, Color.html(ch.get("colour", "#3fa7ff")).lightened(0.3))
	for l in ch["lessons"]:
		var mark: String = "✓ " if progress.has(l["id"]) else ""
		var b: Button = _btn(lesson_box, "%s%s  %s\n      %d cards   ·   %s" % [mark, l["id"], l["title"], l["cards"].size(), l["goal"]],
			func() -> void: open_lesson(l["id"]))
		if l["id"] == lesson.get("id", ""):
			b.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	_show_lesson_toc(ch)


func _show_lesson_toc(ch: Dictionary) -> void:
	_clear(card_box)
	_label(card_box, "Pick a lesson", 18, Color(0.85, 0.9, 1.0))
	var total: int = 0
	for l in ch["lessons"]:
		total += l["cards"].size()
	_label(card_box, "%d lessons  ·  %d cards in this chapter" % [ch["lessons"].size(), total], 14, Color(0.7, 0.8, 0.95))


func open_lesson(id: String) -> void:
	for ch in course["chapters"]:
		for l in ch["lessons"]:
			if l["id"] == id:
				lesson = l
	card_i = 0
	in_quiz = false
	quiz_i = 0
	quiz_score = 0
	lesson["quiz_size"] = _lesson_quiz().size()
	_open_chapter(chapter_i)
	_show_card()
	_speak_current()


func _show_card() -> void:
	_clear(card_box)
	in_quiz = false
	var pr: Dictionary = lesson_progress(lesson["id"])
	var seen: int = maxi(int(pr.get("cards", 0)), card_i)
	pr["cards"] = seen
	progress[lesson["id"]] = pr
	_save_progress()
	_refresh_header()
	var c: Dictionary = lesson["cards"][card_i]
	_label(card_box, "Lesson %s  ·  card %d of %d" % [lesson["id"], card_i + 1, lesson["cards"].size()], 14, Color(0.7, 0.85, 1.0))
	# navigation stays at the top so it is always reachable
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	card_box.add_child(row)
	_btn(row, "◀  Back", func() -> void: _move(-1), false, false)
	_btn(row, "▶  Next", func() -> void: _move(1), true, false)
	_btn(row, "🔊  Listen", func() -> void: _speak_current(), false, false)
	_btn(row, "🔗  Show in 3D", func() -> void: show_concept_requested.emit(String(c["id"])), false, false)
	var lab: String = String(c.get("lab", ""))
	if lab != "":
		_btn(row, "🧪  " + lab.replace("_", " "), func() -> void: open_lab_requested.emit(lab), false, false)
	_label(card_box, c["title"], 24, Color(1.0, 0.88, 0.45))
	_label(card_box, c.get("text", ""), 16, Color(0.9, 0.94, 1.0))
	if c.get("points", []).size() > 0:
		var pts: PackedStringArray = []
		for p in c["points"]:
			pts.append("•  " + String(p))
		_label(card_box, "\n".join(pts), 15, Color(0.82, 0.9, 1.0))
	if String(c.get("formula", "")) != "":
		_label(card_box, "🧮  " + String(c["formula"]), 16, Color(0.55, 0.95, 0.8))
	if String(c.get("example", "")) != "":
		_label(card_box, "Example:  " + String(c["example"]), 15, Color(1.0, 0.85, 0.6))
	if card_i == lesson["cards"].size() - 1:
		_btn(card_box, "🏁  Finish lesson with the quiz (%d questions)" % lesson["quiz_size"], func() -> void: _start_quiz(), true)


## Keyboard / controller helpers for the lesson player.
func advance() -> void:
	if in_quiz:
		quiz_i += 1
		_show_quiz()
	else:
		_move(1)


func back() -> void:
	if not in_quiz:
		_move(-1)


func _move(step: int) -> void:
	var n: int = lesson["cards"].size()
	var ni: int = clampi(card_i + step, 0, n - 1)
	if ni == card_i and step > 0:
		return
	card_i = ni
	_show_card()
	_speak_current()


func _speak_current() -> void:
	if lesson.is_empty() or in_quiz:
		return
	var c: Dictionary = lesson["cards"][card_i]
	var say: String = String(c.get("say", ""))
	if say != "":
		_say(say)


func _say(t: String) -> void:
	if t != "":
		narration_requested.emit(t)


# ── lesson quiz (answer text as 4 buttons; distractors from the lesson file) ──
func _start_quiz() -> void:
	in_quiz = true
	quiz_i = 0
	quiz_score = 0
	_show_quiz()


func _show_quiz() -> void:
	_clear(card_box)
	_answered = false
	var qs: Array = _lesson_quiz()
	if quiz_i >= qs.size():
		var pr: Dictionary = lesson_progress(lesson["id"])
		pr["quiz_best"] = maxi(int(pr.get("quiz_best", 0)), quiz_score)
		pr["done"] = true
		progress[lesson["id"]] = pr
		_save_progress()
		_refresh_header()
		_show_chapters()
		open_lesson(lesson["id"])
		return
	var q: Dictionary = qs[quiz_i]
	_label(card_box, "Quiz  %d / %d          Score: %d" % [quiz_i + 1, qs.size(), quiz_score], 15, Color(1.0, 0.85, 0.35))
	_label(card_box, String(q["q"]), 20, Color(0.92, 0.96, 1.0))
	quiz_opts = VBoxContainer.new()
	quiz_opts.add_theme_constant_override("separation", 6)
	card_box.add_child(quiz_opts)
	var opts: Array = [String(q["answer"])] + (q.get("distractors", []) as Array).duplicate()
	opts.shuffle()
	for o in opts:
		_btn(quiz_opts, String(o), func() -> void: _answer(String(o), q))

func _lesson_quiz() -> Array:
	var out: Array = []
	for q in course["quiz"]:
		if q["lesson"] == lesson.get("id", ""):
			out.append(q)
	return out


func _answer(picked: String, q: Dictionary) -> void:
	if _answered:
		return
	_answered = true
	var right: bool = picked == String(q["answer"])
	if right:
		quiz_score += 1
	_label(card_box, ("✓  Correct!" if right else "✗  Not quite — the answer is:  " + String(q["answer"])), 19,
		Color(0.4, 0.95, 0.5) if right else Color(1.0, 0.5, 0.5))
	_label(card_box, String(q.get("why", "")), 16, Color(0.85, 0.9, 1.0))
	_say(String(q.get("why", "")))
	_btn(card_box, "Continue  ▶", func() -> void:
		quiz_i += 1
		_show_quiz(), true)