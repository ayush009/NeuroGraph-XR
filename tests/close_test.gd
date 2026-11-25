extends Node
## Opens each built-in lab and clicks its Close button with a real mouse event at the
## button's on-screen centre, then reports whether the panel actually closed.

var v: Node


func _ready() -> void:
	v = (load("res://ds_main.tscn") as PackedScene).instantiate()
	add_child(v)
	await get_tree().create_timer(1.2).timeout
	v.intro.begin_leave()
	await get_tree().create_timer(1.0).timeout
	v.menu_panel.visible = false
	await get_tree().create_timer(0.3).timeout
	for pair in [["token", "lab_panel", "_toggle_lab"], ["sampling", "sl_panel", "_toggle_sampling"], ["attention", "al_panel", "_toggle_attention"]]:
		var pnl: PanelContainer = v.get(String(pair[1]))
		v.call(String(pair[2]))
		await get_tree().create_timer(0.6).timeout
		var b: Button = _find_close(pnl)
		if b == null:
			print(pair[0], ": no close button found")
			continue
		var r: Rect2 = b.get_global_rect()
		var xf: Transform2D = b.get_global_transform_with_canvas()
		var centre: Vector2 = xf * (b.size * 0.5)
		print(pair[0], ": close btn global rect ", r, "  screen centre ", centre, "  panel scale ", pnl.scale, " vp=", b.get_viewport())
		var hovered: Control = b.get_viewport().gui_get_hovered_control() if b.get_viewport().has_method("gui_get_hovered_control") else null
		_blockers(get_tree().root, centre)
		_click(b.get_viewport(), centre)
		await get_tree().create_timer(0.4).timeout
		var picked: Control = b.get_viewport().gui_find_control(centre) if b.get_viewport().has_method("gui_find_control") else null
		print(pair[0], ": after click visible=", pnl.visible, "  control at centre=", picked, " hovered=", hovered)
		if pnl.visible:
			v.call(String(pair[2]))
	get_tree().quit()


func _blockers(n: Node, p: Vector2) -> void:
	if n is Control:
		var c: Control = n
		if c.is_visible_in_tree() and c.mouse_filter != Control.MOUSE_FILTER_IGNORE and c.get_global_rect().has_point(p):
			var cl: CanvasLayer = null
			var q: Node = c
			while q != null and cl == null:
				if q is CanvasLayer:
					cl = q
				q = q.get_parent()
			print("   hit: ", c.get_path(), "  type=", c.get_class(), " filter=", c.mouse_filter, " layer=", (cl.layer if cl != null else -999))
	for ch in n.get_children():
		_blockers(ch, p)


func _find_close(n: Node) -> Button:
	for c in n.get_children():
		if c is Button and (c as Button).text.begins_with("Close"):
			return c
		var f: Button = _find_close(c)
		if f != null:
			return f
	return null


func _click(vp: Viewport, p: Vector2) -> void:
	var m: InputEventMouseMotion = InputEventMouseMotion.new()
	m.position = p
	m.global_position = p
	vp.push_input(m)
	for pressed in [true, false]:
		var e: InputEventMouseButton = InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = p
		e.global_position = p
		vp.push_input(e)
