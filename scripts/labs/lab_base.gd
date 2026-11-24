class_name LabBase
extends CanvasLayer
## Shared frame for the course labs: a full-screen panel with a title, a one-line intro,
## a scrollable body and a close button. Each lab only implements title(), intro() and
## build_body(). Works on the desktop and on the VR screen (it is added under the UI layer).

signal closed

var theme_ref: Theme
var panel: PanelContainer
var body: VBoxContainer
var status_lbl: Label


func setup(th: Theme) -> void:
	theme_ref = th
	layer = 33
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.004, 0.008, 0.025, 0.80)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var m: MarginContainer = MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 26)
	add_child(m)
	panel = PanelContainer.new()
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.025, 0.045, 0.085, 0.97)
	sb.border_color = Color(0.3, 0.6, 0.95, 0.55)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", sb)
	m.add_child(panel)
	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)
	var head: HBoxContainer = HBoxContainer.new()
	vb.add_child(head)
	var tl: Label = Label.new()
	tl.text = title().to_upper()
	tl.add_theme_font_size_override("font_size", 24)
	tl.add_theme_color_override("font_color", Color(1.0, 0.86, 0.4))
	head.add_child(tl)
	var sp: Control = Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var cb: Button = Button.new()
	cb.text = "✕  Close"
	cb.focus_mode = Control.FOCUS_NONE
	cb.pressed.connect(close)
	head.add_child(cb)
	var sub: Label = Label.new()
	sub.text = intro()
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_color_override("font_color", Color(0.78, 0.88, 1.0, 0.9))
	vb.add_child(sub)
	var sc: ScrollContainer = ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(sc)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(body)
	visible = false
	build_body(body)


func open() -> void:
	visible = true


func close() -> void:
	visible = false
	closed.emit()


# ── helpers for the labs ──
func title() -> String:
	return "Lab"


func intro() -> String:
	return ""


func build_body(_vb: VBoxContainer) -> void:
	pass


func lbl(parent: Node, text: String, size: int = 15, col: Color = Color(0.9, 0.94, 1.0)) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# keep short labels at their natural width inside HBox rows; long notes still wrap to the panel width
	l.custom_minimum_size = Vector2(minf(float(text.length()) * float(size) * 0.64 + 18.0, 330.0), 0)
	parent.add_child(l)
	return l


func rich(parent: Node, title_text: String, body_text: String) -> VBoxContainer:
	var v: VBoxContainer = VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	parent.add_child(v)
	lbl(v, title_text, 16, Color(1.0, 0.85, 0.5))
	lbl(v, body_text, 14, Color(0.8, 0.88, 1.0))
	return v


func btn(parent: Node, text: String, cb: Callable, accent: bool = false) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	if accent:
		var sb: StyleBoxFlat = StyleBoxFlat.new()
		sb.bg_color = Color(0.13, 0.4, 0.75, 0.9)
		sb.set_corner_radius_all(8)
		sb.set_content_margin_all(6)
		b.add_theme_stylebox_override("normal", sb)
	parent.add_child(b)
	return b


func hbox(parent: Node, sep: int = 8) -> HBoxContainer:
	var h: HBoxContainer = HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	parent.add_child(h)
	return h


func slider(parent: Node, lo: float, hi: float, val: float, step: float, cb: Callable) -> HSlider:
	var s: HSlider = HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = val
	s.custom_minimum_size = Vector2(260, 0)
	s.value_changed.connect(cb)
	parent.add_child(s)
	return s


func bar(parent: Node, label_text: String, fill: float, col: Color, tail: String = "") -> HBoxContainer:
	var h: HBoxContainer = hbox(parent, 6)
	var nl: Label = Label.new()
	nl.text = label_text
	nl.add_theme_font_size_override("font_size", 14)
	nl.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	nl.autowrap_mode = TextServer.AUTOWRAP_OFF
	nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nl.custom_minimum_size = Vector2(190, 0)
	h.add_child(nl)
	var pb: ProgressBar = ProgressBar.new()
	pb.custom_minimum_size = Vector2(200, 14)
	pb.max_value = 1.0
	pb.value = clampf(fill, 0.0, 1.0)
	pb.show_percentage = false
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(4)
	pb.add_theme_stylebox_override("fill", sb)
	h.add_child(pb)
	if tail != "":
		var tl: Label = Label.new()
		tl.text = tail
		tl.add_theme_font_size_override("font_size", 13)
		tl.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
		tl.autowrap_mode = TextServer.AUTOWRAP_OFF
		tl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		h.add_child(tl)
	return h