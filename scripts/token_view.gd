class_name TokenView
extends Control
## Visual for the Token Lab: big "letters -> words -> tokens" counters, then the text drawn as
## colourful token blocks grouped by word, each with its token ID underneath. Blocks pop in one by one.

const PALETTE: Array = [Color("#2f7fd0"), Color("#25a37a"), Color("#c9822b"), Color("#8f62cc"), Color("#c24f74"), Color("#5e9a35")]
const BLOCK_H: float = 40.0
const ROW_H: float = 86.0
const STATS_H: float = 84.0

var words: Array = []          # [[ [text, id], [text, id] ], ...]  one inner array per word
var n_chars: int = 0
var n_words: int = 0
var n_tokens: int = 0
var _anim: float = 0.0          # 0 -> number of blocks, drives the pop-in
var _hover: int = -1
var _rects: Array = []          # [Rect2, token index, text, id, word_size]
var _font: Font


func _ready() -> void:
	_font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_PASS
	custom_minimum_size = Vector2(760, STATS_H + ROW_H + 10.0)


func set_tokens(p_words: Array, chars: int) -> void:
	words = p_words
	n_chars = chars
	n_words = 0
	n_tokens = 0
	for w in words:
		var toks: Array = w
		n_tokens += toks.size()
		if not toks.is_empty() and _is_word(String(toks[0][0])):
			n_words += 1
	_anim = 0.0
	_layout()
	queue_redraw()


func _is_word(t: String) -> bool:
	for ch in t:
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			return true
	return false


func _process(delta: float) -> void:
	if _anim < float(n_tokens) + 1.0:
		_anim += delta * 28.0
		queue_redraw()


func _layout() -> void:
	_rects.clear()
	var x: float = 0.0
	var y: float = STATS_H + 8.0
	var width: float = maxf(size.x, custom_minimum_size.x)
	var idx: int = 0
	for w in words:
		var toks: Array = w
		var ww: float = 0.0
		var widths: Array = []
		for t in toks:
			var tw: float = _font.get_string_size(String(t[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x + 20.0
			widths.append(tw)
			ww += tw + 3.0
		if x > 0.0 and x + ww > width:
			x = 0.0
			y += ROW_H
		for i in toks.size():
			_rects.append([Rect2(x, y, widths[i], BLOCK_H), idx, String(toks[i][0]), int(toks[i][1]), toks.size(), i == 0, i == toks.size() - 1])
			x += float(widths[i]) + 3.0
			idx += 1
		x += 18.0   # gap between words
	custom_minimum_size.y = y + ROW_H + 16.0   # room for the IDs and the hover tooltip
	update_minimum_size()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var h: int = -1
		for r in _rects:
			if (r[0] as Rect2).grow(2.0).has_point((event as InputEventMouseMotion).position):
				h = int(r[1])
		if h != _hover:
			_hover = h
			queue_redraw()


func _stat(x: float, value: String, label: String, col: Color) -> float:
	var vw: float = _font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
	var lw: float = _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	var w: float = maxf(vw, lw) + 36.0
	draw_style_box(_box(Color(col.r, col.g, col.b, 0.14), col.darkened(0.2)), Rect2(x, 4, w, 70))
	draw_string(_font, Vector2(x + (w - vw) * 0.5, 46), value, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, col.lightened(0.25))
	draw_string(_font, Vector2(x + (w - lw) * 0.5, 66), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.75, 0.85, 1.0, 0.85))
	return x + w


func _arrow(x: float) -> float:
	draw_string(_font, Vector2(x + 10, 48), "➜", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(0.6, 0.75, 1.0, 0.7))
	return x + 50.0


func _box(bg: Color, border: Color) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	return sb


func _draw() -> void:
	if _font == null:
		return
	# 1) the three counters
	var x: float = _stat(0.0, str(n_chars), "letters", Color(0.6, 0.7, 0.9))
	x = _arrow(x)
	x = _stat(x, str(n_words), "words" if n_words != 1 else "word", Color(0.45, 0.75, 1.0))
	x = _arrow(x)
	_stat(x, str(n_tokens), "tokens the AI sees" if n_tokens != 1 else "token the AI sees", Color(1.0, 0.75, 0.3))
	# 2) the token blocks, popping in one after another
	for r in _rects:
		var rect: Rect2 = r[0]
		var i: int = r[1]
		var t: float = clampf(_anim - float(i), 0.0, 1.0)
		if t <= 0.0:
			continue
		var s: float = 0.7 + 0.3 * t + 0.12 * sin(t * PI)   # small overshoot
		var rr: Rect2 = Rect2(rect.get_center() - rect.size * s * 0.5, rect.size * s)
		var col: Color = PALETTE[i % PALETTE.size()]
		var hov: bool = i == _hover
		var sb: StyleBoxFlat = _box(col if not hov else col.lightened(0.2), col.lightened(0.35) if hov else col.darkened(0.25))
		# blocks of one word are joined: only the outer corners are rounded
		var first: bool = r[5]
		var last: bool = r[6]
		sb.corner_radius_top_left = 10 if first else 3
		sb.corner_radius_bottom_left = 10 if first else 3
		sb.corner_radius_top_right = 10 if last else 3
		sb.corner_radius_bottom_right = 10 if last else 3
		sb.bg_color.a = t
		draw_style_box(sb, rr)
		var txt: String = r[2]
		var tw: float = _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		draw_string(_font, Vector2(rr.get_center().x - tw * 0.5, rr.position.y + 28), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 1, t))
		# token ID under the block = the number the model actually receives
		var ids: String = "#" + str(r[3]) if int(r[3]) >= 0 else "?"
		var iw: float = _font.get_string_size(ids, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_string(_font, Vector2(rect.get_center().x - iw * 0.5, rect.end.y + 17), ids, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 0.8, 0.95, 0.8 * t))
	# 3) hover help
	if _hover >= 0:
		for r in _rects:
			if int(r[1]) == _hover:
				var rect2: Rect2 = r[0]
				var msg: String = "\"%s\" = token %s" % [r[2], ("#" + str(r[3])) if int(r[3]) >= 0 else "unknown"]
				if int(r[4]) > 1:
					msg += "   (this word was split into %d pieces)" % int(r[4])
				var mw: float = _font.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 20.0
				var px: float = clampf(rect2.position.x, 0.0, size.x - mw)
				draw_style_box(_box(Color(0.02, 0.04, 0.1, 0.95), Color(0.4, 0.6, 1.0)), Rect2(px, rect2.end.y + 22, mw, 26))
				draw_string(_font, Vector2(px + 10, rect2.end.y + 40), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
