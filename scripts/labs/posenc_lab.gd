extends LabBase
## Position-encoding lab: the sinusoid table from the lecture, drawn as a heat map, plus
## the reason it works - the dot product of two positions depends on their distance.

const MAX_POS: int = 40
const MAX_DIM: int = 32
const BASE: float = 10000.0

var grid: Control
var sel_pos: int = 12
var curve: Control


func title() -> String:
	return "Position Encoding Lab"


func intro() -> String:
	return "Attention on its own has no sense of order: 'dog bites man' and 'man bites dog' look the same. Position must be added to the embedding. Click the map to pick a position and watch the similarity curve."


func _val(pos: int, dim: int) -> float:
	var i: int = int(float(dim) / 2.0)
	var denom: float = pow(BASE, float(2 * i) / float(MAX_DIM))
	var angle: float = float(pos) / denom
	return sin(angle) if dim % 2 == 0 else cos(angle)


func build_body(vb: VBoxContainer) -> void:
	grid = Control.new()
	grid.custom_minimum_size = Vector2(0, 220)
	grid.draw.connect(_draw_grid)
	grid.mouse_filter = Control.MOUSE_FILTER_STOP
	grid.gui_input.connect(_on_grid_input)
	vb.add_child(grid)
	curve = Control.new()
	curve.custom_minimum_size = Vector2(0, 170)
	curve.draw.connect(_draw_curve)
	vb.add_child(curve)
	lbl(vb, "The map is the table the model adds to every token embedding: one row per position, one column per embedding dimension. Even dimensions use a sine, odd dimensions a cosine, all at different wavelengths.", 14, Color(0.8, 0.88, 1.0))
	rich(vb, "What you should notice",
		"Nearby rows look alike, distant rows differ - so the pattern itself encodes distance. Because the fast dimensions repeat often and the slow ones rarely, every position gets a unique 'fingerprint' that a linear layer can read off.")
	rich(vb, "Modern practice",
		"Learned absolute tables work, but models that must run on long contexts prefer rotary position embeddings (RoPE), which rotate the query and key vectors by an angle proportional to their position. Rotation makes the attention score depend on the difference of the positions, which is exactly what we want.")


func _on_grid_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
		var p: Vector2 = (ev as InputEventMouseButton).position
		sel_pos = clampi(int(p.y / maxf(grid.size.y, 1.0) * float(MAX_POS)), 0, MAX_POS - 1)
		grid.queue_redraw()
		curve.queue_redraw()


func _draw_grid() -> void:
	var sz: Vector2 = grid.size
	grid.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.02, 0.03, 0.07, 0.95))
	var cw: float = sz.x / float(MAX_DIM)
	var ch: float = sz.y / float(MAX_POS)
	for d in MAX_DIM:
		for p in MAX_POS:
			var v: float = _val(p, d)
			var col: Color = Color(0.1 + 0.9 * (v * 0.5 + 0.5), 0.35 + 0.55 * (v * 0.5 + 0.5), 0.55 - 0.35 * v)
			grid.draw_rect(Rect2(Vector2(float(d) * cw, float(p) * ch), Vector2(cw + 1.0, ch + 1.0)), col)
	grid.draw_rect(Rect2(Vector2(0.0, float(sel_pos) * ch), Vector2(sz.x, ch)), Color(1, 1, 1, 0.9), false, 2.0)
	var f: Font = ThemeDB.fallback_font
	grid.draw_string(f, Vector2(6, float(sel_pos) * ch - 4), "position %d" % sel_pos, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
	grid.draw_string(f, Vector2(6, sz.y - 6), "← embedding dimension 1 … %d →" % MAX_DIM, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.85, 0.9, 1.0))


func _dot(a: int, b: int) -> float:
	var s: float = 0.0
	for d in MAX_DIM:
		s += _val(a, d) * _val(b, d)
	return s / float(MAX_DIM)


func _draw_curve() -> void:
	var sz: Vector2 = curve.size
	curve.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.02, 0.03, 0.07, 0.95))
	var f: Font = ThemeDB.fallback_font
	curve.draw_string(f, Vector2(6, 16), "Similarity between position %d and every other position - the curve is periodic, so distance is visible" % sel_pos, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.85, 0.9, 1.0))
	var last: Vector2 = Vector2.ZERO
	for p in MAX_POS:
		var v: float = _dot(sel_pos, p)
		var pt: Vector2 = Vector2(sz.x * float(p) / float(MAX_POS - 1), sz.y * 0.5 - v * sz.y * 0.35)
		if p > 0:
			curve.draw_line(last, pt, Color(0.4, 0.95, 0.7), 2.0)
		last = pt
	for p in range(0, MAX_POS, 5):
		var x: float = sz.x * float(p) / float(MAX_POS - 1)
		curve.draw_line(Vector2(x, sz.y - 22), Vector2(x, sz.y - 16), Color(0.5, 0.65, 0.9, 0.6), 1.0)
		curve.draw_string(f, Vector2(x - 8, sz.y - 4), str(p), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.8, 0.95))
	var zero_y: float = sz.y * 0.5
	curve.draw_line(Vector2(0, zero_y), Vector2(sz.x, zero_y), Color(0.35, 0.6, 1.0, 0.5), 1.0)