extends LabBase
## HNSW lab: a tiny layered proximity graph, searched greedily from the top layer down.
## Shows why the number of distance comparisons stays small while recall depends on ef.

# layer 0: every node; layer 1: a few hubs. Positions are hand-placed in 0..1 space.
const NAMES: Array = ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l"]
const POS: Array = [Vector2(0.10, 0.20), Vector2(0.22, 0.55), Vector2(0.35, 0.18), Vector2(0.46, 0.62),
	Vector2(0.55, 0.30), Vector2(0.63, 0.78), Vector2(0.70, 0.22), Vector2(0.78, 0.66),
	Vector2(0.86, 0.34), Vector2(0.30, 0.86), Vector2(0.58, 0.95), Vector2(0.92, 0.80)]
const HUBS: Array = [0, 5, 8, 11]        # node indices present in layer 1
const L1_EDGES: Array = [[0, 5], [5, 8], [8, 11], [0, 8]]
const L0_EDGES: Array = [[0, 1], [1, 2], [0, 2], [1, 3], [3, 4], [2, 4], [3, 5], [4, 6], [4, 5],
	[5, 6], [5, 8], [5, 7], [6, 8], [7, 8], [8, 11], [8, 9], [5, 9], [9, 10], [7, 10], [7, 11], [10, 11]]

var query: Vector2 = Vector2(0.72, 0.55)
var ef: int = 2
var canvas: Control
var log_box: VBoxContainer
var steps: Array = []
var brute: Array = []


func title() -> String:
	return "HNSW Lab"


func intro() -> String:
	return "Vector search compares the query with stored vectors. Instead of comparing everything, HNSW builds a layered graph and walks down it greedily. Click anywhere to move the query and run the search."


func build_body(vb: VBoxContainer) -> void:
	canvas = Control.new()
	canvas.custom_minimum_size = Vector2(0, 320)
	canvas.draw.connect(_draw)
	canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.gui_input.connect(_on_input)
	vb.add_child(canvas)
	var h: HBoxContainer = hbox(vb)
	lbl(h, "Search width (ef):", 14)
	var s: HSlider = HSlider.new()
	s.min_value = 1
	s.max_value = 6
	s.step = 1
	s.value = 2
	s.custom_minimum_size = Vector2(220, 0)
	s.value_changed.connect(func(v: float) -> void:
		ef = int(v)
		_search()
		_refresh())
	h.add_child(s)
	btn(h, "New query", func() -> void:
		query = Vector2(randf_range(0.05, 0.95), randf_range(0.05, 0.95))
		_search()
		_refresh())
	log_box = VBoxContainer.new()
	log_box.add_theme_constant_override("separation", 3)
	vb.add_child(log_box)
	rich(vb, "What you should notice",
		"The search starts at a hub in the top layer and always moves to the neighbour that is closer to the query. When no neighbour is closer, it drops a layer and repeats. Each step costs one distance comparison, so the total is tiny compared with comparing all vectors.")
	rich(vb, "Why it matters at scale",
		"On this toy graph of %d vectors a brute-force scan is not slow - the win appears at millions of vectors, where comparing everything per query is hopeless. Approximate search accepts occasionally missing the true nearest neighbour in exchange for a search that costs a few dozen comparisons instead of millions." % NAMES.size())
	rich(vb, "The knob that trades quality for speed",
		"Keeping more candidates (a larger ef) means more comparisons but a higher chance of finding the true nearest neighbour. Practical indexes tune ef at search time and the number of links at build time, and report recall against brute force - exactly as this lab does.")
	_search()
	_refresh()


func _d(i: int) -> float:
	return query.distance_to(POS[i])


func _on_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
		var p: Vector2 = (ev as InputEventMouseButton).position
		query = Vector2(clampf(p.x / maxf(canvas.size.x, 1.0), 0.0, 1.0), clampf(p.y / maxf(canvas.size.y, 1.0), 0.0, 1.0))
		_search()
		_refresh()


func _neighbours(node: int, lyr: int) -> Array:
	var out: Array = []
	for e in (L1_EDGES if lyr == 1 else L0_EDGES):
		if int(e[0]) == node:
			out.append(int(e[1]))
		elif int(e[1]) == node:
			out.append(int(e[0]))
	return out


func _search() -> void:
	steps = []
	var comparisons: int = 0
	var cur: int = 0                      # entry point
	steps.append({"t": "start at entry point '%s' (layer 1)" % NAMES[cur], "n": cur, "l": 1})
	for lyr in [1, 0]:
		var improved: bool = true
		while improved:
			improved = false
			var best: int = cur
			var best_d: float = _d(cur)
			for n in _neighbours(cur, lyr):
				comparisons += 1
				if _d(n) < best_d:
					best_d = _d(n)
					best = n
			if best != cur:
				cur = best
				improved = true
				steps.append({"t": "layer %d: move to '%s' (distance %.3f)" % [lyr, NAMES[cur], _d(cur)], "n": cur, "l": lyr})
		if lyr == 1:
			steps.append({"t": "no closer neighbour in layer 1 - drop to layer 0", "n": cur, "l": 0})
	# keep ef candidates: the visited set closest to the query
	var visited: Dictionary = {}
	for s in steps:
		for n in _neighbours(int(s["n"]), int(s["l"])):
			visited[n] = true
	var cands: Array = visited.keys()
	cands.sort_custom(func(a: int, b: int) -> bool: return _d(a) < _d(b))
	var kept: Array = cands.slice(0, ef)
	brute = []
	for i in NAMES.size():
		brute.append(i)
	brute.sort_custom(func(a: int, b: int) -> bool: return _d(a) < _d(b))
	steps.append({"t": "done: %d distance comparisons (brute force would need %d).  Best found: '%s' at distance %.3f   ·   true nearest: '%s'" % [
		comparisons, NAMES.size(), NAMES[kept[0]], _d(kept[0]), NAMES[brute[0]]], "n": int(kept[0]), "l": 0})
	steps.append({"t": "ef = %d keeps the %d closest candidates seen: %s" % [ef, kept.size(), ", ".join(kept.map(func(i: int) -> String: return String(NAMES[i])))], "n": -1, "l": 0})


func _refresh() -> void:
	canvas.queue_redraw()
	for c in log_box.get_children():
		log_box.remove_child(c)
		c.queue_free()
	for s in steps:
		var col: Color = Color(1.0, 0.8, 0.3) if int(s["n"]) >= 0 else Color(0.8, 0.88, 1.0)
		lbl(log_box, "•  " + String(s["t"]), 14, col)


func _draw() -> void:
	var sz: Vector2 = canvas.size
	canvas.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.02, 0.03, 0.07, 0.95))
	var f: Font = ThemeDB.fallback_font
	# layer 1 (hubs) on a light band, layer 0 below
	canvas.draw_rect(Rect2(Vector2(0, 0), Vector2(sz.x, 26)), Color(0.1, 0.2, 0.4, 0.5))
	canvas.draw_string(f, Vector2(8, 18), "layer 1 - hubs only (coarse)", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.8, 0.9, 1.0))
	for e in L1_EDGES:
		canvas.draw_line(_p(int(e[0]), sz), _p(int(e[1]), sz), Color(0.5, 0.7, 1.0, 0.5), 2.0)
	for e in L0_EDGES:
		canvas.draw_line(_p(int(e[0]), sz), _p(int(e[1]), sz), Color(0.3, 0.45, 0.7, 0.6), 1.0)
	var path_ids: Array = []
	for s in steps:
		if int(s["n"]) >= 0:
			path_ids.append(int(s["n"]))
	for i in range(1, path_ids.size()):
		canvas.draw_line(_p(int(path_ids[i - 1]), sz), _p(int(path_ids[i]), sz), Color(1.0, 0.75, 0.2, 0.9), 3.0)
	for i in NAMES.size():
		var p: Vector2 = _p(i, sz)
		var col: Color = Color(1.0, 0.85, 0.3) if path_ids.has(i) else (Color(0.5, 0.95, 0.7) if HUBS.has(i) else Color(0.6, 0.7, 0.85))
		canvas.draw_circle(p, 11.0 if HUBS.has(i) else 8.0, col)
		canvas.draw_string(f, p + Vector2(13, 5), String(NAMES[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)
	var qp: Vector2 = Vector2(query.x * sz.x, query.y * sz.y)
	canvas.draw_circle(qp, 10.0, Color(1.0, 0.35, 0.45))
	canvas.draw_string(f, qp + Vector2(14, -10), "query", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.5, 0.55))


func _p(i: int, sz: Vector2) -> Vector2:
	var v: Vector2 = POS[i]
	return Vector2(v.x * sz.x, v.y * sz.y)