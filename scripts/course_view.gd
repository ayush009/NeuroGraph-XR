class_name CourseView
extends CanvasLayer
## "AI Engineering" course mode, told as a story:
##  • MAP     - chapter tabs + the lessons as stepping stones on a winding path
##  • LESSON  - a big animated stage (StoryStage) that builds each idea step by step while a
##              friendly guide robot says one short sentence per step (narrated). Everything on the
##              stage can be hovered / clicked. The full text is still there behind "Read more".
##  • QUIZ    - big friendly answer buttons, confetti, stars, then on to the next lesson.
## Built from data/aie_course.json (7 chapters, 43 lessons, 277 cards; every card has a "scene").

signal closed
signal open_lab_requested(lab_id: String)
signal show_concept_requested(node_id: String)
signal narration_requested(text: String)

const PROGRESS_PATH: String = "user://course_progress.json"
const SHORT: Array = ["Intro", "Tokens", "How LLMs work", "Training", "Inference", "Prompting", "RAG"]
const ROBOT_PATH: String = "res://assets/generated/guide_bot.png"

var course: Dictionary = {}
var progress: Dictionary = {}
var ap_theme: Theme
var voice_busy: Callable          # set by the host: is the narrator still talking?
var stop_voice: Callable          # set by the host: silence the narrator

# state
var chapter_i: int = 0
var lesson: Dictionary = {}
var card_i: int = 0
var beat_i: int = 0
var playing: bool = true
var voice_on: bool = true
var in_quiz: bool = false
var quiz_i: int = 0
var quiz_score: int = 0
var _answered: bool = false
var _beat_elapsed: float = 0.0
var _after_voice: float = 0.0
var _t: float = 0.0

# ui
var map_root: VBoxContainer
var lesson_root: VBoxContainer
var tabs_box: HBoxContainer
var map_title: Label
var map_sub: Label
var path_map: Control
var head_sub: Label
var bar: ProgressBar
var lesson_title: Label
var card_dots: Label
var stage: StoryStage
var stage_holder: Control
var read_panel: PanelContainer
var read_box: VBoxContainer
var quiz_panel: PanelContainer
var quiz_box: VBoxContainer
var robot: TextureRect
var robot_holder: Control
var bubble_lbl: Label
var beat_dots: Label
var hint_lbl: Label
var play_btn: Button
var voice_btn: Button
var next_card_btn: Button
var lab_btn: Button
var controls_row: HBoxContainer
var fx: Confetti
var _stones: Array = []           # [{"rect": Rect2, "id": String}]
var _hover_stone: int = -1
var _robot_tex: Texture2D


# ───────────────────────── setup ─────────────────────────
func setup(theme_in: Theme, course_data: Dictionary) -> void:
	ap_theme = theme_in
	course = course_data
	_load_progress()
	layer = 40
	if ResourceLoader.exists(ROBOT_PATH):
		_robot_tex = load(ROBOT_PATH)
	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.008, 0.014, 0.035, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	if ap_theme != null:
		margin.theme = ap_theme
	add_child(margin)
	var both: Control = Control.new()
	margin.add_child(both)
	_build_map(both)
	_build_lesson(both)
	fx = Confetti.new()
	fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fx)
	lesson_root.visible = false


func _full(c: Control) -> void:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.offset_left = 0
	c.offset_top = 0
	c.offset_right = 0
	c.offset_bottom = 0


func _label(box: Node, text: String, size: int, col: Color, wrap_text: bool = true) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if wrap_text:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(l)
	return l


func _btn(box: Node, text: String, cb: Callable, accent: bool = false, wrap_text: bool = false) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap_text else TextServer.AUTOWRAP_OFF
	b.pressed.connect(cb)
	b.add_theme_font_size_override("font_size", 16)
	if accent:
		_paint(b, Color(0.13, 0.45, 0.85, 0.95))
	box.add_child(b)
	return b


func _paint(b: Button, col: Color) -> void:
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.95))
	for st in ["normal", "hover", "pressed", "disabled"]:
		var sb: StyleBoxFlat = StyleBoxFlat.new()
		sb.bg_color = col.lightened(0.12) if st == "hover" else (col.darkened(0.15) if st == "pressed" else col)
		sb.set_corner_radius_all(10)
		sb.content_margin_left = 14
		sb.content_margin_right = 14
		sb.content_margin_top = 7
		sb.content_margin_bottom = 7
		b.add_theme_stylebox_override(st, sb)


func _panel_style(col: Color = Color(0.03, 0.05, 0.1, 0.95), border: Color = Color(0.3, 0.55, 0.95, 0.5), radius: int = 14) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = col
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(12)
	return sb


# ── MAP: chapter tabs + winding lesson path ──
func _build_map(parent: Control) -> void:
	map_root = VBoxContainer.new()
	_full(map_root)
	map_root.add_theme_constant_override("separation", 8)
	parent.add_child(map_root)
	var head: HBoxContainer = HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	map_root.add_child(head)
	_label(head, "AI ENGINEERING", 28, Color(0.6, 0.88, 1.0), false)
	head_sub = _label(head, "", 15, Color(0.8, 0.88, 1.0, 0.85), false)
	head_sub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var gap: Control = Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(gap)
	bar = ProgressBar.new()
	bar.custom_minimum_size = Vector2(200, 12)
	bar.show_percentage = false
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(bar)
	_btn(head, "✕  Close", func() -> void: closed.emit())
	tabs_box = HBoxContainer.new()
	tabs_box.add_theme_constant_override("separation", 6)
	map_root.add_child(tabs_box)
	var info: HBoxContainer = HBoxContainer.new()
	info.add_theme_constant_override("separation", 10)
	map_root.add_child(info)
	map_title = _label(info, "", 22, Color(1.0, 0.88, 0.45), false)
	map_sub = _label(info, "", 15, Color(0.75, 0.85, 1.0), false)
	map_sub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var pp: PanelContainer = PanelContainer.new()
	pp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pp.add_theme_stylebox_override("panel", _panel_style(Color(0.02, 0.035, 0.075, 0.95), Color(0.3, 0.55, 0.95, 0.3), 16))
	map_root.add_child(pp)
	path_map = Control.new()
	path_map.mouse_filter = Control.MOUSE_FILTER_STOP
	path_map.draw.connect(_draw_path_map)
	path_map.gui_input.connect(_on_map_input)
	pp.add_child(path_map)


# ── LESSON: stage + guide + controls ──
func _build_lesson(parent: Control) -> void:
	lesson_root = VBoxContainer.new()
	_full(lesson_root)
	lesson_root.add_theme_constant_override("separation", 8)
	parent.add_child(lesson_root)
	var head: HBoxContainer = HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	lesson_root.add_child(head)
	_btn(head, "◀  Map", func() -> void: show_map())
	lesson_title = _label(head, "", 20, Color(1.0, 0.88, 0.45), false)
	lesson_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lesson_title.clip_text = true
	lesson_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	card_dots = _label(head, "", 16, Color(0.7, 0.85, 1.0), false)
	card_dots.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_btn(head, "✕", func() -> void: closed.emit())
	# stage area (stage, "read more" and quiz share it)
	stage_holder = Control.new()
	stage_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lesson_root.add_child(stage_holder)
	stage = StoryStage.new()
	_full(stage)
	stage_holder.add_child(stage)
	stage.item_clicked.connect(_on_item_clicked)
	read_panel = PanelContainer.new()
	_full(read_panel)
	read_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.03, 0.05, 0.1, 0.98)))
	read_panel.visible = false
	stage_holder.add_child(read_panel)
	var rsc: ScrollContainer = ScrollContainer.new()
	rsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	read_panel.add_child(rsc)
	read_box = VBoxContainer.new()
	read_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	read_box.add_theme_constant_override("separation", 8)
	rsc.add_child(read_box)
	quiz_panel = PanelContainer.new()
	_full(quiz_panel)
	quiz_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.02, 0.035, 0.075, 0.98)))
	quiz_panel.visible = false
	stage_holder.add_child(quiz_panel)
	var qsc: ScrollContainer = ScrollContainer.new()
	qsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	quiz_panel.add_child(qsc)
	quiz_box = VBoxContainer.new()
	quiz_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quiz_box.add_theme_constant_override("separation", 10)
	qsc.add_child(quiz_box)
	# guide robot + speech bubble
	var talk: HBoxContainer = HBoxContainer.new()
	talk.add_theme_constant_override("separation", 6)
	lesson_root.add_child(talk)
	robot_holder = Control.new()
	robot_holder.custom_minimum_size = Vector2(92, 92)
	talk.add_child(robot_holder)
	robot = TextureRect.new()
	robot.texture = _robot_tex
	robot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	robot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	robot.size = Vector2(92, 92)
	robot.pivot_offset = Vector2(46, 80)
	robot_holder.add_child(robot)
	var bub: PanelContainer = PanelContainer.new()
	bub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bsb: StyleBoxFlat = _panel_style(Color(0.95, 0.97, 1.0, 0.97), Color(0.55, 0.8, 1.0, 1.0), 18)
	bsb.content_margin_left = 18
	bsb.content_margin_right = 18
	bub.add_theme_stylebox_override("panel", bsb)
	talk.add_child(bub)
	var bvb: VBoxContainer = VBoxContainer.new()
	bvb.add_theme_constant_override("separation", 2)
	bub.add_child(bvb)
	bubble_lbl = _label(bvb, "", 20, Color(0.06, 0.09, 0.18))
	bubble_lbl.custom_minimum_size = Vector2(0, 52)
	bubble_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var brow: HBoxContainer = HBoxContainer.new()
	bvb.add_child(brow)
	beat_dots = _label(brow, "", 15, Color(0.2, 0.45, 0.85), false)
	hint_lbl = _label(brow, "", 14, Color(0.35, 0.4, 0.55), false)
	hint_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# controls
	var ctl: HBoxContainer = HBoxContainer.new()
	ctl.add_theme_constant_override("separation", 6)
	ctl.alignment = BoxContainer.ALIGNMENT_CENTER
	lesson_root.add_child(ctl)
	controls_row = ctl
	_btn(ctl, "⏮  Card", func() -> void: _move_card(-1))
	_btn(ctl, "◀", func() -> void: back())
	play_btn = _btn(ctl, "⏸  Pause", func() -> void: toggle_play(), true)
	_btn(ctl, "▶", func() -> void: _step_beat(1))
	next_card_btn = _btn(ctl, "Next card  ⏭", func() -> void: next_card())
	var sp: Control = Control.new()
	sp.custom_minimum_size = Vector2(18, 0)
	ctl.add_child(sp)
	voice_btn = _btn(ctl, "🔊  Voice on", func() -> void: _toggle_voice())
	_btn(ctl, "📖  Read more", func() -> void: _toggle_read())
	_btn(ctl, "🔗  3D", func() -> void:
		if not lesson.is_empty():
			show_concept_requested.emit(String(lesson["cards"][card_i]["id"])))
	lab_btn = _btn(ctl, "🧪  Lab", func() -> void:
		var lab: String = String(lesson["cards"][card_i].get("lab", ""))
		if lab != "":
			_halt()
			open_lab_requested.emit(lab))


# ───────────────────────── progress ─────────────────────────
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


func _is_done(id: String) -> bool:
	return bool(lesson_progress(id).get("done", false))


func _refresh_header() -> void:
	var done: int = 0
	var total: int = 0
	for ch in course["chapters"]:
		for l in ch["lessons"]:
			total += 1
			if _is_done(String(l["id"])):
				done += 1
	head_sub.text = "%d of %d lessons finished" % [done, total]
	bar.max_value = maxf(float(total), 1.0)
	bar.value = float(done)


# ───────────────────────── MAP ─────────────────────────
func open() -> void:
	visible = true
	show_map()


func show_map() -> void:
	_halt()
	in_quiz = false
	lesson_root.visible = false
	map_root.visible = true
	_refresh_header()
	_build_tabs()
	_open_chapter(chapter_i)


func _build_tabs() -> void:
	for c in tabs_box.get_children():
		tabs_box.remove_child(c)
		c.queue_free()
	for i in course["chapters"].size():
		var ch: Dictionary = course["chapters"][i]
		var done: int = 0
		for l in ch["lessons"]:
			if _is_done(String(l["id"])):
				done += 1
		var col: Color = Color.html(String(ch.get("colour", "#3fa7ff")))
		var mark: String = "  ✓" if done == ch["lessons"].size() else ""
		var b: Button = _btn(tabs_box, "%d  %s%s" % [int(ch["n"]), SHORT[i] if i < SHORT.size() else String(ch["title"]), mark],
			func() -> void: _open_chapter(i))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_paint(b, col.darkened(0.55) if i != chapter_i else col.darkened(0.15))
		b.add_theme_color_override("font_color", col.lightened(0.45) if i != chapter_i else Color(1, 1, 1))


func _open_chapter(i: int) -> void:
	chapter_i = clampi(i, 0, course["chapters"].size() - 1)
	var ch: Dictionary = course["chapters"][chapter_i]
	var done: int = 0
	for l in ch["lessons"]:
		if _is_done(String(l["id"])):
			done += 1
	map_title.text = "Chapter %d  ·  %s" % [int(ch["n"]), String(ch["title"])]
	map_sub.text = "%d / %d lessons done   ·   pick a stone to start a story" % [done, ch["lessons"].size()]
	_build_tabs()
	path_map.queue_redraw()


func _next_lesson_index(ch: Dictionary) -> int:
	for k in ch["lessons"].size():
		if not _is_done(String(ch["lessons"][k]["id"])):
			return k
	return -1


func _draw_path_map() -> void:
	var sz: Vector2 = path_map.size
	var ch: Dictionary = course["chapters"][chapter_i]
	var ls: Array = ch["lessons"]
	var n: int = ls.size()
	var col: Color = Color.html(String(ch.get("colour", "#3fa7ff")))
	var font: Font = path_map.get_theme_default_font()
	_stones.clear()
	var pts: Array = []
	for k in n:
		var fx_: float = float(k) / float(maxi(n - 1, 1))
		var x: float = lerpf(90.0, sz.x - 90.0, fx_)
		var y: float = sz.y * 0.55 + sin(float(k) * 1.25 + 0.4) * sz.y * 0.14
		pts.append(Vector2(x, y))
	# the road: a thick soft band with a dashed centre line
	var road: PackedVector2Array = PackedVector2Array()
	for k in n - 1:
		var a: Vector2 = pts[k]
		var b: Vector2 = pts[k + 1]
		for s in 12:
			var f: float = float(s) / 12.0
			var p: Vector2 = a.lerp(b, f)
			p.y = lerpf(a.y, b.y, (1.0 - cos(f * PI)) * 0.5)
			road.append(p)
	if n > 0:
		road.append(pts[n - 1])
	if road.size() > 1:
		path_map.draw_polyline(road, Color(col.r, col.g, col.b, 0.16), 30.0, true)
		path_map.draw_polyline(road, Color(col.r, col.g, col.b, 0.45), 3.0, true)
	var nxt: int = _next_lesson_index(ch)
	for k in n:
		var l: Dictionary = ls[k]
		var p: Vector2 = pts[k]
		var done: bool = _is_done(String(l["id"]))
		var is_next: bool = k == nxt
		var r: float = 34.0 + (4.0 * sin(_t * 4.0) if is_next else 0.0) + (4.0 if k == _hover_stone else 0.0)
		var fill: Color = Color(0.2, 0.75, 0.45) if done else (Color(1.0, 0.78, 0.3) if is_next else col.darkened(0.35))
		if is_next:
			path_map.draw_circle(p, r + 12.0, Color(1.0, 0.8, 0.3, 0.18 + 0.1 * sin(_t * 4.0)))
		path_map.draw_circle(p, r, fill)
		path_map.draw_arc(p, r, 0, TAU, 48, Color(1, 1, 1, 0.75), 3.0, true)
		var num: String = "✓" if done else String(l["id"])
		path_map.draw_string(font, p + Vector2(-40, 8), num, HORIZONTAL_ALIGNMENT_CENTER, 80, 22, Color(0.05, 0.07, 0.15) if (done or is_next) else Color(1, 1, 1))
		# title always under the stone (the robot and stars sit above it)
		var below: bool = true
		var ty: float = p.y + r + 26.0
		var tw: float = clampf(sz.x / float(maxi(n, 1)) + 14.0, 110.0, 220.0)
		var tfs: int = 16 if n <= 6 else 14
		path_map.draw_multiline_string(font, Vector2(p.x - tw * 0.5, ty), String(l["title"]), HORIZONTAL_ALIGNMENT_CENTER, tw, tfs, 3,
			Color(1, 1, 1) if k == _hover_stone else Color(0.85, 0.9, 1.0))
		if k == _hover_stone:
			var cards_n: int = (l["cards"] as Array).size()
			path_map.draw_string(font, Vector2(p.x - tw * 0.5, ty + 46.0), "%d animated scenes  ·  click to play" % cards_n,
				HORIZONTAL_ALIGNMENT_CENTER, tw, 13, Color(1.0, 0.85, 0.45))
		var best: int = int(lesson_progress(String(l["id"])).get("quiz_best", -1))
		if done and best >= 0:
			var qn: int = 0
			for q in course["quiz"]:
				if q["lesson"] == l["id"]:
					qn += 1
			var stars: int = _stars(best, qn)
			path_map.draw_string(font, p + Vector2(-50, -r - 10.0) if below else p + Vector2(-50, r + 20.0), "★".repeat(stars) + "☆".repeat(3 - stars),
				HORIZONTAL_ALIGNMENT_CENTER, 100, 17, Color(1.0, 0.85, 0.3))
		_stones.append({"rect": Rect2(p - Vector2(r + 6.0, r + 6.0), Vector2(r + 6.0, r + 6.0) * 2.0), "id": String(l["id"])})
	# the guide robot waits next to the next lesson
	if _robot_tex != null and nxt >= 0:
		# the robot floats straight above the next stone, its line written above its head
		var rp: Vector2 = (pts[nxt] as Vector2) + Vector2(-42, -136 + 6.0 * sin(_t * 2.2))
		rp.x = clampf(rp.x, 4.0, sz.x - 88.0)
		rp.y = maxf(rp.y, 30.0)
		path_map.draw_texture_rect(_robot_tex, Rect2(rp, Vector2(84, 84)), false)
		var say: String = "Start here!" if nxt == 0 else "Next up!"
		path_map.draw_string(font, rp + Vector2(-38, -6), say, HORIZONTAL_ALIGNMENT_CENTER, 160, 17, Color(1.0, 0.9, 0.5))
	elif nxt < 0:
		path_map.draw_string(font, Vector2(0, sz.y - 22.0), "Chapter complete - every lesson can be replayed any time.", HORIZONTAL_ALIGNMENT_CENTER, sz.x, 17, Color(0.5, 0.95, 0.65))


func _stars(score: int, total: int) -> int:
	if total <= 0:
		return 3
	var f: float = float(score) / float(total)
	return 3 if f >= 0.99 else (2 if f >= 0.66 else (1 if f > 0.0 else 0))


func _on_map_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		var h: int = -1
		for k in _stones.size():
			if (_stones[k]["rect"] as Rect2).has_point((ev as InputEventMouseMotion).position):
				h = k
		if h != _hover_stone:
			_hover_stone = h
			path_map.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if h >= 0 else Control.CURSOR_ARROW
	elif ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		for s in _stones:
			if (s["rect"] as Rect2).has_point((ev as InputEventMouseButton).position):
				open_lesson(String(s["id"]))
				return


# ───────────────────────── LESSON ─────────────────────────
func open_lesson(id: String) -> void:
	for ci in course["chapters"].size():
		for l in course["chapters"][ci]["lessons"]:
			if l["id"] == id:
				lesson = l
				chapter_i = ci
	if lesson.is_empty():
		return
	card_i = 0
	in_quiz = false
	quiz_i = 0
	quiz_score = 0
	lesson["quiz_size"] = _lesson_quiz().size()
	map_root.visible = false
	lesson_root.visible = true
	playing = true
	_show_card()


func _scene_of(c: Dictionary) -> Dictionary:
	if c.has("scene"):
		return c["scene"]
	# fallback: the key points appear one by one as a stack
	var items: Array = []
	for p in c.get("points", []):
		items.append({"l": String(p).substr(0, 40), "tip": String(p)})
	var beats: Array = [{"cap": String(c.get("say", c.get("title", ""))), "show": items.size()}]
	return {"t": "stack", "items": items, "beats": beats}


func _show_card() -> void:
	in_quiz = false
	quiz_panel.visible = false
	read_panel.visible = false
	stage.visible = true
	controls_row.visible = true
	var pr: Dictionary = lesson_progress(String(lesson["id"]))
	pr["cards"] = maxi(int(pr.get("cards", 0)), card_i + 1)
	progress[lesson["id"]] = pr
	_save_progress()
	var c: Dictionary = lesson["cards"][card_i]
	lesson_title.text = "%s  ·  %s" % [String(lesson["id"]), String(c["title"])]
	var dots: String = ""
	for k in lesson["cards"].size():
		dots += "●" if k == card_i else ("◉" if k < card_i else "○")
	card_dots.text = dots + "   %d / %d" % [card_i + 1, lesson["cards"].size()]
	var lab: String = String(c.get("lab", ""))
	lab_btn.visible = lab != ""
	lab_btn.text = "🧪  " + lab.replace("_lab", "").replace("_", " ").capitalize() + " lab"
	next_card_btn.text = "Quiz  🏁" if card_i == lesson["cards"].size() - 1 else "Next card  ⏭"
	stage.set_scene(_scene_of(c))
	_play_beat(0)


func _play_beat(i: int) -> void:
	beat_i = clampi(i, 0, stage.beat_count() - 1)
	stage.set_beat(beat_i)
	var cap: String = stage.beat_caption(beat_i)
	bubble_lbl.text = cap
	bubble_lbl.add_theme_color_override("font_color", Color(0.06, 0.09, 0.18))
	var d: String = ""
	for k in stage.beat_count():
		d += "● " if k == beat_i else ("◉ " if k < beat_i else "○ ")
	beat_dots.text = d
	hint_lbl.text = ""
	_beat_elapsed = 0.0
	_after_voice = 0.0
	if beat_i == stage.beat_count() - 1:
		_on_last_beat()
	if voice_on and cap != "":
		narration_requested.emit(cap)
	_update_play_btn()


func _on_last_beat() -> void:
	hint_lbl.text = "✨ your turn: hover or click anything on the stage"


func _step_beat(step: int) -> void:
	var nb: int = beat_i + step
	if nb >= stage.beat_count():
		playing = false
		stage.show_all()
		_update_play_btn()
		return
	if nb < 0:
		return
	_play_beat(nb)


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	if map_root.visible:
		path_map.queue_redraw()
		return
	# guide robot: gentle float; wobbles while it talks
	var talking: bool = voice_on and voice_busy.is_valid() and bool(voice_busy.call())
	robot.position = Vector2(0, 4.0 * sin(_t * 2.2))
	robot.rotation = (0.06 * sin(_t * 14.0)) if talking else (0.03 * sin(_t * 1.5))
	robot.scale = Vector2.ONE * (1.0 + (0.03 * absf(sin(_t * 9.0)) if talking else 0.0))
	if next_card_btn != null:
		var at_end: bool = not in_quiz and beat_i == stage.beat_count() - 1 and not playing
		next_card_btn.modulate = Color(1, 1, 1) if not at_end else Color(1.0, 0.95, 0.6).lerp(Color(1, 1, 1), 0.5 + 0.5 * sin(_t * 5.0))
	if not playing or in_quiz or read_panel.visible:
		return
	_beat_elapsed += delta
	var words: int = stage.beat_caption(beat_i).split(" ", false).size()
	var min_t: float = maxf(1.6, float(words) * (0.26 if voice_on else 0.36))
	if _beat_elapsed < min_t or talking:
		return
	_after_voice += delta
	if _after_voice < 0.7:
		return
	if beat_i < stage.beat_count() - 1:
		_play_beat(beat_i + 1)
	else:
		playing = false
		stage.show_all()
		_update_play_btn()


func _update_play_btn() -> void:
	if play_btn == null:
		return
	if playing:
		play_btn.text = "⏸  Pause"
	elif beat_i >= stage.beat_count() - 1:
		play_btn.text = "↻  Replay"
	else:
		play_btn.text = "▶  Play"


func toggle_play() -> void:
	if in_quiz:
		return
	if playing:
		_halt()
		return
	if beat_i >= stage.beat_count() - 1:
		playing = true
		stage.set_scene(_scene_of(lesson["cards"][card_i]))
		_play_beat(0)
		return
	playing = true
	_beat_elapsed = 0.0
	_after_voice = 0.0
	_update_play_btn()


func _halt() -> void:
	playing = false
	if stop_voice.is_valid():
		stop_voice.call()
	_update_play_btn()


func _toggle_voice() -> void:
	voice_on = not voice_on
	voice_btn.text = "🔊  Voice on" if voice_on else "🔇  Voice off"
	if not voice_on and stop_voice.is_valid():
		stop_voice.call()


func _on_item_clicked(_i: int, tip: String) -> void:
	if tip == "":
		return
	_halt()
	bubble_lbl.text = "💡  " + tip
	bubble_lbl.add_theme_color_override("font_color", Color(0.12, 0.25, 0.5))


func _toggle_read() -> void:
	if lesson.is_empty():
		return
	read_panel.visible = not read_panel.visible
	stage.visible = not read_panel.visible
	if not read_panel.visible:
		return
	_halt()
	for ch in read_box.get_children():
		read_box.remove_child(ch)
		ch.queue_free()
	var c: Dictionary = lesson["cards"][card_i]
	var top: HBoxContainer = HBoxContainer.new()
	read_box.add_child(top)
	var tl: Label = _label(top, String(c["title"]), 24, Color(1.0, 0.88, 0.45))
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn(top, "✕  Back to the story", func() -> void: _toggle_read())
	_label(read_box, String(c.get("text", "")), 17, Color(0.9, 0.94, 1.0))
	if (c.get("points", []) as Array).size() > 0:
		var pts: PackedStringArray = []
		for p in c["points"]:
			pts.append("•  " + String(p))
		_label(read_box, "\n".join(pts), 16, Color(0.82, 0.9, 1.0))
	if String(c.get("formula", "")) != "":
		_label(read_box, "🧮  " + String(c["formula"]), 16, Color(0.55, 0.95, 0.8))
	if String(c.get("example", "")) != "":
		_label(read_box, "Example:  " + String(c["example"]), 16, Color(1.0, 0.85, 0.6))


## Keyboard / controller: → steps the story forward (next beat, then next card, then quiz).
func advance() -> void:
	if in_quiz:
		if _answered:
			_next_question()
		return
	if read_panel.visible:
		_toggle_read()
		return
	if beat_i < stage.beat_count() - 1:
		_halt()
		_play_beat(beat_i + 1)
		playing = false
		_update_play_btn()
	else:
		next_card()


func back() -> void:
	if in_quiz:
		return
	if beat_i > 0:
		_halt()
		_play_beat(beat_i - 1)
		playing = false
		_update_play_btn()
	else:
		_move_card(-1)


## Esc: close an overlay / go back to the map. Returns false when the course itself should close.
func escape() -> bool:
	if read_panel.visible:
		_toggle_read()
		return true
	if lesson_root.visible:
		show_map()
		return true
	return false


func next_card() -> void:
	if card_i >= lesson["cards"].size() - 1:
		_start_quiz()
		return
	_move_card(1)


func _move_card(step: int) -> void:
	if lesson.is_empty():
		return
	var ni: int = clampi(card_i + step, 0, lesson["cards"].size() - 1)
	if ni == card_i:
		return
	card_i = ni
	playing = true
	_show_card()


# ───────────────────────── QUIZ ─────────────────────────
func _lesson_quiz() -> Array:
	var out: Array = []
	for q in course["quiz"]:
		if q["lesson"] == lesson.get("id", ""):
			out.append(q)
	return out


func _start_quiz() -> void:
	_halt()
	in_quiz = true
	quiz_i = 0
	quiz_score = 0
	quiz_panel.visible = true
	read_panel.visible = false
	stage.visible = false
	controls_row.visible = false
	lesson_title.text = "%s  ·  Quiz time!" % String(lesson["id"])
	next_card_btn.text = "Next card  ⏭"
	_show_quiz()


func _show_quiz() -> void:
	for ch in quiz_box.get_children():
		quiz_box.remove_child(ch)
		ch.queue_free()
	_answered = false
	var qs: Array = _lesson_quiz()
	if quiz_i >= qs.size():
		_finish_lesson(qs.size())
		return
	var q: Dictionary = qs[quiz_i]
	var dots: String = ""
	for k in qs.size():
		dots += "●" if k == quiz_i else ("◉" if k < quiz_i else "○")
	beat_dots.text = dots
	hint_lbl.text = "score %d" % quiz_score
	bubble_lbl.text = "Question %d of %d - take your time, there is no rush." % [quiz_i + 1, qs.size()]
	bubble_lbl.add_theme_color_override("font_color", Color(0.06, 0.09, 0.18))
	_label(quiz_box, String(q["q"]), 24, Color(0.95, 0.97, 1.0))
	var opts: Array = [String(q["answer"])] + (q.get("distractors", []) as Array).duplicate()
	opts.shuffle()
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quiz_box.add_child(grid)
	var cols: Array = [Color("#1f6fb8"), Color("#2b8a5a"), Color("#a86a1f"), Color("#7a4fb8")]
	for k in opts.size():
		var o: String = String(opts[k])
		var b: Button = _btn(grid, o, func() -> void: _answer(o, q), false, true)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 64)
		b.add_theme_font_size_override("font_size", 18)
		_paint(b, (cols[k % cols.size()] as Color).darkened(0.25))
		b.set_meta("opt", o)


func _answer(picked: String, q: Dictionary) -> void:
	if _answered:
		return
	_answered = true
	var right: bool = picked == String(q["answer"])
	if right:
		quiz_score += 1
		fx.burst(Vector2(fx.size.x * 0.5, fx.size.y * 0.45))
	for g in quiz_box.get_children():
		if g is GridContainer:
			for b in g.get_children():
				var bb: Button = b
				var o: String = String(bb.get_meta("opt", ""))
				bb.disabled = true
				if o == String(q["answer"]):
					_paint(bb, Color(0.18, 0.62, 0.36))
				elif o == picked:
					_paint(bb, Color(0.7, 0.22, 0.25))
				else:
					bb.modulate = Color(1, 1, 1, 0.45)
	bubble_lbl.text = ("Yes! " if right else "Almost! ") + String(q.get("why", ""))
	hint_lbl.text = "score %d" % quiz_score
	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	quiz_box.add_child(row)
	_label(row, "🎉  Correct!" if right else "Not quite - the green one is right.", 20,
		Color(0.45, 0.95, 0.55) if right else Color(1.0, 0.6, 0.55), false)
	var sp: Control = Control.new()
	sp.custom_minimum_size = Vector2(20, 0)
	row.add_child(sp)
	_btn(row, "Continue  ▶", func() -> void: _next_question(), true)
	_say(String(q.get("why", "")))


func _next_question() -> void:
	quiz_i += 1
	_show_quiz()


func _finish_lesson(total: int) -> void:
	var pr: Dictionary = lesson_progress(String(lesson["id"]))
	pr["quiz_best"] = maxi(int(pr.get("quiz_best", 0)), quiz_score)
	pr["done"] = true
	progress[lesson["id"]] = pr
	_save_progress()
	in_quiz = false
	var stars: int = _stars(quiz_score, total)
	fx.burst(Vector2(fx.size.x * 0.3, fx.size.y * 0.4))
	fx.burst(Vector2(fx.size.x * 0.7, fx.size.y * 0.4))
	var c: VBoxContainer = VBoxContainer.new()
	c.alignment = BoxContainer.ALIGNMENT_CENTER
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.add_theme_constant_override("separation", 14)
	quiz_box.add_child(c)
	var l1: Label = _label(c, "Lesson %s complete!" % String(lesson["id"]), 30, Color(1.0, 0.88, 0.45))
	l1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var l2: Label = _label(c, "★".repeat(stars) + "☆".repeat(3 - stars), 54, Color(1.0, 0.82, 0.3))
	l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var l3: Label = _label(c, "%d of %d answers right" % [quiz_score, total], 18, Color(0.85, 0.9, 1.0))
	l3.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	c.add_child(row)
	_btn(row, "↻  Watch again", func() -> void: open_lesson(String(lesson["id"])))
	_btn(row, "◀  Map", func() -> void: show_map())
	var nl: String = _following_lesson()
	if nl != "":
		_btn(row, "Next lesson  ▶", func() -> void: open_lesson(nl), true)
	bubble_lbl.text = "Amazing work! You finished this lesson." if stars >= 2 else "Well done for finishing! Watch it again any time to collect more stars."
	_say(bubble_lbl.text)


func _following_lesson() -> String:
	var found: bool = false
	for ch in course["chapters"]:
		for l in ch["lessons"]:
			if found:
				return String(l["id"])
			if l["id"] == lesson.get("id", ""):
				found = true
	return ""


func _say(t: String) -> void:
	if t != "" and voice_on:
		narration_requested.emit(t)


# ───────────────────────── confetti ─────────────────────────
class Confetti extends Control:
	var parts: Array = []

	func burst(at: Vector2) -> void:
		var cols: Array = [Color("#4fc3ff"), Color("#5ee6a0"), Color("#ffb85c"), Color("#c59bff"), Color("#ff7aa8"), Color("#ffe066")]
		for i in 70:
			var ang: float = randf_range(-PI, 0.0)
			var sp: float = randf_range(220.0, 620.0)
			parts.append({"p": at, "v": Vector2(cos(ang), sin(ang)) * sp, "c": cols[i % cols.size()], "life": randf_range(1.2, 2.0), "r": randf_range(0, TAU)})

	func _process(delta: float) -> void:
		if parts.is_empty():
			return
		for p in parts:
			p["v"] = (p["v"] as Vector2) + Vector2(0, 900.0 * delta)
			p["p"] = (p["p"] as Vector2) + (p["v"] as Vector2) * delta
			p["life"] = float(p["life"]) - delta
			p["r"] = float(p["r"]) + delta * 8.0
		parts = parts.filter(func(p: Dictionary) -> bool: return float(p["life"]) > 0.0)
		queue_redraw()

	func _draw() -> void:
		for p in parts:
			var c: Color = p["c"]
			c.a = clampf(float(p["life"]), 0.0, 1.0)
			draw_set_transform(p["p"], float(p["r"]))
			draw_rect(Rect2(-5, -3, 10, 6), c)
		draw_set_transform(Vector2.ZERO)
