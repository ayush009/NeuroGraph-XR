extends LabBase
## Scaling lab: the Chinchilla-style trade-off between model size and training tokens.
## Loss curves use the published power-law constants (L = E + A/N^a + B/D^b).

const E_CONST: float = 1.69
const A_CONST: float = 406.4
const ALPHA: float = 0.34
const B_CONST: float = 410.7
const BETA: float = 0.28
const COMPUTE_PER_TOKEN: float = 6.0    # C ≈ 6 · N · D

var chart: Control
var budget_flops: float = 1e21          # training compute budget
var model_b: float = 10.0               # N
var tokens_b: float = 200.0             # D
var out: VBoxContainer


func title() -> String:
	return "Scaling Lab"


func intro() -> String:
	return "Training compute is roughly six times parameters times tokens. Given a budget, how should you split it? Too big a model is under-trained; too little data wastes parameters. Drag the budget and see the loss."


func _loss(n_b: float, d_b: float) -> float:
	var n: float = maxf(n_b, 0.01) * 1e9
	var d: float = maxf(d_b, 0.01) * 1e9
	return E_CONST + A_CONST / pow(n, ALPHA) + B_CONST / pow(d, BETA)


func build_body(vb: VBoxContainer) -> void:
	var h: HBoxContainer = hbox(vb)
	lbl(h, "Training compute budget:", 14)
	var s: HSlider = HSlider.new()
	s.min_value = 17.0
	s.max_value = 26.0
	s.step = 0.1
	s.value = 21.0
	s.custom_minimum_size = Vector2(300, 0)
	s.value_changed.connect(func(v: float) -> void:
		budget_flops = pow(10.0, v)
		_fit()
		_refresh())
	h.add_child(s)
	lbl(h, "C ≈ 6 · N · D,  optimal split is N ≈ √(C/6) and D ≈ C/(6N)", 13, Color(0.8, 0.88, 1.0))
	chart = Control.new()
	chart.custom_minimum_size = Vector2(0, 260)
	chart.draw.connect(_draw_chart)
	vb.add_child(chart)
	out = VBoxContainer.new()
	out.add_theme_constant_override("separation", 3)
	vb.add_child(out)
	rich(vb, "What you should notice",
		"Loss falls as a power law in both directions, so the name of the game is the ratio of tokens to parameters. The optimum sits near twenty tokens per parameter; much below that the model is under-trained, and pushing far above it keeps working but buys less and less.")
	rich(vb, "Beyond a single run",
		"Scaling laws let teams predict a loss before spending the money, and they are why later models are trained on trillions of tokens. They say nothing about what the model can do - capability jumps are a separate, harder question.")
	_fit()
	_refresh()


func _fit() -> void:
	# optimal split for the current budget
	model_b = sqrt(budget_flops / COMPUTE_PER_TOKEN) / 1e9
	tokens_b = budget_flops / (COMPUTE_PER_TOKEN * model_b * 1e9) / 1e9


func _curve_loss(c_flops: float) -> float:
	var n: float = sqrt(c_flops / COMPUTE_PER_TOKEN) / 1e9
	var d: float = c_flops / (COMPUTE_PER_TOKEN * n * 1e9) / 1e9
	return _loss(n, d)


func _draw_chart() -> void:
	var sz: Vector2 = chart.size
	chart.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.02, 0.03, 0.07, 0.95))
	var x_lo: float = 17.0
	var x_hi: float = 27.0
	var y_lo: float = 1.6
	var y_hi: float = 3.4
	var f: Font = ThemeDB.fallback_font
	for i in 11:
		var lx: float = x_lo + (x_hi - x_lo) * float(i) / 10.0
		var x: float = sz.x * float(i) / 10.0
		chart.draw_line(Vector2(x, 0), Vector2(x, sz.y - 18), Color(0.25, 0.4, 0.65, 0.25), 1.0)
		chart.draw_string(f, Vector2(x - 12, sz.y - 4), "1e%.0f" % lx, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.7, 0.8, 0.95))
	# the optimal curve
	var last: Vector2 = Vector2.ZERO
	for i in 121:
		var lc: float = x_lo + (x_hi - x_lo) * float(i) / 120.0
		var c: float = pow(10.0, lc)
		var l: float = _curve_loss(c)
		var p: Vector2 = Vector2(sz.x * float(i) / 120.0, _y_of(l, y_lo, y_hi, sz))
		if i > 0:
			chart.draw_line(last, p, Color(0.4, 0.95, 0.7), 2.0)
		last = p
	# this budget's point
	var cur_loss: float = _loss(model_b, tokens_b)
	var lc_cur: float = log(budget_flops) / log(10.0)
	var px: float = sz.x * (lc_cur - x_lo) / (x_hi - x_lo)
	var py: float = _y_of(cur_loss, y_lo, y_hi, sz)
	chart.draw_circle(Vector2(px, py), 8.0, Color(1.0, 0.8, 0.25))
	chart.draw_string(f, Vector2(px + 12, py - 10), "loss %.2f" % cur_loss, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.85, 0.4))
	# comparison: same budget, wrong split
	var wide_loss: float = _loss(sqrt(budget_flops / COMPUTE_PER_TOKEN) / 1e9 * 4.0, tokens_b / 4.0)
	var wx: float = px
	var wy: float = _y_of(wide_loss, y_lo, y_hi, sz)
	chart.draw_circle(Vector2(wx, wy), 6.0, Color(0.95, 0.4, 0.45))
	chart.draw_string(f, Vector2(wx + 12, wy + 16), "same budget, 4× bigger model: loss %.2f" % wide_loss, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.55, 0.55))
	chart.draw_string(f, Vector2(10, 18), "Loss vs training compute (log scale)", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.85, 0.92, 1.0))


func _y_of(l: float, lo: float, hi: float, sz: Vector2) -> float:
	var t: float = clampf((l - lo) / (hi - lo), 0.0, 1.0)
	return (sz.y - 24.0) * (1.0 - t) + 8.0


func _refresh() -> void:
	chart.queue_redraw()
	for c in out.get_children():
		out.remove_child(c)
		c.queue_free()
	var loss: float = _loss(model_b, tokens_b)
	var ratio: float = tokens_b / maxf(model_b, 0.001)
	lbl(out, "Optimal split for this budget:  %.1f B parameters  ·  %.0f B tokens  ·  ratio %.1f tokens per parameter" % [model_b, tokens_b, ratio], 15, Color(1.0, 0.85, 0.5))
	lbl(out, "Predicted loss: %.3f" % loss, 16, Color(0.55, 0.95, 0.8))
	bar(out, "how far the split is from optimal", clampf(absf(ratio - 20.0) / 40.0, 0.0, 1.0), Color(0.4, 0.9, 0.6), "20 is optimal")
	lbl(out, "Reference points from the lecture: GPT-3 (175 B, 300 B tokens, ratio 1.7) was strongly under-trained; Chinchilla (70 B, 1.4 T tokens, ratio 20) matched it with less compute; Llama-2 7 B used 2 T tokens (ratio about 285) because inference cost matters more than training cost.", 14, Color(0.82, 0.9, 1.0))