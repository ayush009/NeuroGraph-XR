extends LabBase
## pass@k lab: how many attempts you need for a solution to appear at least once, and why
## "at least one of k" and "all of k" are different questions.

var p: float = 0.4
var chart: Control
var out: VBoxContainer
var k_marks: Array = [1, 2, 5, 10, 20]


func title() -> String:
	return "pass@k Lab"


func intro() -> String:
	return "A model that is right 40 percent of the time is not stuck at 40 percent. Sample it k times and the chance that at least one answer is correct climbs fast - this is what the pass@k metric measures."


func build_body(vb: VBoxContainer) -> void:
	var h: HBoxContainer = hbox(vb)
	lbl(h, "Chance one attempt is correct:", 14)
	var s: HSlider = HSlider.new()
	s.min_value = 0.05
	s.max_value = 0.95
	s.step = 0.05
	s.value = 0.4
	s.custom_minimum_size = Vector2(300, 0)
	s.value_changed.connect(func(v: float) -> void:
		p = v
		_refresh())
	h.add_child(s)
	chart = Control.new()
	chart.custom_minimum_size = Vector2(0, 250)
	chart.draw.connect(_draw)
	vb.add_child(chart)
	out = VBoxContainer.new()
	out.add_theme_constant_override("separation", 3)
	vb.add_child(out)
	rich(vb, "What you should notice",
		"pass@k = 1 − (1 − p)^k. With p = 0.4 you pass one in five attempts, and about 92 percent within five. The curve saturates: after enough tries almost everything is found, so pass@1 tells you much more about a model than pass@100.")
	rich(vb, "The other metric in the lecture",
		"pass^k asks a stricter question: are all k attempts correct? That is p^k, which collapses as k grows. Use pass@k for 'can it ever solve this' and pass^k for 'is it reliable enough to ship'.")
	_refresh()


func _pass_at_k(pv: float, k: float) -> float:
	return 1.0 - pow(1.0 - pv, k)


func _draw() -> void:
	var sz: Vector2 = chart.size
	chart.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.02, 0.03, 0.07, 0.95))
	var f: Font = ThemeDB.fallback_font
	# axes
	chart.draw_line(Vector2(36, sz.y - 26), Vector2(sz.x - 8, sz.y - 26), Color(0.4, 0.6, 0.9, 0.6), 1.0)
	chart.draw_line(Vector2(36, 10), Vector2(36, sz.y - 26), Color(0.4, 0.6, 0.9, 0.6), 1.0)
	for i in 6:
		var y: float = (sz.y - 36) * (1.0 - float(i) / 5.0) + 10.0
		chart.draw_string(f, Vector2(6, y + 4), "%d%%" % (i * 20), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.7, 0.8, 0.95))
		chart.draw_line(Vector2(36, y), Vector2(sz.x - 8, y), Color(0.25, 0.4, 0.65, 0.2), 1.0)
	# pass@k curves for three p values
	var ps: Array = [0.2, 0.4, 0.6]
	var cols: Array = [Color(0.95, 0.55, 0.5), Color(0.55, 0.9, 0.7), Color(0.6, 0.75, 1.0)]
	for pi in ps.size():
		var pv: float = float(ps[pi])
		var last: Vector2 = Vector2.ZERO
		for i in 51:
			var k: float = 1.0 + float(i) * 0.4
			var x: float = 36.0 + (sz.x - 44.0) * float(i) / 50.0
			var y: float = (sz.y - 36.0) * (1.0 - _pass_at_k(pv, k)) + 10.0
			if i > 0:
				chart.draw_line(last, Vector2(x, y), cols[pi], 2.0)
			last = Vector2(x, y)
		var lblpos: Vector2 = Vector2(sz.x - 120.0, (sz.y - 36.0) * (1.0 - _pass_at_k(pv, 20.0)) + 10.0 - 6.0)
		chart.draw_string(f, lblpos, "p = %.0f%%" % (pv * 100.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, cols[pi])
	# current p, marked
	var cur_y: float = (sz.y - 36.0) * (1.0 - _pass_at_k(p, 1.0)) + 10.0
	chart.draw_circle(Vector2(36.0, cur_y), 5.0, Color(1.0, 0.85, 0.3))
	for i in 21:
		if (i + 1) % 5 == 0:
			var x: float = 36.0 + (sz.x - 44.0) * float(i) / 50.0
			chart.draw_string(f, Vector2(x - 6, sz.y - 8), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.7, 0.8, 0.95))
	chart.draw_string(f, Vector2(sz.x * 0.5 - 60, sz.y - 8), "number of attempts k", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 0.88, 1.0))
	chart.draw_string(f, Vector2(44, 22), "pass@k for one attempt with probability p", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.85, 0.92, 1.0))


func _refresh() -> void:
	chart.queue_redraw()
	for c in out.get_children():
		out.remove_child(c)
		c.queue_free()
	lbl(out, "With p = %.0f%% per attempt:" % (p * 100.0), 16, Color(1.0, 0.85, 0.5))
	for k in k_marks:
		var pk: float = _pass_at_k(p, float(k))
		var allk: float = pow(p, float(k))
		bar(out, "  pass@%d" % int(k), pk, Color(0.5, 0.95, 0.7), "%.1f%%      pass^%d (all %d correct): %.1f%%" % [pk * 100.0, int(k), int(k), allk * 100.0])