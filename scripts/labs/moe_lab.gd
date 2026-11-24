extends LabBase
## Mixture-of-experts lab: a router sends each token to a few experts, so the parameter
## count grows with the number of experts while the compute per token stays flat.

const N_EXPERTS: int = 8
const EXPERT_PARAMS: float = 3.0e9     # parameters per expert, in billions
const SHARED_PARAMS: float = 4.0e9     # attention and embeddings, shared by every token
const DENSE_BASELINE: float = 30.0e9

var logits: Array = [2.6, 1.9, 1.1, 0.6, 0.2, -0.4, -1.2, -2.1]
var top_k: int = 2
var bars: VBoxContainer
var summary: Label


func title() -> String:
	return "Mixture of Experts Lab"


func intro() -> String:
	return "A dense model runs the same weights for every token. A mixture of experts puts many expert blocks side by side and a small router that picks only a few of them for each token."


func build_body(vb: VBoxContainer) -> void:
	var row: HBoxContainer = hbox(vb)
	lbl(row, "Experts used per token:", 14)
	for k in [1, 2, 4]:
		var kk: int = k
		btn(row, "top-%d" % kk, func() -> void:
			top_k = kk
			_refresh(), top_k == kk)
	lbl(vb, "Router scores for this token (learned, one per expert):", 14, Color(1.0, 0.85, 0.5))
	bars = VBoxContainer.new()
	bars.add_theme_constant_override("separation", 3)
	vb.add_child(bars)
	summary = lbl(vb, "", 15, Color(0.55, 0.95, 0.8))
	rich(vb, "What you should notice",
		"Total parameters grow with the number of experts, but the FLOPs per token do not: only the selected experts run. That is the trade the lecture calls conditional computation - a big model in memory, a small model in compute.")
	rich(vb, "What it costs and what it buys",
		"All experts must be stored, so serving needs the memory of a much larger model; routing must be balanced or a few experts take all the traffic; and training is harder to keep stable. In exchange, quality at a fixed inference budget is usually better than a dense model of the same compute.")
	_refresh()


func _softmax() -> Array:
	var m: float = -1e9
	for l in logits:
		m = maxf(m, float(l))
	var ex: Array = []
	var s: float = 0.0
	for l in logits:
		var e: float = exp(float(l) - m)
		ex.append(e)
		s += e
	for i in ex.size():
		ex[i] = float(ex[i]) / s
	return ex


func _refresh() -> void:
	var p: Array = _softmax()
	var idx: Array = []
	for i in N_EXPERTS:
		idx.append(i)
	idx.sort_custom(func(a: int, b: int) -> bool: return float(p[a]) > float(p[b]))
	var chosen: Array = idx.slice(0, top_k)
	for c in bars.get_children():
		bars.remove_child(c)
		c.queue_free()
	for i in N_EXPERTS:
		var is_in: bool = chosen.has(i)
		var col: Color = Color(0.4, 0.9, 0.6) if is_in else Color(0.35, 0.4, 0.55)
		bar(bars, "expert %d" % (i + 1), float(p[i]) / 0.75, col, "%.1f%%%s" % [float(p[i]) * 100.0, "   ← runs" if is_in else ""])
	var total: float = SHARED_PARAMS + float(N_EXPERTS) * EXPERT_PARAMS
	var active: float = SHARED_PARAMS + float(top_k) * EXPERT_PARAMS
	summary.text = "Total parameters: %.0f B   ·   active per token: %.0f B (%.0f%%)\nA dense model of the same active size would have %.0f B parameters in total and would run all of them for every single token." % [
		total / 1e9, active / 1e9, active / total * 100.0, DENSE_BASELINE / 1e9]