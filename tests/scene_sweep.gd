extends Control
## Renders EVERY course card's animated scene at its final beat (9 per sheet, 3x3) and saves
## contact sheets to _webcheck/sweep/sheet_<n>.png, each tile captioned with lesson + card id.

const OUT_DIR: String = "res://_webcheck/sweep/"
const PER: int = 9

var cards: Array = []


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/aie_course.json"))
	for ch in d["chapters"]:
		for l in ch["lessons"]:
			for c in l["cards"]:
				cards.append({"lesson": String(l["id"]), "id": String(c["id"]), "scene": c.get("scene", {})})
	var start: int = 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--from="):
			start = int(a.substr(7))
	var sheet: int = start / PER
	var i: int = start
	while i < cards.size():
		for ch2 in get_children():
			ch2.queue_free()
		await get_tree().process_frame
		var tw: float = 1152.0 / 3.0
		var th: float = 648.0 / 3.0
		for k in PER:
			if i + k >= cards.size():
				break
			var c: Dictionary = cards[i + k]
			# render at the real stage size, then scale the tile down so layout is judged at true size
			var holder: Control = Control.new()
			holder.position = Vector2(float(k % 3) * tw, float(k / 3) * th)
			holder.scale = Vector2(tw / 1124.0, th / 420.0)
			add_child(holder)
			var st: StoryStage = StoryStage.new()
			st.size = Vector2(1120, 416)
			holder.add_child(st)
			st.set_scene(c["scene"])
			st.set_beat(st.beat_count() - 1)
			st.show_all()
			var tag: Label = Label.new()
			tag.text = "%s  %s" % [c["lesson"], c["id"]]
			tag.position = holder.position + Vector2(6, th - 22)
			tag.add_theme_font_size_override("font_size", 12)
			tag.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
			add_child(tag)
		await get_tree().create_timer(3.2).timeout     # long enough for chat typing to finish
		await RenderingServer.frame_post_draw
		var img: Image = get_viewport().get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path(OUT_DIR + "sheet_%02d.png" % sheet))
		print("sheet ", sheet, "  cards ", i, "-", mini(i + PER, cards.size()) - 1)
		sheet += 1
		i += PER
	print("SWEEP DONE ", cards.size(), " cards")
	get_tree().quit()
