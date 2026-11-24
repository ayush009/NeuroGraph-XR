extends Node
## Course-mode test: opens the AI Engineering course in the real app, walks a lesson,
## runs its quiz, and validates the whole course data set.

var v: Node
var problems: PackedStringArray = []


func _ready() -> void:
	v = (load("res://ds_main.tscn") as PackedScene).instantiate()
	v.preview_vr_ui = true
	add_child(v)
	await get_tree().create_timer(1.2).timeout
	v.intro.begin_leave()
	await get_tree().create_timer(0.8).timeout
	v.menu_panel.visible = false
	_check_data()
	# ── open course mode ──
	v._toggle_course()
	await get_tree().create_timer(0.4).timeout
	var cv: CourseView = v.course_view
	print("course view exists=", cv != null, "  visible=", cv.visible if cv else false)
	if cv == null:
		_finish()
		return
	print("chapters=", cv.course["chapters"].size(), "  lessons=", _lesson_count(cv))
	# ── walk lesson 3.7 (KV cache) card by card ──
	cv.chapter_i = 2
	cv.open_lesson("3.7")
	await get_tree().create_timer(0.3).timeout
	print("lesson opened: ", cv.lesson["id"], " - ", cv.lesson["title"], "  cards=", cv.lesson["cards"].size())
	var seen: PackedStringArray = []
	var spoken: Array = []
	cv.narration_requested.connect(func(t: String) -> void: spoken.append(t))
	for i in cv.lesson["cards"].size():
		seen.append(String(cv.lesson["cards"][cv.card_i]["id"]))
		cv.advance()
		await get_tree().create_timer(0.05).timeout
	print("cards visited: ", seen, "\n  narration lines requested=", spoken.size())
	if seen.size() != cv.lesson["cards"].size():
		problems.append("did not visit every card")
	# ── its quiz: answer everything correctly ──
	cv._start_quiz()
	await get_tree().create_timer(0.2).timeout
	var qs: Array = cv._lesson_quiz()
	print("lesson quiz questions=", qs.size())
	var guard: int = 0
	while cv.in_quiz and guard < 40:
		guard += 1
		var q: Dictionary = qs[cv.quiz_i]
		cv._answer(String(q["answer"]), q)
		await get_tree().create_timer(0.05).timeout
		cv.advance()
		await get_tree().create_timer(0.05).timeout
	print("quiz finished, score=", cv.quiz_score, "/", qs.size(), "  in_quiz=", cv.in_quiz)
	var pr: Dictionary = cv.progress.get("3.7", {})
	print("saved progress for 3.7: ", pr)
	if int(pr.get("quiz_best", 0)) != qs.size():
		problems.append("quiz score not saved (got %s of %d)" % [pr.get("quiz_best", -1), qs.size()])
	# ── "show in 3D" must load the AI Engineering graph and select the node ──
	v._show_concept_in_graph("kv_cache_why")
	await get_tree().create_timer(0.4).timeout
	print("after Show in 3D: course=", v.COURSES[v.course_idx]["name"], "  selected=", v.selected.get("id", "-"),
		"  course view visible=", cv.visible)
	if String(v.selected.get("id", "")) != "kv_cache_why":
		problems.append("Show in 3D did not select the concept")
	# ── a lab route ──
	v._open_lab("token_lab")
	await get_tree().create_timer(0.2).timeout
	print("lab open after route to token_lab: ", v.lab_panel.visible)
	if not v.lab_panel.visible:
		problems.append("token_lab did not open from a course card")
	_finish()


func _lesson_count(cv: CourseView) -> int:
	var n: int = 0
	for ch in cv.course["chapters"]:
		n += ch["lessons"].size()
	return n


func _check_data() -> void:
	var d: Dictionary = v._load_json("res://data/aie_course.json")
	var ids: Dictionary = {}
	var cards: int = 0
	var quizzes: int = 0
	var labs: Dictionary = {}
	var short_text: int = 0
	var long_text: int = 0
	var short_say: int = 0
	for ch in d["chapters"]:
		for l in ch["lessons"]:
			if ids.has(l["id"]):
				problems.append("duplicate lesson id " + String(l["id"]))
			ids[l["id"]] = true
			if l["cards"].size() < 3:
				problems.append("lesson %s has only %d cards" % [l["id"], l["cards"].size()])
			for c in l["cards"]:
				cards += 1
				var w: int = String(c.get("text", "")).split(" ", false).size()
				if w < 45:
					short_text += 1
				elif w > 130:
					long_text += 1
				var ws: int = String(c.get("say", "")).split(" ", false).size()
				if ws < 15:
					short_say += 1
				if String(c.get("lab", "")) != "":
					labs[String(c["lab"])] = int(labs.get(String(c["lab"]), 0)) + 1
	for q in d["quiz"]:
		quizzes += 1
		if (q.get("distractors", []) as Array).size() != 3:
			problems.append("question with %d distractors: %s" % [(q.get("distractors", []) as Array).size(), q["q"]])
	print("DATA: lessons=", ids.size(), " cards=", cards, " quiz=", quizzes)
	print("  card text words: <45 = ", short_text, " , >130 = ", long_text, "  (short narration lines: ", short_say, ")")
	print("  labs referenced by cards: ", labs)
	var known: Array = ["token_lab", "attention_lab", "sampling_lab", "network_view", "embedding_lab", "bigram_lab", "posenc_lab", "kvcache_lab", "moe_lab", "precision_lab", "scaling_lab", "retrieval_lab", "hnsw_lab", "passk_lab", "prompt_lab"]
	for lab in labs.keys():
		if not known.has(lab):
			print("  note: lab '", lab, "' is referenced ", labs[lab], " times and is not wired up yet")


func _finish() -> void:
	print("\n===== COURSE TEST ", ("FAILED: " + ", ".join(problems)) if problems.size() > 0 else "PASSED", " =====")
	await get_tree().create_timer(0.5).timeout
	get_tree().quit()