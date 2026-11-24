extends Node
## Lab smoke test: opens every course lab in the real app (in VR-preview mode so the
## headset stays out of the way) and reports where each one ended up.

var v: Node
var only: String = "hnsw_lab"     # set to a lab id to open just that one (used for screenshots)
var problems: PackedStringArray = []

const LABS: Array = ["bigram_lab", "embedding_lab", "posenc_lab", "kvcache_lab", "moe_lab", "precision_lab",
	"scaling_lab", "retrieval_lab", "hnsw_lab", "passk_lab", "prompt_lab"]


func _ready() -> void:
	v = (load("res://ds_main.tscn") as PackedScene).instantiate()
	v.preview_vr_ui = true
	add_child(v)
	await get_tree().create_timer(1.2).timeout
	v.intro.begin_leave()
	await get_tree().create_timer(0.8).timeout
	v.menu_panel.visible = false
	var list: Array = LABS if only == "" else [only]
	for id in list:
		var lab: String = String(id)
		v.open_lab_view(lab)
		await get_tree().create_timer(0.45).timeout
		var inst: Node = v.lab_views.get(lab, null)
		var in_vr: bool = inst != null and inst.get_parent() == v.ui_vp
		var vis: bool = inst != null and (inst as CanvasLayer).visible
		print("%-14s created=%s  visible=%s  on VR screen=%s  children=%d" % [
			lab, inst != null, vis, in_vr, inst.get_child_count() if inst != null else -1])
		if inst == null or not vis:
			problems.append(lab + " did not open")
		# every other lab must be hidden while this one is open
		for other in v.lab_views.keys():
			if String(other) != lab and (v.lab_views[other] as CanvasLayer).visible:
				problems.append("lab %s stayed visible under %s" % [other, lab])
	# one screenshot-worthy lab left open at the end
	if only == "":
		v.open_lab_view("prompt_lab")
		print("\n===== LAB TEST ", ("FAILED: " + ", ".join(problems)) if problems.size() > 0 else "PASSED", " =====")
		await get_tree().create_timer(0.6).timeout
		get_tree().quit()
	else:
		# single-lab mode: stay open so the screenshot shows the lab
		print("showing ", only)