extends LabBase
## Embedding lab: a small hand-built 2-D embedding space. Shows cosine similarity,
## nearest neighbours, and the classic vector arithmetic (king - man + woman).

# hand-authored 2-D vectors so the picture is readable: axis 1 ≈ royal/abstract, axis 2 ≈ human/food
const VECTORS: Dictionary = {
	"king": Vector2(0.95, 0.55), "queen": Vector2(0.92, 0.92), "prince": Vector2(0.72, 0.50),
	"man": Vector2(0.25, 0.62), "woman": Vector2(0.22, 0.95), "boy": Vector2(0.18, 0.42),
	"girl": Vector2(0.15, 0.70), "dog": Vector2(-0.35, 0.55), "cat": Vector2(-0.42, 0.66),
	"pizza": Vector2(-0.72, -0.55), "bread": Vector2(-0.68, -0.30), "apple": Vector2(-0.55, -0.72),
	"car": Vector2(-0.80, 0.12), "train": Vector2(-0.60, 0.18), "plane": Vector2(-0.45, 0.05),
	"math": Vector2(0.80, -0.55), "physics": Vector2(0.68, -0.42), "biology": Vector2(0.45, -0.30),
}

var query: String = "king"
var top_k: int = 4
var plot: Control
var list_box: VBoxContainer
var math_lbl: Label


func title() -> String:
	return "Embedding Lab"


func intro() -> String:
	return "The model does not see words, it sees points in space. Words used in similar contexts end up close together, and directions carry meaning. Click a word to see its nearest neighbours."


func build_body(vb: VBoxContainer) -> void:
	plot = Control.new()
	plot.custom_minimum_size = Vector2(0, 300)
	plot.draw.connect(_draw_plot)
	plot.mouse_filter = Control.MOUSE_FILTER_STOP
	plot.gui_input.connect(_on_plot_input)
	vb.add_child(plot)
	list_box = VBoxContainer.new()
	list_box.add_theme_constant_override("separation", 3)
	vb.add_child(list_box)
	math_lbl = lbl(vb, "", 15, Color(0.55, 0.95, 0.8))
	btn(vb, "king − man + woman = ?", func() -> void: _do_math(), true)
	rich(vb, "What you should notice",
		"Similarity is the cosine of the angle between two vectors: 1 means the same direction, 0 means unrelated. Distance alone is not enough - direction is what matters, which is why long and short arrows can mean the same thing.")
	rich(vb, "Where this comes from",
		"Embeddings are learned: the model starts with random numbers and gradients push words that appear in similar contexts towards each other. Nothing here was typed in by hand in a real system - the axes only look human-friendly because we chose two dimensions to draw.")
	_refresh()


func _norm(v: Vector2) -> Vector2:
	return v.normalized() if v.length() > 0.0001 else v


func _cos(a: String, b: String) -> float:
	return _norm(VECTORS[a]).dot(_norm(VECTORS[b]))


func _refresh() -> void:
	plot.queue_redraw()
	for c in list_box.get_children():
		list_box.remove_child(c)
		c.queue_free()
	var neighbours: Array = []
	for w in VECTORS.keys():
		if String(w) != query:
			neighbours.append({"w": String(w), "s": _cos(query, String(w))})
	neighbours.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x["s"]) > float(y["s"]))
	lbl(list_box, "Words most similar in meaning to '" + query + "':", 15, Color(1.0, 0.85, 0.5))
	for i in mini(top_k, neighbours.size()):
		var n: Dictionary = neighbours[i]
		bar(list_box, String(n["w"]), (float(n["s"]) + 1.0) * 0.5, Color(0.4, 0.8, 0.6), "cosine %.2f" % float(n["s"]))
	bar(list_box, "myself", 1.0, Color(0.3, 0.5, 0.9), "cosine 1.00")


func _on_plot_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
		var p: Vector2 = (ev as InputEventMouseButton).position
		var best: String = query
		var bd: float = 1e9
		for w in VECTORS.keys():
			var d: float = p.distance_to(_to_screen(w))
			if d < bd:
				bd = d
				best = String(w)
		if bd < 90.0:
			query = best
			_refresh()


func _to_screen(w: String) -> Vector2:
	var v: Vector2 = VECTORS[w]
	var sz: Vector2 = plot.size
	return Vector2(sz.x * 0.5 + v.x * sz.x * 0.45, sz.y * 0.55 - v.y * sz.y * 0.45)


func _draw_plot() -> void:
	var sz: Vector2 = plot.size
	plot.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.02, 0.03, 0.07, 0.9))
	# grid
	for i in 9:
		var x: float = sz.x * float(i) / 8.0
		plot.draw_line(Vector2(x, 0), Vector2(x, sz.y), Color(0.2, 0.35, 0.6, 0.25), 1.0)
		var y: float = sz.y * float(i) / 8.0
		plot.draw_line(Vector2(0, y), Vector2(sz.x, y), Color(0.2, 0.35, 0.6, 0.25), 1.0)
	var origin: Vector2 = _to_screen("king") * 0.0 + Vector2(sz.x * 0.5, sz.y * 0.55)
	plot.draw_line(Vector2(0, origin.y), Vector2(sz.x, origin.y), Color(0.35, 0.6, 1.0, 0.5), 2.0)
	plot.draw_line(Vector2(origin.x, 0), Vector2(origin.x, sz.y), Color(0.35, 0.6, 1.0, 0.5), 2.0)
	var neighbours: Array = []
	for w in VECTORS.keys():
		if String(w) != query:
			neighbours.append({"w": String(w), "s": _cos(query, String(w))})
	neighbours.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x["s"]) > float(y["s"]))
	var near: Array = []
	for i in mini(top_k, neighbours.size()):
		near.append(String(neighbours[i]["w"]))
	for w in VECTORS.keys():
		var p: Vector2 = _to_screen(String(w))
		var is_q: bool = String(w) == query
		var is_n: bool = near.has(String(w))
		var col: Color = Color(1.0, 0.8, 0.25) if is_q else (Color(0.4, 0.95, 0.65) if is_n else Color(0.55, 0.62, 0.75))
		if is_q or is_n:
			plot.draw_line(origin, p, Color(col.r, col.g, col.b, 0.35), 2.0)
		plot.draw_circle(p, 14.0 if is_q else 8.0, col)
		var f: Font = ThemeDB.fallback_font
		plot.draw_string(f, p + Vector2(12, -12), String(w), HORIZONTAL_ALIGNMENT_LEFT, -1, 16 if is_q else 14, col)


func _do_math() -> void:
	var v: Vector2 = VECTORS["king"] - VECTORS["man"] + VECTORS["woman"]
	var best: String = ""
	var best_d: float = 1e9
	for w in VECTORS.keys():
		if ["king", "man", "woman"].has(String(w)):
			continue
		var d: float = _norm(VECTORS[w]).distance_to(_norm(v))
		if d < best_d:
			best_d = d
			best = String(w)
	math_lbl.text = "king − man + woman = (%.2f, %.2f)  ·  closest word: '%s'  (queen is the intended kind of answer: take the 'royal' direction away from 'man' and add it to 'woman')" % [v.x, v.y, best]