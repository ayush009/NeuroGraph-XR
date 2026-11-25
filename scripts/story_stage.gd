class_name StoryStage
extends Control
## Animated, interactive diagram stage for the course "story player".
## A scene is plain data:  {"t": template, "items": [...], "beats": [{"cap", "show", "hi", "note"}], ...extras}
## set_beat(i) reveals items step by step (pop-in animation), highlights some, and shows a callout.
## Everything can be hovered (tooltip) and clicked. Templates:
##   flow, cycle, stack, tokens, bars, vectors, attention, compare, curve, grid, tree, timeline,
##   network, scale, chat, funnel

signal item_clicked(index: int, tip: String)

const PAL: Array = [Color("#4fc3ff"), Color("#5ee6a0"), Color("#ffb85c"), Color("#c59bff"),
	Color("#ff7aa8"), Color("#ffe066"), Color("#5ad6d0"), Color("#ff8a65")]
const TEMPLATES: Array = ["flow", "cycle", "stack", "tokens", "bars", "vectors", "attention", "compare",
	"curve", "grid", "tree", "timeline", "network", "scale", "chat", "funnel"]
const CURVES: Array = ["decay", "power", "log", "sigmoid", "sin", "linear", "exp", "ushape", "bell", "quad", "step"]

var scene: Dictionary = {}
var tpl: String = "flow"
var items: Array = []
var beats: Array = []
var beat_i: int = 0
var shown: int = 0
var hi: Array = []
var note: String = ""
var t: float = 0.0
var beat_t: float = 0.0
var scene_t: float = 0.0
var appear: PackedFloat32Array = PackedFloat32Array()
var hover: int = -1
var pinned: int = -1
var hits: Array = []           # Rect2 per item, refreshed every draw
var temp: float = 1.0          # bars: softmax temperature (interactive)
var temp_rect: Rect2 = Rect2()
var drag_x: float = 0.62       # curve: draggable probe
var plot_rect: Rect2 = Rect2()
var dragging: String = ""
var pulses: Array = []         # network / flow click bursts: {"t0": float}
var mouse: Vector2 = Vector2.ZERO
var font: Font
var _sb: StyleBoxFlat = StyleBoxFlat.new()
var _stars: Array = []


func _ready() -> void:
	font = get_theme_default_font()
	if font == null:
		font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	for i in 40:
		_stars.append(Vector3(rng.randf(), rng.randf(), rng.randf_range(0.3, 1.0)))


func _process(delta: float) -> void:
	if is_visible_in_tree():
		t += delta
		queue_redraw()


# ───────────────────────── scene control ─────────────────────────
func set_scene(s: Dictionary) -> void:
	scene = s
	tpl = String(s.get("t", "flow"))
	if not TEMPLATES.has(tpl):
		tpl = "flow"
	items = s.get("items", [])
	beats = s.get("beats", [])
	appear = PackedFloat32Array()
	appear.resize(items.size())
	appear.fill(-100.0)
	shown = 0
	hover = -1
	pinned = -1
	temp = 1.0
	drag_x = 0.62
	pulses.clear()
	scene_t = t
	set_beat(0)


func beat_count() -> int:
	return maxi(beats.size(), 1)


func beat_caption(i: int) -> String:
	if i < beats.size():
		return String((beats[i] as Dictionary).get("cap", ""))
	return ""


func set_beat(i: int) -> void:
	beat_i = clampi(i, 0, maxi(beats.size() - 1, 0))
	var b: Dictionary = beats[beat_i] if beat_i < beats.size() else {}
	var ns: int = items.size()
	if b.has("show"):
		ns = clampi(int(b["show"]), 0, items.size())
	elif beat_i > 0:
		ns = maxi(shown, 0)
	var k: int = 0
	for j in items.size():
		if j < ns:
			if appear[j] < -50.0:
				appear[j] = t + float(k) * 0.14
				k += 1
		else:
			appear[j] = -100.0
	shown = ns
	hi.clear()
	for h in b.get("hi", []):
		hi.append(int(h))
	note = String(b.get("note", ""))
	beat_t = t


func show_all() -> void:
	## the learner's "free play" view: everything visible, nothing forced
	for j in items.size():
		if appear[j] < -50.0:
			appear[j] = t
	shown = items.size()


# ───────────────────────── helpers ─────────────────────────
func _alpha(i: int) -> float:
	if i < 0 or i >= items.size() or i >= shown or appear[i] < -50.0:
		return 0.0
	return clampf((t - appear[i]) / 0.45, 0.0, 1.0)


func _pop(a: float) -> float:
	var x: float = a - 1.0
	return 1.0 + 2.70158 * x * x * x + 1.70158 * x * x


func _col(i: int) -> Color:
	var it: Dictionary = items[i] if i < items.size() else {}
	return PAL[int(it.get("c", i)) % PAL.size()]


func _lab(i: int) -> String:
	return String((items[i] as Dictionary).get("l", "")) if i < items.size() else ""


func _val(i: int, d: float = 0.0) -> float:
	return float((items[i] as Dictionary).get("v", d)) if i < items.size() else d


func _is_hi(i: int) -> bool:
	return hi.has(i) or i == pinned


func _glow() -> float:
	return 0.5 + 0.5 * sin(t * 5.0)


func _hit(i: int, r: Rect2) -> void:
	while hits.size() <= i:
		hits.append(Rect2())
	hits[i] = r


func _box(r: Rect2, col: Color, a: float, label: String, glow: bool, fs: int = 16, fill_k: float = 0.22) -> Rect2:
	if a <= 0.0:
		return Rect2()
	var s: float = _pop(a)
	var c: Vector2 = r.get_center()
	var rr: Rect2 = Rect2(c - r.size * 0.5 * s, r.size * s)
	if glow:
		var g: float = _glow()
		_sb.bg_color = Color(col.r, col.g, col.b, 0.10 + 0.12 * g)
		_sb.set_corner_radius_all(14)
		_sb.set_border_width_all(0)
		draw_style_box(_sb, rr.grow(6.0 + 4.0 * g))
	_sb.bg_color = Color(col.r * fill_k, col.g * fill_k, col.b * fill_k + 0.03, 0.95 * a)
	_sb.border_color = Color(col.r, col.g, col.b, a * (1.0 if glow else 0.75))
	_sb.set_border_width_all(3 if glow else 2)
	_sb.set_corner_radius_all(10)
	draw_style_box(_sb, rr)
	if label != "" and s > 0.4:
		_text_in(rr.grow(-6.0), label, fs, Color(1, 1, 1, a))
	return rr


func _text_in(r: Rect2, text: String, fs: int, col: Color) -> void:
	var w: float = maxf(r.size.x, 10.0)
	# never cut a word in half: shrink until the longest word fits the box width
	var longest: String = ""
	for word in text.split(" ", false):
		if word.length() > longest.length():
			longest = word
	while fs > 10 and font.get_string_size(longest, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > w:
		fs -= 1
	var sz: Vector2 = font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, w, fs)
	while sz.y > r.size.y + 2.0 and fs > 10:
		fs -= 1
		sz = font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, w, fs)
	var top: float = r.get_center().y - sz.y * 0.5 + font.get_ascent(fs)
	draw_multiline_string(font, Vector2(r.position.x, top), text, HORIZONTAL_ALIGNMENT_CENTER, w, fs, -1, col)


func _text(p: Vector2, text: String, fs: int, col: Color, align: int = HORIZONTAL_ALIGNMENT_CENTER, w: float = 300.0) -> void:
	var x: float = p.x
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		x -= w * 0.5
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		x -= w
	draw_string(font, Vector2(x, p.y + font.get_ascent(fs) * 0.35), text, align, w, fs, col)


## Label placement that avoids earlier labels: tries the preferred spot, then nudges up/down/sideways.
## Returns the rect it used, or an empty Rect2 when no free place was found (the label is skipped).
var _placed: Array = []


func _place_label(anchor: Vector2, text: String, fs: int, sz: Vector2, prefer_up: bool = true) -> Rect2:
	var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 6.0
	var h: float = float(fs) + 6.0
	var offs: Array = [Vector2(-w * 0.5, -h - 12.0), Vector2(-w * 0.5, 12.0), Vector2(14.0, -h * 0.5), Vector2(-w - 14.0, -h * 0.5),
		Vector2(-w * 0.5, -h * 2.0 - 16.0), Vector2(-w * 0.5, h + 16.0), Vector2(14.0, -h - 10.0), Vector2(-w - 14.0, -h - 10.0)]
	if not prefer_up:
		offs = [offs[1], offs[0]] + offs.slice(2)
	for o in offs:
		var r: Rect2 = Rect2(anchor + (o as Vector2), Vector2(w, h))
		r.position.x = clampf(r.position.x, 4.0, sz.x - w - 4.0)
		r.position.y = clampf(r.position.y, 54.0, sz.y - h - 4.0)
		var clash: bool = false
		for p in _placed:
			if (p as Rect2).intersects(r):
				clash = true
				break
		if not clash:
			_placed.append(r)
			return r
	return Rect2()


## Like _place_label but searches rings further and further out (for crowded scatter plots).
func _place_label_far(anchor: Vector2, text: String, fs: int, sz: Vector2) -> Rect2:
	var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 6.0
	var h: float = float(fs) + 6.0
	for ring in 7:
		var dist: float = 12.0 + float(ring) * 22.0
		for k in 8:
			var ang: float = -PI * 0.25 - TAU * float(k) / 8.0
			var dir: Vector2 = Vector2(cos(ang), sin(ang))
			var c: Vector2 = anchor + dir * (dist + absf(dir.x) * w * 0.5 + absf(dir.y) * h * 0.5)
			var r: Rect2 = Rect2(c - Vector2(w, h) * 0.5, Vector2(w, h))
			if r.position.x < 4.0 or r.end.x > sz.x - 4.0 or r.position.y < 54.0 or r.end.y > sz.y - 4.0:
				continue
			var clash: bool = false
			for p in _placed:
				if (p as Rect2).intersects(r.grow(2.0)):
					clash = true
					break
			if not clash:
				_placed.append(r)
				return r
	return _place_label(anchor, text, fs, sz)


func _draw_placed(r: Rect2, text: String, fs: int, col: Color) -> void:
	if r.size.x <= 0.0:
		return
	draw_string(font, r.position + Vector2(3, font.get_ascent(fs) + 2.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _arrow(a: Vector2, b: Vector2, col: Color, width: float = 3.0, head: float = 11.0) -> void:
	draw_line(a, b, col, width, true)
	var d: Vector2 = (b - a).normalized()
	if d == Vector2.ZERO:
		return
	var n: Vector2 = Vector2(-d.y, d.x)
	draw_colored_polygon(PackedVector2Array([b, b - d * head + n * head * 0.55, b - d * head - n * head * 0.55]), col)


func _dots_along(a: Vector2, b: Vector2, col: Color, speed: float = 0.55, n: int = 3) -> void:
	for j in n:
		var f: float = fmod(t * speed + float(j) / float(n), 1.0)
		draw_circle(a.lerp(b, f), 4.0, Color(col.r, col.g, col.b, sin(f * PI)))


func _sig(v: float) -> String:
	## up to 3 significant digits, no trailing zeros (GDScript has no %g)
	var av: float = absf(v)
	var dec: int = 0 if av >= 100.0 else (1 if av >= 10.0 else (2 if av >= 1.0 else 3))
	var s: String = String.num(v, dec)
	if s.contains("."):
		s = s.rstrip("0").rstrip(".")
	return s


func _fmt(v: float) -> String:
	var av: float = absf(v)
	if av >= 1e12:
		return _sig(v / 1e12) + " T"
	if av >= 1e9:
		return _sig(v / 1e9) + " B"
	if av >= 1e6:
		return _sig(v / 1e6) + " M"
	if av >= 1e4:
		return _sig(v / 1e3) + " k"
	if av == floorf(av) and av < 1e4:
		return str(int(v))
	return _sig(v)


# ───────────────────────── drawing ─────────────────────────
func _draw() -> void:
	var sz: Vector2 = size
	hits.clear()
	_placed.clear()
	if note != "":
		_placed.append(Rect2(sz.x * 0.5 - 230.0, 6.0, 460.0, 50.0))   # keep labels off the callout pill
	for i in items.size():
		hits.append(Rect2())
	# backdrop: soft panel + drifting dots, so the stage always feels alive
	_sb.bg_color = Color(0.02, 0.035, 0.075, 0.96)
	_sb.border_color = Color(0.3, 0.55, 0.95, 0.35)
	_sb.set_border_width_all(1)
	_sb.set_corner_radius_all(16)
	draw_style_box(_sb, Rect2(Vector2.ZERO, sz))
	for st in _stars:
		var v3: Vector3 = st
		var p: Vector2 = Vector2(fmod(v3.x + t * 0.008 * v3.z, 1.0) * sz.x, v3.y * sz.y)
		draw_circle(p, 1.2 + v3.z, Color(0.5, 0.7, 1.0, 0.12 + 0.12 * sin(t * v3.z * 2.0 + v3.x * 9.0)))
	if items.is_empty() and tpl != "curve" and tpl != "network" and tpl != "grid":
		return
	call("_draw_" + tpl, sz)
	_draw_note(sz)
	_draw_tip(sz)


func _draw_note(sz: Vector2) -> void:
	if note == "":
		return
	var a: float = clampf((t - beat_t - 0.25) / 0.4, 0.0, 1.0)
	if a <= 0.0:
		return
	var fs: int = 20
	var w: float = font.get_string_size(note, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 36.0
	var s: float = _pop(a)
	var c: Vector2 = Vector2(sz.x * 0.5, 30.0)
	var r: Rect2 = Rect2(c - Vector2(w, 40) * 0.5 * s, Vector2(w, 40) * s)
	_sb.bg_color = Color(1.0, 0.82, 0.3, 0.95 * a)
	_sb.border_color = Color(1, 1, 1, 0.6 * a)
	_sb.set_border_width_all(2)
	_sb.set_corner_radius_all(20)
	draw_style_box(_sb, r)
	if s > 0.6:
		_text_in(r, note, fs, Color(0.08, 0.06, 0.02, a))


func _draw_tip(sz: Vector2) -> void:
	var i: int = hover if hover >= 0 else pinned
	if i < 0 or i >= items.size() or _alpha(i) <= 0.0:
		return
	var it: Dictionary = items[i]
	var tip: String = String(it.get("tip", ""))
	if tip == "":
		tip = _lab(i)
		if it.has("v") and tpl != "tokens":
			tip += "  ·  " + _fmt(float(it["v"]))
	if tip == "":
		return
	var w: float = minf(360.0, font.get_string_size(tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 24.0)
	var h: float = font.get_multiline_string_size(tip, HORIZONTAL_ALIGNMENT_LEFT, w - 20.0, 15).y + 16.0
	var anchor: Vector2 = mouse if hover >= 0 else (hits[i] as Rect2).get_center()
	var p: Vector2 = anchor + Vector2(16, 14)
	p.x = clampf(p.x, 6.0, sz.x - w - 6.0)
	p.y = clampf(p.y, 6.0, sz.y - h - 6.0)
	_sb.bg_color = Color(0.06, 0.09, 0.17, 0.97)
	_sb.border_color = _col(i)
	_sb.set_border_width_all(2)
	_sb.set_corner_radius_all(8)
	draw_style_box(_sb, Rect2(p, Vector2(w, h)))
	draw_multiline_string(font, p + Vector2(10, 8 + font.get_ascent(15)), tip, HORIZONTAL_ALIGNMENT_LEFT, w - 20.0, 15, -1, Color(0.93, 0.96, 1.0))


# ── flow: a pipeline left → right (snakes to two rows when long), dots travel along arrows ──
func _draw_flow(sz: Vector2) -> void:
	var n: int = items.size()
	var rows: int = 1 if n <= 5 else 2
	var per: int = ceili(float(n) / float(rows))
	var gap: float = 46.0
	var bw: float = minf(190.0, (sz.x - 60.0 - gap * float(per - 1)) / float(per))
	var bh: float = 78.0
	var centers: Array = []
	for i in n:
		var r: int = i / per
		var c: int = i % per
		if r == 1:
			c = per - 1 - c        # snake: second row runs right → left
		var total_w: float = float(per) * bw + float(per - 1) * gap
		var x: float = (sz.x - total_w) * 0.5 + float(c) * (bw + gap) + bw * 0.5
		var y: float = sz.y * (0.55 if rows == 1 else (0.36 + 0.36 * float(r)))
		centers.append(Vector2(x, y))
	for i in n - 1:
		var a: float = minf(_alpha(i), _alpha(i + 1))
		if a <= 0.0:
			continue
		var p0: Vector2 = centers[i]
		var p1: Vector2 = centers[i + 1]
		var d: Vector2 = (p1 - p0).normalized()
		var off: float = (bw * 0.5 + 6.0) if absf(d.x) > 0.5 else (bh * 0.5 + 6.0)
		var aa: Vector2 = p0 + d * off
		var bb: Vector2 = p1 - d * off
		_arrow(aa, aa.lerp(bb, a), Color(0.55, 0.75, 1.0, 0.7 * a), 3.0)
		if a >= 1.0:
			_dots_along(aa, bb, _col(i + 1))
	for i in n:
		var r: Rect2 = Rect2(centers[i] - Vector2(bw, bh) * 0.5, Vector2(bw, bh))
		var rr: Rect2 = _box(r, _col(i), _alpha(i), _lab(i), _is_hi(i), 17)
		_hit(i, rr)
	for p in pulses:
		var f: float = (t - float(p["t0"])) / 2.5
		if f < 1.0 and n > 1:
			var seg: float = f * float(n - 1)
			var k: int = mini(int(seg), n - 2)
			draw_circle((centers[k] as Vector2).lerp(centers[k + 1], seg - float(k)), 9.0, Color(1, 0.9, 0.4, 0.9))


# ── cycle: steps around a loop with a comet circling ──
func _draw_cycle(sz: Vector2) -> void:
	var n: int = items.size()
	var bh: float = 58.0
	# keep clear of the callout pill at the top (ends ~y=56) and the bottom edge
	var c: Vector2 = Vector2(sz.x * 0.5, (64.0 + sz.y) * 0.5 + 6.0)
	var rad: float = minf(sz.x * 0.3, (sz.y - 64.0) * 0.5 - bh * 0.5 - 12.0)
	var bw: float = minf(200.0, maxf(rad * 1.15, 150.0))
	var all_a: float = 1.0
	for i in n:
		all_a = minf(all_a, _alpha(i))
	draw_arc(c, rad, 0, TAU, 96, Color(0.45, 0.65, 1.0, 0.18 + 0.25 * all_a), 3.0, true)
	if all_a > 0.0:
		var ang: float = -PI * 0.5 + t * 0.9
		for k in 8:
			var aa: float = ang - float(k) * 0.07
			draw_circle(c + Vector2(cos(aa), sin(aa)) * rad, 7.0 - float(k) * 0.7, Color(1.0, 0.85, 0.4, (1.0 - float(k) / 8.0) * all_a))
	for i in n:
		var ang2: float = -PI * 0.5 + TAU * float(i) / float(n)
		var p: Vector2 = c + Vector2(cos(ang2) * rad * 1.6, sin(ang2) * rad)
		_hit(i, _box(Rect2(p - Vector2(bw, bh) * 0.5, Vector2(bw, bh)), _col(i), _alpha(i), _lab(i), _is_hi(i), 16))
	if scene.has("center"):
		# the centre label fits inside the ring, wrapping and shrinking if needed
		_text_in(Rect2(c - Vector2(rad * 0.75, rad * 0.45), Vector2(rad * 1.5, rad * 0.9)), String(scene["center"]), 19, Color(0.85, 0.92, 1.0, 0.9))


# ── stack: layers built bottom → top, data rising through them ──
func _draw_stack(sz: Vector2) -> void:
	var n: int = items.size()
	var h: float = minf(58.0, (sz.y - 90.0) / float(maxi(n, 1)) - 8.0)
	var w: float = minf(520.0, sz.x * 0.6)
	var x: float = (sz.x - w) * 0.5
	var bottom: float = sz.y - 28.0
	for i in n:
		var a: float = _alpha(i)
		var y: float = bottom - float(i + 1) * (h + 8.0) - (1.0 - a) * 50.0
		_hit(i, _box(Rect2(x, y, w, h), _col(i), a, _lab(i), _is_hi(i), 17))
	if shown > 1:
		var top: float = bottom - float(shown) * (h + 8.0)
		var ax: float = x - 34.0
		_arrow(Vector2(ax, bottom - 6.0), Vector2(ax, top + 10.0), Color(0.55, 0.75, 1.0, 0.6), 3.0)
		_dots_along(Vector2(ax, bottom - 6.0), Vector2(ax, top + 10.0), Color(1.0, 0.85, 0.4), 0.4)
		if scene.has("axis"):
			# written along the arrow, reading bottom → top
			var span: float = bottom - top
			draw_set_transform(Vector2(ax - 16.0, bottom - 6.0), -PI * 0.5)
			var afs: int = 15
			while afs > 10 and font.get_string_size(String(scene["axis"]), HORIZONTAL_ALIGNMENT_LEFT, -1, afs).x > span:
				afs -= 1
			draw_string(font, Vector2(0, 0), String(scene["axis"]), HORIZONTAL_ALIGNMENT_CENTER, span, afs, Color(0.7, 0.82, 1.0))
			draw_set_transform(Vector2.ZERO)


# ── tokens: a sentence breaks into coloured token chips that fly into place, with their IDs ──
func _draw_tokens(sz: Vector2) -> void:
	var text: String = String(scene.get("text", ""))
	var fs_line: int = 24
	var line_w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_line).x
	var lx: float = (sz.x - line_w) * 0.5
	var ly: float = sz.y * 0.24
	if text != "":
		var fade: float = 1.0 - 0.55 * clampf(float(shown) / float(maxi(items.size(), 1)), 0.0, 1.0)
		draw_string(font, Vector2(lx, ly), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_line, Color(0.9, 0.94, 1.0, fade))
	var fs: int = 22
	var widths: Array = []
	var total: float = 0.0
	for i in items.size():
		var w: float = maxf(font.get_string_size(_lab(i), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 26.0, 44.0)
		widths.append(w)
		total += w + 10.0
	var max_row: float = sz.x - 60.0
	var rows: int = ceili(total / max_row)
	var src: int = 0
	var x: float = 0.0
	var row_start: Array = [0]
	var acc: float = 0.0
	for i in items.size():
		if acc + float(widths[i]) > max_row and acc > 0.0:
			row_start.append(i)
			acc = 0.0
		acc += float(widths[i]) + 10.0
	row_start.append(items.size())
	for r in row_start.size() - 1:
		var a0: int = row_start[r]
		var a1: int = row_start[r + 1]
		var rw: float = 0.0
		for i in range(a0, a1):
			rw += float(widths[i]) + 10.0
		x = (sz.x - rw + 10.0) * 0.5
		var y: float = sz.y * (0.56 if rows <= 1 else 0.46) + float(r) * 86.0
		for i in range(a0, a1):
			var piece: String = _lab(i).strip_edges()
			var found: int = text.find(piece, src) if piece != "" else -1
			var start_x: float = lx + line_w * 0.5
			if found >= 0:
				start_x = lx + font.get_string_size(text.substr(0, found), HORIZONTAL_ALIGNMENT_LEFT, -1, fs_line).x + font.get_string_size(piece, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_line).x * 0.5
				src = found + piece.length()
			var a: float = _alpha(i)
			var w: float = widths[i]
			var target: Vector2 = Vector2(x + w * 0.5, y)
			var p: Vector2 = Vector2(start_x, ly - 8.0).lerp(target, 1.0 - pow(1.0 - a, 3.0))
			if a > 0.0:
				var rr: Rect2 = _box(Rect2(p - Vector2(w, 46) * 0.5, Vector2(w, 46)), _col(i), maxf(a, 0.01), _lab(i), _is_hi(i), fs, 0.45)
				_hit(i, rr)
				if items[i].has("v") and a >= 1.0:
					_text(target + Vector2(0, 40), "#" + str(int(_val(i))), 14, Color(0.7, 0.8, 0.95), HORIZONTAL_ALIGNMENT_CENTER, w + 20.0)
			x += w + 10.0
	if shown >= items.size() and items.size() > 0:
		_text(Vector2(sz.x * 0.5, sz.y - 24.0), "%d tokens" % items.size(), 16, Color(1.0, 0.85, 0.45))


# ── bars: scores / probabilities; with "softmax": true they react to a temperature slider ──
func _probs() -> Array:
	var out: Array = []
	var sm: bool = bool(scene.get("softmax", false))
	if sm:
		var mx: float = -1e9
		for i in items.size():
			mx = maxf(mx, _val(i))
		var s: float = 0.0
		for i in items.size():
			var e: float = exp((_val(i) - mx) / maxf(temp, 0.05))
			out.append(e)
			s += e
		for i in out.size():
			out[i] = float(out[i]) / maxf(s, 1e-9)
	else:
		var mx2: float = 0.0
		for i in items.size():
			mx2 = maxf(mx2, absf(_val(i)))
		for i in items.size():
			out.append(_val(i) / maxf(mx2, 1e-9))
	return out


func _draw_bars(sz: Vector2) -> void:
	var n: int = items.size()
	var sm: bool = bool(scene.get("softmax", false))
	var has_temp: bool = sm and bool(scene.get("temp", false))
	var top: float = 64.0
	var bottom: float = sz.y - (78.0 if has_temp else 24.0)
	var rh: float = minf(46.0, (bottom - top) / float(maxi(n, 1)))
	var lw: float = 150.0          # label column fits the longest label (up to ~40% of the stage)
	for i in n:
		lw = maxf(lw, font.get_string_size(_lab(i), HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + 18.0)
	lw = minf(lw, sz.x * 0.4)
	var bx: float = 40.0 + lw
	var bw: float = sz.x - bx - 140.0
	var ps: Array = _probs()
	var unit: String = String(scene.get("unit", ""))
	for i in n:
		var a: float = _alpha(i)
		if a <= 0.0:
			continue
		var y: float = top + float(i) * rh
		var col: Color = _col(i)
		var lfs: int = 18
		while lfs > 11 and font.get_string_size(_lab(i), HORIZONTAL_ALIGNMENT_LEFT, -1, lfs).x > lw - 14.0:
			lfs -= 1
		draw_string(font, Vector2(40, y + rh * 0.5 + 7.0), _lab(i), HORIZONTAL_ALIGNMENT_RIGHT, lw - 14.0, lfs, Color(0.92, 0.95, 1.0, a))
		var p: float = float(ps[i])
		var grow: float = 1.0 - pow(1.0 - clampf((t - appear[i]) / 0.8, 0.0, 1.0), 3.0)
		var w: float = maxf(bw * absf(p) * grow, 3.0)
		var r: Rect2 = Rect2(bx, y + rh * 0.18, w, rh * 0.64)
		if _is_hi(i):
			draw_rect(r.grow(4.0), Color(col.r, col.g, col.b, 0.18 + 0.15 * _glow()))
		draw_rect(r, Color(col.r, col.g, col.b, 0.9 * a))
		var vt: String = ("%.0f%%" % (p * 100.0)) if sm else (_fmt(_val(i)) + unit)
		if sm and p < 0.01:
			vt = "%.1f%%" % (p * 100.0)
		draw_string(font, Vector2(bx + w + 10.0, y + rh * 0.5 + 7.0), vt, HORIZONTAL_ALIGNMENT_LEFT, 130.0, 17, Color(1.0, 0.9, 0.6, a))
		_hit(i, Rect2(40, y, sz.x - 80.0, rh))
	if has_temp:
		var ty: float = sz.y - 40.0
		var tx0: float = bx
		var tx1: float = bx + bw
		temp_rect = Rect2(tx0 - 10.0, ty - 16.0, tx1 - tx0 + 20.0, 32.0)
		draw_line(Vector2(tx0, ty), Vector2(tx1, ty), Color(0.4, 0.55, 0.85, 0.8), 4.0, true)
		var f: float = (temp - 0.1) / 2.4
		var kx: float = lerpf(tx0, tx1, f)
		draw_circle(Vector2(kx, ty), 11.0 + 2.0 * _glow(), Color(1.0, 0.82, 0.3))
		draw_string(font, Vector2(40, ty + 6.0), "temperature  %.2f" % temp, HORIZONTAL_ALIGNMENT_RIGHT, lw - 14.0, 17, Color(1.0, 0.85, 0.45))
		draw_string(font, Vector2(tx0, ty + 28.0), "focused", HORIZONTAL_ALIGNMENT_LEFT, 120.0, 13, Color(0.7, 0.8, 0.95))
		draw_string(font, Vector2(tx1 - 120.0, ty + 28.0), "creative  (drag me)", HORIZONTAL_ALIGNMENT_RIGHT, 120.0, 13, Color(0.7, 0.8, 0.95))


# ── vectors: points / arrows in a 2-D meaning space; two highlighted ones show their angle ──
func _draw_vectors(sz: Vector2) -> void:
	var c: Vector2 = Vector2(sz.x * 0.5, sz.y * 0.56)
	var sy: float = sz.y * 0.36
	var sx: float = minf(sz.x * 0.42, sy * 2.2)   # use the stage's width: spreads crowded points apart
	draw_line(Vector2(c.x - sx * 1.1, c.y), Vector2(c.x + sx * 1.1, c.y), Color(0.35, 0.55, 0.95, 0.35), 2.0)
	draw_line(Vector2(c.x, c.y - sy * 1.15), Vector2(c.x, c.y + sy * 1.15), Color(0.35, 0.55, 0.95, 0.35), 2.0)
	if scene.has("xl"):
		_text(Vector2(c.x + sx * 1.0, c.y + 18.0), String(scene["xl"]), 13, Color(0.6, 0.75, 1.0), HORIZONTAL_ALIGNMENT_CENTER, 200.0)
	if scene.has("yl"):
		_text(Vector2(c.x + 70.0, c.y - sy * 1.1), String(scene["yl"]), 13, Color(0.6, 0.75, 1.0), HORIZONTAL_ALIGNMENT_CENTER, 140.0)
	var arrows: bool = bool(scene.get("arrows", true))
	var pts: Array = []
	for i in items.size():
		var it: Dictionary = items[i]
		pts.append(c + Vector2(float(it.get("x", 0.0)) * sx, -float(it.get("y", 0.0)) * sy))
	# label positions: reserve every point first, then give each label the nearest free spot
	# (above / below / left / right / further out), drawing a thin leader line when it moved away
	for i in items.size():
		_placed.append(Rect2((pts[i] as Vector2) - Vector2(9, 9), Vector2(18, 18)))
	var lab_rects: Array = []
	for i in items.size():
		var lr: Rect2 = _place_label_far(pts[i], _lab(i), 17, sz)
		lab_rects.append(lr)
	for i in items.size():
		var a: float = _alpha(i)
		if a <= 0.0:
			continue
		var col: Color = _col(i)
		var p: Vector2 = c.lerp(pts[i], 1.0 - pow(1.0 - a, 3.0))
		if arrows:
			_arrow(c, p, Color(col.r, col.g, col.b, 0.75 * a), 3.0 if _is_hi(i) else 2.0)
		if _is_hi(i):
			draw_circle(p, 13.0 + 3.0 * _glow(), Color(col.r, col.g, col.b, 0.25))
		draw_circle(p, 8.0, Color(col.r, col.g, col.b, a))
		var lr2: Rect2 = lab_rects[i]
		if lr2.size.x > 0.0:
			var near: Vector2 = Vector2(clampf(p.x, lr2.position.x, lr2.end.x), clampf(p.y, lr2.position.y, lr2.end.y))
			if near.distance_to(p) > 26.0:
				draw_line(p, near, Color(col.r, col.g, col.b, 0.55 * a), 1.5)
			_draw_placed(lr2, _lab(i), 17, Color(1, 1, 1, a))
		_hit(i, Rect2(p - Vector2(22, 22), Vector2(44, 44)))
	var his: Array = []
	for h in hi:
		if int(h) < items.size() and _alpha(int(h)) > 0.0:
			his.append(int(h))
	if pinned >= 0 and not his.has(pinned):
		his.append(pinned)
	if his.size() >= 2 and arrows:
		var va: Vector2 = (pts[his[0]] as Vector2) - c
		var vb: Vector2 = (pts[his[1]] as Vector2) - c
		var a0: float = atan2(va.y, va.x)
		var a1: float = a0 + wrapf(atan2(vb.y, vb.x) - a0, -PI, PI)
		draw_arc(c, 46.0, minf(a0, a1), maxf(a0, a1), 32, Color(1.0, 0.85, 0.35, 0.9), 3.0, true)
		var cosv: float = va.normalized().dot(vb.normalized())
		_text(c + Vector2(cos((a0 + a1) * 0.5), sin((a0 + a1) * 0.5)) * 76.0, "cos = %.2f" % cosv, 17, Color(1.0, 0.85, 0.35), HORIZONTAL_ALIGNMENT_CENTER, 140.0)


# ── attention: words in a row; arcs show who looks at whom (hover a word) ──
func _draw_attention(sz: Vector2) -> void:
	var n: int = items.size()
	var fs: int = 20
	var widths: Array = []
	var total: float = 0.0
	for i in n:
		var w: float = font.get_string_size(_lab(i), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 28.0
		widths.append(w)
		total += w + 14.0
	var x: float = (sz.x - total + 14.0) * 0.5
	var y: float = sz.y * 0.72
	var cs: Array = []
	for i in n:
		cs.append(Vector2(x + float(widths[i]) * 0.5, y))
		x += float(widths[i]) + 14.0
	var focus: int = hover if hover >= 0 else (pinned if pinned >= 0 else (int(hi[0]) if not hi.is_empty() else -1))
	var links: Array = scene.get("links", [])
	if links.is_empty() and focus >= 0:
		# default pattern: a word looks at itself and earlier words, nearer ones more
		var tot: float = 0.0
		var tmp: Array = []
		for j in focus + 1:
			var wv: float = exp(-0.6 * float(focus - j))
			tmp.append([focus, j, wv])
			tot += wv
		for l in tmp:
			links.append([l[0], l[1], float(l[2]) / tot])
	for l in links:
		var li: Array = l
		var i0: int = int(li[0])
		var j0: int = int(li[1])
		var wv2: float = float(li[2])
		if i0 >= n or j0 >= n:
			continue
		var a: float = minf(_alpha(i0), _alpha(j0))
		if a <= 0.0:
			continue
		var on: bool = focus < 0 or i0 == focus
		if not on:
			continue
		var p0: Vector2 = cs[i0]
		var p1: Vector2 = cs[j0]
		var hgt: float = minf(40.0 + absf(p1.x - p0.x) * 0.45, y - 140.0)
		var col: Color = _col(j0)
		var pts: PackedVector2Array = PackedVector2Array()
		var grow: float = clampf((t - beat_t) / 0.6, 0.0, 1.0)
		for k in 25:
			var f: float = float(k) / 24.0 * grow
			var q: Vector2 = p0.lerp(p1, f) + Vector2(0, -sin(f * PI) * hgt - 26.0)
			pts.append(q)
		if i0 == j0:
			draw_arc(p0 + Vector2(0, -40), 14.0, 0, TAU, 20, Color(col.r, col.g, col.b, 0.3 + 0.7 * wv2), 1.0 + wv2 * 10.0, true)
		elif pts.size() > 1:
			draw_polyline(pts, Color(col.r, col.g, col.b, (0.25 + 0.75 * wv2) * a), 1.0 + wv2 * 12.0, true)
		if wv2 >= 0.08 and focus >= 0:
			# percentage at the arc's peak; labels that would collide are moved or skipped
			var top: Vector2 = p0.lerp(p1, 0.5) + Vector2(0, -hgt - 26.0)
			if i0 == j0:
				top = p0 + Vector2(0, -58)
			var pct: String = "%.0f%%" % (wv2 * 100.0)
			_draw_placed(_place_label(top + Vector2(0, 10), pct, 15, sz), pct, 15, Color(1.0, 0.9, 0.6, a))
	for i in n:
		var w: float = widths[i]
		_hit(i, _box(Rect2((cs[i] as Vector2) - Vector2(w, 46) * 0.5, Vector2(w, 46)), _col(i), _alpha(i), _lab(i), i == focus or _is_hi(i), fs, 0.45))
	if focus < 0 and shown > 0:
		_text(Vector2(sz.x * 0.5, sz.y - 22.0), "hover a word to see where it looks", 15, Color(0.7, 0.8, 0.95))


# ── compare: two columns (A vs B) ──
func _draw_compare(sz: Vector2) -> void:
	var colw: float = sz.x * 0.4
	var xs: Array = [sz.x * 0.27, sz.x * 0.73]
	var titles: Array = [String(scene.get("left", "")), String(scene.get("right", ""))]
	var tcols: Array = [PAL[0], PAL[2]]
	for s in 2:
		if titles[s] != "":
			_text(Vector2(xs[s], 74.0), titles[s], 22, (tcols[s] as Color).lightened(0.2), HORIZONTAL_ALIGNMENT_CENTER, colw)
	var counts: Array = [0, 0]
	for i in items.size():
		var side: int = int((items[i] as Dictionary).get("side", i % 2))
		counts[side] = int(counts[side]) + 1
	var maxc: int = maxi(int(counts[0]), int(counts[1]))
	var h: float = minf(64.0, (sz.y - 130.0) / float(maxi(maxc, 1)) - 10.0)
	var idx: Array = [0, 0]
	for i in items.size():
		var side2: int = int((items[i] as Dictionary).get("side", i % 2))
		var y: float = 104.0 + float(idx[side2]) * (h + 10.0)
		idx[side2] = int(idx[side2]) + 1
		var a: float = _alpha(i)
		var r: Rect2 = Rect2(float(xs[side2]) - colw * 0.5 + (1.0 - a) * (-40.0 if side2 == 0 else 40.0), y, colw, h)
		var c: Color = _col(i) if (items[i] as Dictionary).has("c") else tcols[side2]
		_hit(i, _box(r, c, a, _lab(i), _is_hi(i), 16))
	draw_line(Vector2(sz.x * 0.5, 96.0), Vector2(sz.x * 0.5, sz.y - 20.0), Color(0.4, 0.6, 1.0, 0.25), 2.0)
	draw_circle(Vector2(sz.x * 0.5, 74.0), 22.0, Color(0.12, 0.18, 0.32))
	_text(Vector2(sz.x * 0.5, 74.0), "vs", 17, Color(1.0, 0.85, 0.45), HORIZONTAL_ALIGNMENT_CENTER, 40.0)


# ── curve: an animated function plot with a draggable probe and labelled markers ──
func _f(fname: String, x: float) -> float:
	match fname:
		"decay": return 0.08 + 0.85 * exp(-4.0 * x)
		"power": return 0.1 + 0.85 * pow(1.0 + 9.0 * x, -0.75)
		"log": return log(1.0 + 9.0 * x) / log(10.0)
		"sigmoid": return 1.0 / (1.0 + exp(-12.0 * (x - 0.5)))
		"sin": return 0.5 + 0.4 * sin(TAU * 2.0 * x)
		"exp": return (exp(4.0 * x) - 1.0) / (exp(4.0) - 1.0)
		"ushape": return 0.08 + 3.4 * (x - 0.5) * (x - 0.5)
		"bell": return 0.05 + 0.9 * exp(-pow(x - 0.5, 2.0) / 0.025)
		"quad": return x * x
		"step": return 0.15 if x < 0.5 else 0.85
	return x


func _draw_curve(sz: Vector2) -> void:
	var r: Rect2 = Rect2(90, 90, sz.x - 150.0, sz.y - 148.0)
	plot_rect = r
	draw_line(r.position + Vector2(0, r.size.y), r.end, Color(0.5, 0.65, 1.0, 0.6), 2.0)
	draw_line(r.position, r.position + Vector2(0, r.size.y), Color(0.5, 0.65, 1.0, 0.6), 2.0)
	_text(Vector2(r.get_center().x, r.end.y + 28.0), String(scene.get("xl", "")), 15, Color(0.7, 0.82, 1.0), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	draw_set_transform(Vector2(28, r.get_center().y), -PI * 0.5)
	draw_string(font, Vector2(-r.size.y * 0.5, 6), String(scene.get("yl", "")), HORIZONTAL_ALIGNMENT_CENTER, r.size.y, 15, Color(0.7, 0.82, 1.0))
	draw_set_transform(Vector2.ZERO)
	var grow: float = clampf((t - scene_t) / 1.4, 0.0, 1.0)
	var curves: Array = [[String(scene.get("f", "linear")), PAL[0], String(scene.get("fl", ""))]]
	if scene.has("f2"):
		curves.append([String(scene["f2"]), PAL[2], String(scene.get("fl2", ""))])
	for ci in curves.size():
		var cv: Array = curves[ci]
		if ci == 1 and beat_i == 0 and beats.size() > 1:
			continue          # the second curve is revealed on a later beat
		var pts: PackedVector2Array = PackedVector2Array()
		var steps: int = 80
		for k in steps + 1:
			var x: float = float(k) / float(steps) * grow
			pts.append(Vector2(r.position.x + x * r.size.x, r.end.y - clampf(_f(String(cv[0]), x), 0.0, 1.0) * r.size.y))
		draw_polyline(pts, cv[1], 4.0, true)
		if String(cv[2]) != "" and grow >= 1.0:
			# legend in the plot's top-right corner (never runs off the edge or onto the curve's end)
			var lg: String = String(cv[2])
			var lgw: float = font.get_string_size(lg, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
			# legend sits just ABOVE the plot area, right-aligned, so curves never run through it
			var lp: Vector2 = Vector2(r.end.x - lgw - 30.0 - float(ci) * 0.0, r.position.y - 26.0 - float(1 - ci) * 0.0)
			if curves.size() > 1:
				var other: String = String((curves[1 - ci] as Array)[2])
				var ow: float = font.get_string_size(other, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
				if ci == 0:
					lp.x = r.end.x - lgw - 30.0 - ow - 50.0   # two legends side by side
			var bgw: Rect2 = Rect2(lp - Vector2(6, 4), Vector2(lgw + 38.0, 24.0))
			draw_rect(bgw, Color(0.02, 0.035, 0.075, 0.9))
			draw_line(lp + Vector2(0, 8), lp + Vector2(20, 8), cv[1], 4.0)
			draw_string(font, lp + Vector2(26, 14), lg, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, cv[1])
			_placed.append(Rect2(lp - Vector2(4, 4), Vector2(lgw + 34.0, 24.0)))
	for i in items.size():
		var a: float = _alpha(i)
		if a <= 0.0:
			continue
		var x2: float = float((items[i] as Dictionary).get("x", 0.5))
		var p: Vector2 = Vector2(r.position.x + x2 * r.size.x, r.end.y - clampf(_f(String(scene.get("f", "linear")), x2), 0.0, 1.0) * r.size.y)
		if _is_hi(i):
			draw_circle(p, 16.0 + 3.0 * _glow(), Color(_col(i).r, _col(i).g, _col(i).b, 0.3))
		draw_circle(p, 9.0 * _pop(a), _col(i))
		var above: bool = p.y > r.position.y + 50.0
		_draw_placed(_place_label(p, _lab(i), 16, sz, above), _lab(i), 16, Color(1, 1, 1, a))
		_hit(i, Rect2(p - Vector2(20, 20), Vector2(40, 40)))
	if grow >= 1.0 and bool(scene.get("probe", true)):
		var px: float = r.position.x + drag_x * r.size.x
		var py: float = r.end.y - clampf(_f(String(scene.get("f", "linear")), drag_x), 0.0, 1.0) * r.size.y
		draw_dashed_line(Vector2(px, r.end.y), Vector2(px, py), Color(1.0, 0.85, 0.4, 0.6), 2.0, 6.0)
		draw_circle(Vector2(px, py), 9.0 + 2.0 * _glow(), Color(1.0, 0.85, 0.35))
		if dragging != "probe":
			_draw_placed(_place_label(Vector2(px, py), "drag me", 13, sz, false), "drag me", 13, Color(1.0, 0.85, 0.45, 0.8))


# ── grid: a matrix filling row by row (attention mask, embedding table, cache…) ──
func _cell(pattern: String, i: int, j: int) -> float:
	match pattern:
		"causal": return 1.0 if j <= i else 0.0
		"diag": return 1.0 if i == j else 0.08
		"band": return 1.0 if absi(i - j) <= 1 else 0.06
		"window": return 1.0 if j <= i and i - j <= 2 else 0.0
		"random": return fposmod(sin(float(i * 37 + j * 91)) * 43758.5, 1.0)
		"sparse": return 1.0 if fposmod(sin(float(i * 13 + j * 7)) * 9631.7, 1.0) > 0.72 else 0.05
		"causal_soft":
			if j > i:
				return 0.0
			return exp(-0.5 * float(i - j))
	return 0.75


func _draw_grid(sz: Vector2) -> void:
	var rows: int = int(scene.get("rows", maxi(items.size(), 4)))
	var cols: int = int(scene.get("cols", rows))
	var pattern: String = String(scene.get("pattern", "full"))
	var clabels: Array = scene.get("col_labels", [])
	# label column as wide as the longest row label (up to 35% of the stage)
	var lab_w: float = 20.0
	for i in items.size():
		lab_w = maxf(lab_w, font.get_string_size(_lab(i), HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 10.0)
	lab_w = minf(lab_w, sz.x * 0.35)
	# column headers: leave room above the grid; long headers are drawn slanted
	var longest_h: float = 0.0
	for j in mini(cols, clabels.size()):
		longest_h = maxf(longest_h, font.get_string_size(String(clabels[j]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x)
	var y0: float = 92.0
	var cs: float = minf((sz.x - lab_w - 80.0) / float(cols), (sz.y - y0 - 16.0) / float(rows))
	cs = minf(cs, 58.0)
	var slant: bool = longest_h > cs - 4.0
	if slant:
		y0 = minf(70.0 + longest_h * 0.6, 150.0)
		cs = minf(cs, (sz.y - y0 - 16.0) / float(rows))
	var gw: float = cs * float(cols)
	var x0: float = (sz.x - gw + lab_w) * 0.5
	var vis_rows: int = rows if items.is_empty() else shown
	if not items.is_empty() and shown >= items.size():
		vis_rows = rows                 # extra rows without a label appear with the last item
	for j in mini(cols, clabels.size()):
		var hx: float = x0 + float(j) * cs
		if slant:
			draw_set_transform(Vector2(hx + cs * 0.5, y0 - 6.0), -0.6)
			draw_string(font, Vector2.ZERO, String(clabels[j]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.75, 0.85, 1.0))
			draw_set_transform(Vector2.ZERO)
		else:
			draw_string(font, Vector2(hx, y0 - 10.0), String(clabels[j]), HORIZONTAL_ALIGNMENT_CENTER, cs, 13, Color(0.75, 0.85, 1.0))
	for i in rows:
		var a: float = _alpha(i) if i < items.size() else clampf((t - scene_t) / 0.5 - float(i) * 0.15, 0.0, 1.0)
		if i >= vis_rows:
			a = 0.0
		var y: float = y0 + float(i) * cs
		if i < items.size():
			var rfs: int = 15
			while rfs > 10 and font.get_string_size(_lab(i), HORIZONTAL_ALIGNMENT_LEFT, -1, rfs).x > lab_w - 6.0:
				rfs -= 1
			draw_string(font, Vector2(x0 - lab_w - 8.0, y + cs * 0.5 + 6.0), _lab(i), HORIZONTAL_ALIGNMENT_RIGHT, lab_w, rfs, Color(0.92, 0.95, 1.0, maxf(a, 0.25)))
		var rc: Color = _col(i) if i < items.size() else PAL[0]
		for j in cols:
			var v: float = _cell(pattern, i, j)
			var fa: float = clampf(a * 1.6 - float(j) / float(cols) * 0.6, 0.0, 1.0)
			var cr: Rect2 = Rect2(x0 + float(j) * cs + 2.0, y + 2.0, cs - 4.0, cs - 4.0)
			draw_rect(cr, Color(0.12, 0.16, 0.28, 0.6))
			if fa > 0.0 and v > 0.0:
				draw_rect(cr, Color(rc.r, rc.g, rc.b, v * fa * 0.95))
		if i < items.size():
			var rr: Rect2 = Rect2(x0 - lab_w - 8.0, y, gw + lab_w + 8.0, cs)
			if _is_hi(i) and a > 0.0:
				draw_rect(rr.grow(2.0), Color(1.0, 0.85, 0.35, 0.25 + 0.25 * _glow()), false, 3.0)
			_hit(i, rr)


# ── tree: a hierarchy growing from the root ──
func _draw_tree(sz: Vector2) -> void:
	var n: int = items.size()
	var depth: Array = []
	var kids: Dictionary = {}
	for i in n:
		var p: int = int((items[i] as Dictionary).get("p", -1 if i == 0 else 0))
		depth.append(0 if p < 0 else int(depth[p]) + 1 if p < i else 1)
		if p >= 0:
			if not kids.has(p):
				kids[p] = []
			(kids[p] as Array).append(i)
	var maxd: int = 0
	for d in depth:
		maxd = maxi(maxd, int(d))
	# leaf order → x positions
	var xs: Dictionary = {}
	var leaf: Array = [0]
	var order: Callable = func(self_ref: Callable, i: int) -> float:
		if not kids.has(i):
			xs[i] = float(leaf[0])
			leaf[0] = int(leaf[0]) + 1
			return xs[i]
		var s: float = 0.0
		for k in kids[i]:
			s += float(self_ref.call(self_ref, int(k)))
		xs[i] = s / float((kids[i] as Array).size())
		return xs[i]
	for i in n:
		if int((items[i] as Dictionary).get("p", -1 if i == 0 else 0)) < 0:
			order.call(order, i)
	var leaves: int = maxi(int(leaf[0]), 1)
	var bw: float = minf(190.0, (sz.x - 30.0) / float(leaves) - 12.0)
	var bh: float = 56.0
	var pos: Array = []
	# root row starts below the callout pill; rows spread over the remaining height
	var y_top: float = 64.0 + bh * 0.5 + 6.0
	var y_step: float = minf(118.0, (sz.y - 12.0 - bh * 0.5 - y_top) / float(maxi(maxd, 1)))
	for i in n:
		var lx: float = float(xs.get(i, 0.0))
		var x: float = (sz.x - float(leaves) * (bw + 12.0)) * 0.5 + (lx + 0.5) * (bw + 12.0)
		var y: float = y_top + float(depth[i]) * y_step
		pos.append(Vector2(x, y))
	# inner (non-leaf) nodes can be wider than one leaf slot
	var inner_w: float = minf(260.0, sz.x * 0.3)
	for i in n:
		var p2: int = int((items[i] as Dictionary).get("p", -1 if i == 0 else 0))
		if p2 >= 0 and p2 < n:
			var a: float = minf(_alpha(i), _alpha(p2))
			if a > 0.0:
				var aa: Vector2 = (pos[p2] as Vector2) + Vector2(0, bh * 0.5)
				var bb: Vector2 = (pos[i] as Vector2) - Vector2(0, bh * 0.5)
				draw_line(aa, aa.lerp(bb, a), Color(0.55, 0.72, 1.0, 0.6 * a), 2.5, true)
	for i in n:
		var w: float = bw
		if kids.has(i):
			# a parent may use the span of its children (no overlap with neighbours on its row)
			var span: float = float((kids[i] as Array).size()) * (bw + 12.0) - 12.0
			w = clampf(span, bw, inner_w)
		_hit(i, _box(Rect2((pos[i] as Vector2) - Vector2(w, bh) * 0.5, Vector2(w, bh)), _col(i), _alpha(i), _lab(i), _is_hi(i), 15))


# ── timeline: events along an axis, a dot travelling through time ──
func _draw_timeline(sz: Vector2) -> void:
	var n: int = items.size()
	var y: float = sz.y * 0.56
	var x0: float = 60.0
	var x1: float = sz.x - 60.0
	draw_line(Vector2(x0, y), Vector2(x1, y), Color(0.45, 0.65, 1.0, 0.6), 3.0, true)
	var bw: float = minf(170.0, (x1 - x0) / float(maxi(n, 1)) * 1.6)
	for i in n:
		var a: float = _alpha(i)
		var x: float = lerpf(x0 + 40.0, x1 - 40.0, float(i) / float(maxi(n - 1, 1)))
		var up: bool = i % 2 == 0
		if a > 0.0:
			draw_circle(Vector2(x, y), 8.0 * _pop(a), _col(i))
			if (items[i] as Dictionary).has("v"):
				_text(Vector2(x, y + (22.0 if up else -22.0)), _fmt(_val(i)), 15, Color(1.0, 0.85, 0.45, a), HORIZONTAL_ALIGNMENT_CENTER, 90.0)
			var by: float = y + (-78.0 if up else 78.0)
			draw_line(Vector2(x, y), Vector2(x, by + (24.0 if up else -24.0)), Color(_col(i).r, _col(i).g, _col(i).b, 0.5 * a), 2.0)
			_hit(i, _box(Rect2(Vector2(x, by) - Vector2(bw, 48) * 0.5, Vector2(bw, 48)), _col(i), a, _lab(i), _is_hi(i), 15))
	if shown > 0:
		var f: float = fmod(t * 0.15, 1.0)
		var last_x: float = lerpf(x0 + 40.0, x1 - 40.0, float(shown - 1) / float(maxi(n - 1, 1)))
		draw_circle(Vector2(lerpf(x0, last_x, f), y), 5.0, Color(1, 1, 1, 0.8))


# ── network: neurons in layers, signals pulsing through (click to fire) ──
func _draw_network(sz: Vector2) -> void:
	var layers: Array = scene.get("layers", [3, 5, 5, 2])
	var nl: int = layers.size()
	var cols: Array = []
	for li in nl:
		var cnt: int = int(layers[li])
		var x: float = lerpf(110.0, sz.x - 110.0, float(li) / float(maxi(nl - 1, 1)))
		var ps: Array = []
		var sp: float = minf(56.0, (sz.y - 130.0) / float(maxi(cnt, 1)))
		for k in cnt:
			ps.append(Vector2(x, sz.y * 0.5 + (float(k) - float(cnt - 1) * 0.5) * sp))
		cols.append(ps)
	var vis: int = nl if items.is_empty() else clampi(shown, 0, nl)
	for li in vis - 1:
		for a in cols[li]:
			for b in cols[li + 1]:
				draw_line(a, b, Color(0.4, 0.6, 1.0, 0.16), 1.0, true)
	for li in vis - 1:
		for k in (cols[li] as Array).size():
			var a2: Vector2 = cols[li][k]
			var tgt: int = (k * 7 + int(t * 0.7) * 3) % (cols[li + 1] as Array).size()
			var b2: Vector2 = cols[li + 1][tgt]
			var f: float = fmod(t * 0.8 - float(li) * 0.33 + float(k) * 0.13, 1.0)
			draw_circle(a2.lerp(b2, f), 3.5, Color(1.0, 0.85, 0.4, sin(f * PI) * 0.9))
	for p in pulses:
		var f2: float = (t - float(p["t0"])) / 1.6
		if f2 < 1.0 and vis > 1:
			var seg: float = f2 * float(vis - 1)
			var li2: int = mini(int(seg), vis - 2)
			for a3 in cols[li2]:
				for b3 in cols[li2 + 1]:
					draw_circle((a3 as Vector2).lerp(b3, seg - float(li2)), 3.0, Color(1, 1, 1, 0.8))
	for li in vis:
		var col: Color = _col(li) if li < items.size() else PAL[li % PAL.size()]
		var a4: float = _alpha(li) if li < items.size() else 1.0
		var glow: bool = hi.has(li)
		for p2 in cols[li]:
			if glow:
				draw_circle(p2, 17.0 + 3.0 * _glow(), Color(col.r, col.g, col.b, 0.25))
			draw_circle(p2, 11.0 * _pop(a4), Color(col.r, col.g, col.b, a4))
		if li < items.size():
			var lx: float = (cols[li][0] as Vector2).x
			_text(Vector2(lx, sz.y - 26.0), _lab(li), 15, Color(1, 1, 1, a4), HORIZONTAL_ALIGNMENT_CENTER, 200.0)
			_hit(li, Rect2(lx - 40.0, 40.0, 80.0, sz.y - 60.0))


# ── scale: sizes compared as growing circles (log-scaled when they differ hugely) ──
func _draw_scale(sz: Vector2) -> void:
	var n: int = items.size()
	var mx: float = 1e-9
	var mn: float = 1e30
	for i in n:
		mx = maxf(mx, absf(_val(i, 1.0)))
		mn = minf(mn, maxf(absf(_val(i, 1.0)), 1e-9))
	var use_log: bool = bool(scene.get("log", mx / maxf(mn, 1e-9) > 200.0))
	var maxr: float = minf(sz.y * 0.32, (sz.x - 60.0) / float(maxi(n, 1)) * 0.45)
	var base_y: float = sz.y * 0.78
	var unit: String = String(scene.get("unit", ""))
	for i in n:
		var a: float = _alpha(i)
		if a <= 0.0:
			continue
		var v: float = maxf(absf(_val(i, 1.0)), 1e-9)
		var f: float = (log(v) - log(mn) + 1.0) / (log(mx) - log(mn) + 1.0) if use_log else sqrt(v / mx)
		var rad: float = maxf(maxr * f * _pop(clampf((t - appear[i]) / 0.8, 0.0, 1.0)), 6.0)
		var x: float = lerpf(sz.x / float(n) * 0.5, sz.x - sz.x / float(n) * 0.5, float(i) / float(maxi(n - 1, 1))) if n > 1 else sz.x * 0.5
		var c: Vector2 = Vector2(x, base_y - rad)
		var col: Color = _col(i)
		if _is_hi(i):
			draw_circle(c, rad + 8.0 + 3.0 * _glow(), Color(col.r, col.g, col.b, 0.2))
		draw_circle(c, rad, Color(col.r * 0.35, col.g * 0.35, col.b * 0.35 + 0.05, 0.95 * a))
		draw_arc(c, rad, 0, TAU, 48, Color(col.r, col.g, col.b, a), 3.0, true)
		var vtxt: String = _fmt(_val(i, 1.0)) + unit
		var fits: bool = font.get_string_size(vtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x < rad * 1.8
		if fits:
			_text(c, vtxt, 16, Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_CENTER, rad * 2.0)
		else:
			_text(c - Vector2(0, rad + 16.0), vtxt, 15, Color(1.0, 0.9, 0.6, a), HORIZONTAL_ALIGNMENT_CENTER, 200.0)
		_text(Vector2(x, base_y + 22.0), _lab(i), 15, Color(0.88, 0.93, 1.0, a), HORIZONTAL_ALIGNMENT_CENTER, sz.x / float(maxi(n, 1)))
		_hit(i, Rect2(c - Vector2(rad, rad), Vector2(rad, rad) * 2.0))
	if use_log and shown > 1:
		_text(Vector2(sz.x - 90.0, sz.y - 16.0), "(log scale)", 12, Color(0.6, 0.72, 0.95), HORIZONTAL_ALIGNMENT_CENTER, 160.0)


# ── chat: messages appear with a typing effect ──
func _chat_fs(full: String, maxw: float, base: int) -> int:
	## shrink until the longest unbreakable word (code, ids, urls) fits inside the bubble
	var fs: int = base
	var longest: String = ""
	for word in full.split(" ", false):
		if word.length() > longest.length():
			longest = word
	while fs > 11 and font.get_string_size(longest, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > maxw - 30.0:
		fs -= 1
	return fs


func _draw_chat(sz: Vector2) -> void:
	var maxw: float = sz.x * 0.66
	var whos: Dictionary = {"sys": [Color("#9aa6c0"), "system"], "user": [PAL[0], "user"], "ai": [PAL[1], "assistant"],
		"tool": [PAL[2], "tool"], "doc": [PAL[3], "document"]}
	# measure every visible bubble first, then shrink text / spacing so the conversation fits
	var base_fs: int = 16
	var gap: float = 12.0
	var y0: float = 62.0
	for _attempt in 6:
		var total: float = 0.0
		for i in items.size():
			if _alpha(i) <= 0.0:
				continue
			var full0: String = _lab(i)
			var fs0: int = _chat_fs(full0, maxw, base_fs)
			var tw0: float = minf(font.get_string_size(full0, HORIZONTAL_ALIGNMENT_LEFT, -1, fs0).x + 30.0, maxw)
			total += font.get_multiline_string_size(full0, HORIZONTAL_ALIGNMENT_LEFT, tw0 - 24.0, fs0).y + 30.0 + gap
		if total <= sz.y - y0 - 6.0 or base_fs <= 12:
			break
		base_fs -= 1
		gap = maxf(gap - 2.0, 4.0)
	var y: float = y0
	for i in items.size():
		var a: float = _alpha(i)
		if a <= 0.0:
			continue
		var it: Dictionary = items[i]
		var who: String = String(it.get("who", "ai" if i % 2 == 1 else "user"))
		var wd: Array = whos.get(who, whos["ai"])
		var col: Color = wd[0]
		var full: String = _lab(i)
		var chars: int = mini(full.length(), int((t - appear[i]) * 55.0))
		var txt: String = full.substr(0, chars)
		var fs: int = _chat_fs(full, maxw, base_fs)
		var tw: float = minf(font.get_string_size(full, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 30.0, maxw)
		var th: float = font.get_multiline_string_size(full, HORIZONTAL_ALIGNMENT_LEFT, tw - 24.0, fs).y + 30.0
		var x: float = 40.0
		if who == "user":
			x = sz.x - 40.0 - tw
		elif who == "sys":
			x = (sz.x - tw) * 0.5
		var r: Rect2 = Rect2(x, y, tw, th)
		if _is_hi(i):
			_sb.bg_color = Color(col.r, col.g, col.b, 0.15 + 0.12 * _glow())
			_sb.set_border_width_all(0)
			_sb.set_corner_radius_all(16)
			draw_style_box(_sb, r.grow(5.0))
		_sb.bg_color = Color(col.r * 0.22, col.g * 0.22, col.b * 0.22 + 0.04, 0.95 * a)
		_sb.border_color = Color(col.r, col.g, col.b, a)
		_sb.set_border_width_all(2)
		_sb.set_corner_radius_all(14)
		draw_style_box(_sb, r)
		draw_string(font, r.position + Vector2(12, 16), String(wd[1]), HORIZONTAL_ALIGNMENT_LEFT, 120.0, 12, Color(col.r, col.g, col.b, a))
		draw_multiline_string(font, r.position + Vector2(12, 22 + font.get_ascent(fs)), txt, HORIZONTAL_ALIGNMENT_LEFT, tw - 24.0, fs, -1, Color(0.95, 0.97, 1.0, a))
		_hit(i, r)
		y += th + gap


# ── funnel: many candidates go in, the highlighted few come out ──
func _draw_funnel(sz: Vector2) -> void:
	var n: int = items.size()
	var item_rows: int = ceili(float(n) / 5.0)
	var top_y: float = 104.0           # first row of candidates sits below the callout pill
	var rows_bottom: float = top_y - 40.0 + float(item_rows) * 52.0
	var fw_top: float = sz.x * 0.7
	var neck_y: float = clampf(rows_bottom + 96.0, sz.y * 0.6, sz.y - 70.0)
	var cx: float = sz.x * 0.5
	var mouth_y: float = maxf(neck_y - 110.0, rows_bottom + 4.0)
	var poly: PackedVector2Array = PackedVector2Array([Vector2(cx - fw_top * 0.5, mouth_y), Vector2(cx + fw_top * 0.5, mouth_y),
		Vector2(cx + 50.0, neck_y), Vector2(cx - 50.0, neck_y)])
	draw_colored_polygon(poly, Color(0.25, 0.4, 0.8, 0.12))
	draw_polyline(PackedVector2Array([poly[0], poly[3], Vector2(cx - 50.0, neck_y + 20.0)]), Color(0.45, 0.65, 1.0, 0.6), 3.0, true)
	draw_polyline(PackedVector2Array([poly[1], poly[2], Vector2(cx + 50.0, neck_y + 20.0)]), Color(0.45, 0.65, 1.0, 0.6), 3.0, true)
	if scene.has("label"):
		_text_in(Rect2(cx - 150.0, (mouth_y + neck_y) * 0.5 - 16.0, 300.0, 40.0), String(scene["label"]), 17, Color(0.8, 0.88, 1.0, 0.9))
	var per: int = mini(n, 5)
	var bw: float = minf(170.0, (sz.x - 40.0) / float(maxi(per, 1)) - 12.0)
	var kept: Array = hi.duplicate()
	var kx: int = 0
	var drop: float = clampf((t - beat_t - 0.3) / 0.9, 0.0, 1.0)
	for i in n:
		var a: float = _alpha(i)
		var r: int = i / per
		var c: int = i % per
		var rowc: int = mini(per, n - r * per)
		var x: float = cx + (float(c) - float(rowc - 1) * 0.5) * (bw + 12.0)
		var y: float = top_y - 40.0 + float(r) * 54.0
		var p: Vector2 = Vector2(x, y)
		var col: Color = _col(i)
		if kept.has(i) and not kept.is_empty():
			var out: Vector2 = Vector2(cx + (float(kx) - float(kept.size() - 1) * 0.5) * (bw + 12.0), sz.y - 46.0)
			kx += 1
			p = p.lerp(Vector2(cx, neck_y), clampf(drop * 2.0, 0.0, 1.0)).lerp(out, clampf(drop * 2.0 - 1.0, 0.0, 1.0))
		elif not kept.is_empty():
			col = Color(0.4, 0.45, 0.55)
			a *= 1.0 - 0.6 * drop
		_hit(i, _box(Rect2(p - Vector2(bw, 42) * 0.5, Vector2(bw, 42)), col, a, _lab(i), kept.has(i), 15))


# ───────────────────────── input ─────────────────────────
func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		mouse = (ev as InputEventMouseMotion).position
		if dragging == "temp":
			temp = clampf(0.1 + (mouse.x - temp_rect.position.x - 10.0) / maxf(temp_rect.size.x - 20.0, 1.0) * 2.4, 0.1, 2.5)
			return
		if dragging == "probe":
			drag_x = clampf((mouse.x - plot_rect.position.x) / maxf(plot_rect.size.x, 1.0), 0.0, 1.0)
			return
		hover = -1
		for i in hits.size():
			if i < shown and (hits[i] as Rect2).has_point(mouse):
				hover = i
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if hover >= 0 else Control.CURSOR_ARROW
	elif ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb: InputEventMouseButton = ev
		mouse = mb.position
		if not mb.pressed:
			dragging = ""
			return
		if tpl == "bars" and temp_rect.size.x > 0.0 and temp_rect.grow(8.0).has_point(mouse):
			dragging = "temp"
			temp = clampf(0.1 + (mouse.x - temp_rect.position.x - 10.0) / maxf(temp_rect.size.x - 20.0, 1.0) * 2.4, 0.1, 2.5)
			return
		if tpl == "curve" and plot_rect.grow(10.0).has_point(mouse):
			dragging = "probe"
			drag_x = clampf((mouse.x - plot_rect.position.x) / maxf(plot_rect.size.x, 1.0), 0.0, 1.0)
		var picked: int = -1
		for i in hits.size():
			if i < shown and (hits[i] as Rect2).has_point(mouse):
				picked = i
		if tpl == "network" or tpl == "flow":
			pulses.append({"t0": t})
			if pulses.size() > 6:
				pulses.pop_front()
		if picked >= 0:
			pinned = -1 if pinned == picked else picked
			item_clicked.emit(picked, String((items[picked] as Dictionary).get("tip", _lab(picked))))


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		hover = -1
