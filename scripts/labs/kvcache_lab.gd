extends LabBase
## KV-cache lab: prefill vs decode, why recomputing the prefix is quadratic, and the real
## cost of a cache - memory that grows linearly with context and a decode step that is
## bound by memory bandwidth, not by FLOPs.

var n_tokens: int = 2048
var n_layers: int = 32
var n_heads: int = 32
var head_dim: int = 128
var batch: int = 1
var dtype_bytes: int = 2
var use_cache: bool = true

var out: VBoxContainer
var calc_lbl: Label


func title() -> String:
	return "KV Cache Lab"


func intro() -> String:
	return "During generation the model predicts one token at a time. The cache stores the keys and values of everything already generated, so each new token costs one small step instead of a full re-run. Play with the numbers."


func build_body(vb: VBoxContainer) -> void:
	var controls: VBoxContainer = VBoxContainer.new()
	controls.add_theme_constant_override("separation", 4)
	vb.add_child(controls)
	_slider_row(controls, "Context length (tokens)", 128, 32768, n_tokens, 128, func(v: float) -> void:
		n_tokens = int(v)
		_refresh())
	_slider_row(controls, "Layers", 4, 80, n_layers, 1, func(v: float) -> void:
		n_layers = int(v)
		_refresh())
	_slider_row(controls, "Heads", 4, 64, n_heads, 1, func(v: float) -> void:
		n_heads = int(v)
		_refresh())
	_slider_row(controls, "Head dimension", 32, 256, head_dim, 32, func(v: float) -> void:
		head_dim = int(v)
		_refresh())
	_slider_row(controls, "Batch size", 1, 32, batch, 1, func(v: float) -> void:
		batch = int(v)
		_refresh())
	var row: HBoxContainer = hbox(vb)
	btn(row, "Prefilter cache: ON" if use_cache else "Cache: OFF", func() -> void:
		use_cache = not use_cache
		_refresh(), true)
	out = VBoxContainer.new()
	out.add_theme_constant_override("separation", 3)
	vb.add_child(out)
	calc_lbl = lbl(vb, "", 14, Color(0.85, 0.9, 1.0))
	rich(vb, "What you should notice",
		"Attention of a new token against the cache is one dot product per stored key: work grows linearly with context per token, so the total grows quadratically - and without a cache it would grow cubically, because the whole prefix would be recomputed each step.")
	rich(vb, "The part budgets are actually spent on",
		"A decode step reads the whole cache out of memory to compute a handful of FLOPs per byte: it is memory-bandwidth bound. That is why serving throughput is measured in tokens per second per byte of memory per second, and why shrinking the cache raises throughput more than shrinking the model does.")
	_refresh()


func _slider_row(parent: Node, text: String, lo: float, hi: float, val: float, step: float, cb: Callable) -> void:
	var h: HBoxContainer = hbox(parent)
	var l: Label = Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(210, 0)
	l.add_theme_font_size_override("font_size", 14)
	h.add_child(l)
	var s: HSlider = HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(val)
	s.custom_minimum_size = Vector2(280, 0)
	s.value_changed.connect(cb)
	h.add_child(s)
	var v: Label = Label.new()
	v.name = "value"
	v.custom_minimum_size = Vector2(90, 0)
	v.add_theme_font_size_override("font_size", 14)
	v.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	h.add_child(v)
	_update_value_label(h, s)


func _update_value_label(row: Node, s: HSlider) -> void:
	(row.get_node("value") as Label).text = str(int(s.value))


func _refresh() -> void:
	# refresh the small value labels next to the sliders
	for c in out.get_parent().get_children():
		if c is VBoxContainer:
			for h in c.get_children():
				if h is HBoxContainer and h.get_node_or_null("value") != null:
					var s: HSlider = h.get_children()[1]
					(h.get_node("value") as Label).text = str(int(s.value))
	for c in out.get_children():
		out.remove_child(c)
		c.queue_free()
	var kv_values: int = 2 * n_layers * n_heads * head_dim * n_tokens * batch
	var kv_bytes: float = float(kv_values) * float(dtype_bytes)
	bar(out, "Cache memory", minf(kv_bytes / (1024.0 * 1024.0 * 1024.0 * 16.0), 1.0), Color(0.95, 0.5, 0.35),
		"%.2f GB" % (kv_bytes / (1024.0 * 1024.0 * 1024.0)))
	var per_step_no: float = float(n_tokens) * float(n_layers * n_heads * head_dim) * float(batch) * 2.0
	var per_step_with: float = float(1) * float(n_layers * n_heads * head_dim) * float(batch) * 2.0
	var total_no: float = per_step_no * float(n_tokens) * 0.5
	var total_with: float = per_step_with * float(n_tokens)
	bar(out, "Attention work per decode step (cache)", minf(per_step_with / per_step_no, 1.0), Color(0.4, 0.9, 0.6),
		"%.3f GFLOP" % (per_step_with / 1e9))
	bar(out, "Attention work per decode step (no cache)", 1.0, Color(0.95, 0.35, 0.45),
		"%.3f GFLOP" % (per_step_no / 1e9))
	lbl(out, "Generating all %d tokens:" % n_tokens, 15, Color(1.0, 0.85, 0.5))
	bar(out, "  with cache", total_with / maxf(total_no, 1.0), Color(0.4, 0.9, 0.6), "%.1f TFLOP" % (total_with / 1e12))
	bar(out, "  without cache", 1.0, Color(0.95, 0.35, 0.45), "%.1f TFLOP" % (total_no / 1e12))
	calc_lbl.text = "Cache reads per step: %.2f GB   ·   at 2 TB/s of memory bandwidth that is %.1f ms per token before any other work.  (Memory = 2 · layers · heads · head dim · tokens · batch · %d bytes)" % [
		kv_bytes / (1024.0 * 1024.0 * 1024.0), kv_bytes / (2.0e12) * 1000.0, dtype_bytes]