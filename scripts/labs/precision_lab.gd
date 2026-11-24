extends LabBase
## Numerics lab: what a floating-point format actually stores. Shows the bit layout,
## the number of representable values near one, and the memory a model needs in each format.

const FORMATS: Array = [
	{"name": "FP32", "bits": 32, "exp": 8, "man": 23, "col": Color(0.45, 0.7, 1.0)},
	{"name": "TF32", "bits": 19, "exp": 8, "man": 10, "col": Color(0.45, 0.85, 0.95)},
	{"name": "FP16", "bits": 16, "exp": 5, "man": 10, "col": Color(0.5, 0.95, 0.7)},
	{"name": "BF16", "bits": 16, "exp": 8, "man": 7, "col": Color(0.9, 0.9, 0.4)},
	{"name": "FP8 E4M3", "bits": 8, "exp": 4, "man": 3, "col": Color(1.0, 0.75, 0.4)},
	{"name": "INT8", "bits": 8, "exp": 0, "man": 7, "col": Color(1.0, 0.6, 0.45)},
	{"name": "NF4", "bits": 4, "exp": 0, "man": 3, "col": Color(1.0, 0.45, 0.6)},
]

var sel: int = 3
var layout: Control
var info: VBoxContainer
var model_b: float = 70.0
var value: float = 0.1


func title() -> String:
	return "Numerics & Precision Lab"


func intro() -> String:
	return "Every number the model stores is a sign, an exponent and a mantissa. Cutting bits makes models smaller and faster - and quietly removes precision. Pick a format."


func build_body(vb: VBoxContainer) -> void:
	var row: HBoxContainer = hbox(vb)
	for i in FORMATS.size():
		var ii: int = i
		btn(row, String(FORMATS[i]["name"]), func() -> void:
			sel = ii
			_refresh(), sel == i)
	layout = Control.new()
	layout.custom_minimum_size = Vector2(0, 110)
	layout.draw.connect(_draw_layout)
	vb.add_child(layout)
	info = VBoxContainer.new()
	info.add_theme_constant_override("separation", 3)
	vb.add_child(info)
	var h: HBoxContainer = hbox(vb)
	lbl(h, "Example model size (B params):", 14)
	var ed: LineEdit = LineEdit.new()
	ed.text = "70"
	ed.custom_minimum_size = Vector2(80, 0)
	ed.text_changed.connect(func(t: String) -> void:
		var f: float = t.to_float()
		if f > 0.0:
			model_b = f
			_refresh())
	h.add_child(ed)
	lbl(h, "  Value to round:", 14)
	var ed2: LineEdit = LineEdit.new()
	ed2.text = "0.1"
	ed2.custom_minimum_size = Vector2(80, 0)
	ed2.text_changed.connect(func(t: String) -> void:
		value = t.to_float()
		_refresh())
	h.add_child(ed2)
	rich(vb, "What you should notice",
		"BF16 keeps the wide exponent range of FP32 but only 8 bits of precision: it can still represent tiny and huge numbers, just coarsely. FP16 is more precise but overflows past about 65 thousand, which is why scaling tricks are needed when training with it.")
	rich(vb, "Why 4-bit is possible at all",
		"Quantisation does not store each weight alone. Weights are grouped into blocks, the block gets a shared scale (and sometimes a zero point), and each weight stores only its offset within that scale. NF4 chooses 16 offsets that match the shape of a normal distribution instead of spacing them evenly.")
	_refresh()


func _fmt() -> Dictionary:
	return FORMATS[sel]


func _draw_layout() -> void:
	var sz: Vector2 = layout.size
	layout.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.02, 0.03, 0.07, 0.95))
	var f: Dictionary = _fmt()
	var total: int = int(f["bits"])
	var exp_bits: int = int(f["exp"])
	var man_bits: int = int(f["man"])
	var sign_bits: int = 1
	var seg: Array = []
	if exp_bits > 0:
		seg = [["sign", sign_bits, Color(1.0, 0.45, 0.5)], ["exponent", exp_bits, Color(0.55, 0.8, 1.0)], ["mantissa", man_bits, Color(0.5, 0.95, 0.7)]]
	else:
		seg = [["integer part", maxi(total - man_bits, 0), Color(0.55, 0.8, 1.0)], ["fraction / offset", total - maxi(total - man_bits, 0), Color(0.5, 0.95, 0.7)]]
	var x: float = 10.0
	var w: float = (sz.x - 20.0) / float(total)
	for s in seg:
		var bits: int = int(s[1])
		var seg_w: float = w * float(bits)
		layout.draw_rect(Rect2(Vector2(x, 30), Vector2(seg_w, 46)), s[2])
		layout.draw_rect(Rect2(Vector2(x, 30), Vector2(seg_w, 46)), Color(0.05, 0.08, 0.15), false, 1.0)
		var font: Font = ThemeDB.fallback_font
		var txt: String = "%s\n%d bit%s" % [String(s[0]), bits, "" if bits == 1 else "s"]
		layout.draw_multiline_string(font, Vector2(x + 4, 50), txt, HORIZONTAL_ALIGNMENT_LEFT, seg_w - 6, 12, -1, Color(0.05, 0.08, 0.15))
		x += seg_w
	var ftxt: String = "%s = %d bits = %.1f bytes per value" % [String(f["name"]), total, float(total) / 8.0]
	layout.draw_string(ThemeDB.fallback_font, Vector2(10, 20), ftxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1.0, 0.86, 0.4))
	# representable grid near 1.0
	var n_near: int = int(pow(2.0, float(man_bits)))
	var draw_n: int = mini(n_near, 40)
	var y: float = 96.0
	layout.draw_string(ThemeDB.fallback_font, Vector2(10, y), "Number of distinct values between 1.0 and 2.0: %s" % n_near, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.85, 0.92, 1.0))
	for i in draw_n:
		var px: float = 10.0 + float(i) * (sz.x - 20.0) / float(draw_n)
		layout.draw_line(Vector2(px, y + 4), Vector2(px, y + 14), Color(0.5, 0.95, 0.7, 0.9), 2.0)


func _refresh() -> void:
	layout.queue_redraw()
	for c in info.get_children():
		info.remove_child(c)
		c.queue_free()
	var f: Dictionary = _fmt()
	var bits: int = int(f["bits"])
	var gb: float = model_b * 1e9 * float(bits) / 8.0 / (1024.0 * 1024.0 * 1024.0)
	var fp32_gb: float = model_b * 1e9 * 4.0 / (1024.0 * 1024.0 * 1024.0)
	lbl(info, "Weights for a %.0f B parameter model: %.1f GB  (FP32 would need %.1f GB, saving %.0f%%)" % [
		model_b, gb, fp32_gb, (1.0 - gb / fp32_gb) * 100.0], 15, Color(1.0, 0.85, 0.5))
	var man: int = int(f["man"])
	var eps: float = 0.0
	if int(f["exp"]) > 0:
		eps = pow(2.0, -float(man))
		lbl(info, "Smallest step between two values near 1.0: %.6f   (FP32: %.8f)" % [eps, pow(2.0, -23.0)], 14)
	else:
		var levels: int = int(pow(2.0, float(maxi(bits - 1, 1))))
		lbl(info, "Integer format: %d levels spread over the range of each weight block, with a shared scale per block." % levels, 14)
	# what happens to the example value
	var rounded: float = value
	if int(f["exp"]) > 0:
		if value != 0.0:
			var e: int = int(floor(log(absf(value)) / log(2.0)))
			var step: float = pow(2.0, float(e - man))
			rounded = round(value / step) * step
		lbl(info, "Rounding the value %s gives %s   (error %s)" % [str(value), String.num(rounded, 8), String.num_scientific(absf(rounded - value))], 14, Color(0.8, 0.9, 1.0))
	else:
		var step_i: float = 1.0 / pow(2.0, float(maxi(bits - 1, 1)) - 1.0)
		rounded = round(value / step_i) * step_i
		lbl(info, "Rounding the value %s with this format's step (%.4f) gives %s" % [str(value), step_i, String.num(rounded, 6)], 14, Color(0.8, 0.9, 1.0))
	lbl(info, "Training in BF16 or FP16 with FP32 accumulation is now standard; inference in 8-bit or 4-bit is common. Accuracy drops first on the tasks that need exact numbers, not on fluent text.", 14, Color(0.8, 0.88, 1.0))