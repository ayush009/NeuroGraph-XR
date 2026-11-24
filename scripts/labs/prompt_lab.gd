extends LabBase
## Prompt lab: build a prompt from blocks and watch how much of the model's answer is
## pinned down by the prompt itself. The score is a transparent teaching heuristic that
## counts what the blocks actually contain - it is not a model's opinion.

var use_role: bool = true
var use_context: bool = true
var use_format: bool = true
var use_examples: bool = true
var n_examples: int = 2
var use_constraints: bool = false
var task: String = "Summarise this support ticket for the engineering team"
var prompt_box: TextEdit
var score_box: VBoxContainer
var score_lbl: Label


func title() -> String:
	return "Prompt Lab"


func intro() -> String:
	return "A vague instruction leaves the model guessing. Add a role, the context, a format and examples, and the same model suddenly looks much better. Toggle the blocks and watch the prompt and its specificity score change."


func build_body(vb: VBoxContainer) -> void:
	var h: HBoxContainer = hbox(vb)
	lbl(h, "Task:", 14)
	var ed: LineEdit = LineEdit.new()
	ed.text = task
	ed.custom_minimum_size = Vector2(460, 0)
	ed.text_changed.connect(func(t: String) -> void:
		task = t
		_refresh())
	h.add_child(ed)
	var row: HBoxContainer = hbox(vb)
	_toggle(row, "Role", use_role, func(v: bool) -> void:
		use_role = v
		_refresh())
	_toggle(row, "Context", use_context, func(v: bool) -> void:
		use_context = v
		_refresh())
	_toggle(row, "Output format", use_format, func(v: bool) -> void:
		use_format = v
		_refresh())
	_toggle(row, "Examples", use_examples, func(v: bool) -> void:
		use_examples = v
		_refresh())
	_toggle(row, "Constraints", use_constraints, func(v: bool) -> void:
		use_constraints = v
		_refresh())
	var row2: HBoxContainer = hbox(vb)
	lbl(row2, "Few-shot examples:", 14)
	var s: HSlider = HSlider.new()
	s.min_value = 1
	s.max_value = 5
	s.step = 1
	s.value = 2
	s.custom_minimum_size = Vector2(200, 0)
	s.value_changed.connect(func(v: float) -> void:
		n_examples = int(v)
		_refresh())
	row2.add_child(s)
	btn(row2, "empty prompt", func() -> void:
		use_role = false
		use_context = false
		use_format = false
		use_examples = false
		use_constraints = false
		_refresh())
	btn(row2, "fully specified", func() -> void:
		use_role = true
		use_context = true
		use_format = true
		use_examples = true
		use_constraints = true
		_refresh(), true)
	prompt_box = TextEdit.new()
	prompt_box.custom_minimum_size = Vector2(0, 190)
	prompt_box.editable = false
	vb.add_child(prompt_box)
	score_lbl = lbl(vb, "", 16, Color(1.0, 0.85, 0.5))
	score_box = VBoxContainer.new()
	score_box.add_theme_constant_override("separation", 3)
	vb.add_child(score_box)
	rich(vb, "What you should notice",
		"Every block removes one degree of freedom. A role sets the vocabulary and the level of detail; context supplies the facts the model cannot know; a format makes the output parseable by the next program; examples demonstrate the shape far better than describing it.")
	rich(vb, "Failure modes to watch",
		"Contradicting yourself across blocks, burying the instruction in the middle of a long context, asking for a format without saying what to do with missing data, and adding examples that disagree with the instructions. Keep the instruction in the strongest positions - the beginning and the end.")
	_refresh()


func _toggle(row: HBoxContainer, text: String, on: bool, cb: Callable) -> void:
	var c: CheckBox = CheckBox.new()
	c.text = text
	c.button_pressed = on
	c.focus_mode = Control.FOCUS_NONE
	c.toggled.connect(cb)
	row.add_child(c)


func _assemble() -> String:
	var parts: PackedStringArray = []
	if use_role:
		parts.append("You are a senior support engineer who writes concise, factual updates.")
	if use_context:
		parts.append("Context: the customer reports that exports fail every Monday morning after the weekly data sync. Logs are attached separately.")
	parts.append("Task: " + task + ".")
	if use_constraints:
		parts.append("Constraints: do not invent numbers, keep every claim traceable to the log excerpt, say explicitly when the cause is unknown.")
	if use_examples:
		var ex: PackedStringArray = []
		for i in n_examples:
			ex.append("Example %d input: %s\nExample %d output: %s" % [
				i + 1, _example_in(i), i + 1, _example_out(i)])
		parts.append("Follow the style of these examples:\n" + "\n".join(ex))
	if use_format:
		parts.append("Output format: a JSON object with the fields \"summary\" (one sentence), \"likely_cause\" (one sentence or null), \"next_steps\" (a list of at most three items).")
	return "\n\n".join(parts) if parts.size() > 0 else task


func _example_in(i: int) -> String:
	var ins: Array = ["checkout times out on mobile", "nightly report is empty"]
	return String(ins[i % ins.size()])


func _example_out(i: int) -> String:
	var outs: Array = ["{\"summary\": \"Checkout times out on mobile only\", \"likely_cause\": \"mobile retry loop\", \"next_steps\": [\"add retry backoff\"]}",
		"{\"summary\": \"Nightly report is empty\", \"likely_cause\": null, \"next_steps\": [\"check the scheduler\", \"verify the source table is loaded\"]}"]
	return String(outs[i % outs.size()])


func _refresh() -> void:
	var text: String = _assemble()
	prompt_box.text = text
	for c in score_box.get_children():
		score_box.remove_child(c)
		c.queue_free()
	# transparent heuristic: each block adds points, and a vague task loses some
	var score: float = 0.0
	var notes: PackedStringArray = []
	if use_role:
		score += 0.18
		notes.append("role set: the model knows whose voice and how much detail")
	if use_context:
		score += 0.22
		notes.append("context given: the model does not have to invent facts")
	if use_format:
		score += 0.22
		notes.append("output format fixed: the result can be parsed by code")
	if use_examples:
		score += 0.16 + 0.03 * float(n_examples)
		notes.append("%d worked example%s: the shape is shown, not described" % [n_examples, "" if n_examples == 1 else "s"])
	if use_constraints:
		score += 0.14
		notes.append("constraints stated: no invented numbers, unknowns must be admitted")
	var words: int = text.split(" ", false).size()
	if words < 12:
		score = minf(score, 0.25)
		notes.append("the task alone is short and open: many different answers would satisfy it")
	if words > 400:
		score -= 0.10
		notes.append("a very long prompt: the instruction can get lost in the middle")
	score_lbl.text = "Specificity score:  %.0f%%   ·   %d words, about %d tokens" % [clampf(score, 0.0, 1.0) * 100.0, words, int(float(words) * 1.35)]
	bar(score_box, "how much of the answer is pinned down", clampf(score, 0.0, 1.0), Color(0.5, 0.95, 0.7), "")
	for n in notes:
		lbl(score_box, "•  " + String(n), 14, Color(0.82, 0.9, 1.0))