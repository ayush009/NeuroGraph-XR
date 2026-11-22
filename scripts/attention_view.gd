class_name AttentionView
extends Control
## Visual for the Attention Lab: the sentence as big word chips. Click a word, and arcs fly from it
## to the words it pays attention to - thicker and brighter = more attention. The top targets get a % tag.

signal word_clicked(index: int)

const CHIP_H: float = 54.0
const GAP: float = 12.0
const ARC_SPACE: float = 150.0
const SEL_COL: Color = Color(0.3, 0.65, 1.0)
const HOT_COL: Color = Color(1.0, 0.62, 0.2)

var words: Array = []
var types: Array = []           # small word-type tag under each chip ("noun", "verb", ...)
var weights: PackedFloat32Array = PackedFloat32Array()   # attention of the selected word to every word
var sel: int = 0
var masked: bool = false
var _grow: float = 1.0          # 0 -> 1 when the selection changes (arcs fly out)
var _chips: Array = []          # Rect2 per word
var _font: Font
var _fs: int = 22
var _hover: int = -1


func _ready() -> void:
	_font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(980, ARC_SPACE + CHIP_H + 40.0)


func set_data(p_words: Array, p_types: Array, p_weights: PackedFloat32Array, p_sel: int, p_masked: bool) -> void:
	var changed: bool = p_sel != sel or p_words != words
	words = p_words
	types = p_types
	weights = p_weights
	sel = p_sel
	masked = p_masked
	if changed:
		_grow = 0.0
	_layout()
	queue_redraw()


func _layout() -> void:
	_chips.clear()
	var width: float = maxf(size.x, custom_minimum_size.x)
	_fs = 30
	var total: float = 0.0
	var widths: Array = []
	for attempt in 6:   # shrink the font for long sentences so everything stays on one line
		total = 0.0
		widths.clear()
		var pad: float = 18.0 + float(_fs) * 0.6
		for i in words.size():
			var cw: float = _font.get_string_size(String(words[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, _fs).x + pad
			if i < types.size():   # the chip is at least as wide as its word-type tag
				cw = maxf(cw, _font.get_string_size(String(types[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 6.0)
			widths.append(cw)
			total += cw + GAP
		if total <= width or _fs <= 14:
			break
		_fs -= 3
	var gap: float = GAP
	if total < width * 0.7:   # short sentence: spread the words out a bit, so the arcs have room
		gap = minf(GAP + (width * 0.7 - total) / maxf(float(words.size() - 1), 1.0), 46.0)
		total += (gap - GAP) * float(words.size() - 1)
	var x: float = maxf(0.0, (width - total) * 0.5)
	var ch: float = float(_fs) + 24.0
	for i in words.size():
		_chips.append(Rect2(x, ARC_SPACE + (CHIP_H - ch) * 0.5, widths[i], ch))
		x += float(widths[i]) + gap


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout()


func _process(delta: float) -> void:
	if _grow < 1.0:
		_grow = minf(1.0, _grow + delta * 2.6)
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		for i in _chips.size():
			if (_chips[i] as Rect2).grow(4.0).has_point((event as InputEventMouseButton).position):
				word_clicked.emit(i)
				accept_event()
				return
	elif event is InputEventMouseMotion:
		var h: int = -1
		for i in _chips.size():
			if (_chips[i] as Rect2).grow(4.0).has_point((event as InputEventMouseMotion).position):
				h = i
		if h != _hover:
			_hover = h
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if h >= 0 else Control.CURSOR_ARROW
			queue_redraw()


func _box(bg: Color, border: Color, bw: int = 2) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(10)
	return sb


func _draw() -> void:
	if _font == null or _chips.is_empty() or weights.size() != words.size():
		return
	var e: float = 1.0 - pow(1.0 - _grow, 3.0)   # ease out
	var src: Vector2 = Vector2((_chips[sel] as Rect2).get_center().x, (_chips[sel] as Rect2).position.y - 4.0)
	# rank the targets so the strongest ones get a % tag
	var order: Array = range(words.size())
	order.sort_custom(func(a: int, b: int) -> bool: return weights[a] > weights[b])
	var tagged: Array = order.slice(0, 3)
	# 1) arcs (weakest first, so strong ones are drawn on top)
	for k in range(order.size() - 1, -1, -1):
		var j: int = order[k]
		var w: float = weights[j]
		if j == sel or w < 0.03:
			continue
		var dst: Vector2 = Vector2((_chips[j] as Rect2).get_center().x, (_chips[j] as Rect2).position.y - 4.0)
		var dist: float = absf(dst.x - src.x)
		var hgt: float = clampf(40.0 + dist * 0.28, 48.0, ARC_SPACE - 30.0)
		var ctrl: Vector2 = Vector2((src.x + dst.x) * 0.5, src.y - hgt * 1.6)
		var pts: PackedVector2Array = PackedVector2Array()
		var steps: int = 28
		var n: int = maxi(2, int(float(steps) * e))
		for s in n + 1:
			var t: float = float(s) / float(steps)
			pts.append(src.lerp(ctrl, t).lerp(ctrl.lerp(dst, t), t))
		var col: Color = HOT_COL.lerp(Color(1.0, 0.9, 0.5), w)
		var a: float = 0.18 + 0.82 * clampf(w * 1.4, 0.0, 1.0)
		draw_polyline(pts, Color(col.r, col.g, col.b, a * 0.25), 2.0 + 16.0 * w, true)   # soft glow
		draw_polyline(pts, Color(col.r, col.g, col.b, a), 1.5 + 7.0 * w, true)
		if e >= 1.0:   # arrow head on arrival
			var tip: Vector2 = dst
			var dir: Vector2 = (dst - pts[pts.size() - 2]).normalized()
			var side: Vector2 = Vector2(-dir.y, dir.x) * (5.0 + 5.0 * w)
			draw_colored_polygon(PackedVector2Array([tip, tip - dir * (10.0 + 6.0 * w) + side, tip - dir * (10.0 + 6.0 * w) - side]), Color(col.r, col.g, col.b, a))
			if tagged.has(j) and w >= 0.06:
				var apex: Vector2 = src.lerp(ctrl, 0.5).lerp(ctrl.lerp(dst, 0.5), 0.5)
				var tag: String = "%d%%" % roundi(w * 100.0)
				var tw: float = _font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 14.0
				draw_style_box(_box(Color(0.05, 0.05, 0.08, 0.92), col, 1), Rect2(apex.x - tw * 0.5, apex.y - 13, tw, 24))
				draw_string(_font, Vector2(apex.x - tw * 0.5 + 7, apex.y + 5), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
	# 2) word chips
	for i in words.size():
		var r: Rect2 = _chips[i]
		var w2: float = weights[i] if i != sel else 0.0
		var future: bool = masked and i > sel
		var bg: Color
		var border: Color
		if i == sel:
			bg = SEL_COL.darkened(0.15)
			border = SEL_COL.lightened(0.4)
		elif future:
			bg = Color(0.08, 0.09, 0.12, 0.8)
			border = Color(0.25, 0.27, 0.32)
		else:
			bg = Color(0.1, 0.13, 0.2).lerp(HOT_COL.darkened(0.15), clampf(w2 * 1.5 * e, 0.0, 1.0))
			border = Color(0.3, 0.4, 0.6).lerp(HOT_COL.lightened(0.3), clampf(w2 * 2.0 * e, 0.0, 1.0))
		if i == _hover and i != sel:
			border = Color(0.7, 0.85, 1.0)
		draw_style_box(_box(bg, border, 3 if i == sel else 2), r)
		var txt: String = String(words[i])
		var tw2: float = _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs).x
		var fc: Color = Color(0.45, 0.48, 0.55) if future else Color.WHITE
		draw_string(_font, Vector2(r.get_center().x - tw2 * 0.5, r.position.y + r.size.y * 0.5 + _fs * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs, fc)
		if i < types.size():
			var ty: String = String(types[i])
			var yw: float = _font.get_string_size(ty, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			draw_string(_font, Vector2(r.get_center().x - yw * 0.5, r.end.y + 18), ty, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.6, 0.72, 0.9, 0.75))
	# 3) prompt when nothing has been clicked yet
	if e < 1.0:
		return
	var lbl: String = "looking from here"
	var lw: float = _font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	var sr: Rect2 = _chips[sel]
	draw_string(_font, Vector2(sr.get_center().x - lw * 0.5, sr.end.y + 34), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, SEL_COL.lightened(0.3))
