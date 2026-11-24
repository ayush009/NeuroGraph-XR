extends LabBase
## Bigram lab: predict the next character from the previous one, using a tiny corpus we
## actually count here. Shows why a model that only looks one step back is so weak.

const CORPUS: String = "the transformer reads the whole sentence at once because attention lets every position look at every other position. the model learns from text, the more text the better. the cat sat on the mat, the mat was warm, and the cat slept. attention is all you need, but data is what you feed it. the quick brown fox jumps over the lazy dog while the cat watches."

var counts: Dictionary = {}
var totals: Dictionary = {}
var current: String = "t"
var bars_box: VBoxContainer
var context_lbl: Label
var pred_box: VBoxContainer


func title() -> String:
	return "Bigram Lab"


func intro() -> String:
	return "A language model is a next-token predictor. The simplest one looks only one token back - that is a bigram model. Count the letter pairs in a small text and try it yourself."


func build_body(vb: VBoxContainer) -> void:
	_count()
	context_lbl = lbl(vb, "", 15, Color(1.0, 0.85, 0.5))
	var row: HBoxContainer = hbox(vb)
	lbl(row, "Type letters to follow:", 14)
	var ed: LineEdit = LineEdit.new()
	ed.text = "t"
	ed.custom_minimum_size = Vector2(120, 0)
	ed.text_changed.connect(func(t: String) -> void:
		if t.length() > 0:
			current = t.substr(t.length() - 1, 1).to_lower()
			_predict())
	row.add_child(ed)
	_btn_row(row, ["t", "e", "a", "s", " "])
	pred_box = VBoxContainer.new()
	pred_box.add_theme_constant_override("separation", 2)
	vb.add_child(pred_box)
	rich(vb, "What you should notice",
		"A bigram model can only see one character back, so it produces locally plausible but globally meaningless text. Making the window longer - and then letting attention pick which earlier tokens matter - is the whole story of the next chapters.")
	rich(vb, "The link to real models",
		"Real models use the same idea with tokens instead of letters, a much longer context, and a neural network instead of a counted table. The table below is exactly what the network learns to imitate.")
	bars_box = VBoxContainer.new()
	bars_box.add_theme_constant_override("separation", 3)
	vb.add_child(bars_box)
	_predict()


func _btn_row(row: HBoxContainer, letters: Array) -> void:
	for l in letters:
		var s: String = String(l)
		btn(row, "«" + ("space" if s == " " else s) + "»", func() -> void:
			current = s
			_predict())


func _count() -> void:
	var text: String = CORPUS.to_lower()
	for i in text.length() - 1:
		var a: String = text[i]
		var b: String = text[i + 1]
		if not counts.has(a):
			counts[a] = {}
			totals[a] = 0
		var d: Dictionary = counts[a]
		d[b] = int(d.get(b, 0)) + 1
		totals[a] = int(totals[a]) + 1


func _top(a: String, n: int) -> Array:
	if not counts.has(a):
		return []
	var d: Dictionary = counts[a]
	var keys: Array = d.keys()
	keys.sort_custom(func(x: String, y: String) -> bool: return int(d[x]) > int(d[y]))
	var out: Array = []
	for k in keys.slice(0, n):
		out.append({"ch": String(k), "p": float(d[k]) / float(totals[a]), "n": int(d[k])})
	return out


func _predict() -> void:
	for c in pred_box.get_children():
		pred_box.remove_child(c)
		c.queue_free()
	var top: Array = _top(current, 5)
	if top.is_empty():
		lbl(pred_box, "'" + current + "' never appears in this little text.", 15, Color(1.0, 0.6, 0.6))
		_fill_bars()
		return
	var shown: String = "space" if current == " " else current
	context_lbl.text = "After '" + shown + "'  ·  %d different continuations seen, %d times in total" % [(counts[current] as Dictionary).size(), int(totals[current])]
	for t in top:
		var ch: String = "␣" if String(t["ch"]) == " " else String(t["ch"])
		bar(pred_box, "'" + ch + "'", float(t["p"]), Color(0.35, 0.75, 0.95), "%.0f%%  (%d times)" % [float(t["p"]) * 100.0, int(t["n"])])
	_fill_bars()


func _fill_bars() -> void:
	for c in bars_box.get_children():
		bars_box.remove_child(c)
		c.queue_free()
	lbl(bars_box, "Sampling this table over and over (greedy, always the most likely letter):", 14, Color(0.8, 0.88, 1.0))
	var s: String = current
	var line: String = current
	for i in 60:
		var t: Array = _top(s, 1)
		if t.is_empty():
			break
		var nxt: String = String(t[0]["ch"])
		line += nxt
		s = nxt
	var stuck: bool = line.length() > 8 and line.substr(line.length() - 6, 5) == line.substr(line.length() - 11, 5)
	lbl(bars_box, "→  " + line + ("   (yes, it gets stuck in a loop)" if stuck else ""), 16, Color(0.55, 0.95, 0.8))