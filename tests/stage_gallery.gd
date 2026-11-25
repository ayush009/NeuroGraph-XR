extends Control
## Renders every StoryStage template with sample data, 4 per page (2x2), and saves
## each page to _webcheck/stage_gallery_<n>.png for visual review.

const OUT: String = "res://_webcheck/stage_gallery_%d.png"

var SAMPLES: Array = [
	{"t": "flow", "items": [{"l": "Text"}, {"l": "Tokens"}, {"l": "Vectors"}, {"l": "Transformer"}, {"l": "Next token"}],
		"beats": [{"cap": "x", "show": 5, "hi": [3], "note": "One token at a time"}]},
	{"t": "tokens", "text": "unbelievably cheap tokens", "items": [{"l": "un", "v": 403}, {"l": "believ", "v": 8213}, {"l": "ably", "v": 2245}, {"l": " cheap", "v": 11872}, {"l": " tok", "v": 7911}, {"l": "ens", "v": 641}],
		"beats": [{"cap": "x", "show": 6, "hi": [1]}]},
	{"t": "bars", "softmax": true, "temp": true, "items": [{"l": "Paris", "v": 8.4}, {"l": "Lyon", "v": 3.1}, {"l": "France", "v": 2.7}, {"l": "London", "v": 1.9}],
		"beats": [{"cap": "x", "show": 4, "hi": [0], "note": "Softmax"}]},
	{"t": "vectors", "items": [{"l": "king", "x": 0.8, "y": 0.5}, {"l": "queen", "x": 0.75, "y": 0.8}, {"l": "pizza", "x": -0.7, "y": -0.5}],
		"beats": [{"cap": "x", "show": 3, "hi": [0, 1]}]},
	{"t": "attention", "items": [{"l": "The"}, {"l": "cat"}, {"l": "sat"}, {"l": "because"}, {"l": "it"}, {"l": "was"}, {"l": "tired"}],
		"links": [[4, 1, 0.62], [4, 4, 0.15], [4, 3, 0.1], [4, 0, 0.05], [4, 2, 0.08]], "beats": [{"cap": "x", "show": 7, "hi": [4]}]},
	{"t": "compare", "left": "Pre-training", "right": "Fine-tuning", "items": [{"l": "Trillions of tokens", "side": 0}, {"l": "Thousands of examples", "side": 1}, {"l": "Learns language", "side": 0}, {"l": "Learns behaviour", "side": 1}],
		"beats": [{"cap": "x", "show": 4, "hi": [1]}]},
	{"t": "curve", "f": "power", "xl": "compute", "yl": "loss", "fl": "bigger model", "f2": "decay", "fl2": "data-limited", "items": [{"l": "GPT-2", "x": 0.2}, {"l": "GPT-3", "x": 0.6}],
		"beats": [{"cap": "x", "show": 2, "hi": [1]}]},
	{"t": "grid", "pattern": "causal", "items": [{"l": "The"}, {"l": "cat"}, {"l": "sat"}, {"l": "on"}, {"l": "the"}, {"l": "mat"}], "col_labels": ["The", "cat", "sat", "on", "the", "mat"],
		"beats": [{"cap": "x", "show": 6, "hi": [3], "note": "No peeking ahead"}]},
	{"t": "tree", "items": [{"l": "AI"}, {"l": "Machine learning", "p": 0}, {"l": "Rules", "p": 0}, {"l": "Deep learning", "p": 1}, {"l": "Classic ML", "p": 1}, {"l": "LLMs", "p": 3}],
		"beats": [{"cap": "x", "show": 6, "hi": [5]}]},
	{"t": "timeline", "items": [{"l": "Attention paper", "v": 2017}, {"l": "BERT", "v": 2018}, {"l": "GPT-3", "v": 2020}, {"l": "ChatGPT", "v": 2022}, {"l": "Reasoning models", "v": 2024}],
		"beats": [{"cap": "x", "show": 5, "hi": [3]}]},
	{"t": "network", "layers": [3, 5, 5, 2], "items": [{"l": "input"}, {"l": "hidden"}, {"l": "hidden"}, {"l": "output"}],
		"beats": [{"cap": "x", "show": 4, "hi": [1]}]},
	{"t": "scale", "unit": " params", "items": [{"l": "GPT-1", "v": 117000000}, {"l": "GPT-2", "v": 1500000000}, {"l": "GPT-3", "v": 175000000000}],
		"beats": [{"cap": "x", "show": 3, "hi": [2]}]},
	{"t": "chat", "items": [{"who": "sys", "l": "You are a helpful tutor."}, {"who": "user", "l": "What is a token?"}, {"who": "ai", "l": "A token is a small piece of text, like a word or part of a word."}],
		"beats": [{"cap": "x", "show": 3, "hi": [2]}]},
	{"t": "funnel", "label": "retrieve top 2", "items": [{"l": "doc A"}, {"l": "doc B"}, {"l": "doc C"}, {"l": "doc D"}, {"l": "doc E"}, {"l": "doc F"}],
		"beats": [{"cap": "x", "show": 6, "hi": [1, 4]}]},
	{"t": "cycle", "center": "agent loop", "items": [{"l": "Think"}, {"l": "Act"}, {"l": "Observe"}, {"l": "Update"}],
		"beats": [{"cap": "x", "show": 4, "hi": [1]}]},
	{"t": "stack", "axis": "data flows up", "items": [{"l": "Embedding"}, {"l": "Attention"}, {"l": "Feed-forward"}, {"l": "Attention"}, {"l": "Feed-forward"}, {"l": "Output head"}],
		"beats": [{"cap": "x", "show": 6, "hi": [1]}]},
]


func _ready() -> void:
	var page: int = 0
	var i: int = 0
	while i < SAMPLES.size():
		for c in get_children():
			c.queue_free()
		await get_tree().process_frame
		for k in 4:
			if i + k >= SAMPLES.size():
				break
			var st: StoryStage = StoryStage.new()
			st.position = Vector2(float(k % 2) * 576.0 + 4.0, float(k / 2) * 324.0 + 4.0)
			st.size = Vector2(568, 316)
			add_child(st)
			st.set_scene(SAMPLES[i + k])
		await get_tree().create_timer(2.2).timeout
		await RenderingServer.frame_post_draw
		var img: Image = get_viewport().get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path(OUT % page))
		print("saved page ", page)
		page += 1
		i += 4
	get_tree().quit()
