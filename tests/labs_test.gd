extends Node
## Lab test: opens EVERY lab (the 11 course labs + Token/Sampling/Attention) and presses its
## Close button exactly like a user does (the button's own pressed signal), then checks that
## the lab is really gone. Also checks a lab opened from a lesson returns to that lesson.

var v: Node
var only: String = ""     # set to a lab id to open just that one (used for screenshots)
var problems: PackedStringArray = []

const LABS: Array = ["bigram_lab", "embedding_lab", "posenc_lab", "kvcache_lab", "moe_lab", "precision_lab",
	"scaling_lab", "retrieval_lab", "hnsw_lab", "passk_lab", "prompt_lab"]


func _ready() -> void:
	v = (load("res://ds_main.tscn") as PackedScene).instantiate()
	v.preview_vr_ui = true
	add_child(v)
	await get_tree().create_timer(1.2).timeout
	v.intro.begin_leave()
	await get_tree().create_timer(0.8).timeout
	v.menu_panel.visible = false
	v.demo_voice = false
	if only != "":
		v.open_lab_view(only)
		print("showing ", only)
		return
	for id in LABS:
		var lab: String = String(id)
		v.open_lab_view(lab)
		await get_tree().create_timer(0.3).timeout
		var inst: CanvasLayer = v.lab_views.get(lab, null)
		var in_vr: bool = inst != null and inst.get_parent() == v.ui_vp
		if inst == null or not inst.visible:
			problems.append(lab + " did not open")
			continue
		for other in v.lab_views.keys():
			if String(other) != lab and (v.lab_views[other] as CanvasLayer).visible:
				problems.append("lab %s stayed visible under %s" % [other, lab])
		var closed_ok: bool = await _press_close(inst, inst)
		print("%-14s opened, on VR screen=%s, Close works=%s" % [lab, in_vr, closed_ok])
	# the three original labs (these had the "Close re-opens it" bug)
	for pair in [["token_lab", "lab_panel"], ["sampling_lab", "sl_panel"], ["attention_lab", "al_panel"]]:
		v._open_lab(String(pair[0]))
		await get_tree().create_timer(0.3).timeout
		var pnl: PanelContainer = v.get(String(pair[1]))
		if not pnl.visible:
			problems.append(String(pair[0]) + " did not open")
			continue
		var ok: bool = await _press_close(pnl, pnl)
		print("%-14s opened, Close works=%s" % [pair[0], ok])
	# lab opened from inside a lesson → closing it returns to that lesson
	v._toggle_course()
	var cv: CourseView = v.course_view
	cv.open_lesson("2.3")
	await get_tree().create_timer(0.3).timeout
	cv.open_lab_requested.emit("embedding_lab")
	await get_tree().create_timer(0.3).timeout
	var e: CanvasLayer = v.lab_views["embedding_lab"]
	print("from lesson: lab visible=", e.visible, " course hidden=", not cv.visible)
	await _press_close(e, e)
	await get_tree().create_timer(0.3).timeout
	print("after closing the lab: course visible again=", cv.visible, "  lesson=", cv.lesson.get("id", "-"))
	if not cv.visible:
		problems.append("closing a lab opened from a lesson did not return to the lesson")
	print("\n===== LAB TEST ", ("FAILED: " + ", ".join(problems)) if problems.size() > 0 else "PASSED", " =====")
	await get_tree().create_timer(0.4).timeout
	get_tree().quit()


func _press_close(root: Node, watch: Node) -> bool:
	var b: Button = _find_close(root)
	if b == null:
		problems.append("no Close button in " + str(root))
		return false
	b.pressed.emit()
	await get_tree().create_timer(0.25).timeout
	var vis: bool = bool(watch.get("visible"))
	if vis:
		problems.append("Close did not close " + str(root.name))
	return not vis


func _find_close(n: Node) -> Button:
	for c in n.get_children():
		if c is Button and ((c as Button).text.contains("Close") or (c as Button).text.strip_edges() == "✕"):
			return c
		var f: Button = _find_close(c)
		if f != null:
			return f
	return null
