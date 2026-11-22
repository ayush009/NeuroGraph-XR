extends Node
## Temporary diagnostic: loads the real game and reports what the VR session is doing.

var viewer: Node
var events: PackedStringArray = []


func _ready() -> void:
	var xr: XRInterface = XRServer.find_interface("OpenXR")
	if xr:
		for sig in ["session_begun", "session_visible", "session_focussed", "session_stopping", "session_loss_pending", "instance_exiting", "pose_recentered"]:
			if xr.has_signal(sig):
				var s: String = sig
				xr.connect(sig, func() -> void:
					events.append("%.1fs %s" % [Time.get_ticks_msec() / 1000.0, s]))
	viewer = (load("res://ds_main.tscn") as PackedScene).instantiate()
	add_child(viewer)
	for t in [2.0, 5.0, 8.0]:
		await get_tree().create_timer(t - (0.0 if t == 2.0 else (3.0))).timeout
		_report(t)


func _report(t: float) -> void:
	var xr: XRInterface = XRServer.find_interface("OpenXR")
	print("\n----- t=%.0fs -----" % t)
	print("xr_active=", viewer.xr_active, "  interface initialized=", xr != null and xr.is_initialized(), "  use_xr=", get_viewport().use_xr)
	print("session events: ", events)
	print("fps=", Engine.get_frames_per_second(), "  render size=", xr.get_render_target_size() if xr else Vector2.ZERO)
	if viewer.xr_active:
		var cam: XRCamera3D = viewer.xr_camera
		var content: Node3D = viewer.content
		print("head pos=", cam.global_position.snapped(Vector3.ONE * 0.01), "  looking=", (-cam.global_transform.basis.z).snapped(Vector3.ONE * 0.01))
		print("content pos=", content.global_position, " scale=", snappedf(content.scale.x, 0.001), " items=", viewer.items.size(), " graph_radius(m)=", (viewer.graph_radius * content.scale.x))
		print("head -> graph centre distance (m)=", snappedf(cam.global_position.distance_to(content.global_position), 0.01))
		var nearest: float = INF
		for it in viewer.items:
			nearest = minf(nearest, cam.global_position.distance_to((it["node"] as Node3D).global_position))
		print("nearest concept to the eyes (m)=", snappedf(nearest, 0.01))
		print("left ctrl tracked=", viewer.xr_left.get_has_tracking_data(), "  right ctrl tracked=", viewer.xr_right.get_has_tracking_data())
		# VR screen
		var sheet: Node3D = viewer.ui_sheet
		print("VR screen: exists=", sheet != null, "  dist from eyes=", snappedf(cam.global_position.distance_to(sheet.global_position), 0.01) if sheet else -1.0,
			"  intro playing=", viewer.intro != null and viewer.intro.visible, "  menu visible=", viewer.menu_panel.visible,
			"  layers on screen=", viewer.ui_vp.get_children().filter(func(c): return c is CanvasLayer).size() if viewer.ui_vp else 0)
		# concept label size as seen by the eye (fixed_size: angle = pixel_size * font_size * world scale)
		var angs: Array = []
		for it in viewer.items.slice(0, 3):
			var l: Label3D = it["label"]
			angs.append(snappedf(rad_to_deg(l.pixel_size * l.font_size * l.global_transform.basis.get_scale().y), 0.01))
		print("concept label height (degrees, desktop = 1.19): ", angs)
	if viewer.ui_vp:
		var img: Image = viewer.ui_vp.get_texture().get_image()
		var sum: float = 0.0
		var n: int = 0
		for y in range(0, img.get_height(), 40):
			for x in range(0, img.get_width(), 40):
				sum += img.get_pixel(x, y).a
				n += 1
		print("VR screen image ", img.get_size(), "  covered (non-transparent) = ", snappedf(sum / maxf(n, 1), 0.01))
		img.save_png("user://vr_screen_%d.png" % int(t))
