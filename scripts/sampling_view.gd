class_name SamplingView
extends Control
## Visual for the Sampling Lab: one tall bar per candidate word (height = probability).
## Bars glide smoothly when temperature / top-k change. Drag a bar up/down to change that word's score.
## spin(i) runs a roulette highlight across the bars that slows down and lands on word i.

signal score_dragged(index: int, delta: float)
signal spin_done(index: int)

const COLS: Array = [Color("#3f8fe0"), Color("#2fb38a"), Color("#e09a35"), Color("#9a6ee0"), Color("#e0577f"), Color("#6fae3c"), Color("#3cb8c8")]
const TOP: float = 40.0         # room for the % labels
const BOTTOM: float = 58.0      # room for the word + tally

var words: Array = []
var probs: PackedFloat32Array = PackedFloat32Array()
var allowed: Array = []
var tally: Dictionary = {}
var _shown: PackedFloat32Array = PackedFloat32Array()   # animated bar heights
var _font: Font
var _drag: int = -1
var _hover: int = -1
var _spin_t: float = -1.0
var _spin_target: int = -1
var _spin_pos: float = 0.0
var _spin_speed: float = 0.0
var _flash: float = 0.0
var _flash_i: int = -1
var _zoom: float = 1.0          # vertical scale: the tallest bar always fills most of the chart


func _ready() -> void:
	_font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(800, 280)


func set_data(p_words: Array, p_probs: PackedFloat32Array, p_allowed: Array, p_tally: Dictionary) -> void:
	words = p_words
	probs = p_probs
	allowed = p_allowed
	tally = p_tally
	if _shown.size() != probs.size():
		_shown = probs.duplicate()
	queue_redraw()


func spinning() -> bool:
	return _spin_t >= 0.0


## Roulette: a highlight runs over the allowed bars, slows down and stops on `target`.
func spin(target: int) -> void:
	_spin_target = target
	_spin_t = 0.0
	_spin_pos = float(randi() % maxi(words.size(), 1))
	_spin_speed = 22.0


func flash(i: int) -> void:
	_flash_i = i
	_flash = 1.0


func _bar_rect(i: int) -> Rect2:
	var n: int = maxi(words.size(), 1)
	var slot: float = size.x / float(n)
	var bw: float = minf(slot * 0.62, 96.0)
	var h: float = size.y - TOP - BOTTOM
	var bh: float = maxf(_shown[i] if i < _shown.size() else 0.0, 0.0) * h * _zoom
	return Rect2(slot * (float(i) + 0.5) - bw * 0.5, TOP + h - bh, bw, bh)


func _slot_at(p: Vector2) -> int:
	if words.is_empty():
		return -1
	var i: int = int(p.x / (size.x / float(words.size())))
	return i if i >= 0 and i < words.size() else -1


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb: InputEventMouseButton = event
		_drag = _slot_at(mb.position) if mb.pressed and not spinning() else -1
		accept_event()
	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		if _drag >= 0:
			score_dragged.emit(_drag, -mm.relative.y * 0.03)   # up = more likely
			accept_event()
		var h: int = _slot_at(mm.position)
		if h != _hover:
			_hover = h
			mouse_default_cursor_shape = Control.CURSOR_VSIZE if h >= 0 else Control.CURSOR_ARROW
			queue_redraw()


func _process(delta: float) -> void:
	var moving: bool = false
	var mx: float = 0.0
	for p in probs:
		mx = maxf(mx, p)
	var zg: float = 0.92 / maxf(mx, 0.35)   # never zoom in more than ~2.6x, so small chances stay small
	if absf(zg - _zoom) > 0.001:
		_zoom = lerpf(_zoom, zg, 1.0 - exp(-delta * 6.0))
		moving = true
	for i in _shown.size():
		if i < probs.size():
			var nv: float = lerpf(_shown[i], probs[i], 1.0 - exp(-delta * 12.0))
			if absf(nv - _shown[i]) > 0.0005:
				moving = true
			_shown[i] = nv
	if spinning():
		_spin_t += delta
		_spin_speed = maxf(_spin_speed * (1.0 - delta * 2.2), 6.0)
		var n: int = maxi(words.size(), 1)
		var before: int = int(_spin_pos) % n
		_spin_pos += _spin_speed * delta
		var now: int = int(_spin_pos) % n
		# once it is slow enough, stop exactly on the target (about 1.5 s in total)
		if _spin_speed <= 6.1 and now == _spin_target and before != now or _spin_t > 2.4:
			_spin_pos = float(_spin_target)
			_spin_t = -1.0
			flash(_spin_target)
			spin_done.emit(_spin_target)
		moving = true
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 1.2)
		moving = true
	if moving:
		queue_redraw()


func _box(bg: Color, border: Color, r: int = 8) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(r)
	sb.corner_radius_bottom_left = 2
	sb.corner_radius_bottom_right = 2
	return sb


func _draw() -> void:
	if _font == null or words.is_empty():
		return
	var h: float = size.y - TOP - BOTTOM
	# baseline + faint guide lines at 25 / 50 / 75 / 100 %
	for g in [0.25, 0.5, 0.75, 1.0]:
		var gy: float = TOP + h - h * float(g) * _zoom
		if gy < TOP - 2.0:
			continue
		draw_line(Vector2(0, gy), Vector2(size.x, gy), Color(0.4, 0.55, 0.8, 0.12), 1.0)
		draw_string(_font, Vector2(2, gy - 3), "%d%%" % roundi(float(g) * 100.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.62, 0.85, 0.45))
	draw_line(Vector2(0, TOP + h), Vector2(size.x, TOP + h), Color(0.5, 0.65, 0.9, 0.5), 2.0)
	var best: int = 0
	for i in probs.size():
		if probs[i] > probs[best]:
			best = i
	var spin_i: int = int(_spin_pos) % words.size() if spinning() else -1
	for i in words.size():
		var ok: bool = i < allowed.size() and bool(allowed[i])
		var r: Rect2 = _bar_rect(i)
		var col: Color = COLS[i % COLS.size()] if ok else Color(0.25, 0.27, 0.32)
		var lit: bool = i == spin_i or (i == _flash_i and _flash > 0.0)
		var glow: float = 1.0 if i == spin_i else _flash if i == _flash_i else 0.0
		if lit:
			col = col.lightened(0.35 * glow)
			var gr: Rect2 = r.grow(6.0 + 4.0 * glow)
			draw_style_box(_box(Color(1.0, 0.9, 0.5, 0.18 * glow), Color(1.0, 0.9, 0.5, 0.6 * glow), 12), gr)
		var bc: Color = col.lightened(0.3) if (i == _hover or i == _drag) else col.darkened(0.2)
		if r.size.y > 0.5:
			draw_style_box(_box(col, bc), r)
		var cx: float = r.get_center().x
		# % above the bar
		var pct: String = ("%d%%" % roundi(probs[i] * 100.0)) if ok else "out"
		var pw: float = _font.get_string_size(pct, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		draw_string(_font, Vector2(cx - pw * 0.5, r.position.y - 9), pct, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE if ok else Color(0.5, 0.52, 0.58))
		# the word under the bar (crown on the favourite)
		var wtxt: String = String(words[i])
		var fs: int = 18 if wtxt.length() <= 9 else 14
		var ww: float = _font.get_string_size(wtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(_font, Vector2(cx - ww * 0.5, TOP + h + 24), wtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.85, 0.4) if i == best and ok else (Color.WHITE if ok else Color(0.45, 0.47, 0.52)))
		if not ok:   # strike-through for words removed by top-k
			draw_line(Vector2(cx - ww * 0.5 - 3, TOP + h + 18), Vector2(cx + ww * 0.5 + 3, TOP + h + 18), Color(0.9, 0.35, 0.35, 0.8), 2.0)
		# how often it was picked
		var cnt: int = int(tally.get(wtxt, 0))
		if cnt > 0:
			var ct: String = "picked ×%d" % cnt
			var cw: float = _font.get_string_size(ct, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			draw_string(_font, Vector2(cx - cw * 0.5, TOP + h + 44), ct, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.5, 1.0, 0.7))
	if _hover >= 0 and _drag < 0 and not spinning():
		var tip: String = "drag up / down to make it more / less likely"
		var tw: float = _font.get_string_size(tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_string(_font, Vector2(size.x - tw - 4, 14), tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.6, 0.75, 1.0, 0.8))
