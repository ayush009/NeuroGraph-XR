extends LabBase
## Retrieval lab: the same query ranked three ways - keyword search (BM25), semantic
## search (embeddings), and reciprocal rank fusion of both.

const DOCS: Array = [
	{"id": "chunk1", "text": "The car needs a new battery before winter.", "terms": {"car": 2.0, "battery": 2.0, "engine": 0.6, "vehicle": 1.0, "repair": 1.0}},
	{"id": "chunk2", "text": "How to replace the batteries in a smoke detector.", "terms": {"battery": 2.0, "batteries": 2.0, "replace": 1.2, "home": 1.0, "detector": 1.4}},
	{"id": "chunk3", "text": "Automobile maintenance schedule and service intervals.", "terms": {"automobile": 2.0, "maintenance": 1.6, "vehicle": 1.2, "service": 1.0, "engine": 0.8}},
	{"id": "chunk4", "text": "Train timetables and ticket refund policy.", "terms": {"train": 2.0, "ticket": 1.6, "refund": 1.2, "travel": 1.0}},
	{"id": "chunk5", "text": "Electric vehicle charging stations and range tips.", "terms": {"electric": 1.6, "vehicle": 1.6, "car": 1.0, "charging": 1.4, "battery": 0.8}},
]
const SYNONYMS: Dictionary = {"car": ["vehicle", "automobile"], "vehicle": ["car", "automobile"], "battery": ["batteries"], "engine": ["motor"]}
const PRESETS: Array = ["car battery", "battery replacement at home", "how do I keep my vehicle running"]

var query: String = "car battery"
var out: VBoxContainer
var term_map: Dictionary = {}


func title() -> String:
	return "Retrieval Lab"


func intro() -> String:
	return "Retrieval has two families: keyword matching, which is precise but blind to meaning, and embedding similarity, which understands paraphrases but can drift. Hybrid search runs both and fuses the ranks. Try a query."


func build_body(vb: VBoxContainer) -> void:
	var h: HBoxContainer = hbox(vb)
	lbl(h, "Query:", 14)
	var ed: LineEdit = LineEdit.new()
	ed.text = query
	ed.custom_minimum_size = Vector2(320, 0)
	ed.text_submitted.connect(func(t: String) -> void:
		query = t
		_refresh())
	h.add_child(ed)
	btn(h, "Search", func() -> void:
		query = ed.text
		_refresh(), true)
	var hp: HBoxContainer = hbox(vb)
	lbl(hp, "Try:", 13)
	for p in PRESETS:
		var ps: String = String(p)
		btn(hp, ps, func() -> void:
			query = ps
			ed.text = ps
			_refresh())
	out = VBoxContainer.new()
	out.add_theme_constant_override("separation", 4)
	vb.add_child(out)
	rich(vb, "What you should notice",
		"Keyword search ranks on exact terms, so it finds 'battery' but not 'vehicle'. Semantic search matches meaning, so it finds the car chunk for a paraphrased query, but it also pulls in the smoke-detector chunk because both are about batteries.")
	rich(vb, "Why fuse the two lists",
		"Reciprocal rank fusion scores each document by 1 / (60 + rank) in every list and adds the scores. It needs no tuning, cannot be dominated by one list's raw scores, and rewards a document that ranks well in both. A document that is second in both lists beats one that is first in only one of them.")
	_refresh()


func _refresh() -> void:
	for c in out.get_children():
		out.remove_child(c)
		c.queue_free()
	var q_terms: Array = []
	for w in query.to_lower().split(" ", false):
		q_terms.append(String(w))
	# expand the query with synonyms for the semantic side
	var sem_terms: Dictionary = {}
	for t in q_terms:
		sem_terms[t] = 1.0
		for syn in SYNONYMS.get(t, []):
			sem_terms[String(syn)] = 1.0
	var bm: Array = []
	var dn: Array = []
	for d in DOCS:
		var bm_score: float = 0.0
		for t in q_terms:
			bm_score += float((d["terms"] as Dictionary).get(t, 0.0))
		var dot: float = 0.0
		var nq: float = 0.0
		var nd: float = 0.0
		for t in sem_terms.keys():
			var w: float = float(sem_terms[t])
			nq += w * w
			var dv: float = float((d["terms"] as Dictionary).get(t, 0.0))
			dot += w * dv
			nd += dv * dv
		var cos_sim: float = dot / maxf(sqrt(nq) * sqrt(nd), 0.0001)
		bm.append({"id": d["id"], "t": d["text"], "s": bm_score})
		dn.append({"id": d["id"], "t": d["text"], "s": cos_sim})
	bm.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x["s"]) > float(y["s"]))
	dn.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x["s"]) > float(y["s"]))
	var max_bm: float = maxf(float(bm[0]["s"]), 0.001)
	var max_dn: float = maxf(float(dn[0]["s"]), 0.001)
	lbl(out, "1.  Keyword search (BM25 - exact terms, weighted by rarity)", 16, Color(1.0, 0.85, 0.5))
	for i in bm.size():
		bar(out, "   %s" % String(bm[i]["id"]), float(bm[i]["s"]) / max_bm, Color(0.45, 0.7, 1.0), "score %.2f   %s" % [float(bm[i]["s"]), String(bm[i]["t"]).substr(0, 46)])
	lbl(out, "2.  Semantic search (embedding cosine similarity, synonyms count)", 16, Color(1.0, 0.85, 0.5))
	for i in dn.size():
		bar(out, "   %s" % String(dn[i]["id"]), float(dn[i]["s"]) / max_dn, Color(0.5, 0.95, 0.7), "cosine %.2f   %s" % [float(dn[i]["s"]), String(dn[i]["t"]).substr(0, 46)])
	# RRF
	var fused: Dictionary = {}
	for i in bm.size():
		var id: String = String(bm[i]["id"])
		fused[id] = float(fused.get(id, 0.0)) + 1.0 / (60.0 + float(i + 1))
	for i in dn.size():
		var id: String = String(dn[i]["id"])
		fused[id] = float(fused.get(id, 0.0)) + 1.0 / (60.0 + float(i + 1))
	var keys: Array = fused.keys()
	keys.sort_custom(func(x: String, y: String) -> bool: return float(fused[x]) > float(fused[y]))
	var best: float = float(fused[keys[0]])
	lbl(out, "3.  Hybrid: reciprocal rank fusion, 1 / (60 + rank) added over both lists", 16, Color(1.0, 0.85, 0.5))
	for k in keys:
		var text: String = ""
		for d in DOCS:
			if String(d["id"]) == String(k):
				text = String(d["text"])
		bar(out, "   %s" % String(k), float(fused[k]) / best, Color(1.0, 0.8, 0.3), "%.5f   %s" % [float(fused[k]), text.substr(0, 46)])