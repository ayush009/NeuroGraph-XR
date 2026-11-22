class_name DSViewer
extends Node3D
## NeuroGraph XR - explore knowledge graphs and neural networks in 3D / VR
## Mode 1: 3D Knowledge Graph (res://data/ds_graph.json) with GraphRAG-style Q&A via local Ollama.
## Mode 2: Neural-network "device" (res://data/ds_network.json): explode the layers, watch a forward pass.
## Works on desktop (mouse) and in VR (OpenXR controllers).
##
## Desktop: 1 graph | 2 network | E explode | F forward pass | R reset | T auto-rotate
##          hover = preview, click = select, drag = orbit, wheel = zoom, type a question + Enter
## VR:      right trigger = select, A = explode, B = switch mode, left X = explain selection,
##          left Y = reset, left stick = rotate, right stick up/down = scale

## Selectable courses. Each course = a knowledge graph + a network ("device") + a quiz, all plain JSON.
const COURSES: Array = [
	{"name": "LLM Engineering", "graph": "res://data/llm_graph.json", "net": "res://data/llm_network.json", "quiz": "res://data/llm_quiz.json"},
	{"name": "Data Science Basics", "graph": "res://data/ds_graph.json", "net": "res://data/ds_network.json", "quiz": "res://data/ds_quiz.json"},
]
var course_idx: int = 0
const OLLAMA_URL: String = "http://127.0.0.1:11434/api/generate"
const OLLAMA_MODEL: String = "llama3.2:3b"
const VR_SCALE: float = 0.11
const VR_CONTENT_POS: Vector3 = Vector3(0.0, 1.3, -1.6)
const STOP_WORDS: Array = ["the", "and", "what", "how", "why", "does", "with", "for", "are", "is", "of", "to", "in", "a", "an", "do", "me", "about", "explain", "tell", "between", "can", "this", "that", "use", "used", "which", "after", "work"]
const GRAPH_CHIPS: Array = ["What is GraphRAG?", "How do I avoid overfitting?", "What comes after data cleaning?", "Which models work on tabular data?"]
const NET_CHIPS: Array = ["What does the LSTM layer do?", "Why is there an attention layer?", "What does the output layer predict?"]

enum Mode { GRAPH, NETWORK }

var mode: int = Mode.GRAPH
var graph_data: Dictionary = {}
var net_data: Dictionary = {}

# scene
var content: Node3D
var camera: Camera3D
var edge_mesh: MeshInstance3D
var edge_mat: StandardMaterial3D
var stars: Node3D
var env: Environment

# runtime data
var items: Array = []
var g_items: Dictionary = {}
var g_edges: Array = []
var g_adj: Dictionary = {}
var n_layers: Array = []
var n_neurons: Array = []
var n_conns: Array = []
var selected: Dictionary = {}
var highlighted: Array = []
var hover_id: String = ""
var filter_cat: String = ""
var pulses: Array = []
var time_s: float = 0.0

# animation state
var spread: float = 0.0
var spread_target: float = 0.0
var _spread_applied: float = -1.0
var forward_pass: bool = true
var fwd_t: float = 0.0

# flat camera
var yaw: float = 0.5
var pitch: float = 0.3
var dist: float = 14.0
var dist_goal: float = 14.0
var cam_focus: Vector3 = Vector3.ZERO
var auto_rotate: bool = true
var _dragging: bool = false
var _drag_moved: float = 0.0

# UI
var info_label: Label
var card_title: Label
var card_cat: Label
var card_rule_ref: ColorRect
var answer_label: Label
var answer_scroll: ScrollContainer
var question_edit: LineEdit
var status_label: Label
var legend_panel: PanelContainer
var legend_box: VBoxContainer
var focus_ids: Array = []     # while non-empty: only these concepts keep colour, everything else turns grey
var sfx_pop: AudioStream
var graph_radius: float = 9.0
var cat_lbls: Array = []
var graph_scale: float = 1.0
var label_min_deg: int = 3
var chips_row: HBoxContainer
var http: HTTPRequest
var _ai_busy: bool = false
var _last_facts: String = ""
var _answer_text: String = ""

# XR
var xr_active: bool = false
var xr_origin: XROrigin3D
var xr_camera: XRCamera3D
var xr_left: XRController3D
var xr_right: XRController3D
var vr_label: Label3D
var vr_anchor: Vector3 = Vector3(0.0, 1.3, -1.6)   # where the model floats (set from the real head pose)
var vr_scale: float = 0.11
var vr_yaw: float = 0.0
var _vr_placed: bool = false
var _vr_wait: float = 0.0
const VR_VIEW_DIST: float = 2.0     # metres in front of the eyes (behind the UI screen)
const VR_MODEL_RADIUS: float = 0.6  # the whole model fits in a ~1.2 m wide space


func _ready() -> void:
	get_window().title = "NeuroGraph XR"
	_load_course(0)
	_load_progress()
	_setup_environment()
	content = Node3D.new()
	content.name = "Content"
	add_child(content)
	camera = Camera3D.new()
	camera.far = 600.0
	camera.fov = 52.0   # narrower angle: spheres stay round at the screen edges
	camera.current = true
	add_child(camera)
	http = HTTPRequest.new()
	http.timeout = 120.0
	http.request_completed.connect(_on_ai_done)
	add_child(http)
	_apply_theme()
	_setup_ui()
	_theme_layers()
	_setup_audio()
	_setup_voice()
	_setup_xr()
	if not xr_active and preview_vr_ui:
		_setup_vr_ui()   # desktop test of the headset screen
	_set_mode(Mode.GRAPH)
	_update_camera(0.0)
	# same start on desktop AND in the headset: intro animation -> home menu
	menu_panel.visible = false
	_play_intro()


# ═════════════════════ VR SCREEN: the complete desktop UI inside the headset ═════════════════════
# Every 2D layer (intro, menu, top bar, cards, captions, quiz, labs, Ask AI) is drawn into one
# off-screen 1280x720 viewport. That image floats in front of you as a see-through screen, the 3D
# graph behind it. The right-controller laser is the mouse: aim = hover, trigger = click, stick = scroll.
const VR_UI_SIZE: Vector2i = Vector2i(1280, 720)
const VR_UI_WIDTH: float = 1.6       # metres
const VR_UI_DIST: float = 1.25       # metres in front of your eyes
const VR_LABEL_BOOST: float = 1.6    # concept names in VR: 60% bigger than on desktop
var preview_vr_ui: bool = false      # set by tests: shows the VR screen on desktop, steered by the mouse
var ui_vp: SubViewport
var ui_sheet: MeshInstance3D
var ui_dot: MeshInstance3D
var vr_ray: MeshInstance3D
var ui_mouse: Vector2 = Vector2(-100, -100)
var ui_hit: bool = false
var _ui_down: bool = false
var _wheel_t: float = 0.0
var _lbl_scale: float = -1.0


func _ui_vp() -> Viewport:
	return ui_vp if ui_vp != null else get_viewport()


func _ui_mouse_pos() -> Vector2:
	return ui_mouse if ui_vp != null else get_viewport().get_mouse_position()


func _ui_over_control() -> bool:
	if ui_vp == null or not ui_hit:
		return false
	# an open dropdown (Labs / View) is its own little window: count it as UI too
	return ui_vp.gui_get_hovered_control() != null or not ui_vp.get_embedded_subwindows().is_empty()


func _setup_vr_ui() -> void:
	ui_vp = SubViewport.new()
	ui_vp.name = "VRScreen"
	ui_vp.size = VR_UI_SIZE
	ui_vp.transparent_bg = true
	ui_vp.gui_embed_subwindows = true
	ui_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(ui_vp)
	for ch in get_children():
		if ch is CanvasLayer:
			remove_child(ch)
			ui_vp.add_child(ch)
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(VR_UI_WIDTH, VR_UI_WIDTH * float(VR_UI_SIZE.y) / float(VR_UI_SIZE.x))
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = true          # the UI is always drawn on top of the graph, like on a monitor
	m.render_priority = 10
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	m.albedo_texture = ui_vp.get_texture()
	m.albedo_texture_force_srgb = true   # the 2D image is sRGB: without this every colour looks washed-out grey
	m.disable_fog = true
	ui_sheet = MeshInstance3D.new()
	ui_sheet.name = "VRScreenQuad"
	ui_sheet.mesh = quad
	ui_sheet.material_override = m
	ui_sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if xr_active:
		add_child(ui_sheet)
		ui_sheet.position = Vector3(0.0, 1.2, -VR_UI_DIST)   # moved in front of the real head once it is tracked
	else:
		camera.add_child(ui_sheet)
		ui_sheet.position = Vector3(0.0, 0.0, -VR_UI_DIST)
	# laser dot where the pointer touches the screen
	var ds: SphereMesh = SphereMesh.new()
	ds.radius = 0.007
	ds.height = 0.014
	var dm: StandardMaterial3D = StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.albedo_color = Color(0.4, 0.95, 1.0)
	dm.no_depth_test = true
	dm.render_priority = 11
	ds.material = dm
	ui_dot = MeshInstance3D.new()
	ui_dot.mesh = ds
	ui_dot.visible = false
	add_child(ui_dot)


## Casts a ray at the floating screen. Moves the UI mouse there (hover) and returns the hit distance (-1 = miss).
func _ui_ray(o: Vector3, d: Vector3) -> float:
	var was: bool = ui_hit
	ui_hit = false
	var hit_d: float = -1.0
	if ui_sheet != null and ui_sheet.is_visible_in_tree():
		var inv: Transform3D = ui_sheet.global_transform.affine_inverse()
		var lo: Vector3 = inv * o
		var ld: Vector3 = inv.basis * d
		if absf(ld.z) > 0.00001:
			var t: float = -lo.z / ld.z
			if t > 0.0:
				var p: Vector3 = lo + ld * t
				var sz: Vector2 = (ui_sheet.mesh as QuadMesh).size
				var uv: Vector2 = Vector2(p.x / sz.x + 0.5, 0.5 - p.y / sz.y)
				if uv.x >= 0.0 and uv.x <= 1.0 and uv.y >= 0.0 and uv.y <= 1.0:
					ui_hit = true
					var wp: Vector3 = ui_sheet.global_transform * Vector3(p.x, p.y, 0.0)
					hit_d = o.distance_to(wp)
					ui_dot.global_position = wp
					_ui_move(uv * Vector2(VR_UI_SIZE))
	if was and not ui_hit:
		_ui_move(Vector2(-100, -100))   # pointer left the screen: end hover effects
	if ui_dot != null:
		ui_dot.visible = ui_hit and xr_active
	return hit_d


func _ui_move(px: Vector2) -> void:
	if px.distance_to(ui_mouse) < 0.5:
		return
	var mm: InputEventMouseMotion = InputEventMouseMotion.new()
	mm.position = px
	mm.global_position = px
	mm.relative = px - ui_mouse
	mm.button_mask = MOUSE_BUTTON_MASK_LEFT if _ui_down else 0
	ui_mouse = px
	ui_vp.push_input(mm, true)   # true = position is already in screen pixels (no window scaling)


func _ui_button(idx: MouseButton, pressed: bool) -> bool:
	var mb: InputEventMouseButton = InputEventMouseButton.new()
	mb.button_index = idx
	mb.pressed = pressed
	mb.position = ui_mouse
	mb.global_position = ui_mouse
	mb.button_mask = MOUSE_BUTTON_MASK_LEFT if (pressed and idx == MOUSE_BUTTON_LEFT) else 0
	ui_vp.push_input(mb, true)
	return ui_vp.is_input_handled()


## Trigger / click: goes to the UI if the pointer is on a button or panel, otherwise selects in the 3D graph.
func _vr_trigger(pressed: bool, o: Vector3, d: Vector3) -> void:
	if pressed:
		if ui_hit and _ui_button(MOUSE_BUTTON_LEFT, true):
			_ui_down = true
			return
		var hit: Dictionary = _pick(o, d)
		if not hit.is_empty():
			_select(hit)
		elif not demo_running and not quiz_active and not selected.is_empty():
			selected = {}
			_refresh_materials()
			_rebuild_pulses()
			_update_texts()
	elif _ui_down or ui_hit:
		_ui_down = false
		_ui_button(MOUSE_BUTTON_LEFT, false)


func _ui_wheel(up: bool) -> void:
	var b: MouseButton = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
	_ui_button(b, true)
	_ui_button(b, false)


## Every frame in VR: right-controller laser drives the screen and the 3D hover.
func _vr_ui_update(delta: float) -> void:
	if ui_vp == null or xr_right == null:
		return
	var xf: Transform3D = xr_right.global_transform
	var o: Vector3 = xf.origin
	var d: Vector3 = -xf.basis.z.normalized()
	var ray_d: float = _ui_ray(o, d)
	var nid: String = ""
	if not _ui_over_control():
		var h: Dictionary = _pick(o, d)
		nid = "" if h.is_empty() else String(h["id"])
		if not h.is_empty() and ray_d < 0.0:
			ray_d = o.distance_to((h["node"] as Node3D).global_position)
	if nid != hover_id:
		hover_id = nid
		_refresh_materials()
	if vr_ray != null:   # laser stops where it touches the screen
		var L: float = clampf(ray_d if ray_d > 0.0 else 4.0, 0.05, 4.0)
		vr_ray.scale = Vector3(1.0, L / 4.0, 1.0)
		vr_ray.position = Vector3(0.0, 0.0, -L * 0.5)
	_wheel_t -= delta


## Concept names in VR: same on-screen size as on desktop (x VR_LABEL_BOOST), whatever the model scale.
func _vr_fix_labels() -> void:
	var s: float = content.scale.x
	if absf(s - _lbl_scale) < 0.0004:
		return
	_lbl_scale = s
	for n in content.find_children("*", "Label3D", true, false):
		var l: Label3D = n
		if not l.has_meta("vr_px"):
			var base: float = l.pixel_size if l.fixed_size else 0.021 / float(l.font_size)
			l.font_size *= 2           # rendered at double resolution: sharp text in the headset
			l.outline_size *= 2
			l.fixed_size = true
			l.set_meta("vr_px", base * VR_LABEL_BOOST * 0.5)
		l.pixel_size = float(l.get_meta("vr_px")) / maxf(s, 0.001)


func _input(event: InputEvent) -> void:
	if ui_vp == null:
		return
	if event is InputEventKey:
		# a physical keyboard still works: typing goes to the text box on the VR screen
		ui_vp.push_input(event)
		if ui_vp.is_input_handled():
			get_viewport().set_input_as_handled()
	elif preview_vr_ui and not xr_active and event is InputEventMouse:
		var mp: Vector2 = (event as InputEventMouse).position
		var o: Vector3 = camera.project_ray_origin(mp)
		var d: Vector3 = camera.project_ray_normal(mp)
		_ui_ray(o, d)
		if event is InputEventMouseButton:
			var mb: InputEventMouseButton = event
			if mb.button_index == MOUSE_BUTTON_LEFT and (_ui_over_control() or _ui_down):
				_vr_trigger(mb.pressed, o, d)
				get_viewport().set_input_as_handled()
			elif (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN) and _ui_over_control():
				if mb.pressed:
					_ui_wheel(mb.button_index == MOUSE_BUTTON_WHEEL_UP)
				get_viewport().set_input_as_handled()
		elif _ui_over_control():
			get_viewport().set_input_as_handled()


# ───────────────────────── audio ─────────────────────────
var music_player: AudioStreamPlayer
var sfx_select: AudioStream
var sfx_explode: AudioStream
var music_on: bool = true


func _setup_audio() -> void:
	var music: AudioStream = load("res://assets/generated/audio/ambient_music.mp3")
	if music is AudioStreamMP3:
		(music as AudioStreamMP3).loop = true
	music_player = AudioStreamPlayer.new()
	music_player.stream = music
	music_player.volume_db = -14.0
	music_player.autoplay = false
	add_child(music_player)
	music_player.play()
	DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_BOUNDARY, _on_tts_boundary)
	if FileAccess.file_exists("user://narration_lines.json"):   # keep lines from earlier recordings
		var prev: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://narration_lines.json"))
		if prev is Dictionary:
			narr_lines = prev
	narr_player = AudioStreamPlayer.new()
	narr_player.volume_db = 2.0
	add_child(narr_player)
	if ResourceLoader.exists("res://assets/generated/audio/pop_blip.mp3"):
		sfx_pop = load("res://assets/generated/audio/pop_blip.mp3")
	sfx_select = load("res://assets/generated/audio/select_blip.mp3")
	sfx_explode = load("res://assets/generated/audio/explode_whoosh.mp3")


const MUSIC_NORMAL_DB: float = -14.0
const MUSIC_DUCKED_DB: float = -26.0   # music level while the demo narrator speaks (lower number = quieter)


## Lowers the background music smoothly while the narrator speaks, then brings it back.
func _update_music_duck(delta: float) -> void:
	if music_player == null:
		return
	var speaking: bool = (demo_running and demo_voice and (_say_active or _voice_busy())) or (intro != null and intro.visible) or (tts_http != null and _answer_speaking())
	var target: float = MUSIC_DUCKED_DB if speaking else MUSIC_NORMAL_DB
	if intro != null and intro.visible:
		target = -48.0   # the intro has its own sound: app music almost silent
	if voice_rec:
		target = -48.0   # recording a voice question: music almost off so the microphone hears only you
	music_player.volume_db = lerpf(music_player.volume_db, target, 1.0 - exp(-delta * 5.0 if target > -40.0 else -delta * 14.0))


func _toggle_music() -> void:
	music_on = not music_on
	music_player.stream_paused = not music_on
	status_label.text = "Music: " + ("ON" if music_on else "OFF") + "  (M)"


func _play_sfx(stream: AudioStream, db: float = -6.0) -> void:
	if stream == null:
		return
	var p: AudioStreamPlayer = AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = db
	p.finished.connect(p.queue_free)
	add_child(p)
	p.play()


# ───────────────────────── environment extras ─────────────────────────
const SKY_SHADER: String = """
shader_type sky;
uniform vec3 tint : source_color = vec3(0.05, 0.25, 0.8);
uniform vec3 tint2 : source_color = vec3(0.4, 0.1, 0.6);
float hash(vec3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float noise(vec3 x) {
	vec3 i = floor(x); vec3 f = fract(x); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i + vec3(0,0,0)), hash(i + vec3(1,0,0)), f.x), mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
			   mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x), mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}
float fbm(vec3 p) { float v = 0.0; float a = 0.5; for (int i = 0; i < 4; i++) { v += a * noise(p); p *= 2.02; a *= 0.5; } return v; }
void sky() {
	vec3 d = normalize(EYEDIR);
	float t = TIME * 0.012;
	float n = fbm(d * 2.5 + vec3(t, 0.0, -t));
	float n2 = fbm(d * 4.0 + vec3(10.0, 3.0, 7.0) - vec3(0.0, t, 0.0));
	vec3 base = mix(vec3(0.012, 0.016, 0.04), vec3(0.0, 0.0, 0.015), d.y * 0.5 + 0.5);
	vec3 neb = tint * smoothstep(0.42, 0.85, n) * 1.0 + tint2 * smoothstep(0.48, 0.9, n2) * 0.8;
	COLOR = base + neb * (0.45 + 0.55 * smoothstep(-0.7, 0.8, d.y));
}
"""
const GRID_SHADER: String = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
uniform vec3 line_color : source_color = vec3(0.2, 0.6, 1.0);
uniform float cell = 2.0;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 uv = wpos.xz / cell;
	vec2 g = abs(fract(uv - 0.5) - 0.5) / max(fwidth(uv), vec2(0.0001));
	float line = 1.0 - min(min(g.x, g.y), 1.0);
	float d = length(wpos.xz - CAMERA_POSITION_WORLD.xz);
	float fade = 1.0 - smoothstep(cell * 8.0, cell * 45.0, d);
	ALBEDO = line_color;
	ALPHA = line * fade * 0.55;
}
"""
const TOUR_IDS: Array = ["raw_data", "cleaning", "feature_eng", "scaling", "dataset", "xgboost", "cross_val", "overfitting", "hyperparam", "explain", "api", "monitoring", "dashboard"]

var sky_mat: ShaderMaterial
var floor_mesh: MeshInstance3D
var floor_mat: ShaderMaterial
var dust: CPUParticles3D
var sel_light: OmniLight3D
var sky_a: Color = Color(0.05, 0.25, 0.8)
var sky_b: Color = Color(0.4, 0.1, 0.6)
var sky_a_goal: Color = Color(0.05, 0.25, 0.8)
var sky_b_goal: Color = Color(0.4, 0.1, 0.6)
var path_ids: Array = []
var path_edges: Dictionary = {}
var tour_active: bool = false
var tour_idx: int = 0
var tour_timer: float = 0.0
var speak_on: bool = false


func _make_sky() -> void:
	var shader: Shader = Shader.new()
	shader.code = SKY_SHADER
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = shader
	var sky: Sky = Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky


func _make_floor() -> void:
	var shader: Shader = Shader.new()
	shader.code = GRID_SHADER
	floor_mat = ShaderMaterial.new()
	floor_mat.shader = shader
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(500, 500)
	floor_mesh = MeshInstance3D.new()
	floor_mesh.mesh = plane
	floor_mesh.material_override = floor_mat
	floor_mesh.position = Vector3(0, -16, 0)
	floor_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(floor_mesh)


func _make_dust() -> void:
	dust = CPUParticles3D.new()
	dust.amount = 90
	dust.lifetime = 14.0
	dust.preprocess = 14.0
	dust.local_coords = true
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = Vector3(22, 14, 22)
	dust.direction = Vector3.UP
	dust.spread = 180.0
	dust.gravity = Vector3.ZERO
	dust.initial_velocity_min = 0.1
	dust.initial_velocity_max = 0.4
	var sm: SphereMesh = SphereMesh.new()
	sm.radius = 0.035
	sm.height = 0.07
	sm.radial_segments = 6
	sm.rings = 3
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 1.6, 2.2)
	sm.material = m
	dust.mesh = sm
	add_child(dust)


func _make_sel_light() -> void:
	sel_light = OmniLight3D.new()
	sel_light.light_energy = 0.0
	sel_light.omni_range = 8.0
	sel_light.shadow_enabled = false
	add_child(sel_light)


func _update_environment(delta: float) -> void:
	var k: float = 1.0 - exp(-delta * 1.5)
	sky_a = sky_a.lerp(sky_a_goal, k)
	sky_b = sky_b.lerp(sky_b_goal, k)
	sky_mat.set_shader_parameter("tint", Vector3(sky_a.r, sky_a.g, sky_a.b))
	sky_mat.set_shader_parameter("tint2", Vector3(sky_b.r, sky_b.g, sky_b.b))
	dust.position = content.position
	dust.scale = content.scale
	var lk: float = 1.0 - exp(-delta * 6.0)
	if selected.is_empty():
		sel_light.light_energy = lerpf(sel_light.light_energy, 0.0, lk)
	else:
		var node: Node3D = selected["node"]
		sel_light.global_position = node.global_position
		sel_light.light_color = selected["color"]
		sel_light.light_energy = lerpf(sel_light.light_energy, 3.0, lk)
	sel_light.omni_range = 8.0 * content.scale.x


# ───────────────────────── shortest path (graph algorithm) ─────────────────────────
func _bfs_path(a: String, b: String) -> Array:
	var prev: Dictionary = {a: ""}
	var queue: Array = [a]
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		if cur == b:
			break
		for adj in g_adj[cur]:
			var nx: String = adj[0]
			if not prev.has(nx):
				prev[nx] = cur
				queue.append(nx)
	if not prev.has(b):
		return []
	var out: Array = []
	var c: String = b
	while c != "":
		out.push_front(c)
		c = prev[c]
	return out


func _show_path(target: Dictionary) -> void:
	var a: String = selected["id"]
	var b: String = target["id"]
	if a == b:
		return
	var path: Array = _bfs_path(a, b)
	if path.is_empty():
		_show_answer("No connection found between these two concepts.")
		return
	path_ids = path
	path_edges.clear()
	for i in range(path.size() - 1):
		path_edges[str(path[i]) + "|" + str(path[i + 1])] = true
		path_edges[str(path[i + 1]) + "|" + str(path[i])] = true
	highlighted = path.duplicate()
	var names: PackedStringArray = []
	for id in path:
		names.append(String((g_items[id] as Dictionary)["title"]))
	_play_sfx(sfx_select)
	_refresh_materials()
	_rebuild_pulses()
	_show_answer("Shortest path (%d hops):\n%s" % [path.size() - 1, "  ->  ".join(names)])


# ───────────────────────── guided tour ─────────────────────────
func _toggle_tour() -> void:
	if mode != Mode.GRAPH:
		_set_mode(Mode.GRAPH)
	tour_active = not tour_active
	if tour_active:
		tour_idx = 0
		tour_timer = 0.0
		auto_rotate = false
		_tour_step()
	else:
		status_label.text = "Tour stopped"


func _tour_step() -> void:
	var id: String = String(_demo("tour", TOUR_IDS)[tour_idx])
	if not g_items.has(id):
		return
	highlighted.clear()
	_select(g_items[id])
	var desc: String = ""
	for n in graph_data["nodes"]:
		if n["id"] == id:
			desc = n["desc"]
	var text: String = "Guided tour %d/%d - %s: %s" % [tour_idx + 1, (_demo("tour", TOUR_IDS) as Array).size(), (g_items[id] as Dictionary)["title"], desc]
	_show_answer(text)
	_speak(text)
	status_label.text = "Guided tour running - press G to stop"


func _update_tour(delta: float) -> void:
	if not tour_active:
		return
	tour_timer += delta
	if tour_timer < 7.0:
		return
	tour_timer = 0.0
	tour_idx += 1
	if tour_idx >= (_demo("tour", TOUR_IDS) as Array).size():
		tour_active = false
		_show_answer(String(_demo("tour_end", "Tour finished. From raw data to a VR dashboard: that is the whole pipeline.")))
		status_label.text = "Tour finished"
	else:
		_tour_step()


# ───────────────────────── spoken answers ─────────────────────────
func _toggle_voice() -> void:
	if demo_running:
		demo_voice = not demo_voice
		if not demo_voice:
			DisplayServer.tts_stop()
		return
	speak_on = not speak_on
	if not speak_on:
		DisplayServer.tts_stop()
	status_label.text = "Spoken answers: " + ("ON" if speak_on else "OFF") + "  (V)"


func _speak(t: String) -> void:
	if not speak_on:
		return
	var voices: PackedStringArray = DisplayServer.tts_get_voices_for_language("en")
	if voices.is_empty():
		return
	DisplayServer.tts_stop()
	DisplayServer.tts_speak(t, voices[0])


# ═════════════════════════ CALCULATION ENGINE ═════════════════════════
# Real numbers behind the visuals:
#  - a small neural network forward pass (weighted sums, bias, activation, softmax)
#  - PageRank iterations on the knowledge graph
#  - hop-by-hop information spreading (BFS message passing)
const SAMPLE_INPUT: Array = [0.82, 0.10, 0.55, 0.93, 0.31, 0.74, 0.12, 0.66, 0.48, 0.90, 0.05, 0.37, 0.71, 0.25, 0.59, 0.84]
const CLASS_NAMES: Array = ["normal", "drift", "anomaly"]

var net_acts: Array = []     # per layer: PackedFloat32Array of activations
var net_zs: Array = []       # per layer: PackedFloat32Array of pre-activation sums
var net_W: Array = []        # per layer (l>=1): Array of PackedFloat32Array rows
var net_b: Array = []        # per layer: PackedFloat32Array of biases
var net_focus: Array = []    # per layer: index of the most active neuron
var net_act_kind: Array = [] # per layer: "input" | "relu" | "tanh" | "attn" | "softmax"
var calc_net: bool = false
var calc_layer: int = -1
var calc_graph: bool = false
var calc_energy: Dictionary = {}
var calc_scale: Dictionary = {}


func _act_for(layer_name: String) -> String:
	if layer_name.begins_with("Input"):
		return "input"
	if layer_name.begins_with("LSTM"):
		return "tanh"
	if layer_name.begins_with("Attention"):
		return "attn"
	if layer_name.begins_with("Output"):
		return "softmax"
	return "relu"


func _softmax(z: PackedFloat32Array) -> PackedFloat32Array:
	var mx: float = -INF
	for v in z:
		mx = maxf(mx, v)
	var out: PackedFloat32Array = PackedFloat32Array()
	var total: float = 0.0
	for v in z:
		var e: float = exp(v - mx)
		out.append(e)
		total += e
	for i in out.size():
		out[i] = out[i] / total
	return out


func _argmax(a: PackedFloat32Array) -> int:
	var best: int = 0
	for i in a.size():
		if a[i] > a[best]:
			best = i
	return best


## Runs a real forward pass with fixed (illustrative, untrained) random weights.
func _compute_network() -> void:
	net_acts.clear()
	net_zs.clear()
	net_W.clear()
	net_b.clear()
	net_focus.clear()
	net_act_kind.clear()
	var layers: Array = net_data["layers"]
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 2024
	var prev: PackedFloat32Array = PackedFloat32Array()
	for l in layers.size():
		var units: int = int(layers[l]["units"])
		var kind: String = String(layers[l].get("act", _act_for(String(layers[l]["name"]))))
		net_act_kind.append(kind)
		if l == 0:
			var a0: PackedFloat32Array = PackedFloat32Array()
			for i in units:
				a0.append(float(SAMPLE_INPUT[i % SAMPLE_INPUT.size()]))
			net_acts.append(a0)
			net_zs.append(a0)
			net_W.append([])
			net_b.append(PackedFloat32Array())
			net_focus.append(_argmax(a0))
			prev = a0
			continue
		var rows: Array = []
		var bias: PackedFloat32Array = PackedFloat32Array()
		var z: PackedFloat32Array = PackedFloat32Array()
		var wscale: float = sqrt(2.0 / float(prev.size()))
		for j in units:
			var row: PackedFloat32Array = PackedFloat32Array()
			var s: float = 0.0
			for i in prev.size():
				var w: float = rng.randfn(0.0, wscale)
				row.append(w)
				s += w * prev[i]
			var b: float = rng.randf_range(-0.1, 0.1)
			bias.append(b)
			z.append(s + b)
			rows.append(row)
		if kind == "softmax" and net_data.has("favor"):
			var fav: int = int(net_data["favor"])
			z[fav] += 1.5
			bias[fav] += 1.5
		var a: PackedFloat32Array = PackedFloat32Array()
		if kind == "relu":
			for v in z:
				a.append(maxf(0.0, v))
		elif kind == "tanh":
			for v in z:
				a.append(tanh(v))
		elif kind == "attn":
			var sm: PackedFloat32Array = _softmax(z)
			for v in sm:
				a.append(v * float(units))
		else:
			a = _softmax(z)
		net_acts.append(a)
		net_zs.append(z)
		net_W.append(rows)
		net_b.append(bias)
		net_focus.append(_argmax(a))
		prev = a


func _neuron_equation(l: int) -> String:
	var j: int = net_focus[l]
	var prev: PackedFloat32Array = net_acts[l - 1]
	var row: PackedFloat32Array = (net_W[l] as Array)[j]
	var idx: Array = range(prev.size())
	idx.sort_custom(func(p1: int, p2: int) -> bool: return absf(row[p1] * prev[p1]) > absf(row[p2] * prev[p2]))
	var terms: PackedStringArray = []
	var shown: float = 0.0
	for k in mini(3, idx.size()):
		var i: int = idx[k]
		terms.append("(%+.2f x %.2f)" % [row[i], prev[i]])
		shown += row[i] * prev[i]
	var z: float = (net_zs[l] as PackedFloat32Array)[j]
	var b: float = (net_b[l] as PackedFloat32Array)[j]
	var rest: float = z - b - shown
	return "z = %s + [%d other terms = %+.2f] + bias %+.2f  =  %.2f" % [" + ".join(terms), prev.size() - 3, rest, b, z]


func _layer_caption(l: int) -> String:
	var layers: Array = net_data["layers"]
	var L: Dictionary = layers[l]
	var kind: String = net_act_kind[l]
	var a: PackedFloat32Array = net_acts[l]
	if l == 0:
		var vals: PackedStringArray = []
		for i in 6:
			vals.append("%.2f" % a[i])
		return "Shape %s  (batch = samples processed at once).  %s\nSample values (bigger = brighter sphere):  %s ..." % [L["shape"], _short(String(L["desc"]), 100), ", ".join(vals)]
	var j: int = net_focus[l]
	if kind == "softmax":
		var parts: PackedStringArray = []
		for i in a.size():
			parts.append("%s %.0f%%" % [_classes()[i], a[i] * 100.0])
		return "%s\n%s  ->  %s (%.0f%%).  Illustrative weights: this shows the mechanics." % [_neuron_equation(l), " | ".join(parts), String(_classes()[j]).to_upper(), a[j] * 100.0]
	var act_text: String = "ReLU (max(0, z))"
	if kind == "tanh":
		act_text = "tanh"
	elif kind == "attn":
		act_text = "softmax attention weights"
	return "Weighted sum of all previous outputs + bias, then %s.   (%d parameters)\nNeuron #%d:  %s   ->   a = %.2f" % [act_text, int(L["params"]), j, _neuron_equation(l), a[j]]


## Colours/sizes every neuron by its REAL activation value up to the layer being explained.
func _apply_activation_visuals() -> void:
	for l in n_layers.size():
		var neurons: Array = n_neurons[l]
		var mats: Array = (n_layers[l] as Dictionary)["mats"]
		var a: PackedFloat32Array = net_acts[l]
		var maxa: float = 0.0001
		for v in a:
			maxa = maxf(maxa, absf(v))
		for j in neurons.size():
			var node: Node3D = neurons[j]
			var m: StandardMaterial3D = mats[j]
			if not calc_net:
				m.emission_energy_multiplier = 0.35
				node.scale = Vector3.ONE
			elif l <= calc_layer:
				var nv: float = absf(a[j]) / maxa
				m.emission_energy_multiplier = 0.15 + 3.2 * nv
				node.scale = Vector3.ONE * (0.55 + 1.0 * nv)
				if l == calc_layer and j == int(net_focus[l]):
					m.emission_energy_multiplier = 6.0
					node.scale = Vector3.ONE * 2.1
			else:
				m.emission_energy_multiplier = 0.1
				node.scale = Vector3.ONE * 0.55


func _animate_net_pulses() -> void:
	for p in pulses:
		if not p.has("conn"):
			continue
		var c: Array = n_conns[p["conn"]]
		var li: int = c[0]
		var la: Dictionary = n_layers[li]
		var lb: Dictionary = n_layers[li + 1]
		var a: Vector3 = (la["node"] as Node3D).position + ((n_neurons[li] as Array)[c[1]] as Node3D).position
		var b: Vector3 = (lb["node"] as Node3D).position + ((n_neurons[li + 1] as Array)[c[2]] as Node3D).position
		var t: float = fmod(time_s * 0.8 + float(p["off"]), 1.0)
		(p["node"] as Node3D).position = a.lerp(b, t)


func _reset_calc_state() -> void:
	calc_graph = false
	calc_net = false
	calc_layer = -1
	calc_energy.clear()
	calc_scale.clear()


func _clear_calc() -> void:
	var had_net: bool = calc_net
	_reset_calc_state()
	path_edges.clear()
	if had_net and mode == Mode.NETWORK and not n_layers.is_empty():
		_apply_activation_visuals()
	forward_pass = _forward_pass_saved
	_refresh_materials()
	_rebuild_pulses()


# ── graph calculations ──
func _node_desc(id: String) -> String:
	for n in graph_data["nodes"]:
		if n["id"] == id:
			return String(n["desc"])
	return ""


func _hop_levels(src: String) -> Dictionary:
	var lv: Dictionary = {src: 0}
	var queue: Array = [src]
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		for adj in g_adj[cur]:
			var nx: String = adj[0]
			if not lv.has(nx):
				lv[nx] = int(lv[cur]) + 1
				queue.append(nx)
	return lv


func _show_hop(lv: Dictionary, h: int) -> void:
	calc_graph = true
	calc_energy.clear()
	calc_scale.clear()
	path_edges.clear()
	for id in g_items.keys():
		if lv.has(id) and int(lv[id]) <= h:
			var newest: bool = int(lv[id]) == h
			calc_energy[id] = 3.2 if newest else 0.15   # earlier hops fade to grey so only the new ones stand out
			calc_scale[id] = 1.35 if newest else 0.85
		else:
			calc_energy[id] = 0.08
			calc_scale[id] = 0.7
	for e in g_edges:
		if lv.has(e[0]) and lv.has(e[1]) and int(lv[e[0]]) <= h and int(lv[e[1]]) <= h and absi(int(lv[e[0]]) - int(lv[e[1]])) == 1 and maxi(int(lv[e[0]]), int(lv[e[1]])) == h:
			path_edges[str(e[0]) + "|" + str(e[1])] = true
			path_edges[str(e[1]) + "|" + str(e[0])] = true
	_refresh_materials()
	_rebuild_pulses()


func _pagerank(iters: int) -> Array:
	var ids: Array = g_items.keys()
	var n: int = ids.size()
	var out_deg: Dictionary = {}
	for id in ids:
		out_deg[id] = 0
	for e in g_edges:
		out_deg[e[0]] = int(out_deg[e[0]]) + 1
	var pr: Dictionary = {}
	for id in ids:
		pr[id] = 1.0 / float(n)
	var history: Array = [pr.duplicate()]
	for it in iters:
		var dangling: float = 0.0
		for id in ids:
			if int(out_deg[id]) == 0:
				dangling += float(pr[id])
		var nxt: Dictionary = {}
		for id in ids:
			nxt[id] = 0.15 / float(n) + 0.85 * dangling / float(n)
		for e in g_edges:
			nxt[e[1]] = float(nxt[e[1]]) + 0.85 * float(pr[e[0]]) / float(out_deg[e[0]])
		pr = nxt
		history.append(pr.duplicate())
	return history


func _show_pr(pr: Dictionary) -> void:
	var mx: float = 0.0001
	for v in pr.values():
		mx = maxf(mx, float(v))
	calc_graph = true
	calc_energy.clear()
	calc_scale.clear()
	for id in pr.keys():
		var r: float = float(pr[id]) / mx
		calc_energy[id] = 0.2 + 3.0 * r
		calc_scale[id] = 0.6 + 1.2 * r
	_refresh_materials()


func _top_pr(pr: Dictionary, n: int) -> String:
	var arr: Array = []
	for id in pr.keys():
		arr.append([float(pr[id]), id])
	arr.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var parts: PackedStringArray = []
	for i in mini(n, arr.size()):
		parts.append("%s %.3f" % [(g_items[arr[i][1]] as Dictionary)["title"], arr[i][0]])
	return "   |   ".join(parts)


# ═════════════════════════ AUTOMATIC DEMO ═════════════════════════
var left_panel: PanelContainer
var bottom_box: VBoxContainer
var demo_panel: PanelContainer
var demo_title: Label
var demo_body: Label
var demo_running: bool = false
var demo_skip: bool = false
var demo_id: int = 0
var demo_cam: bool = false
var demo_yaw: float = 0.5
var demo_pitch: float = 0.3
var cam_override: bool = false
var cam_focus_goal: Vector3 = Vector3.ZERO
var _forward_pass_saved: bool = true


func _build_demo_ui(layer: CanvasLayer) -> void:
	demo_panel = PanelContainer.new()
	# compact caption, centred at the very bottom; grows upwards only as much as the text needs
	demo_panel.custom_minimum_size = Vector2(800, 0)   # position is set by _place_caption() after every text change
	var sb: StyleBoxFlat = _panel_style()
	sb.bg_color = Color(0.03, 0.05, 0.1, 0.88)
	sb.set_content_margin_all(10)
	sb.set_corner_radius_all(10)
	demo_panel.add_theme_stylebox_override("panel", sb)
	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	demo_panel.add_child(vb)
	demo_title = Label.new()
	demo_title.add_theme_font_size_override("font_size", 17)
	demo_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	vb.add_child(demo_title)
	demo_body = Label.new()
	demo_body.add_theme_font_size_override("font_size", 14)
	demo_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	demo_body.custom_minimum_size = Vector2(780, 0)
	vb.add_child(demo_body)
	# quiz answer options (2 x 2 buttons) - only shown during the quiz
	quiz_opts = GridContainer.new()
	quiz_opts.columns = 2
	quiz_opts.add_theme_constant_override("h_separation", 8)
	quiz_opts.add_theme_constant_override("v_separation", 6)
	quiz_opts.visible = false
	vb.add_child(quiz_opts)
	quiz_fb = Label.new()
	quiz_fb.add_theme_font_size_override("font_size", 14)
	quiz_fb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	quiz_fb.custom_minimum_size = Vector2(780, 0)
	quiz_fb.visible = false
	vb.add_child(quiz_fb)
	# feedback card shown after an answer: why + example + related concepts + Next button
	quiz_card = VBoxContainer.new()
	quiz_card.add_theme_constant_override("separation", 8)
	quiz_card.visible = false
	vb.add_child(quiz_card)
	quiz_why = _quiz_card_label(17, Color(0.95, 0.97, 1.0))
	# example: a small quote box instead of another line of text
	quiz_ex_box = PanelContainer.new()
	var exs: StyleBoxFlat = StyleBoxFlat.new()
	exs.bg_color = Color(0.12, 0.18, 0.3, 0.7)
	exs.border_color = Color(0.4, 0.6, 1.0, 0.8)
	exs.border_width_left = 4
	exs.set_corner_radius_all(6)
	exs.content_margin_left = 12
	exs.content_margin_right = 12
	exs.content_margin_top = 5
	exs.content_margin_bottom = 5
	quiz_ex_box.add_theme_stylebox_override("panel", exs)
	quiz_card.add_child(quiz_ex_box)
	quiz_ex = Label.new()
	quiz_ex.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	quiz_ex.custom_minimum_size = Vector2(740, 0)
	quiz_ex.add_theme_font_size_override("font_size", 14)
	quiz_ex.add_theme_color_override("font_color", Color(0.8, 0.88, 1.0))
	quiz_ex_box.add_child(quiz_ex)
	# related concepts: coloured chips (same colours as in the 3D graph)
	quiz_rel_box = HBoxContainer.new()
	quiz_rel_box.add_theme_constant_override("separation", 6)
	quiz_card.add_child(quiz_rel_box)
	var nrow: HBoxContainer = HBoxContainer.new()
	nrow.alignment = BoxContainer.ALIGNMENT_END
	nrow.add_theme_constant_override("separation", 10)
	quiz_card.add_child(nrow)
	var rp: Button = Button.new()
	rp.text = "🔊  Listen again"
	rp.focus_mode = Control.FOCUS_NONE
	rp.custom_minimum_size = Vector2(150, 38)
	rp.add_theme_font_size_override("font_size", 14)
	rp.add_theme_stylebox_override("normal", _quiz_btn_style(Color(0.4, 0.55, 0.8), 0.18))
	rp.add_theme_stylebox_override("hover", _quiz_btn_style(Color(0.5, 0.7, 1.0), 0.35))
	rp.add_theme_stylebox_override("pressed", _quiz_btn_style(Color(0.4, 0.55, 0.8), 0.18))
	rp.tooltip_text = "Hear the explanation again  (V turns the voice on/off)"
	rp.pressed.connect(func() -> void:
		var was: bool = demo_voice
		demo_voice = true
		_say_quiz(_quiz_last_line)
		demo_voice = was)
	nrow.add_child(rp)
	quiz_next_btn = Button.new()
	quiz_next_btn.text = "Next question  ➜"
	quiz_next_btn.focus_mode = Control.FOCUS_NONE
	quiz_next_btn.custom_minimum_size = Vector2(200, 38)
	quiz_next_btn.add_theme_font_size_override("font_size", 15)
	var nsb: StyleBoxFlat = _quiz_btn_style(Color(0.25, 0.6, 1.0), 0.75)
	quiz_next_btn.add_theme_stylebox_override("normal", nsb)
	quiz_next_btn.add_theme_stylebox_override("hover", _quiz_btn_style(Color(0.4, 0.72, 1.0), 0.95))
	quiz_next_btn.add_theme_stylebox_override("pressed", nsb)
	quiz_next_btn.pressed.connect(func() -> void: quiz_next.emit())
	nrow.add_child(quiz_next_btn)
	var hint: Label = Label.new()
	demo_hint = hint
	hint.add_theme_font_size_override("font_size", 11)
	hint.text = "AUTO DEMO   -   Space: next step   |   D or Esc: stop   |   V: narration on/off   |   drag the mouse to look around"
	hint.modulate = Color(0.6, 0.75, 0.95)
	vb.add_child(hint)
	demo_panel.visible = false
	layer.add_child(demo_panel)


## Keeps the caption bar fully on screen: centred, bottom edge 14 px above the window bottom, growing upwards.
func _place_caption() -> void:
	demo_panel.reset_size()
	await get_tree().process_frame
	var vs: Vector2 = _ui_vp().get_visible_rect().size
	demo_panel.position = Vector2((vs.x - demo_panel.size.x) * 0.5, vs.y - demo_panel.size.y - 14.0)


var _re_num: RegEx


func _strip_no(t: String) -> String:
	if _re_num == null:
		_re_num = RegEx.new()
		_re_num.compile("^\\d+/\\d+\\s+")
	return _re_num.sub(t, "")


func _caption(title: String, body: String) -> void:
	title = _strip_no(title)
	demo_title.text = title
	demo_body.text = body
	_place_caption()
	_answer_text = title + "\n" + body
	if vr_label:
		vr_label.text = title + "\n\n" + body


## Short spoken narration for the demo (not the full caption text).
var demo_voice: bool = true
var _say_active: bool = false
var _say_start_ms: int = 0


func _short(s: String, n: int) -> String:
	var one: String = s.replace("\n", "  ")
	if one.length() <= n:
		return one
	return one.substr(0, n).strip_edges() + " ..."


func _centroid(ids: Array) -> Vector3:
	var c: Vector3 = Vector3.ZERO
	var n: int = 0
	for nid in ids:
		if g_items.has(nid):
			c += ((g_items[nid] as Dictionary)["node"] as Node3D).position
			n += 1
	return c / float(maxi(n, 1))


func _title_of(id: String) -> String:
	return String((g_items[id] as Dictionary)["title"])


## "A, B and C" (max n names) - for captions and speech.
func _names(ids: Array, _max_names: int = 99) -> String:
	var parts: PackedStringArray = []
	for i in ids.size():   # always spell out every name (no "and 5 more")
		parts.append(_title_of(String(ids[i])))
	var extra: int = ids.size() - parts.size()
	if parts.is_empty():
		return ""
	if parts.size() == 1:
		return parts[0]
	var s: String = ", ".join(parts.slice(0, parts.size() - 1)) + " and " + parts[parts.size() - 1]
	if extra > 0:
		s += " and %d more" % extra
	return s


## Spoken form: makes abbreviations pronounceable.
func _spoken(s: String) -> String:
	return s.replace("VR", "V R").replace("LSTM", "L S T M").replace("API", "A P I").replace("PCA", "P C A").replace("LLM", "L L M").replace("GraphRAG", "Graph RAG").replace("K-Means", "K means").replace("XR", "X R").replace("RLHF", "R L H F").replace("DPO", "D P O").replace("GPU", "G P U")


## Narration: uses a pre-recorded natural voice file (assets/narration/<id>.mp3) when it exists,
## otherwise falls back to the system voice. Every line spoken is also recorded to
## user://narration_lines.json so tools/make_narration.py can create the voice files.
var narr_player: AudioStreamPlayer
var narr_lines: Dictionary = {}
var narr_record: bool = false   # N key: run the whole tour instantly, only collecting the spoken lines
var narr_words: Array = []      # exact word timings of the current narration line: [{"t": seconds, "w": word}]
var narr_cursor: int = 0
var narr_serial: int = 0
var narr_file_mode: bool = false


func _narr_key(t: String) -> String:
	return t.md5_text().substr(0, 12)


func _stop_voice() -> void:
	if narr_player:
		narr_player.stop()
	if tts_http != null:
		_stop_answer_voice()
	DisplayServer.tts_stop()


func _voice_busy() -> bool:
	if narr_file_mode:
		return narr_player != null and narr_player.playing
	return DisplayServer.tts_is_speaking()


func _say(t: String) -> void:
	if not demo_voice or not demo_running:
		return
	var key: String = _narr_key(t)
	if not narr_lines.has(key):
		narr_lines[key] = t
		var f: FileAccess = FileAccess.open("user://narration_lines.json", FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(narr_lines, "  "))
	if narr_record:
		return
	_say_active = true
	_say_start_ms = Time.get_ticks_msec()
	_stop_voice()
	var path: String = "res://assets/narration/%s.mp3" % key
	narr_serial += 1
	narr_words = []
	narr_cursor = 0
	tts_text = t
	tts_cursor = 0
	tts_pending.clear()
	if narr_player and ResourceLoader.exists(path):
		narr_file_mode = true
		tts_text = ""
		var jpath: String = "res://assets/narration/%s.json" % key
		if ResourceLoader.exists(jpath):
			var jr: Resource = load(jpath)
			if jr is JSON and jr.data is Array:
				narr_words = jr.data
		narr_player.stream = load(path)
		narr_player.play()
		return
	narr_file_mode = false
	var voices: PackedStringArray = DisplayServer.tts_get_voices_for_language("en")
	if voices.is_empty():
		_say_active = false
		return
	DisplayServer.tts_speak(t, voices[0], 85, 1.0, 1.0)


## Quiz voice: same natural voice files as the tour, but works outside the tour.
## The exact sentences are built by _quiz_lines() so tools/make_quiz_voice.py can pre-generate them.
const QUIZ_WRONG_LINE: String = "Not quite. Have another look, and try again."
var _quiz_last_line: String = ""


func _say_quiz(t: String) -> void:
	_quiz_last_line = t
	if not demo_voice or t == "":
		return
	_stop_voice()
	var path: String = "res://assets/narration/%s.mp3" % _narr_key(t)
	if narr_player and ResourceLoader.exists(path):
		narr_file_mode = true
		narr_player.stream = load(path)
		narr_player.play()
		return
	narr_file_mode = false
	var voices: PackedStringArray = DisplayServer.tts_get_voices_for_language("en")
	if not voices.is_empty():
		DisplayServer.tts_speak(t, voices[0], 85, 1.0, 1.0)


## The spoken sentences for one question. Keep in sync with tools/make_quiz_voice.py.
func _quiz_lines(q: Dictionary) -> Dictionary:
	var say: String = String(q.get("say", q.get("why", "")))
	var nm: String = String(q.get("say_name", ""))
	return {
		"question": String(q["q"]),
		"correct": "Correct! " + say,
		"second": "Yes, that's it. " + say,
		"reveal": ("The answer is " + nm + ". " + say) if nm != "" else say,
	}


func _layer_say(l: int) -> String:
	var kind: String = net_act_kind[l]
	var a: PackedFloat32Array = net_acts[l]
	var custom: String = String((net_data["layers"] as Array)[l].get("say", ""))
	if custom != "" and kind != "softmax":
		return custom
	if l == 0:
		return "The input. The shape is batch, sixty, eight. Batch means how many samples the network processes at the same time. Sixty is the number of time steps, and eight is the number of features at each step. Here we show sixteen values of one sample."
	if kind == "softmax":
		return "Finally, softmax turns the scores into probabilities. The network predicts %s, with %.0f percent." % [_classes()[net_focus[l]], a[net_focus[l]] * 100.0]
	if kind == "tanh":
		return "The L S T M layer remembers patterns over time. Each neuron sums its weighted inputs, then applies tanh."
	if kind == "attn":
		return "The attention layer decides which parts of the signal matter most."
	if l == net_acts.size() - 2:
		return "A dense layer combines everything learned so far, again with a weighted sum and re lu."
	if l == 1:
		return "The first convolution layer turns eight features into thirty two learned features per time step. Each neuron computes a weighted sum, adds a bias, and applies re lu. Brighter means stronger."
	return "A convolution layer. Each neuron computes a weighted sum of the previous layer, adds a bias, and applies re lu. Brighter means a stronger activation."


## Focus: only these concepts keep their colour; everything else goes grey and small.
func _set_focus(ids: Array) -> void:
	focus_ids = ids.duplicate()
	for it in items:
		it.erase("poplabel")
	_refresh_materials()
	_rebuild_pulses()


## Makes one concept "pop" (grow, glow, show its name) with a small pop sound.
func _pop(id: String) -> void:
	if not g_items.has(id):
		return
	var it: Dictionary = g_items[id]
	it["pop"] = 1.0
	it["poplabel"] = true
	_play_sfx(sfx_pop, -12.0)
	_refresh_materials()


## Pops each concept at about the moment its name is spoken (estimated from the word count).
var tts_text: String = ""
var tts_cursor: int = 0
var tts_pending: Array = []


## Called by the system voice at the start of every spoken word (pos = character index in the text).
func _on_tts_boundary(pos: int, _utterance_id: int = 0) -> void:   # Godot passes (char index, utterance id)
	if not demo_running or tts_pending.is_empty():
		return
	var keep: Array = []
	for p in tts_pending:
		if int(p["serial"]) != narr_serial:
			continue
		if pos >= int(p["pos"]):
			_pop(String(p["id"]))
		else:
			keep.append(p)
	tts_pending = keep


func _norm(s: String) -> String:
	var out: String = ""
	for ch in s.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
	return out


func _pop_spoken(prefix: String, ids: Array) -> void:
	if narr_record:
		return
	var my: int = demo_id
	var serial: int = narr_serial
	await get_tree().process_frame   # the matching _say() call has started by now
	if not demo_running or demo_id != my or serial != narr_serial:
		return
	# EXACT mode: the narration file has word timings -> pop when the name is really spoken
	if narr_file_mode and not narr_words.is_empty():
		var start: int = maxi(narr_cursor, prefix.split(" ", false).size() - 3)
		for nid in ids:
			var toks: Array = []
			for part in _spoken(_title_of(String(nid))).split(" ", false):
				var nt: String = _norm(part)
				if nt != "":
					toks.append(nt)
			var span: int = toks.size()
			var found: int = -1
			for wi in range(start, narr_words.size()):
				var all_ok: bool = span > 0
				for ti in span:
					if wi + ti >= narr_words.size() or _norm(str(narr_words[wi + ti]["w"])) != toks[ti]:
						all_ok = false
						break
				if all_ok:
					found = wi
					break
			if found < 0:
				continue
			var t_pop: float = float(narr_words[found]["t"])
			narr_cursor = found + span
			start = found + span
			while true:
				if not demo_running or demo_id != my or serial != narr_serial or not narr_player.playing:
					return
				var pos: float = narr_player.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()
				if pos >= t_pop - 0.05:
					break
				await get_tree().process_frame
			_pop(String(nid))
		return
	# SYSTEM VOICE: Windows reports the character position of every word it speaks -> pop on that
	if not narr_file_mode and tts_text != "":
		for nid in ids:
			var title: String = _spoken(_title_of(String(nid)))
			var idx: int = tts_text.findn(title, maxi(tts_cursor, prefix.length() - 10))
			if idx < 0:
				continue
			tts_cursor = idx + title.length()
			tts_pending.append({"pos": idx, "id": String(nid), "serial": serial})
		return
	# LAST RESORT (no timing information at all): estimate from the word count
	var wait: float = float(prefix.split(" ", false).size()) / 1.8 + 0.4
	for nid in ids:
		await get_tree().create_timer(wait).timeout
		if not demo_running or demo_id != my:
			return
		_pop(String(nid))
		wait = float(_title_of(String(nid)).split(" ", false).size()) / 2.4 + 0.25


## Frames a set of graph nodes: looks at their centre from OUTSIDE the graph, and picks the distance
## so that exactly these nodes fill the view (closer for few/near nodes, farther for spread-out ones).
func _frame(ids: Array, min_d: float = 6.0) -> void:
	var c: Vector3 = _centroid(ids)
	var r: float = 0.0
	for nid in ids:
		if g_items.has(nid):
			r = maxf(r, (((g_items[nid] as Dictionary)["node"] as Node3D).position - c).length())
	dist_goal = maxf(min_d, r * 1.32 + 3.4)
	cam_override = true
	cam_focus_goal = c + Vector3(0.0, dist_goal * 0.045, 0.0)   # look slightly above the subject -> it sits lower, clear of the top edge
	if Vector2(c.x, c.z).length() > 2.0:
		demo_yaw = atan2(c.x, c.z)
	demo_pitch = 0.3
	demo_cam = true


func _cam(focus: Vector3, d: float, yaw_g: float, pitch_g: float) -> void:
	cam_override = true
	cam_focus_goal = focus + Vector3(0.0, d * 0.03, 0.0)   # keep the subject a touch below centre, clear of top labels
	dist_goal = d * graph_scale if (mode == Mode.GRAPH and d >= 9.0) else d
	demo_yaw = yaw_g
	demo_pitch = pitch_g
	demo_cam = true


## Waits at least `sec` seconds, AND until the narration of this step has finished speaking.
func _dw(sec: float, my_id: int) -> bool:
	if narr_record:
		await get_tree().process_frame
		return demo_running and demo_id == my_id
	var t: float = 0.0
	while t < sec:
		await get_tree().process_frame
		if not demo_running or demo_id != my_id:
			return false
		if demo_skip:
			demo_skip = false
			_stop_voice()
			return true
		t += get_process_delta_time()
	# let the voice finish its sentence before moving on (max 20 s extra)
	var extra: float = 0.0
	while demo_voice and _say_active and extra < 20.0:
		await get_tree().process_frame
		if not demo_running or demo_id != my_id:
			return false
		if demo_skip:
			demo_skip = false
			_stop_voice()
			return true
		extra += get_process_delta_time()
		var since_ms: int = Time.get_ticks_msec() - _say_start_ms
		if since_ms > 800 and not _voice_busy():
			break
	_say_active = false
	if demo_running and demo_id == my_id:
		# short breathing pause between steps
		await get_tree().create_timer(0.6).timeout
	return demo_running and demo_id == my_id


# ═════════════════════════ LEARNING QUIZ ═════════════════════════
# The learner answers by SELECTING the matching concept in the graph (mouse click or VR trigger).
const QUIZ_PATH: String = "res://data/ds_quiz.json"
var quiz_active: bool = false
var quiz_busy: bool = false
var quiz_i: int = 0
var quiz_score: int = 0
var quiz_tries: int = 0
var quiz_list: Array = []
var demo_hint: Label
var quiz_opts: GridContainer
var quiz_fb: Label
var quiz_btns: Dictionary = {}   # concept id -> Button
var quiz_card: VBoxContainer
var quiz_why: Label
var quiz_ex: Label
var quiz_ex_box: PanelContainer
var quiz_rel_box: HBoxContainer
var quiz_next_btn: Button
var quiz_waiting: bool = false
var quiz_streak: int = 0
signal quiz_next


func _quiz_card_label(fs: int, col: Color) -> Label:
	var l: Label = Label.new()
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(780, 0)
	quiz_card.add_child(l)
	return l


## Fills the feedback card and waits until the learner presses Next (button, Enter or Space).
func _quiz_explain(q: Dictionary, right: String, last: bool) -> void:
	var why: String = String(q.get("why", _brief(right)))
	var ex: String = String(q.get("example", ""))
	quiz_why.text = why
	quiz_ex.text = ("e.g.   " + ex) if ex != "" else ""
	quiz_ex_box.visible = ex != ""
	# light up the concepts it is connected to, so the answer is seen in context
	var rel: Array = []
	for adj in g_adj.get(right, []):
		var oid: String = String(adj[0])
		if g_items.has(oid) and not rel.has(oid) and rel.size() < 4:
			rel.append(oid)
	highlighted = [right] + rel
	for oid in rel:
		(g_items[oid] as Dictionary)["poplabel"] = true
	_refresh_materials()
	for c in quiz_rel_box.get_children():
		quiz_rel_box.remove_child(c)
		c.queue_free()
	if not rel.is_empty():
		var lk: Label = Label.new()
		lk.text = "linked:"
		lk.add_theme_font_size_override("font_size", 13)
		lk.add_theme_color_override("font_color", Color(0.6, 0.72, 0.9))
		quiz_rel_box.add_child(lk)
	for oid in rel:
		var col: Color = (g_items[oid] as Dictionary)["color"]
		var chip: Label = Label.new()
		chip.text = "●  " + _title_of(String(oid))
		chip.add_theme_font_size_override("font_size", 13)
		chip.add_theme_color_override("font_color", col.lightened(0.45))
		var cs: StyleBoxFlat = StyleBoxFlat.new()
		cs.bg_color = Color(col.r, col.g, col.b, 0.18)
		cs.border_color = Color(col.r, col.g, col.b, 0.6)
		cs.set_border_width_all(1)
		cs.set_corner_radius_all(12)
		cs.content_margin_left = 10
		cs.content_margin_right = 10
		cs.content_margin_top = 3
		cs.content_margin_bottom = 3
		chip.add_theme_stylebox_override("normal", cs)
		quiz_rel_box.add_child(chip)
	quiz_rel_box.visible = not rel.is_empty()
	quiz_next_btn.text = "See my result  ➜" if last else "Next question  ➜"
	quiz_card.visible = true
	demo_hint.text = "Read the explanation, then press  Next  (or Enter / Space)   |   End quiz: stop"
	_place_caption()
	quiz_waiting = true
	await quiz_next
	quiz_waiting = false
	quiz_card.visible = false


## One short sentence about a concept, for quiz feedback.
func _brief(id: String, n: int = 120) -> String:
	var d: String = _node_desc(id).replace("\n", " ").strip_edges()
	var cut: int = d.find(". ")
	if cut > 0 and cut < n:
		return d.substr(0, cut + 1)
	return _short(d, n)


## The correct answer plus 3 believable distractors (same category first), shuffled.
func _quiz_choices(right: String) -> Array:
	var cat: String = String((g_items[right] as Dictionary)["cat"])
	var same: Array = []
	var other: Array = []
	for it in items:
		var id: String = String(it["id"])
		if id == right:
			continue
		if String(it["cat"]) == cat:
			same.append(id)
		else:
			other.append(id)
	same.shuffle()
	other.shuffle()
	var picks: Array = [right]
	for id in same.slice(0, 2) + other:
		if picks.size() >= 4:
			break
		picks.append(id)
	picks.shuffle()
	return picks


func _quiz_btn_style(col: Color, fill: float) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(col.r, col.g, col.b, fill)
	sb.border_color = col
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	return sb


func _quiz_paint(id: String, col: Color, fill: float) -> void:
	if not quiz_btns.has(id):
		return
	var b: Button = quiz_btns[id]
	for st in ["normal", "hover", "pressed", "disabled"]:
		b.add_theme_stylebox_override(st, _quiz_btn_style(col, fill))
	b.add_theme_color_override("font_disabled_color", Color.WHITE)


func _quiz_build_options(right: String) -> void:
	for c in quiz_opts.get_children():
		quiz_opts.remove_child(c)   # remove now, so the panel measures only the new 4 buttons
		c.queue_free()
	quiz_btns.clear()
	var letters: String = "ABCD"
	var choices: Array = _quiz_choices(right)
	for i in choices.size():
		var id: String = choices[i]
		var b: Button = Button.new()
		b.text = "%s   %s" % [letters[i], _title_of(id)]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(386, 38)
		b.add_theme_font_size_override("font_size", 15)
		b.mouse_entered.connect(func() -> void:
			if not quiz_busy:
				hover_id = id
				_refresh_materials())
		b.pressed.connect(func() -> void:
			if quiz_active and not quiz_busy and g_items.has(id):
				_quiz_answer(g_items[id]))
		quiz_opts.add_child(b)
		quiz_btns[id] = b
		_quiz_paint(id, Color(0.35, 0.55, 0.85), 0.18)


func _quiz_lock(on: bool) -> void:
	for b in quiz_btns.values():
		(b as Button).disabled = on


## Lights up one concept in 3D: glow, name, pop, and the camera glides to it.
func _quiz_spotlight(id: String) -> void:
	highlighted = [id]
	selected = {}
	_pop(id)
	# glide to it, keeping it in the upper half of the screen (the answer panel covers the bottom)
	var c: Vector3 = ((g_items[id] as Dictionary)["node"] as Node3D).position
	cam_override = true
	dist_goal = 12.0
	cam_focus_goal = c + Vector3(0.0, -2.6, 0.0)
	if Vector2(c.x, c.z).length() > 2.0:
		demo_yaw = atan2(c.x, c.z)
	demo_pitch = 0.22
	demo_cam = true
	_refresh_materials()
	_rebuild_pulses()


func _quiz_text(title: String, body: String) -> void:
	demo_title.text = title
	demo_body.text = body
	_place_caption()
	_answer_text = title + "\n" + body
	if vr_label:
		vr_label.text = title + "\n\n" + body


func _toggle_quiz() -> void:
	if quiz_active:
		_end_quiz()
	else:
		_start_quiz()


func _start_quiz() -> void:
	quiz_missed = []
	focus_ids.clear()
	lab_panel.visible = false
	if demo_running:
		_stop_demo()
	if mode != Mode.GRAPH:
		_set_mode(Mode.GRAPH)
	var d: Dictionary = _load_json(String(COURSES[course_idx]["quiz"]))
	quiz_list = d.get("questions", [])
	if quiz_list.is_empty():
		return
	quiz_list.shuffle()
	quiz_active = true
	quiz_busy = false
	quiz_i = 0
	quiz_score = 0
	quiz_tries = 0
	quiz_streak = 0
	bottom_box.visible = false
	demo_panel.visible = true
	demo_hint.text = "QUIZ  -  pick an answer below (or click the concept in the graph)   |   Q or End quiz: stop"
	ask_on = false
	quiz_opts.visible = true
	_quiz_show()


func _quiz_show() -> void:
	selected = {}
	highlighted.clear()
	path_ids.clear()
	path_edges.clear()
	quiz_tries = 0
	for it in items:
		it.erase("poplabel")
	# back to the overview, lifted above the answer panel, so every option can be found in the graph
	cam_override = true
	cam_focus_goal = Vector3(0.0, -graph_radius * 0.22, 0.0)
	demo_cam = false
	dist_goal = _default_dist() * 1.05
	_refresh_materials()
	_rebuild_pulses()
	var q: Dictionary = quiz_list[quiz_i]
	var right: String = String(q["answer"])
	if not g_items.has(right):   # bad data: skip the question
		quiz_i += 1
		if quiz_i >= quiz_list.size():
			_finish_quiz()
		else:
			_quiz_show()
		return
	quiz_fb.visible = false
	quiz_card.visible = false
	demo_hint.text = "QUIZ  -  pick an answer below (or click the concept in the graph)   |   Q or End quiz: stop"
	_quiz_build_options(right)
	_quiz_text("Question %d of %d          Score: %d" % [quiz_i + 1, quiz_list.size(), quiz_score], String(q["q"]))
	_say_quiz(String(_quiz_lines(q)["question"]))


func _quiz_answer(item: Dictionary) -> void:
	if quiz_busy:
		return
	quiz_busy = true
	var q: Dictionary = quiz_list[quiz_i]
	var right: String = String(q["answer"])
	var picked: String = String(item["id"])
	const GREEN: Color = Color(0.25, 0.85, 0.45)
	const RED: Color = Color(0.95, 0.3, 0.3)
	var last: bool = quiz_i + 1 >= quiz_list.size()
	if picked == right:
		var first_try: bool = quiz_tries == 0
		if first_try:
			quiz_score += 1
			quiz_streak += 1
			mastered[right] = true
			_save_progress()
		else:
			quiz_streak = 0
		_quiz_lock(true)
		_quiz_paint(right, GREEN, 0.45)
		_quiz_spotlight(right)
		_play_sfx(sfx_select)
		_quiz_text("Question %d of %d          Score: %d" % [quiz_i + 1, quiz_list.size(), quiz_score], String(q["q"]))
		var praise: Array = ["Correct!", "Exactly right!", "Spot on!", "Nice one!", "Well done!"] if first_try else ["Got it!", "That's the one!"]
		var head_txt: String = "✓  %s   %s" % [praise[randi() % praise.size()], _title_of(right)]
		if first_try:
			head_txt += "     +1 point · now gold in the graph"
			if quiz_streak >= 2:
				head_txt += "     ★ %d in a row" % quiz_streak
		else:
			head_txt += "     (second try - no point, but now you know it)"
		quiz_fb.text = head_txt
		quiz_fb.add_theme_color_override("font_color", GREEN.lightened(0.3))
		quiz_fb.visible = true
		_place_caption()
		_say_quiz(String(_quiz_lines(q)["correct" if first_try else "second"]))
		await _quiz_explain(q, right, last)
	else:
		quiz_tries += 1
		_quiz_paint(picked, RED, 0.35)
		if quiz_btns.has(picked):
			(quiz_btns[picked] as Button).disabled = true
		if g_items.has(picked):
			_pop(picked)   # show where the wrong choice lives in the graph
		if quiz_tries < 2:
			_say_quiz(QUIZ_WRONG_LINE)
			quiz_fb.text = "✗  Not quite - %s is: %s  Try again." % [_title_of(picked), _brief(picked, 90)]
			quiz_fb.add_theme_color_override("font_color", RED.lightened(0.35))
			quiz_fb.visible = true
			_place_caption()
			quiz_busy = false
			return
		_quiz_lock(true)
		_quiz_paint(right, GREEN, 0.45)
		_quiz_spotlight(right)
		if not quiz_missed.has(right):
			quiz_missed.append(right)
		quiz_streak = 0
		quiz_fb.text = "The answer is  %s  - it is glowing in the graph. It goes on your review list." % _title_of(right)
		quiz_fb.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
		quiz_fb.visible = true
		_place_caption()
		_say_quiz(String(_quiz_lines(q)["reveal"]))
		await _quiz_explain(q, right, last)
	if not quiz_active:
		return
	quiz_i += 1
	quiz_busy = false
	if quiz_i >= quiz_list.size():
		_finish_quiz()
	else:
		_quiz_show()


func _finish_quiz() -> void:
	var n: int = quiz_list.size()
	var msg: String = "Well done!" if quiz_score * 10 >= n * 8 else ("Good progress. Run the guided tour to review." if quiz_score * 2 >= n else "Keep practising: press D for the guided tour, then try again.")
	_save_progress(quiz_score, n)
	var review: String = ""
	if not quiz_missed.is_empty():
		review = "\nTo review (shown in colour): " + _names(quiz_missed)
	quiz_opts.visible = false
	quiz_fb.visible = false
	quiz_card.visible = false
	cam_override = false
	demo_cam = false
	dist_goal = _default_dist()
	_quiz_text("Quiz finished:  %d / %d correct   -   %d concepts mastered in total" % [quiz_score, n, mastered.size()], msg + review + "\nPress Q to play again.")
	quiz_active = false
	selected = {}
	highlighted.clear()
	_set_focus(quiz_missed)
	_refresh_materials()


func _end_quiz() -> void:
	quiz_active = false
	quiz_busy = false
	highlighted.clear()
	focus_ids.clear()
	quiz_opts.visible = false
	quiz_fb.visible = false
	quiz_card.visible = false
	if quiz_waiting:   # release a pending "Next" wait so the old question flow ends cleanly
		quiz_next.emit()
	if not demo_running:
		_stop_voice()
	cam_override = false
	demo_cam = false
	for it in items:
		it.erase("poplabel")
	demo_panel.visible = false
	bottom_box.visible = true
	_refresh_materials()
	_update_texts()


## Press P: saves a PNG of the current view to Desktop/NeuroGraph_Screenshots (for posts, reports).
func _save_screenshot() -> void:
	var dir_path: String = OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP).path_join("NeuroGraph_Screenshots")
	DirAccess.make_dir_recursive_absolute(dir_path)
	var img: Image = get_viewport().get_texture().get_image()
	var file: String = dir_path.path_join("shot_%s.png" % Time.get_datetime_string_from_system().replace(":", "-"))
	var err: int = img.save_png(file)
	if status_label:
		status_label.text = "Screenshot saved: " + file if err == OK else "Screenshot failed (error %d)" % err


func _toggle_demo() -> void:
	if demo_running:
		_stop_demo()
	else:
		_run_demo()


## N: records the narration lines of EVERY course, one after the other (silent, takes a few seconds).
func _start_recording() -> void:
	if demo_running:
		_stop_demo()
	var original: int = course_idx
	for ci in COURSES.size():
		_set_course(ci)
		narr_record = true
		await _run_demo()
	_set_course(original)
	status_label.text = "Recorded %d narration lines for all courses. Now run tools/make_narration.py." % narr_lines.size()


func _stop_demo() -> void:
	if not demo_running:
		return
	var was_recording: bool = narr_record
	narr_record = false
	demo_running = false
	if was_recording:
		status_label.text = "Recorded %d lines so far (%s done)" % [narr_lines.size(), _course_key()]
	demo_cam = false
	cam_override = false
	focus_ids.clear()
	_clear_calc()
	filter_cat = ""
	highlighted.clear()
	spread_target = 0.0
	demo_panel.visible = false
	left_panel.visible = true
	bottom_box.visible = true
	legend_panel.visible = mode == Mode.GRAPH
	auto_rotate = true
	dist_goal = _default_dist()
	_refresh_materials()
	_update_texts()
	yaw = 0.5
	pitch = 0.3
	if not was_recording:
		status_label.text = "Demo finished - press D to replay"
	_stop_voice()


func _run_demo() -> void:
	demo_id += 1
	var id: int = demo_id
	if quiz_active:
		_end_quiz()
	demo_hint.text = "GUIDED TOUR  -  Space: next step   |   D or Esc: stop   |   V: voice on/off"
	demo_running = true
	demo_skip = false
	_forward_pass_saved = true
	# the tour can be started from anywhere (D key on the home menu, from a lab ...): close what covers the 3D view
	menu_panel.visible = false
	lab_panel.visible = false
	sl_panel.visible = false
	al_panel.visible = false
	lab_edit.release_focus()
	left_panel.visible = false
	bottom_box.visible = false
	legend_panel.visible = false
	demo_panel.visible = true
	auto_rotate = false
	_set_mode(Mode.GRAPH)
	legend_panel.visible = false
	selected = {}
	var total: int = 10

	# 1 ─ intro
	_cam(Vector3.ZERO, 15.0, 0.5, 0.35)
	_caption("1/%d   Welcome to NeuroGraph XR" % total, String(_demo("welcome_caption", "Explore how data science concepts connect, and how a neural network makes a decision.")))
	_say(String(_demo("welcome_say", "Welcome to NeuroGraph X R. In this short tour, you will see how data science concepts connect, and how a neural network makes a decision.")))
	if not await _dw(8.0, id):
		return
	if (_demo("story", []) as Array).is_empty():
		await _demo_algorithms(id, total)
	else:
		await _run_story(id)
	if not demo_running or demo_id != id:
		return
	await _demo_finish(id, total)


func _demo_algorithms(id: int, total: int) -> void:
	# 2 ─ categories
	_caption("2/%d   The graph: concepts and relations" % total, "Each sphere is a concept, each line a relation. Colour = category, size = number of connections.")
	_say("Each sphere is a concept, and each line is a relation. The colours show the categories. Let's look at them one by one.")
	if not await _dw(5.0, id):
		return
	var cat_say: Dictionary = _demo("category_say", {})
	for cat in cat_say.keys():
		filter_cat = cat
		_refresh_materials()
		var cat_ids: Array = []
		for cn in graph_data["nodes"]:
			if cn["category"] == cat:
				cat_ids.append(cn["id"])
		_frame(cat_ids, 7.0)
		_pop_spoken("", cat_ids.slice(0, 6))
		_caption("2/%d   Category: %s" % [total, cat], _short(_names(cat_ids, 8), 220))
		_say(String(cat_say[cat]))
		if not await _dw(4.0, id):
			return
	filter_cat = ""
	_refresh_materials()

	# 3 ─ zoom on a node
	var fid: String = String(_demo("focus_node", "feature_eng"))
	var fe: Dictionary = g_items[fid]
	_select(fe)
	var fe_nb: Array = []
	for fadj in g_adj[fid]:
		fe_nb.append(fadj[0])
	_frame([fid] + fe_nb, 5.0)
	_set_focus([fid] + fe_nb)
	_pop_spoken("Let's zoom in on", [fid])
	_pop_spoken("Let's zoom in on %s. %s It has %d connections:" % [_title_of(fid), _node_desc(fid), fe_nb.size()], fe_nb)
	_say("Let's zoom in on %s. %s It has %d connections: %s. They are highlighted." % [_spoken(_title_of(fid)), _spoken(_node_desc(fid)), fe_nb.size(), _spoken(_names(fe_nb, 4))])
	_caption("3/%d   Zooming in on one concept" % total, "%s  (%d connections)" % [_node_desc(fid), fe_nb.size()])
	if not await _dw(7.0, id):
		return
	selected = {}
	_refresh_materials()
	_rebuild_pulses()

	_set_focus([])
	# 4 ─ information spreading hop by hop
	var hop_start: String = String(_demo("hop_start", "raw_data"))
	var levels: Dictionary = _hop_levels(hop_start)
	var maxh: int = 0
	for v in levels.values():
		maxh = maxi(maxh, int(v))
	maxh = mini(maxh, 7)
	_cam(Vector3.ZERO, 15.0, 0.9, 0.4)
	_say("Now watch information spread from %s, one hop at a time, like message passing in a graph neural network. The brightest nodes are the newly reached ones." % _spoken(_title_of(hop_start)))
	if not await _dw(6.0, id):
		return
	for h in range(maxh + 1):
		_show_hop(levels, h)
		var hop_ids: Array = []
		for nid in levels.keys():
			if int(levels[nid]) == h:
				hop_ids.append(nid)
		# concepts reached in the same hop can lie in different clusters: show ONE cluster at a time, close up
		var groups: Dictionary = {}
		for hid2 in hop_ids:
			var gcat: String = String((g_items[hid2] as Dictionary)["cat"])
			if not groups.has(gcat):
				groups[gcat] = []
			(groups[gcat] as Array).append(hid2)
		var gi: int = 0
		for gk in groups.keys():
			var grp: Array = groups[gk]
			_frame(grp, 4.5)
			_caption("4/%d   Information flowing through the graph  (hop %d)" % [total, h], "Newly reached: %s" % _short(_names(grp, 6), 190))
			var line: String
			var pre: String
			if h == 0:
				pre = "We start at"
				line = "We start at %s." % _spoken(_names(grp, 6))
			elif gi == 0:
				pre = "Hop %d. The signal reaches" % h
				line = "Hop %d. The signal reaches %s." % [h, _spoken(_names(grp, 6))]
			else:
				pre = "Then it reaches to"
				line = "Then it reaches to %s." % _spoken(_names(grp, 6))
			_say(line)
			_pop_spoken(pre, grp)
			gi += 1
			if not await _dw(3.0, id):
				return
	_clear_calc()

	# 5 ─ PageRank
	var hist: Array = _pagerank(25)
	_cam(Vector3.ZERO, 15.0, 2.2, 0.3)
	_say("Next, PageRank. It measures which concepts matter most. Bigger and brighter means more important.")
	if not await _dw(5.0, id):
		return
	var pr_say: Dictionary = {
		0: "At the start, every concept is equally important.",
		1: "In each round, a concept shares its importance with the concepts it links to.",
		3: "Concepts that receive many links start to grow.",
		10: "The ranking is settling down.",
	}
	for k in [0, 1, 3, 10, 25]:
		var prk: Dictionary = hist[k]
		_show_pr(prk)
		_caption("5/%d   PageRank  (iteration %d)" % [total, k], "PR(v) = (1-d)/N + d x sum( PR(u) / outdegree(u) ),  d = 0.85,  N = %d\nTop: %s" % [g_items.size(), _top_pr(prk, 3)])
		if k == 25:
			var ranked: Array = []
			for pid2 in prk.keys():
				ranked.append([float(prk[pid2]), String(pid2)])
			ranked.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
			var top_ids: Array = [ranked[0][1], ranked[1][1], ranked[2][1]]
			_frame(top_ids, 7.0)
			_say("After twenty five rounds, the most important concept is %s." % _spoken(_names(top_ids, 3)))
			_pop_spoken("After twenty five rounds, the most important concept is", top_ids)
		else:
			_say(String(pr_say[k]))
		if not await _dw(4.5 if k < 25 else 6.0, id):
			return
	_clear_calc()

	# 6 ─ shortest path
	var p_from: String = String(_demo("path_from", "raw_data"))
	var p_to: String = String(_demo("path_to", "dashboard"))
	_select(g_items[p_from])
	_show_path(g_items[p_to])
	_frame(path_ids, 8.0)
	_set_focus(path_ids)
	_say("A shortest path search connects %s to %s in %d steps. Let's follow it." % [_spoken(_title_of(p_from)), _spoken(_title_of(p_to)), path_ids.size() - 1])
	var pnames: PackedStringArray = []
	for pid in path_ids:
		pnames.append(String((g_items[pid] as Dictionary)["title"]))
	_caption("6/%d   Shortest path between two concepts" % total, "Breadth-first search, %d hops:  %s" % [path_ids.size() - 1, "  ->  ".join(pnames)])
	if not await _dw(5.0, id):
		return
	var path_copy: Array = path_ids.duplicate()
	for pi in path_copy.size():
		var pnode: String = String(path_copy[pi])
		_frame([pnode], 4.0)
		_set_focus([pnode])
		_pop(pnode)
		_caption("6/%d   Path step %d of %d:  %s" % [total, pi + 1, path_copy.size(), _title_of(pnode)], _short(_node_desc(pnode), 120))
		_say(_spoken(_title_of(pnode)))
		if not await _dw(2.8, id):
			return
	_set_focus([])
	selected = {}
	path_ids.clear()
	path_edges.clear()
	highlighted.clear()
	_refresh_materials()
	_rebuild_pulses()

## Lesson mode: a plain-language story that follows the course, one idea per step.
func _run_story(id: int) -> void:
	var story: Array = _demo("story", [])
	var n: int = story.size()
	for si in n:
		var s: Dictionary = story[si]
		var ids: Array = s["focus"]
		_frame(ids, 5.0)
		_set_focus(ids)
		_caption("Lesson %d of %d   %s" % [si + 1, n, String(s["title"])], String(s["caption"]))
		_say(String(s["say"]))
		_pop_spoken("", ids)
		if not await _dw(float(s.get("min", 6.0)), id):
			return
		if String(s.get("calc", "")) == "temperature":
			await _story_temperature(id, n, si)
			if not demo_running or demo_id != id:
				return
	_set_focus([])


## Live calculation: softmax of the same scores at three temperatures.
func _story_temperature(id: int, n: int, si: int) -> void:
	var words: Array = ["mat", "floor", "roof", "moon", "car"]
	var logits: Array = [2.4, 1.6, 0.8, 0.2, -0.5]
	var says: Dictionary = {
		0.5: "With a low temperature, the model is confident and almost always picks the top word.",
		1.0: "At normal temperature, the probabilities are spread more evenly.",
		2.0: "At a high temperature, even unlikely words get a real chance, so the text becomes more surprising.",
	}
	var names: Dictionary = {0.5: "low (0.5): focused", 1.0: "normal (1.0)", 2.0: "high (2.0): adventurous"}
	for temp in [0.5, 1.0, 2.0]:
		var z: PackedFloat32Array = PackedFloat32Array()
		for lg in logits:
			z.append(float(lg) / float(temp))
		var pr: PackedFloat32Array = _softmax(z)
		var parts: PackedStringArray = []
		for i in words.size():
			parts.append("%s %.0f%%" % [words[i], pr[i] * 100.0])
		_caption("Lesson %d of %d   Temperature: %s" % [si + 1, n, String(names[temp])], "Next word after \"The cat sat on the\":   " + "   |   ".join(parts) + "\nprobability = softmax( score / temperature )")
		_say(String(says[temp]))
		if not await _dw(4.0, id):
			return


func _demo_finish(id: int, total: int) -> void:
	# 7 ─ GraphRAG
	var question: String = String(_demo("question", "How do I avoid overfitting?"))
	_cam(Vector3.ZERO, 14.0, 1.4, 0.3)
	_say("Now Graph RAG. We ask a question, retrieve the matching concepts, and let a local language model answer using only those facts.")
	_caption("7/%d   GraphRAG: a question answered from the graph" % total, "\"%s\"\nFind matching concepts -> add neighbours -> send only these facts to the local LLM." % question)
	if not await _dw(6.0, id):
		return
	_ask(question)
	var rn: Array = highlighted.duplicate()
	_frame(rn, 7.0)
	_set_focus(rn)
	_pop_spoken("The graph search found these concepts:", rn)
	_say("The graph search found these concepts: %s. They are glowing. Only these facts go to the language model." % _spoken(_names(rn, 4)))
	_caption("7/%d   GraphRAG: retrieved nodes are glowing" % total, "Related concepts: %s\nPreparing the answer ..." % _short(_names(rn, 8), 190))
	# wait for the real AI answer (Space must NOT skip this, or the grounded answer is lost)
	var waited: float = 0.0
	while (_ai_busy or waited < 2.0) and waited < 40.0:
		await get_tree().process_frame
		if not demo_running or demo_id != id:
			return
		waited += get_process_delta_time()
	demo_skip = false
	if not await _dw(0.1, id):   # let the "found these concepts" narration finish
		return
	var ans: String = _answer_text
	if ans.begins_with("Ollama is not reachable") or ans.begins_with("Q:") or IS_WEB:
		ans = "Key facts: " + _last_facts
	_caption("7/%d   Grounded answer" % total, _short(ans, 280))
	_say("Here is the answer, grounded in the retrieved facts.")
	if not await _dw(10.0, id):
		return
	highlighted.clear()
	_refresh_materials()
	_rebuild_pulses()

	_set_focus([])
	# 8 ─ neural network
	_set_mode(Mode.NETWORK)
	demo_panel.visible = true
	_forward_pass_saved = true
	forward_pass = false
	_cam(Vector3.ZERO, 12.5, 0.7, 0.25)   # far enough that the outer layer labels stay on screen
	_say(String(net_data.get("intro_say", "Now the neural network. Each column is a layer, and each sphere is a neuron. The labels show the data shape at each layer. The word batch means how many samples are processed together.")))
	_caption("8/%d   Second view: a neural network" % total, String(net_data.get("intro_caption", "Input -> Conv1D -> Conv1D -> LSTM -> Attention -> Dense -> Output.  Column = layer, sphere = neuron, line = connection.")))
	if not await _dw(7.0, id):
		return
	spread_target = 1.0
	_play_sfx(sfx_explode)
	_cam(Vector3.ZERO, 16.0, 0.5, 0.2)
	_say("We pull the layers apart, so each one can be inspected.")
	_caption("8/%d   Explode view" % total, "Layers pulled apart for inspection. Next: a real calculation, layer by layer.")
	if not await _dw(5.0, id):
		return

	# 9 ─ step-by-step forward pass with real numbers
	calc_net = true
	var layers: Array = net_data["layers"]
	for l in layers.size():
		calc_layer = l
		_apply_activation_visuals()
		_rebuild_edges()
		_rebuild_pulses()
		var lnode: Node3D = (n_layers[l] as Dictionary)["node"]
		_cam(lnode.position, 5.0, 1.0, 0.2)
		_say(_layer_say(l))
		_caption("9/%d   Forward pass - layer %d of %d: %s   %s" % [total, l + 1, layers.size(), layers[l]["name"], layers[l]["shape"]], _layer_caption(l))
		if not await _dw(5.0 if l == 0 else 9.0, id):
			return

	# 10 ─ finale
	_clear_calc()
	spread_target = 0.0
	_cam(Vector3.ZERO, 11.0, 0.6, 0.3)
	_say("That was the full tour. Press D to replay, or explore on your own.")
	_caption("10/%d   Summary" % total, String(_demo("summary", "Graph layout, message passing, PageRank, shortest path, GraphRAG and a real forward pass. Press D to replay.")))
	if not await _dw(9.0, id):
		return
	_stop_demo()


# ═════════════════════ PROGRESS · TOKEN LAB · START MENU ═════════════════════
const PROGRESS_PATH: String = "user://progress.json"
var progress: Dictionary = {}
var mastered: Dictionary = {}      # concept id -> true (answered correctly in the quiz), per course
var quiz_missed: Array = []
var lab_panel: PanelContainer
var lab_edit: LineEdit
var lab_view: TokenView
var lab_merges: Label
var bpe_merges: Array = []
var bpe_vocab: Dictionary = {}
var bpe_course: int = -1
var menu_panel: PanelContainer
var menu_progress: Label
var menu_course_btns: Array = []


func _course_key() -> String:
	return String(COURSES[course_idx]["name"])


func _load_progress() -> void:
	if FileAccess.file_exists(PROGRESS_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROGRESS_PATH))
		if parsed is Dictionary:
			progress = parsed
	_apply_progress()


func _apply_progress() -> void:
	mastered = {}
	var cp: Dictionary = progress.get(_course_key(), {})
	for mid in cp.get("mastered", []):
		mastered[String(mid)] = true


func _save_progress(best: int = -1, of: int = 0) -> void:
	var cp: Dictionary = progress.get(_course_key(), {})
	cp["mastered"] = mastered.keys()
	if best >= 0 and best >= int(cp.get("best", 0)):
		cp["best"] = best
		cp["best_of"] = of
	progress[_course_key()] = cp
	var f: FileAccess = FileAccess.open(PROGRESS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(progress))


func _mastery_line() -> String:
	var total: int = (graph_data.get("nodes", []) as Array).size()
	return "Mastered: %d / %d concepts  (gold names = answered correctly in the quiz)\n\n" % [mastered.size(), total]


# ── Token Lab: a real (mini) Byte-Pair-Encoding tokenizer trained on the course's own text ──
func _merge_pair(s: Array, a: String, b: String) -> Array:
	var out: Array = []
	var i: int = 0
	while i < s.size():
		if i < s.size() - 1 and s[i] == a and s[i + 1] == b:
			out.append(a + b)
			i += 2
		else:
			out.append(s[i])
			i += 1
	return out


const BPE_COMMON: String = "the a an and or but of to in on at by for with from as is are was were be been it its this that these those he she they we you i me my your his her our their them him us not no yes do does did have has had will would can could should may might there here what which who when where why how all any some more most many much one two three new old good bad big small first last long great little own other same such only just also very well even back still way day time year people man woman child world life hand part place case week company system group number point home water room mother area money story fact month lot right study book eye job word business issue side kind head house service friend father power hour game line end member law car city community name team minute idea kid body information school face others level office door health person art war history party result change morning reason research girl guy moment air teacher force education cat dog sat mat sit run ran eat ate see saw go went make made take took give gave know think say said get got come came want need like love look use find tell ask work seem feel try leave call keep let begin help talk turn start show hear play move live believe bring happen write provide stand lose pay meet include continue set learn lead understand watch follow stop create speak read allow add spend grow open walk win offer remember consider appear buy wait serve die send expect build stay fall cut reach kill remain cool fun happy sad hot cold fast slow red blue green black white light dark today tomorrow"


const BPE_VERSION: int = 4
const BPE_MERGES: int = 1000


## Trains the tokenizer for every course and saves it to data/<course>_bpe.json (run once after changing the content).
func _bake_bpe() -> void:
	for ci in COURSES.size():
		course_idx = ci
		graph_data = _load_json(String(COURSES[ci]["graph"]))
		bpe_course = -1
		var path: String = "res://data/%s_bpe.json" % String(COURSES[ci]["name"]).to_lower().replace(" ", "_")
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		_train_bpe()
		var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		f.store_string(JSON.stringify({"version": BPE_VERSION, "merges": bpe_merges, "vocab": bpe_vocab}))
		f.close()
		print("baked ", path, "  merges=", bpe_merges.size())


func _train_bpe() -> void:
	if bpe_course == course_idx:
		return
	bpe_course = course_idx
	var text: String = ""
	for n in graph_data.get("nodes", []):
		text += " " + String(n["label"]) + " " + String(n["desc"])
	text = text.to_lower() + " "
	# pre-computed tokenizer (tools: _bake_bpe) -> opening the lab is instant
	var baked_path: String = "res://data/%s_bpe.json" % String(COURSES[course_idx]["name"]).to_lower().replace(" ", "_")
	if FileAccess.file_exists(baked_path):
		var bd: Variant = JSON.parse_string(FileAccess.get_file_as_string(baked_path))
		if bd is Dictionary and int((bd as Dictionary).get("version", 0)) == BPE_VERSION:
			bpe_merges = (bd as Dictionary)["merges"]
			bpe_vocab = (bd as Dictionary)["vocab"]
			return
	var counts: Dictionary = {}
	var cur: String = ""
	for ch in text:
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			cur += ch
		else:
			if cur != "":
				counts[cur] = int(counts.get(cur, 0)) + 1
				cur = ""
	# real tokenizers learn from everyday text too, so very common words become ONE token
	for cw in BPE_COMMON.split(" ", false):
		counts[cw] = int(counts.get(cw, 0)) + 8
	var words: Array = []
	var chars: Dictionary = {"▁": true}
	for pch in ".,!?;:'\"-()/&%$€@#+*=<>[]":   # punctuation gets its own token, like in real tokenizers
		chars[pch] = true
	for w in counts.keys():
		var syms: Array = ["▁"]
		for c in String(w):
			syms.append(c)
			chars[c] = true
		words.append([syms, int(counts[w])])
	bpe_merges = []
	for _it in BPE_MERGES:
		var pc: Dictionary = {}
		for wd in words:
			var s: Array = wd[0]
			for i in range(s.size() - 1):
				var key: String = String(s[i]) + "\u0001" + String(s[i + 1])
				pc[key] = int(pc.get(key, 0)) + int(wd[1])
		var best: String = ""
		var best_c: int = 1
		for k in pc.keys():
			var cnt: int = int(pc[k])
			if cnt > best_c or (cnt == best_c and best != "" and String(k) < best):
				best = String(k)
				best_c = cnt
		if best == "":
			break
		var parts: PackedStringArray = best.split("\u0001")
		bpe_merges.append([parts[0], parts[1]])
		for wd in words:
			wd[0] = _merge_pair(wd[0], parts[0], parts[1])
	bpe_vocab = {}
	var keys: Array = chars.keys()
	keys.sort()
	for k in keys:
		bpe_vocab[String(k)] = bpe_vocab.size()
	for m in bpe_merges:
		bpe_vocab[String(m[0]) + String(m[1])] = bpe_vocab.size()


func _bpe_word(w: String) -> Array:
	var s: Array = ["▁"]
	for c in w:
		s.append(c)
	for m in bpe_merges:
		s = _merge_pair(s, String(m[0]), String(m[1]))
	return s


func _lab_update(_text: String = "") -> void:
	_train_bpe()
	var src: String = lab_edit.text.to_lower()
	var groups: Array = []   # one array of [text, id] per word (punctuation = its own group)
	var cur: String = ""
	for ch in src + " ":
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			cur += ch
		else:
			if cur != "":
				var g: Array = []
				for t in _bpe_word(cur):
					var shown: String = String(t).replace("▁", "")
					if shown == "":
						continue   # the bare word-start marker is not worth a block of its own
					g.append([shown, int(bpe_vocab.get(String(t), -1))])
				groups.append(g)
				cur = ""
			if ch != " ":
				groups.append([[ch, int(bpe_vocab.get(ch, -1))]])
	lab_view.set_tokens(groups, src.replace(" ", "").length())
	var ms: PackedStringArray = []
	for i in mini(8, bpe_merges.size()):
		ms.append("%s+%s → %s" % [String(bpe_merges[i][0]).replace("▁", "_"), String(bpe_merges[i][1]), (String(bpe_merges[i][0]) + String(bpe_merges[i][1])).replace("▁", "_")])
	lab_merges.text = "First pairs it glued together:   " + "     ".join(ms)


## Centres a lab panel on screen at exactly the size its content needs (call after showing/hiding parts).
func _fit_panel(pnl: PanelContainer) -> void:
	if not pnl.has_meta("solid"):   # labs get an almost opaque background - the busy 3D graph behind is distracting
		var sb: StyleBoxFlat = (pnl.get_theme_stylebox("panel") as StyleBoxFlat).duplicate()
		sb.bg_color = Color(0.025, 0.04, 0.085, 1.0)
		pnl.add_theme_stylebox_override("panel", sb)
		pnl.set_meta("solid", true)
	pnl.reset_size()
	var sz: Vector2 = pnl.get_combined_minimum_size()
	pnl.offset_left = -sz.x * 0.5
	pnl.offset_right = sz.x * 0.5
	pnl.offset_top = -sz.y * 0.5
	pnl.offset_bottom = sz.y * 0.5


## Small title + one-line instruction used by every lab.
func _lab_header(vb: VBoxContainer, title_txt: String, line: String) -> void:
	var title: Label = Label.new()
	title.text = title_txt
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	vb.add_child(title)
	var sub: Label = Label.new()
	sub.text = line
	sub.add_theme_font_size_override("font_size", 16)
	sub.add_theme_color_override("font_color", Color(0.82, 0.9, 1.0))
	vb.add_child(sub)


## "How does it work? ▸" toggle that shows / hides a details box.
func _lab_details(vb: VBoxContainer, pnl: PanelContainer, label: String) -> VBoxContainer:
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.visible = false
	var b: Button = Button.new()
	b.text = label + "  ▸"
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_color_override("font_color", Color(0.55, 0.75, 1.0))
	b.add_theme_color_override("font_hover_color", Color(0.75, 0.88, 1.0))
	b.pressed.connect(func() -> void:
		box.visible = not box.visible
		b.text = label + ("  ▾" if box.visible else "  ▸")
		_fit_panel(pnl))
	vb.add_child(b)
	vb.add_child(box)
	return box


func _small_note(parent: Control, txt: String) -> Label:
	var l: Label = Label.new()
	l.text = txt
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(760, 0)
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Color(0.7, 0.8, 0.95))
	parent.add_child(l)
	return l


func _build_lab_ui(layer: CanvasLayer) -> void:
	lab_panel = PanelContainer.new()
	lab_panel.anchor_left = 0.5
	lab_panel.anchor_right = 0.5
	lab_panel.anchor_top = 0.5
	lab_panel.anchor_bottom = 0.5
	lab_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	lab_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	lab_panel.add_theme_stylebox_override("panel", _panel_style())
	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	lab_panel.add_child(vb)
	_lab_header(vb, "TOKEN LAB", "An AI doesn't read words - it reads tokens.  Type anything:")
	lab_edit = LineEdit.new()
	lab_edit.placeholder_text = "Type here..."
	lab_edit.text = "The cat sat on the mat"
	lab_edit.custom_minimum_size = Vector2(800, 40)
	lab_edit.add_theme_font_size_override("font_size", 18)
	lab_edit.text_changed.connect(_lab_update)
	vb.add_child(lab_edit)
	var pre: HBoxContainer = HBoxContainer.new()
	pre.add_theme_constant_override("separation", 6)
	vb.add_child(pre)
	var tl: Label = Label.new()
	tl.text = "Try:"
	tl.add_theme_color_override("font_color", Color(0.6, 0.72, 0.9))
	pre.add_child(tl)
	for ex in ["The cat sat on the mat", "unbelievably", "tokenization", "Transformers are cool!"]:
		var etext: String = String(ex)
		_add_button(pre, etext, func() -> void:
			lab_edit.text = etext
			_lab_update())
	lab_view = TokenView.new()
	lab_view.custom_minimum_size = Vector2(800, 180)
	vb.add_child(lab_view)
	_small_note(vb, "Common words = 1 block.   Rare words = several pieces.   Hover a block for details.")
	var det: VBoxContainer = _lab_details(vb, lab_panel, "How does it decide where to cut?")
	_small_note(det, "It counted which letter pairs appear most often in this course's text, and glued them together - again and again. That is called Byte-Pair Encoding (BPE). The # number under each block is the token ID: the only thing the model really receives.")
	lab_merges = _small_note(det, "")
	_add_button(vb, "Close  (L)", func() -> void: _toggle_lab())
	lab_panel.visible = false
	layer.add_child(lab_panel)


func _toggle_lab() -> void:
	if demo_running:
		_stop_demo()
	if quiz_active:
		_end_quiz()
	menu_panel.visible = false
	sl_panel.visible = false
	al_panel.visible = false
	lab_panel.visible = not lab_panel.visible
	if lab_panel.visible:
		_lab_update()
		_fit_panel(lab_panel)
		lab_edit.grab_focus()
		lab_edit.caret_column = lab_edit.text.length()
	else:
		lab_edit.release_focus()


# ── Sampling Lab v2: type ANY prompt, edit the candidate words and their scores, or let the local AI suggest them ──
const SL_PRESETS: Array = [
	{"p": "The cat sat on the", "w": ["mat", "floor", "sofa", "roof", "moon", "car", "pizza"], "s": [3.0, 2.2, 1.9, 1.0, 0.2, -0.3, -1.0]},
	{"p": "The capital of France is", "w": ["Paris", "Lyon", "beautiful", "a", "located", "Berlin", "pizza"], "s": [4.2, 1.0, 1.4, 1.2, 1.1, 0.3, -1.5]},
	{"p": "I would like a cup of", "w": ["coffee", "tea", "water", "milk", "juice", "soup", "gravel"], "s": [3.2, 2.8, 2.0, 1.5, 1.2, 0.4, -2.0]},
	{"p": "Once upon a", "w": ["time", "midnight", "hill", "dream", "star", "tax", "banana"], "s": [4.5, 1.0, 0.8, 0.7, 0.6, -1.0, -1.5]},
]
var sl2_words: Array = []
var sl2_scores: Array = []
var sl2_bars: Array = []
var sl2_pcts: Array = []
var sl2_prompt: LineEdit
var sl2_status: Label
var sl2_http: HTTPRequest
var sl_view: SamplingView
var sl_k_label: Label


func _sl2_probs() -> PackedFloat32Array:
	var t: float = maxf(sl_temp.value, 0.05)
	var k: int = int(sl_topk.value)
	var n: int = sl2_scores.size()
	var order: Array = range(n)
	order.sort_custom(func(a: int, b: int) -> bool: return (sl2_scores[a] as HSlider).value > (sl2_scores[b] as HSlider).value)
	var z: PackedFloat32Array = PackedFloat32Array()
	for i in n:
		z.append(-1000.0 if order.find(i) >= k else float((sl2_scores[i] as HSlider).value) / t)
	return _softmax(z)


func _sl2_update(_v: Variant = 0) -> void:
	if sl2_scores.is_empty() or sl_view == null:
		return
	var pr: PackedFloat32Array = _sl2_probs()
	var words: Array = []
	var ok: Array = []
	for i in pr.size():
		words.append((sl2_words[i] as LineEdit).text)
		ok.append(pr[i] > 0.0001)
	sl_view.set_data(words, pr, ok, sl_tally)
	var t: float = sl_temp.value
	var mood: String = "SAFE - it almost always picks the favourite" if t < 0.5 else ("BALANCED - mostly the favourite, sometimes another" if t < 1.3 else "CREATIVE - even unlikely words get a chance")
	sl_info.text = "Temperature %.1f   →   %s" % [t, mood]
	sl_info.add_theme_color_override("font_color", Color(0.45, 0.8, 1.0).lerp(Color(1.0, 0.55, 0.3), clampf((t - 0.3) / 2.2, 0.0, 1.0)))
	sl_k_label.text = "Only consider the top  %d  word%s" % [int(sl_topk.value), "" if int(sl_topk.value) == 1 else "s"]
	if not sl_view.spinning():
		_sl_sentence("")


func _sl_draw2() -> int:
	var pr: PackedFloat32Array = _sl2_probs()
	var r: float = sl_rng.randf()
	var acc: float = 0.0
	for j in pr.size():
		acc += pr[j]
		if r <= acc:
			return j
	return 0


## Shows the sentence with the blank, or with the chosen word filled in.
func _sl_sentence(word: String) -> void:
	if word == "":
		sl_result.text = "%s  ____" % sl2_prompt.text
		sl_result.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	else:
		sl_result.text = "%s  %s" % [sl2_prompt.text, word]
		sl_result.add_theme_color_override("font_color", Color(1.0, 0.88, 0.45))


func _sl2_sample(n: int) -> void:
	if sl_view.spinning():
		return
	if n == 1:   # one pick: roulette animation, then the word drops into the sentence
		sl_view.spin(_sl_draw2())
		return
	for _i in n:
		var w: String = (sl2_words[_sl_draw2()] as LineEdit).text
		sl_tally[w] = int(sl_tally.get(w, 0)) + 1
	_play_sfx(sfx_pop, -14.0)
	_sl2_update()


func _sl_spin_done(i: int) -> void:
	var w: String = (sl2_words[i] as LineEdit).text
	sl_tally[w] = int(sl_tally.get(w, 0)) + 1
	_play_sfx(sfx_select, -6.0)
	_sl2_update()
	_sl_sentence(w)


func _sl2_load(i: int) -> void:
	var p: Dictionary = SL_PRESETS[i]
	sl2_prompt.text = String(p["p"])
	for r in sl2_words.size():
		(sl2_words[r] as LineEdit).text = String(p["w"][r])
		(sl2_scores[r] as HSlider).value = float(p["s"][r])
	sl_tally.clear()
	_sl2_update()


func _sl2_ask_ai() -> void:
	var prompt: String = "Text: \"%s\"\nList the 7 most plausible next words, from most to least likely, one per line, in the exact format word|score where score is a number between -2 and 5 (higher means more likely). Output only those 7 lines." % sl2_prompt.text
	var body: String = JSON.stringify({"model": OLLAMA_MODEL, "prompt": prompt, "stream": false})
	sl2_status.text = "Asking the AI ..."
	if sl2_http.request(OLLAMA_URL, ["Content-Type: application/json"], HTTPClient.METHOD_POST, body) != OK:
		sl2_status.text = "Could not reach the AI. Edit the words and scores by hand instead."


func _sl2_ai_done(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if result != OK or code != 200:
		sl2_status.text = "The local AI (Ollama) is not running. You can still type the words and scores yourself."
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (parsed is Dictionary) or not parsed.has("response"):
		sl2_status.text = "Unexpected AI answer."
		return
	var row: int = 0
	for line in String(parsed["response"]).split("\n"):
		if not line.contains("|") or row >= sl2_words.size():
			continue
		var parts: PackedStringArray = line.split("|")
		var wd: String = parts[0].strip_edges().lstrip("0123456789.-*) ").strip_edges()
		if wd == "":
			continue
		(sl2_words[row] as LineEdit).text = wd
		(sl2_scores[row] as HSlider).value = clampf(float(parts[1].strip_edges()), -2.0, 5.0)
		row += 1
	sl2_status.text = "The AI suggested %d next words (scores are the AI's estimate, not exact model probabilities)." % row
	sl_tally.clear()
	_sl2_update()


func _build_sampling_ui2(layer: CanvasLayer) -> void:
	sl_panel = PanelContainer.new()
	sl_panel.anchor_left = 0.5
	sl_panel.anchor_right = 0.5
	sl_panel.anchor_top = 0.5
	sl_panel.anchor_bottom = 0.5
	sl_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	sl_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	sl_panel.add_theme_stylebox_override("panel", _panel_style())
	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	sl_panel.add_child(vb)
	_lab_header(vb, "SAMPLING LAB", "How does an AI pick the next word?  Drag the temperature, then press Pick.")
	# the sentence with the blank to fill - big, the centre of attention
	sl_result = Label.new()
	sl_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sl_result.add_theme_font_size_override("font_size", 30)
	vb.add_child(sl_result)
	var ex_row: HBoxContainer = HBoxContainer.new()
	ex_row.alignment = BoxContainer.ALIGNMENT_CENTER
	ex_row.add_theme_constant_override("separation", 6)
	vb.add_child(ex_row)
	for pi in SL_PRESETS.size():
		var pidx: int = pi
		_add_button(ex_row, String(SL_PRESETS[pi]["p"]) + " …", func() -> void: _sl2_load(pidx))
	sl_view = SamplingView.new()
	sl_view.custom_minimum_size = Vector2(820, 270)
	sl_view.score_dragged.connect(func(i: int, d: float) -> void:
		(sl2_scores[i] as HSlider).value += d)
	sl_view.spin_done.connect(_sl_spin_done)
	vb.add_child(sl_view)
	var r1: HBoxContainer = HBoxContainer.new()
	r1.add_theme_constant_override("separation", 10)
	vb.add_child(r1)
	var l1: Label = Label.new()
	l1.text = "safe"
	l1.add_theme_color_override("font_color", Color(0.45, 0.8, 1.0))
	r1.add_child(l1)
	sl_temp = HSlider.new()
	sl_temp.min_value = 0.1
	sl_temp.max_value = 3.0
	sl_temp.step = 0.05
	sl_temp.value = 1.0
	sl_temp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl_temp.value_changed.connect(_sl2_update)
	r1.add_child(sl_temp)
	var l1b: Label = Label.new()
	l1b.text = "creative"
	l1b.add_theme_color_override("font_color", Color(1.0, 0.55, 0.3))
	r1.add_child(l1b)
	sl_info = Label.new()
	sl_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sl_info.add_theme_font_size_override("font_size", 16)
	vb.add_child(sl_info)
	# action buttons - big and clear
	var br: HBoxContainer = HBoxContainer.new()
	br.alignment = BoxContainer.ALIGNMENT_CENTER
	br.add_theme_constant_override("separation", 12)
	vb.add_child(br)
	var pick: Button = Button.new()
	pick.text = "Pick a word  ▶"
	pick.focus_mode = Control.FOCUS_NONE
	pick.custom_minimum_size = Vector2(200, 44)
	pick.add_theme_font_size_override("font_size", 18)
	pick.add_theme_stylebox_override("normal", _quiz_btn_style(Color(0.25, 0.6, 1.0), 0.8))
	pick.add_theme_stylebox_override("hover", _quiz_btn_style(Color(0.4, 0.72, 1.0), 0.95))
	pick.add_theme_stylebox_override("pressed", _quiz_btn_style(Color(0.25, 0.6, 1.0), 0.8))
	pick.pressed.connect(func() -> void: _sl2_sample(1))
	br.add_child(pick)
	_add_button(br, "Pick 20 at once", func() -> void: _sl2_sample(20))
	_add_button(br, "Reset", func() -> void:
		sl_tally.clear()
		_sl2_update())
	# everything else is optional
	var det: VBoxContainer = _lab_details(vb, sl_panel, "Change the sentence and words   ·   how does it work?")
	var pr_row: HBoxContainer = HBoxContainer.new()
	pr_row.add_theme_constant_override("separation", 6)
	det.add_child(pr_row)
	sl2_prompt = LineEdit.new()
	sl2_prompt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl2_prompt.placeholder_text = "Type the start of a sentence..."
	sl2_prompt.text_changed.connect(func(_t: String) -> void:
		sl_tally.clear()
		_sl2_update())
	pr_row.add_child(sl2_prompt)
	_add_button(pr_row, "✦ AI suggests words", func() -> void: _sl2_ask_ai())
	var wgrid: GridContainer = GridContainer.new()
	wgrid.columns = 4
	wgrid.add_theme_constant_override("h_separation", 10)
	det.add_child(wgrid)
	for i in 7:
		var we: LineEdit = LineEdit.new()
		we.custom_minimum_size = Vector2(150, 0)
		we.text_changed.connect(func(_t: String) -> void:
			sl_tally.clear()
			_sl2_update())
		wgrid.add_child(we)
		sl2_words.append(we)
		var sc_s: HSlider = HSlider.new()   # hidden score store - the bars are dragged instead
		sc_s.min_value = -2.0
		sc_s.max_value = 5.0
		sc_s.step = 0.01
		sc_s.visible = false
		sc_s.value_changed.connect(_sl2_update)
		wgrid.add_child(sc_s)
		sl2_scores.append(sc_s)
	var kr: HBoxContainer = HBoxContainer.new()
	kr.add_theme_constant_override("separation", 10)
	det.add_child(kr)
	sl_k_label = Label.new()
	sl_k_label.custom_minimum_size = Vector2(250, 0)
	kr.add_child(sl_k_label)
	sl_topk = HSlider.new()
	sl_topk.min_value = 1
	sl_topk.max_value = 7
	sl_topk.step = 1
	sl_topk.value = 7
	sl_topk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl_topk.value_changed.connect(_sl2_update)
	kr.add_child(sl_topk)
	var hn: Label = _small_note(det, "The model gives every possible word a score. Temperature divides the scores before turning them into chances (softmax): low = the favourite wins almost always, high = the chances even out. Top-k throws away all but the k best words. Drag a bar to change a score.")
	hn.custom_minimum_size = Vector2(820, 0)
	sl2_status = _small_note(det, "")
	sl2_status.add_theme_color_override("font_color", Color(1.0, 0.9, 0.55))
	_add_button(vb, "Close  (K)", func() -> void: _toggle_sampling())
	sl2_http = HTTPRequest.new()
	sl2_http.timeout = 90.0
	sl2_http.request_completed.connect(_sl2_ai_done)
	sl_panel.add_child(sl2_http)
	sl_panel.visible = false
	layer.add_child(sl_panel)
	_sl2_load(0)


# ── (older fixed-example version, kept for reference) ──
const SL_WORDS: Array = ["mat", "floor", "sofa", "roof", "moon", "car", "pizza"]
const SL_LOGITS: Array = [3.0, 2.2, 1.9, 1.0, 0.2, -0.3, -1.0]
var sl_panel: PanelContainer
var sl_temp: HSlider
var sl_topk: HSlider
var sl_info: Label
var sl_bars: Array = []
var sl_pcts: Array = []
var sl_result: Label
var sl_tally: Dictionary = {}
var sl_rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _sl_probs() -> PackedFloat32Array:
	var t: float = maxf(sl_temp.value, 0.05)
	var k: int = int(sl_topk.value)
	var order: Array = range(SL_WORDS.size())
	order.sort_custom(func(a: int, b: int) -> bool: return SL_LOGITS[a] > SL_LOGITS[b])
	var z: PackedFloat32Array = PackedFloat32Array()
	for i in SL_WORDS.size():
		z.append(-1000.0 if order.find(i) >= k else float(SL_LOGITS[i]) / t)
	return _softmax(z)


func _sl_update(_v: float = 0.0) -> void:
	var pr: PackedFloat32Array = _sl_probs()
	for i in SL_WORDS.size():
		(sl_bars[i] as ProgressBar).value = pr[i] * 100.0
		(sl_pcts[i] as Label).text = "%.0f%%" % (pr[i] * 100.0)
	var mood: String = "very safe and repetitive" if sl_temp.value < 0.5 else ("balanced" if sl_temp.value < 1.3 else "creative, even wild")
	sl_info.text = "Temperature %.2f  (%s)      Top-k = %d  (only the %d most likely words may be chosen)" % [sl_temp.value, mood, int(sl_topk.value), int(sl_topk.value)]


func _sl_draw() -> int:
	var pr: PackedFloat32Array = _sl_probs()
	var r: float = sl_rng.randf()
	var acc: float = 0.0
	for i in pr.size():
		acc += pr[i]
		if r <= acc:
			return i
	return 0


func _sl_sample(n: int) -> void:
	for _i in n:
		var w: String = String(SL_WORDS[_sl_draw()])
		sl_tally[w] = int(sl_tally.get(w, 0)) + 1
	var parts: PackedStringArray = []
	for w in sl_tally.keys():
		parts.append("%s x%d" % [w, sl_tally[w]])
	sl_result.text = "\"The cat sat on the ___\"   chosen so far:   " + "   ".join(parts)


func _build_sampling_ui(layer: CanvasLayer) -> void:
	sl_panel = PanelContainer.new()
	sl_panel.anchor_left = 0.5
	sl_panel.anchor_right = 0.5
	sl_panel.anchor_top = 0.5
	sl_panel.anchor_bottom = 0.5
	sl_panel.offset_left = -400
	sl_panel.offset_right = 400
	sl_panel.offset_top = -260
	sl_panel.offset_bottom = 260
	sl_panel.add_theme_stylebox_override("panel", _panel_style())
	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	sl_panel.add_child(vb)
	var title: Label = Label.new()
	title.text = "SAMPLING LAB  -  how a model chooses the next word"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	vb.add_child(title)
	var ex: Label = Label.new()
	ex.text = "After \"The cat sat on the\" the model gives every word a score. Temperature and top-k decide how those scores become a choice. Drag the sliders, then press Sample to let the model choose."
	ex.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ex.custom_minimum_size = Vector2(760, 0)
	vb.add_child(ex)
	var r1: HBoxContainer = HBoxContainer.new()
	vb.add_child(r1)
	var l1: Label = Label.new()
	l1.text = "Temperature  "
	l1.custom_minimum_size = Vector2(110, 0)
	r1.add_child(l1)
	sl_temp = HSlider.new()
	sl_temp.min_value = 0.1
	sl_temp.max_value = 3.0
	sl_temp.step = 0.05
	sl_temp.value = 1.0
	sl_temp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl_temp.value_changed.connect(_sl_update)
	r1.add_child(sl_temp)
	var r2: HBoxContainer = HBoxContainer.new()
	vb.add_child(r2)
	var l2: Label = Label.new()
	l2.text = "Top-k  "
	l2.custom_minimum_size = Vector2(110, 0)
	r2.add_child(l2)
	sl_topk = HSlider.new()
	sl_topk.min_value = 1
	sl_topk.max_value = SL_WORDS.size()
	sl_topk.step = 1
	sl_topk.value = SL_WORDS.size()
	sl_topk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl_topk.value_changed.connect(_sl_update)
	r2.add_child(sl_topk)
	sl_info = Label.new()
	sl_info.modulate = Color(0.7, 0.85, 1.0)
	vb.add_child(sl_info)
	for i in SL_WORDS.size():
		var row: HBoxContainer = HBoxContainer.new()
		vb.add_child(row)
		var wl: Label = Label.new()
		wl.text = String(SL_WORDS[i])
		wl.custom_minimum_size = Vector2(70, 0)
		row.add_child(wl)
		var pb: ProgressBar = ProgressBar.new()
		pb.max_value = 100.0
		pb.show_percentage = false
		pb.custom_minimum_size = Vector2(560, 20)
		pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(pb)
		sl_bars.append(pb)
		var pl: Label = Label.new()
		pl.custom_minimum_size = Vector2(50, 0)
		row.add_child(pl)
		sl_pcts.append(pl)
	var br: HBoxContainer = HBoxContainer.new()
	vb.add_child(br)
	_add_button(br, "Sample 1 word", func() -> void: _sl_sample(1))
	_add_button(br, "Sample 20 times", func() -> void: _sl_sample(20))
	_add_button(br, "Clear", func() -> void:
		sl_tally.clear()
		sl_result.text = "")
	_add_button(br, "Close  (K)", func() -> void: _toggle_sampling())
	sl_result = Label.new()
	sl_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sl_result.modulate = Color(0.75, 1.0, 0.8)
	vb.add_child(sl_result)
	sl_panel.visible = false
	layer.add_child(sl_panel)
	_sl_update()


func _toggle_sampling() -> void:
	if demo_running:
		_stop_demo()
	if quiz_active:
		_end_quiz()
	menu_panel.visible = false
	lab_panel.visible = false
	al_panel.visible = false
	sl_panel.visible = not sl_panel.visible
	if sl_panel.visible:
		_sl2_update()
		_fit_panel(sl_panel)


# ── Attention Lab: scaled dot-product attention, computed live on small illustrative vectors ──
# Each word has a QUERY ("what am I looking for?") and a KEY ("what am I?") over 5 features:
# [entity, action, object, state, function-word].  score = 4 * Q.K - 0.25 * distance, then softmax per row.
const AL_FEATURES: String = "features: entity, action, object, state, function word"
const AL_SENTENCES: Array = [
	{
		"name": "The cat sat on the mat",
		"hint": "Notice: 'the' looks for the noun right after it, 'cat' looks for its verb, and 'mat' looks back at the preposition 'on'.",
		"tip": "Try clicking “the” or “mat” - each word looks for a different partner.",
		"words": ["the", "cat", "sat", "on", "the", "mat"],
		"k": [[0, 0, 0, 0, 1], [1, 0, 0, 0, 0], [0, 1, 0, 0, 0], [0, 0, 0, 0, 1], [0, 0, 0, 0, 1], [0, 0, 1, 0, 0]],
		"q": [[1, 0, 1, 0, 0], [0, 1, 0, 0, 0], [1, 0, 1, 0, 0], [0, 0, 1, 0, 0], [0, 0, 1, 0, 0], [0, 0, 0, 0, 1]],
	},
	{
		"name": "The animal did not cross the road because it was tired",
		"hint": "The famous puzzle: what does 'it' refer to? Select 'it': most attention goes to 'animal', not 'road'. Attention resolves the reference.",
		"tip": "Puzzle: who was tired - the animal or the road?  Look where “it” points.",
		"words": ["the", "animal", "did", "not", "cross", "the", "road", "because", "it", "was", "tired"],
		"k": [[0, 0, 0, 0, 1], [1, 0, 0, 0, 0], [0, 1, 0, 0, 0], [0, 0, 0, 0, 1], [0, 1, 0, 0, 0], [0, 0, 0, 0, 1], [0, 0, 1, 0, 0], [0, 0, 0, 0, 1], [0.5, 0, 0, 0, 0.5], [0, 1, 0, 0, 0], [0, 0, 0, 1, 0]],
		"q": [[1, 0, 1, 0, 0], [0, 1, 0, 0, 0], [1, 0, 0, 0, 0], [0, 1, 0, 0, 0], [1, 0, 1, 0, 0], [0, 0, 1, 0, 0], [0, 1, 0, 0, 0], [0, 1, 0, 0, 0], [1, 0, 0, 0, 0], [1, 0, 0, 0, 0], [1, 0, 0, 0, 0]],
	},
]
const AL_DET: Array = ["the", "a", "an", "this", "that", "these", "those", "my", "your", "his", "her", "its", "our", "their", "some", "any", "every", "each", "no"]
const AL_PREP: Array = ["on", "in", "at", "by", "with", "from", "to", "of", "for", "about", "over", "under", "between", "into", "through", "after", "before", "near", "across", "behind", "above", "below"]
const AL_PRON: Array = ["it", "he", "she", "they", "them", "him", "her", "we", "you", "i", "me", "us", "this", "which", "who"]
const AL_AUX: Array = ["is", "are", "was", "were", "be", "been", "am", "do", "does", "did", "has", "have", "had", "will", "would", "can", "could", "should", "may", "might", "not"]
const AL_CONJ: Array = ["and", "but", "or", "because", "so", "if", "while", "although", "when", "than", "that"]
const AL_VERB: Array = ["sat", "sit", "ran", "run", "ate", "eat", "saw", "see", "went", "go", "made", "make", "took", "take", "gave", "give", "chased", "jumped", "read", "wrote", "write", "said", "say", "got", "get", "came", "come", "found", "find", "know", "knew", "think", "thought", "love", "loves", "like", "likes", "need", "needs", "want", "wants", "cross", "crossed", "learn", "learns", "predict", "predicts", "process", "processes", "train", "trains", "build", "builds", "use", "uses", "show", "shows"]
const AL_VERB2: Array = ["sing", "sings", "sang", "play", "plays", "played", "walk", "walks", "walked", "talk", "talks", "speak", "speaks", "fly", "flies", "swim", "swims", "drive", "drives", "open", "opens", "close", "closes", "start", "starts", "begin", "begins", "help", "helps", "work", "works", "worked", "live", "lives", "lived", "call", "calls", "ask", "asks", "tell", "tells", "try", "tries", "feel", "feels", "leave", "leaves", "put", "keep", "keeps", "let", "mean", "means", "become", "becomes", "bring", "brings", "hold", "holds", "stand", "stands", "hear", "hears", "watch", "watches", "follow", "follows", "stop", "stops", "create", "creates", "change", "changes", "move", "moves", "teach", "teaches", "study", "studies", "understand", "understands", "remember", "remembers", "answer", "answers", "explain", "explains", "solve", "solves", "break", "breaks", "send", "sends", "receive", "receives", "grow", "grows", "paint", "paints", "cook", "cooks", "drink", "drinks", "sleep", "sleeps", "run", "runs", "jump", "jumps", "catch", "catches", "throw", "throws", "buy", "buys", "sell", "sells", "pay", "pays", "meet", "meets", "visit", "visits", "wait", "waits", "wear", "wears"]
const AL_ADV: Array = ["very", "quite", "really", "too", "so", "also", "always", "never", "often", "now", "then", "here", "there", "just", "still", "even", "almost", "already", "soon", "again", "today", "tomorrow", "yesterday", "well", "fast", "hard", "rather", "extremely", "totally"]
const AL_ING_NOUNS: Array = ["morning", "evening", "thing", "something", "nothing", "anything", "everything", "king", "ring", "spring", "wing", "string", "building", "ceiling", "painting", "meeting", "feeling", "ending", "beginning", "learning", "training", "reading", "writing"]
const AL_ADJ: Array = ["big", "small", "tired", "hungry", "fast", "slow", "red", "blue", "green", "old", "new", "good", "bad", "happy", "sad", "large", "little", "long", "short", "hot", "cold", "smart", "quick", "lazy", "bright", "dark", "wide", "narrow", "deep", "simple", "powerful"]
const AL_CLASS_NAME: Dictionary = {"det": "determiner", "prep": "preposition", "pron": "pronoun", "aux": "helper verb", "conj": "connector", "verb": "verb", "adj": "adjective", "adv": "adverb", "noun": "noun"}
var al_cur: Dictionary = {}
var al_edit: LineEdit
var al_types: Label


func _al_classify(word: String) -> String:
	var w: String = word.to_lower()
	if AL_DET.has(w) and not AL_PRON.has(w):
		return "det"
	if AL_PRON.has(w):
		return "pron"
	if AL_PREP.has(w):
		return "prep"
	if AL_AUX.has(w):
		return "aux"
	if AL_CONJ.has(w):
		return "conj"
	if AL_ING_NOUNS.has(w):
		return "noun"
	if AL_ADV.has(w):
		return "adv"
	if AL_VERB.has(w) or AL_VERB2.has(w):
		return "verb"
	if AL_ADJ.has(w):
		return "adj"
	if w.ends_with("ly") and w.length() > 3:
		return "adv"
	if (w.ends_with("ing") or w.ends_with("ed")) and w.length() > 4:
		return "verb"
	# ("-al" is left out on purpose: animal, signal, capital, hospital are nouns)
	if w.ends_with("ful") or w.ends_with("ous") or w.ends_with("ive") or w.ends_with("able") or w.ends_with("ical"):
		return "adj"
	return "noun"


## Query / key vectors per word type (features: entity, action, object, state, function word).
func _al_qk(cls: String) -> Array:
	match cls:
		"det":
			return [[1, 0, 1, 0, 0], [0, 0, 0, 0, 1]]
		"noun":
			return [[0, 1, 0, 0, 0], [0.8, 0, 0.35, 0, 0]]
		"verb":
			return [[1, 0, 1, 0, 0], [0, 1, 0, 0, 0]]
		"aux":
			return [[1, 0, 0, 0, 0], [0, 1, 0, 0, 0.3]]
		"prep":
			return [[0, 0, 1, 0, 0], [0, 0, 0, 0, 1]]
		"pron":
			return [[1.6, 0, 0, 0, 0], [0.5, 0, 0, 0, 0.5]]
		"adj":
			return [[1, 0, 0, 0, 0], [0, 0, 0, 1, 0]]
		"adv":
			return [[0, 1, 0, 0, 0], [0, 0, 0, 0.6, 0]]
	return [[0, 1, 0, 0, 0], [0, 0, 0, 0, 1]]   # connector


func _al_from_text(text: String) -> void:
	var words: Array = []
	var cur: String = ""
	for ch in text + " ":
		if (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9") or ch == "'":
			cur += ch
		else:
			if cur != "":
				words.append(cur)
				cur = ""
	if words.size() > 14:
		words = words.slice(0, 14)
	if words.size() < 2:
		words = ["the", "cat", "sat"]
	var q: Array = []
	var k: Array = []
	var tags: PackedStringArray = []
	for w in words:
		var cls: String = _al_classify(String(w))
		var qk: Array = _al_qk(cls)
		q.append(qk[0])
		k.append(qk[1])
		tags.append("%s = %s" % [w, AL_CLASS_NAME[cls]])
	al_cur = {"name": "custom", "hint": "Your own sentence. Determiners look for their noun, nouns look for their verb, verbs look for who and what, pronouns look back for the thing they refer to.", "tip": "Your sentence!  Try clicking a pronoun (it, she, they) or a verb.", "words": words, "q": q, "k": k, "tags": ", ".join(tags)}


func _al_load_preset(i: int) -> void:
	al_cur = (AL_SENTENCES[i] as Dictionary).duplicate()
	var tags: PackedStringArray = []
	for w in al_cur["words"]:
		tags.append("%s = %s" % [w, AL_CLASS_NAME[_al_classify(String(w))]])
	al_cur["tags"] = ", ".join(tags)


var al_panel: PanelContainer
var al_sent: int = 0
var al_sel: int = 1
var al_masked: bool = false
var al_view: AttentionView
var al_grid: GridContainer
var al_text: Label
var al_hint: Label


func _al_matrix() -> Array:
	var s: Dictionary = al_cur
	var n: int = (s["words"] as Array).size()
	var m: Array = []
	for i in n:
		var z: PackedFloat32Array = PackedFloat32Array()
		for j in n:
			if al_masked and j > i:
				z.append(-1000.0)
				continue
			var dot: float = 0.0
			for d in 5:
				dot += float(s["q"][i][d]) * float(s["k"][j][d])
			z.append(4.0 * dot - 0.25 * absf(float(i - j)))
		m.append(_softmax(z))
	return m


func _al_cell(text: String, bg: Color, w: float = 46.0, bold: bool = false) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(w, 22)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 12)
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg
	l.add_theme_stylebox_override("normal", sb)
	if bold:
		l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	return l


func _al_update() -> void:
	if al_cur.is_empty():
		_al_load_preset(0)
	var s: Dictionary = al_cur
	var words: Array = s["words"]
	var n: int = words.size()
	al_sel = clampi(al_sel, 0, n - 1)
	var m: Array = _al_matrix()
	var row: PackedFloat32Array = m[al_sel]
	var types: Array = []
	for w in words:
		types.append(AL_CLASS_NAME[_al_classify(String(w))])
	al_view.set_data(words, types, row, al_sel, al_masked)
	for c in al_grid.get_children():
		al_grid.remove_child(c)
		c.queue_free()
	al_grid.columns = n + 1
	al_grid.add_child(_al_cell("", Color(0, 0, 0, 0), 64.0))
	for j in n:
		al_grid.add_child(_al_cell(String(words[j]), Color(0.1, 0.14, 0.22), 46.0, j == al_sel))
	for i in n:
		al_grid.add_child(_al_cell(String(words[i]), Color(0.1, 0.14, 0.22), 64.0, i == al_sel))
		for j in n:
			var v: float = m[i][j]
			var col: Color = Color(0.06, 0.08, 0.12).lerp(Color(1.0, 0.55, 0.15), clampf(v * 1.15, 0.0, 1.0))
			al_grid.add_child(_al_cell("%d" % roundi(v * 100.0) if v > 0.005 else "", col))
	# one short, plain sentence about the strongest link (ignoring the word looking at itself)
	var best: int = -1
	for j in n:
		if j != al_sel and (best < 0 or row[j] > row[best]):
			best = j
	if best >= 0:
		al_text.text = "\"%s\"  looks mostly at  \"%s\"   (%d%%)" % [words[al_sel], words[best], roundi(row[best] * 100.0)]
	al_hint.text = String(s.get("tip", s["hint"])) if not al_masked else "No peeking: a word can only look back, never ahead - that's how a model writes text, one word at a time."


func _build_attention_ui(layer: CanvasLayer) -> void:
	al_panel = PanelContainer.new()
	al_panel.anchor_left = 0.5
	al_panel.anchor_right = 0.5
	al_panel.anchor_top = 0.5
	al_panel.anchor_bottom = 0.5
	al_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	al_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	al_panel.add_theme_stylebox_override("panel", _panel_style())
	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	al_panel.add_child(vb)
	_lab_header(vb, "ATTENTION LAB", "Click any word - the arrows show which words it pays attention to.")
	var top: HBoxContainer = HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	vb.add_child(top)
	al_edit = LineEdit.new()
	al_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	al_edit.custom_minimum_size = Vector2(0, 40)
	al_edit.add_theme_font_size_override("font_size", 17)
	al_edit.placeholder_text = "Type your own sentence..."
	al_edit.text = "The cat sat on the mat"
	al_edit.text_changed.connect(func(txt: String) -> void:
		_al_from_text(txt)
		al_sel = clampi(al_sel, 0, (al_cur["words"] as Array).size() - 1)
		_al_update())
	top.add_child(al_edit)
	for si in AL_SENTENCES.size():
		var sidx: int = si
		_add_button(top, ["Cat example", "\"it\" puzzle"][si], func() -> void:
			al_sent = sidx
			_al_load_preset(sidx)
			al_sel = 1 if sidx == 0 else 8
			al_edit.text = " ".join(al_cur["words"])
			_al_update())
	var mask: CheckButton = CheckButton.new()
	mask.text = "No peeking ahead"
	mask.tooltip_text = "Masked attention: each word may only look at earlier words - how a model writes text"
	mask.focus_mode = Control.FOCUS_NONE
	mask.toggled.connect(func(on: bool) -> void:
		al_masked = on
		_al_update())
	top.add_child(mask)
	al_view = AttentionView.new()
	al_view.custom_minimum_size = Vector2(980, 240)
	al_view.word_clicked.connect(func(i: int) -> void:
		al_sel = i
		_play_sfx(sfx_pop, -16.0)
		_al_update())
	vb.add_child(al_view)
	al_text = Label.new()
	al_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	al_text.add_theme_font_size_override("font_size", 20)
	al_text.add_theme_color_override("font_color", Color(1.0, 0.8, 0.45))
	vb.add_child(al_text)
	al_hint = Label.new()
	al_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	al_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	al_hint.custom_minimum_size = Vector2(980, 0)
	al_hint.add_theme_font_size_override("font_size", 15)
	al_hint.add_theme_color_override("font_color", Color(0.72, 0.84, 1.0))
	vb.add_child(al_hint)
	var det: VBoxContainer = _lab_details(vb, al_panel, "How is attention calculated?  (full map + maths)")
	var dn: Label = _small_note(det, "Every word asks a question (its query: \"what am I looking for?\") and every word offers an answer (its key: \"what am I?\"). The better they match, the more attention. Each row of the map below adds up to 100%.")
	dn.custom_minimum_size = Vector2(980, 0)
	al_grid = GridContainer.new()
	al_grid.add_theme_constant_override("h_separation", 2)
	al_grid.add_theme_constant_override("v_separation", 2)
	det.add_child(al_grid)
	var fl: Label = _small_note(det, "Rows = the word that looks, columns = the word looked at.   score = 4 × Q·K − 0.25 × distance, then softmax.   Illustrative vectors (" + AL_FEATURES + ") - real models learn thousands of such features.")
	fl.custom_minimum_size = Vector2(980, 0)
	_add_button(vb, "Close  (A)", func() -> void: _toggle_attention())
	al_panel.visible = false
	layer.add_child(al_panel)


func _toggle_attention() -> void:
	if demo_running:
		_stop_demo()
	if quiz_active:
		_end_quiz()
	menu_panel.visible = false
	lab_panel.visible = false
	sl_panel.visible = false
	al_panel.visible = not al_panel.visible
	if al_panel.visible:
		_al_update()
		_fit_panel(al_panel)


# ── Start menu ──
## App-wide visual design: one consistent look for every button, menu, slider, text box and bar.
func _apply_theme() -> void:
	var th: Theme = Theme.new()
	var text_col: Color = Color(0.9, 0.95, 1.0)
	var accent: Color = Color(0.25, 0.6, 1.0)
	var norm: StyleBoxFlat = StyleBoxFlat.new()
	norm.bg_color = Color(0.1, 0.14, 0.22, 0.9)
	norm.border_color = Color(0.25, 0.4, 0.65, 0.5)
	norm.set_border_width_all(1)
	norm.set_corner_radius_all(9)
	norm.content_margin_left = 14
	norm.content_margin_right = 14
	norm.content_margin_top = 7
	norm.content_margin_bottom = 7
	var hov: StyleBoxFlat = norm.duplicate()
	hov.bg_color = Color(0.16, 0.26, 0.42, 0.95)
	hov.border_color = accent
	var prs: StyleBoxFlat = norm.duplicate()
	prs.bg_color = Color(0.12, 0.4, 0.75, 0.95)
	prs.border_color = accent.lightened(0.3)
	for t in ["Button", "MenuButton", "CheckButton"]:
		th.set_stylebox("normal", t, norm)
		th.set_stylebox("hover", t, hov)
		th.set_stylebox("pressed", t, prs)
		th.set_stylebox("hover_pressed", t, prs)
		th.set_stylebox("focus", t, StyleBoxEmpty.new())
		th.set_color("font_color", t, text_col)
		th.set_color("font_hover_color", t, Color.WHITE)
		th.set_color("font_pressed_color", t, Color.WHITE)
		th.set_font_size("font_size", t, 15)
	th.set_font_size("font_size", "Label", 15)
	th.set_color("font_color", "Label", text_col)
	var pop: StyleBoxFlat = StyleBoxFlat.new()
	pop.bg_color = Color(0.05, 0.08, 0.14, 0.98)
	pop.border_color = Color(0.25, 0.5, 0.85, 0.7)
	pop.set_border_width_all(1)
	pop.set_corner_radius_all(10)
	pop.set_content_margin_all(8)
	th.set_stylebox("panel", "PopupMenu", pop)
	th.set_stylebox("hover", "PopupMenu", hov)
	th.set_font_size("font_size", "PopupMenu", 15)
	th.set_constant("v_separation", "PopupMenu", 8)
	var le: StyleBoxFlat = norm.duplicate()
	le.bg_color = Color(0.04, 0.06, 0.11, 0.95)
	th.set_stylebox("normal", "LineEdit", le)
	th.set_stylebox("focus", "LineEdit", hov)
	th.set_color("font_color", "LineEdit", text_col)
	th.set_font_size("font_size", "LineEdit", 15)
	var track: StyleBoxFlat = StyleBoxFlat.new()
	track.bg_color = Color(0.1, 0.14, 0.22, 0.9)
	track.set_corner_radius_all(6)
	track.content_margin_top = 5
	track.content_margin_bottom = 5
	var fill: StyleBoxFlat = track.duplicate()
	fill.bg_color = accent
	th.set_stylebox("background", "ProgressBar", track)
	th.set_stylebox("fill", "ProgressBar", fill)
	th.set_stylebox("slider", "HSlider", track)
	th.set_stylebox("grabber_area", "HSlider", fill)
	th.set_stylebox("grabber_area_highlight", "HSlider", fill)
	app_theme = th
	get_window().theme = th
	if IS_WEB:   # browsers have no system fonts: bundle symbol / emoji fallbacks so ▶ 🎤 ☰ … don't show as boxes
		var extra: Array[Font] = []
		for fp in ["res://assets/fonts/NotoSansSymbols2.ttf", "res://assets/fonts/NotoSansSymbols.ttf", "res://assets/fonts/NotoEmoji.ttf"]:
			if ResourceLoader.exists(fp):
				extra.append(load(fp) as Font)
		var base: Font = ThemeDB.fallback_font
		var fbs: Array[Font] = base.fallbacks.duplicate()
		fbs.append_array(extra)
		base.fallbacks = fbs


var app_theme: Theme


## Godot does not hand a window theme through a CanvasLayer, so give it to every top-level control of every layer.
func _theme_layers() -> void:
	for ch in get_children():
		if ch is CanvasLayer:
			for c in ch.get_children():
				if c is Control:
					(c as Control).theme = app_theme


const MENU_INFO: Dictionary = {
	"GUIDED TOUR": "Sit back and watch: a narrated lesson with live visuals, one idea at a time.",
	"QUIZ": "Answer by picking the right concept in the 3D graph - every correct answer turns it gold.",
	"EXPLORE": "Free play: click concepts, follow their connections, and ask the AI tutor anything.",
	"TOKEN LAB": "Type any sentence and watch a real tokenizer cut it into tokens.",
	"ATTENTION LAB": "Click a word and see which other words the model pays attention to.",
	"SAMPLING LAB": "Drag temperature and top-k and see how a model chooses its next word.",
}
var menu_logo: TextureRect
var menu_title: Label
var menu_bar: ProgressBar
var menu_hint: Label
var menu_cards: Array = []
var menu_actions: Array = []


func _card(parent: Node, symbol: String, title: String, sub: String, col: Color, cb: Callable) -> void:
	var b: Button = Button.new()
	b.custom_minimum_size = Vector2(250, 150)
	b.focus_mode = Control.FOCUS_NONE
	b.pivot_offset = Vector2(125, 75)
	var n: StyleBoxFlat = StyleBoxFlat.new()
	n.bg_color = Color(0.06, 0.09, 0.15, 0.96)
	n.border_color = col.darkened(0.25)
	n.set_border_width_all(2)
	n.set_corner_radius_all(18)
	n.shadow_color = Color(col.r, col.g, col.b, 0.18)
	n.shadow_size = 10
	var h: StyleBoxFlat = n.duplicate()
	h.bg_color = col.darkened(0.7)
	h.border_color = col.lightened(0.25)
	h.shadow_size = 18
	h.shadow_color = Color(col.r, col.g, col.b, 0.4)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", h)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var vb: VBoxContainer = VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 14
	vb.offset_right = -14
	vb.offset_top = 12
	vb.offset_bottom = -12
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 4)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(vb)
	var ic: Label = Label.new()
	ic.text = symbol
	ic.add_theme_font_size_override("font_size", 40)
	ic.add_theme_color_override("font_color", col.lightened(0.2))
	ic.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(ic)
	var tl: Label = Label.new()
	tl.text = title
	tl.add_theme_font_size_override("font_size", 18)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(tl)
	var sl: Label = Label.new()
	sl.text = sub
	sl.add_theme_font_size_override("font_size", 13)
	sl.modulate = Color(0.75, 0.82, 0.95, 0.75)
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(sl)
	var info: String = String(MENU_INFO.get(title, ""))
	b.mouse_entered.connect(func() -> void:
		create_tween().tween_property(b, "scale", Vector2(1.07, 1.07), 0.12)
		if menu_hint != null:
			menu_hint.text = info)
	b.mouse_exited.connect(func() -> void:
		create_tween().tween_property(b, "scale", Vector2.ONE, 0.12)
		if menu_hint != null:
			menu_hint.text = "Choose how you want to learn  -  or press 1 to 6")
	b.pressed.connect(cb)
	var badge: Label = Label.new()
	badge.text = str(menu_actions.size() + 1)
	badge.position = Vector2(14, 8)
	badge.add_theme_font_size_override("font_size", 13)
	badge.add_theme_color_override("font_color", Color(col.r, col.g, col.b, 0.8))
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(badge)
	menu_actions.append(cb)
	menu_cards.append(b)
	parent.add_child(b)


func _grad(horizontal: bool, a0: Color, a1: Color) -> GradientTexture2D:
	var g: Gradient = Gradient.new()
	g.colors = PackedColorArray([a0, a1])
	g.offsets = PackedFloat32Array([0.0, 1.0])
	var tex: GradientTexture2D = GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_LINEAR
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(1, 0) if horizontal else Vector2(0, 1)
	tex.width = 256
	tex.height = 256
	return tex


## A streaming-app style tile: full-bleed artwork, dark gradient, title + subtitle, hover zoom.
func _art_tile(parent: Node, art_path: String, title: String, sub: String, col: Color, min_size: Vector2, cb: Callable, big: bool = false) -> Button:
	var b: Button = Button.new()
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE
	b.clip_contents = true
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pivot_offset = min_size * 0.5
	var n: StyleBoxFlat = StyleBoxFlat.new()
	n.bg_color = Color(0.05, 0.07, 0.12)
	n.border_color = col.darkened(0.3)
	n.set_border_width_all(2)
	n.set_corner_radius_all(16)
	n.shadow_color = Color(col.r, col.g, col.b, 0.18)
	n.shadow_size = 10
	var h: StyleBoxFlat = n.duplicate()
	h.border_color = col.lightened(0.3)
	h.shadow_size = 22
	h.shadow_color = Color(col.r, col.g, col.b, 0.5)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", h)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var art_tr: TextureRect = null
	if art_path != "" and ResourceLoader.exists(art_path):
		art_tr = TextureRect.new()
		art_tr.texture = load(art_path)
		art_tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art_tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art_tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		art_tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art_tr.modulate = Color(0.82, 0.82, 0.82)
		b.add_child(art_tr)
	var ov: TextureRect = TextureRect.new()
	ov.texture = _grad(big, Color(0.01, 0.02, 0.06, 0.92) if big else Color(0.0, 0.0, 0.0, 0.0), Color(0.01, 0.02, 0.06, 0.0) if big else Color(0.0, 0.0, 0.0, 0.92))
	ov.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ov.stretch_mode = TextureRect.STRETCH_SCALE
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(ov)
	var tv: VBoxContainer = VBoxContainer.new()
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.add_theme_constant_override("separation", 4)
	if big:
		tv.set_anchors_preset(Control.PRESET_FULL_RECT)
		tv.anchor_right = 0.58
		tv.offset_left = 30
		tv.offset_top = 14
		tv.offset_bottom = -14
		tv.alignment = BoxContainer.ALIGNMENT_CENTER
	else:
		tv.set_anchors_preset(Control.PRESET_FULL_RECT)
		tv.offset_left = 14
		tv.offset_right = -14
		tv.offset_bottom = -14
		tv.offset_top = 14
		tv.alignment = BoxContainer.ALIGNMENT_END
	b.add_child(tv)
	if big:
		var kicker: Label = Label.new()
		kicker.text = "START HERE"
		kicker.add_theme_font_size_override("font_size", 13)
		kicker.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
		kicker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tv.add_child(kicker)
	var tl: Label = Label.new()
	tl.text = title.capitalize() if big else title
	tl.add_theme_font_size_override("font_size", 40 if big else 18)
	tl.add_theme_color_override("font_color", Color.WHITE)
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.add_child(tl)
	var sl: Label = Label.new()
	sl.text = sub
	sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sl.add_theme_font_size_override("font_size", 16 if big else 13)
	sl.modulate = Color(0.85, 0.9, 1.0, 0.85)
	sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.add_child(sl)
	var info: String = String(MENU_INFO.get(title, ""))
	b.mouse_entered.connect(func() -> void:
		var tw: Tween = create_tween().set_parallel(true)
		tw.tween_property(b, "scale", Vector2(1.015, 1.015) if big else Vector2(1.05, 1.05), 0.14)
		if art_tr != null:
			tw.tween_property(art_tr, "modulate", Color.WHITE, 0.14)
		if menu_hint != null:
			menu_hint.text = info)
	b.mouse_exited.connect(func() -> void:
		var tw2: Tween = create_tween().set_parallel(true)
		tw2.tween_property(b, "scale", Vector2.ONE, 0.14)
		if art_tr != null:
			tw2.tween_property(art_tr, "modulate", Color(0.82, 0.82, 0.82), 0.14)
		if menu_hint != null:
			menu_hint.text = "Choose how you want to learn  -  or press 1 to 6")
	b.pressed.connect(cb)
	var badge: Label = Label.new()
	badge.text = str(menu_actions.size() + 1)
	badge.position = Vector2(12, 8)
	badge.add_theme_font_size_override("font_size", 13)
	badge.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(badge)
	menu_actions.append(cb)
	menu_cards.append(b)
	parent.add_child(b)
	return b


func _build_menu(layer: CanvasLayer) -> void:
	menu_panel = PanelContainer.new()
	menu_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg0: StyleBoxFlat = StyleBoxFlat.new()
	bg0.bg_color = Color(0.008, 0.012, 0.04, 1.0)
	menu_panel.add_theme_stylebox_override("panel", bg0)
	menu_panel.add_child(MenuBackdrop.new())
	menu_cards.clear()
	menu_actions.clear()
	var mg: MarginContainer = MarginContainer.new()
	mg.add_theme_constant_override("margin_left", 56)
	mg.add_theme_constant_override("margin_right", 56)
	mg.add_theme_constant_override("margin_top", 34)
	mg.add_theme_constant_override("margin_bottom", 26)
	menu_panel.add_child(mg)
	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	mg.add_child(vb)
	# header: logo, name, course switcher
	var head: HBoxContainer = HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	vb.add_child(head)
	if ResourceLoader.exists("res://assets/generated/neurograph_logo.png"):
		var lg: TextureRect = TextureRect.new()
		lg.texture = load("res://assets/generated/neurograph_logo.png")
		lg.custom_minimum_size = Vector2(64, 64)
		lg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		lg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		head.add_child(lg)
		menu_logo = lg
	var tcol: VBoxContainer = VBoxContainer.new()
	tcol.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(tcol)
	var title: Label = Label.new()
	title.text = "NEUROGRAPH XR"
	menu_title = title
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.6, 0.88, 1.0))
	tcol.add_child(title)
	var sub: Label = Label.new()
	sub.text = "Learn how AI works by exploring it in 3D"
	sub.add_theme_font_size_override("font_size", 14)
	sub.modulate = Color(0.75, 0.85, 1.0, 0.8)
	tcol.add_child(sub)
	var sp: Control = Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var cl: Label = Label.new()
	cl.text = "COURSE"
	cl.modulate = Color(1.0, 0.85, 0.35, 0.8)
	cl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(cl)
	for i in COURSES.size():
		var idx: int = i
		var cb: Button = Button.new()
		cb.focus_mode = Control.FOCUS_NONE
		cb.custom_minimum_size = Vector2(200, 38)
		cb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cb.pressed.connect(func() -> void:
			_set_course(idx)
			_refresh_menu())
		head.add_child(cb)
		menu_course_btns.append(cb)
	# hero banner = the guided tour, with your progress
	var hero: Button = _art_tile(vb, "res://assets/generated/hd_hero.png", "GUIDED TOUR", "A narrated lesson that explains the whole course, step by step.", Color(0.25, 0.6, 1.0), Vector2(0, 236), func() -> void:
		menu_panel.visible = false
		if not demo_running:
			_toggle_demo(), true)
	var htv: Control = hero.get_child(2)
	var pill: PanelContainer = PanelContainer.new()
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var psb: StyleBoxFlat = StyleBoxFlat.new()
	psb.bg_color = Color(0.1, 0.5, 0.95, 0.95)
	psb.set_corner_radius_all(22)
	psb.content_margin_left = 22
	psb.content_margin_right = 22
	psb.content_margin_top = 8
	psb.content_margin_bottom = 8
	pill.add_theme_stylebox_override("panel", psb)
	var pl: Label = Label.new()
	pl.text = "▶   Start the tour"
	pl.add_theme_font_size_override("font_size", 17)
	pl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(pl)
	htv.add_child(pill)
	menu_progress = Label.new()
	menu_progress.modulate = Color(0.75, 1.0, 0.8)
	menu_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	htv.add_child(menu_progress)
	menu_bar = ProgressBar.new()
	menu_bar.custom_minimum_size = Vector2(300, 6)
	menu_bar.show_percentage = false
	menu_bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	menu_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	htv.add_child(menu_bar)
	# practice and play
	var sec: Label = Label.new()
	sec.text = "PRACTICE AND PLAY"
	sec.add_theme_font_size_override("font_size", 14)
	sec.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	vb.add_child(sec)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(row)
	_art_tile(row, "res://assets/generated/hd_rag.png", "QUIZ", "Test yourself and unlock concepts", Color(1.0, 0.75, 0.2), Vector2(170, 168), func() -> void:
		menu_panel.visible = false
		_start_quiz())
	_art_tile(row, "res://assets/generated/hd_graph.png", "EXPLORE", "Click, drag and ask the AI", Color(0.95, 0.35, 0.6), Vector2(170, 168), func() -> void:
		menu_panel.visible = false)
	_art_tile(row, "res://assets/generated/hd_tokens.png", "TOKEN LAB", "Type text, see how a model splits it", Color(0.3, 0.65, 1.0), Vector2(170, 168), func() -> void:
		menu_panel.visible = false
		_toggle_lab())
	_art_tile(row, "res://assets/generated/hd_attention.png", "ATTENTION LAB", "See which words a word looks at", Color(1.0, 0.5, 0.2), Vector2(170, 168), func() -> void:
		menu_panel.visible = false
		_toggle_attention())
	_art_tile(row, "res://assets/generated/hd_prob.png", "SAMPLING LAB", "Drag temperature, watch it choose", Color(0.3, 0.85, 0.9), Vector2(170, 168), func() -> void:
		menu_panel.visible = false
		_toggle_sampling())
	menu_hint = Label.new()
	menu_hint.text = "Choose how you want to learn  -  or press 1 to 6"
	menu_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_hint.custom_minimum_size = Vector2(0, 26)
	menu_hint.add_theme_font_size_override("font_size", 15)
	menu_hint.add_theme_color_override("font_color", Color(1.0, 0.9, 0.55))
	vb.add_child(menu_hint)
	layer.add_child(menu_panel)


func _build_menu_v2_old(layer: CanvasLayer) -> void:
	menu_panel = PanelContainer.new()
	menu_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg: StyleBoxFlat = StyleBoxFlat.new()
	bg.bg_color = Color(0.008, 0.012, 0.04, 1.0)   # fully opaque: nothing of the 3D scene shows through
	menu_panel.add_theme_stylebox_override("panel", bg)
	menu_panel.add_child(MenuBackdrop.new())
	menu_cards.clear()
	menu_actions.clear()
	var center: CenterContainer = CenterContainer.new()
	menu_panel.add_child(center)
	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	center.add_child(vb)
	if ResourceLoader.exists("res://assets/generated/neurograph_logo.png"):
		var lg: TextureRect = TextureRect.new()
		lg.texture = load("res://assets/generated/neurograph_logo.png")
		lg.custom_minimum_size = Vector2(110, 110)
		lg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		lg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		vb.add_child(lg)
		menu_logo = lg
	var title: Label = Label.new()
	title.text = "NEUROGRAPH XR"
	menu_title = title
	title.add_theme_font_size_override("font_size", 46)
	title.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var sub: Label = Label.new()
	sub.text = "Learn how AI works by exploring it in 3D"
	sub.add_theme_font_size_override("font_size", 18)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.modulate = Color(0.75, 0.85, 1.0)
	vb.add_child(sub)
	var tabs: HBoxContainer = HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 10)
	vb.add_child(tabs)
	for i in COURSES.size():
		var idx: int = i
		var cb: Button = Button.new()
		cb.focus_mode = Control.FOCUS_NONE
		cb.custom_minimum_size = Vector2(230, 38)
		cb.pressed.connect(func() -> void:
			_set_course(idx)
			_refresh_menu())
		tabs.add_child(cb)
		menu_course_btns.append(cb)
	menu_progress = Label.new()
	menu_progress.modulate = Color(0.7, 0.95, 0.75)
	menu_progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(menu_progress)
	menu_bar = ProgressBar.new()
	menu_bar.custom_minimum_size = Vector2(360, 12)
	menu_bar.show_percentage = false
	menu_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(menu_bar)
	var grid: GridContainer = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	vb.add_child(grid)
	_card(grid, "▶", "GUIDED TOUR", "A narrated lesson,\nstep by step", Color(0.2, 0.6, 1.0), func() -> void:
		menu_panel.visible = false
		if not demo_running:
			_toggle_demo())
	_card(grid, "?", "QUIZ", "Test yourself and\nunlock concepts", Color(1.0, 0.75, 0.2), func() -> void:
		menu_panel.visible = false
		_start_quiz())
	_card(grid, "◎", "EXPLORE", "Click, drag and\nask the AI", Color(0.3, 0.85, 0.6), func() -> void:
		menu_panel.visible = false)
	_card(grid, "Aa", "TOKEN LAB", "Type text, see how a\nmodel splits it", Color(0.7, 0.5, 1.0), func() -> void:
		menu_panel.visible = false
		_toggle_lab())
	_card(grid, "≋", "ATTENTION LAB", "See which words a\nword looks at", Color(1.0, 0.5, 0.2), func() -> void:
		menu_panel.visible = false
		_toggle_attention())
	_card(grid, "↕", "SAMPLING LAB", "Drag temperature,\nwatch it choose", Color(1.0, 0.35, 0.5), func() -> void:
		menu_panel.visible = false
		_toggle_sampling())
	menu_hint = Label.new()
	menu_hint.text = "Choose how you want to learn  -  or press 1 to 6"
	menu_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_hint.custom_minimum_size = Vector2(0, 28)
	menu_hint.add_theme_font_size_override("font_size", 16)
	menu_hint.add_theme_color_override("font_color", Color(1.0, 0.9, 0.55))
	vb.add_child(menu_hint)
	var foot: Label = Label.new()
	foot.text = "Tip: press  ☰ Menu  at any time to return here          ·          NeuroGraph XR  v1.0"
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	foot.modulate = Color(0.7, 0.8, 0.95, 0.6)
	vb.add_child(foot)
	layer.add_child(menu_panel)


func _build_menu_old(layer: CanvasLayer) -> void:
	menu_panel = PanelContainer.new()
	menu_panel.anchor_left = 0.5
	menu_panel.anchor_right = 0.5
	menu_panel.anchor_top = 0.5
	menu_panel.anchor_bottom = 0.5
	menu_panel.offset_left = -300
	menu_panel.offset_right = 300
	menu_panel.offset_top = -230
	menu_panel.offset_bottom = 230
	menu_panel.add_theme_stylebox_override("panel", _panel_style())
	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	menu_panel.add_child(vb)
	var title: Label = Label.new()
	title.text = "NEUROGRAPH  XR"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var sub: Label = Label.new()
	sub.text = "Learn how AI works by exploring it in 3D"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.modulate = Color(0.75, 0.85, 1.0)
	vb.add_child(sub)
	var cl: Label = Label.new()
	cl.text = "1.  Choose a course"
	cl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	vb.add_child(cl)
	for i in COURSES.size():
		var idx: int = i
		var b: Button = Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func() -> void:
			_set_course(idx)
			_refresh_menu())
		vb.add_child(b)
		menu_course_btns.append(b)
	menu_progress = Label.new()
	menu_progress.modulate = Color(0.7, 0.9, 0.7)
	menu_progress.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(menu_progress)
	var al: Label = Label.new()
	al.text = "2.  Choose how to learn"
	al.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	vb.add_child(al)
	_add_button(vb, "▶   Guided tour  -  a narrated lesson, step by step", func() -> void:
		menu_panel.visible = false
		if not demo_running:
			_toggle_demo())
	_add_button(vb, "?   Quiz  -  test yourself and unlock concepts", func() -> void:
		menu_panel.visible = false
		_start_quiz())
	_add_button(vb, "⌨   Token Lab  -  type text, see how a model tokenizes it", func() -> void:
		menu_panel.visible = false
		_toggle_lab())
	_add_button(vb, "👁   Attention Lab  -  see which words a word looks at", func() -> void:
		menu_panel.visible = false
		_toggle_attention())
	_add_button(vb, "🎚   Sampling Lab  -  drag temperature and top-k, watch the model choose", func() -> void:
		menu_panel.visible = false
		_toggle_sampling())
	_add_button(vb, "◎   Explore freely  -  click, drag, ask the AI", func() -> void: menu_panel.visible = false)
	layer.add_child(menu_panel)


func _refresh_menu() -> void:
	for i in menu_course_btns.size():
		var cbtn: Button = menu_course_btns[i]
		cbtn.text = String(COURSES[i]["name"])
		cbtn.toggle_mode = true
		cbtn.button_pressed = (i == course_idx)
	var cp: Dictionary = progress.get(_course_key(), {})
	var total: int = (graph_data.get("nodes", []) as Array).size()
	var line: String = "Your progress:  %d / %d concepts mastered" % [mastered.size(), total]
	if cp.has("best"):
		line += "     |     best quiz score: %d / %d" % [int(cp["best"]), int(cp.get("best_of", 0))]
	menu_progress.text = line
	menu_bar.max_value = maxf(float(total), 1.0)
	create_tween().tween_property(menu_bar, "value", float(mastered.size()), 0.6)


## Home-screen entrance: the logo drops in, the title fades up, and the six cards pop in one after another.
func _animate_menu_in() -> void:
	await get_tree().process_frame   # wait until the layout has real sizes
	if menu_logo != null:
		menu_logo.modulate.a = 0.0
		menu_logo.pivot_offset = menu_logo.custom_minimum_size * 0.5
		menu_logo.scale = Vector2(1.6, 1.6)
		var lt: Tween = create_tween().set_parallel(true)
		lt.tween_property(menu_logo, "modulate:a", 1.0, 0.5)
		lt.tween_property(menu_logo, "scale", Vector2.ONE, 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if menu_title != null:
		menu_title.modulate.a = 0.0
		create_tween().tween_property(menu_title, "modulate:a", 1.0, 0.6).set_delay(0.25)
	for i in menu_cards.size():
		var c: Control = menu_cards[i]
		c.pivot_offset = c.size * 0.5
		c.modulate.a = 0.0
		c.scale = Vector2(0.7, 0.7)
		var tw: Tween = create_tween().set_parallel(true)
		tw.tween_property(c, "modulate:a", 1.0, 0.35).set_delay(0.45 + 0.09 * float(i))
		tw.tween_property(c, "scale", Vector2.ONE, 0.5).set_delay(0.45 + 0.09 * float(i)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _show_menu() -> void:
	if demo_running:
		_stop_demo()
	if quiz_active:
		_end_quiz()
	lab_panel.visible = false
	sl_panel.visible = false
	al_panel.visible = false
	_refresh_menu()
	menu_panel.modulate.a = 0.0
	menu_panel.visible = true
	create_tween().tween_property(menu_panel, "modulate:a", 1.0, 0.45)
	_animate_menu_in()


# ───────────────────────── courses ─────────────────────────
func _demo(key: String, def: Variant) -> Variant:
	var d: Dictionary = graph_data.get("demo", {})
	return d.get(key, def)


func _load_course(i: int) -> void:
	course_idx = i
	var c: Dictionary = COURSES[i]
	graph_data = _load_json(String(c["graph"]))
	net_data = _load_json(String(c["net"]))


func _switch_course() -> void:
	_set_course((course_idx + 1) % COURSES.size())


func _set_course(i: int) -> void:
	if demo_running:
		_stop_demo()
	if quiz_active:
		_end_quiz()
	_load_course(i)
	_apply_progress()
	if lab_panel != null and lab_panel.visible:
		_lab_update()
	_fill_legend()
	_set_mode(Mode.GRAPH)
	status_label.text = "Course: %s   (C = switch course)" % String(COURSES[course_idx]["name"])


func _fill_legend() -> void:
	for c in legend_box.get_children():
		c.queue_free()
	var lt: Label = Label.new()
	lt.text = "Filter by category"
	lt.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
	legend_box.add_child(lt)
	if graph_data.has("categories"):
		var cats: Dictionary = graph_data["categories"]
		for cat in cats.keys():
			var b: Button = Button.new()
			b.text = "● " + String(cat)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.focus_mode = Control.FOCUS_NONE
			b.add_theme_color_override("font_color", Color.html(cats[cat]))
			b.add_theme_color_override("font_hover_color", Color.WHITE)
			var cname: String = String(cat)
			b.pressed.connect(func() -> void: _set_filter(cname))
			legend_box.add_child(b)


func _classes() -> Array:
	return net_data.get("classes", CLASS_NAMES)


# ───────────────────────── setup ─────────────────────────
func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Missing data file: " + path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return parsed
	push_error("Invalid JSON: " + path)
	return {}


func _setup_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.015, 0.02, 0.05)
	_make_sky()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.55, 0.7)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.15
	env.glow_hdr_threshold = 0.9
	var we: WorldEnvironment = WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 35, 0)
	sun.light_energy = 0.8
	add_child(sun)
	edge_mat = StandardMaterial3D.new()
	edge_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	edge_mat.vertex_color_use_as_albedo = true
	edge_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_make_stars()
	_make_floor()
	_make_dust()
	_make_sel_light()


func _make_stars() -> void:
	stars = Node3D.new()
	add_child(stars)
	var sm: SphereMesh = SphereMesh.new()
	sm.radius = 0.2
	sm.height = 0.4
	sm.radial_segments = 6
	sm.rings = 3
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.8, 0.9, 1.0)
	sm.material = m
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = sm
	mm.instance_count = 600
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 3
	for i in mm.instance_count:
		var dir: Vector3 = Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		var s: float = rng.randf_range(0.3, 1.5)
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * s), dir * rng.randf_range(70.0, 150.0)))
	var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
	mmi.multimesh = mm
	stars.add_child(mmi)


func _panel_style() -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.035, 0.05, 0.1, 0.95)
	sb.border_color = Color(0.25, 0.55, 0.9, 0.7)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(12)
	return sb


func _setup_ui() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)

	# left: title, mode buttons, info
	var panel: PanelContainer = PanelContainer.new()
	panel.position = Vector2(14, 14)
	left_panel = panel
	panel.add_theme_stylebox_override("panel", _panel_style())
	layer.add_child(panel)
	var vb: VBoxContainer = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)
	var title: Label = Label.new()
	title.text = "NEUROGRAPH  XR"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
	vb.add_child(title)
	var row: HBoxContainer = HBoxContainer.new()
	vb.add_child(row)
	_add_button(row, "1 Graph", func() -> void: _set_mode(Mode.GRAPH))
	_add_button(row, "2 Neural Net", func() -> void: _set_mode(Mode.NETWORK))
	_add_button(row, "E Explode", func() -> void: _toggle_explode())
	_add_button(row, "F Forward pass", func() -> void: forward_pass = not forward_pass)
	_add_button(row, "T Spin", func() -> void: auto_rotate = not auto_rotate)
	_add_button(row, "R Reset", func() -> void: _reset_view())
	_add_button(row, "M Music", func() -> void: _toggle_music())
	var row2: HBoxContainer = HBoxContainer.new()
	vb.add_child(row2)
	_add_button(row2, "D ▶ GUIDED TOUR", func() -> void: _toggle_demo())
	_add_button(row2, "Q ? QUIZ", func() -> void: _toggle_quiz())
	_add_button(row2, "C Course", func() -> void: _switch_course())
	_add_button(row2, "L Token Lab", func() -> void: _toggle_lab())
	_add_button(row2, "K Sampling Lab", func() -> void: _toggle_sampling())
	_add_button(row2, "A Attention Lab", func() -> void: _toggle_attention())
	_add_button(row2, "H Menu", func() -> void: _show_menu())
	_add_button(row2, "G Guided tour", func() -> void: _toggle_tour())
	_add_button(row2, "V Voice", func() -> void: _toggle_voice())
	status_label = Label.new()
	status_label.modulate = Color(0.7, 0.85, 1.0)
	vb.add_child(status_label)
	info_label = Label.new()
	info_label.custom_minimum_size = Vector2(460, 0)
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(info_label)

	# right: legend / category filter
	legend_panel = PanelContainer.new()
	legend_panel.anchor_left = 1.0
	legend_panel.anchor_right = 1.0
	legend_panel.offset_left = -200
	legend_panel.offset_right = -14
	legend_panel.offset_top = 14
	legend_panel.add_theme_stylebox_override("panel", _panel_style())
	layer.add_child(legend_panel)
	legend_box = VBoxContainer.new()
	legend_panel.add_child(legend_box)
	_fill_legend()

	# bottom: suggested questions, answer, input
	var bottom: VBoxContainer = VBoxContainer.new()
	bottom.anchor_left = 0.0
	bottom.anchor_right = 1.0
	bottom.anchor_top = 1.0
	bottom.anchor_bottom = 1.0
	bottom.offset_left = 14
	bottom.offset_right = -14
	bottom.offset_top = -210
	bottom.offset_bottom = -14
	bottom.add_theme_constant_override("separation", 6)
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN   # if it ever needs more room, grow upwards, never below the window
	bottom_box = bottom
	layer.add_child(bottom)
	chips_row = HBoxContainer.new()
	bottom.add_child(chips_row)
	var ans_panel: PanelContainer = PanelContainer.new()
	ans_panel.add_theme_stylebox_override("panel", _panel_style())
	bottom.add_child(ans_panel)
	# long AI answers scroll inside a fixed-height box, so the question field below never gets pushed off screen
	answer_scroll = ScrollContainer.new()
	answer_scroll.custom_minimum_size = Vector2(0, 120)
	answer_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ans_panel.add_child(answer_scroll)
	answer_label = Label.new()
	answer_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	answer_label.custom_minimum_size = Vector2(800, 70)
	answer_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	answer_label.text = "Local AI answers appear here. Pick a suggested question or type your own."
	answer_scroll.add_child(answer_label)
	var ask_row: HBoxContainer = HBoxContainer.new()
	bottom.add_child(ask_row)
	question_edit = LineEdit.new()
	question_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	question_edit.text_submitted.connect(_on_question_submitted)
	ask_row.add_child(question_edit)
	_add_button(ask_row, "Ask AI", func() -> void: _on_question_submitted(question_edit.text))
	voice_btn = Button.new()
	voice_btn.text = "🎤  Hold to speak"
	voice_btn.focus_mode = Control.FOCUS_NONE
	voice_btn.tooltip_text = "Hold, ask your question out loud, release.  (In VR: hold the right joystick down.)"
	voice_btn.button_down.connect(_voice_start)
	voice_btn.button_up.connect(_voice_stop)
	ask_row.add_child(voice_btn)
	var hear: Button = Button.new()
	hear.text = "🔊"
	hear.focus_mode = Control.FOCUS_NONE
	hear.tooltip_text = "Read the current answer out loud (press again to stop)"
	hear.pressed.connect(func() -> void:
		if _answer_speaking():
			_stop_answer_voice()
		elif _answer_text != "":
			_speak_answer(_answer_text))
	ask_row.add_child(hear)
	_build_demo_ui(layer)
	_build_lab_ui(layer)
	_build_sampling_ui2(layer)
	_build_attention_ui(layer)
	_build_menu(layer)
	_build_chrome(layer)


# ═════════════════════ CLEAN APP CHROME (top bar, info card, hints) ═════════════════════
var info_panel: PanelContainer
var hint_label: Label
var toast_panel: PanelContainer
var course_label: Label
var mastery_label: Label
var nb_box: VBoxContainer
var tip_panel: PanelContainer
var tip_label: Label
var _card_id: String = "-"
var legend_on: bool = false
var ask_on: bool = false
var _toast_prev: String = ""
var _toast_t: float = 0.0


var _learn_cursor: int = -1
var quiz_top_btn: Button
var ask_top_btn: Button
var learn_top_btn: Button
var _toolbar_quiz_state: int = -1


## Top bar reacts to the quiz: helpers that would give away answers are greyed out,
## and the Quiz button becomes a clear "End quiz". Tour / Labs / Menu stay usable and end the quiz.
func _sync_toolbar() -> void:
	if quiz_top_btn == null:
		return
	var st: int = 1 if quiz_active else 0
	if st == _toolbar_quiz_state:
		return
	_toolbar_quiz_state = st
	quiz_top_btn.text = "✕  End quiz" if quiz_active else "?  Quiz"
	quiz_top_btn.tooltip_text = "Stop the quiz (your score so far is kept)" if quiz_active else "Test yourself: 4 options per question"
	for b in [ask_top_btn, learn_top_btn]:
		(b as Button).disabled = quiz_active
		(b as Button).modulate = Color(1, 1, 1, 0.35) if quiz_active else Color.WHITE
		(b as Button).mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN if quiz_active else Control.CURSOR_POINTING_HAND
	ask_top_btn.tooltip_text = "Not available during the quiz - no peeking!" if quiz_active else "Ask the AI tutor about any concept"
	learn_top_btn.tooltip_text = "Not available during the quiz - finish or end it first" if quiz_active else "Takes you to the next concept you have not mastered yet, in course order.\nPress again to move on."


## Concepts in teaching order: the guided-tour story first, then everything else.
func _course_order() -> Array:
	var order: Array = []
	for s in (_demo("story", []) as Array):
		for fid in (s as Dictionary).get("focus", []):
			if g_items.has(String(fid)) and not order.has(String(fid)):
				order.append(String(fid))
	for n in graph_data["nodes"]:
		if not order.has(String(n["id"])):
			order.append(String(n["id"]))
	return order


## "Learn next": flies to the next not-yet-mastered concept and opens its card.
func _learn_next() -> void:
	if quiz_active or demo_running:
		return
	if mode != Mode.GRAPH:
		_set_mode(Mode.GRAPH)
	var order: Array = _course_order()
	if order.is_empty():
		return
	var todo: Array = order.filter(func(x: Variant) -> bool: return not mastered.has(String(x)))
	if todo.is_empty():
		status_label.text = "You have mastered all %d concepts - try the quiz again or explore freely!" % order.size()
		return
	_learn_cursor = (_learn_cursor + 1) % todo.size()
	var id: String = todo[_learn_cursor]
	for it in items:   # only the current concept keeps its popped name label
		it.erase("poplabel")
	_select(g_items[id])
	_pop(id)
	var c: Vector3 = ((g_items[id] as Dictionary)["node"] as Node3D).position
	cam_override = true
	cam_focus_goal = c
	dist_goal = 11.0
	if Vector2(c.x, c.z).length() > 2.0:
		demo_yaw = atan2(c.x, c.z)
	demo_pitch = 0.25
	demo_cam = true
	auto_rotate = false
	status_label.text = "Next to learn:  %s   ·   %d concepts left to master\nRead the card, then press Learn next again." % [_title_of(id), todo.size()]


func _flat_btn(parent: Node, text: String, cb: Callable, accent: bool = false) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	if accent:
		var sb: StyleBoxFlat = StyleBoxFlat.new()
		sb.bg_color = Color(0.1, 0.45, 0.8, 0.9)
		sb.set_corner_radius_all(8)
		sb.set_content_margin_all(6)
		sb.content_margin_left = 12
		sb.content_margin_right = 12
		b.add_theme_stylebox_override("normal", sb)
	parent.add_child(b)
	return b


func _menu_btn(parent: Node, text: String, entries: Array, cb: Callable) -> void:
	var mb: MenuButton = MenuButton.new()
	mb.flat = false
	mb.text = text
	mb.focus_mode = Control.FOCUS_NONE
	var pop: PopupMenu = mb.get_popup()
	for i in entries.size():
		if String(entries[i]) == "-":
			pop.add_separator()
		else:
			pop.add_item(String(entries[i]), i)
	pop.id_pressed.connect(cb)
	parent.add_child(mb)


var intro: Intro
var intro_layer: CanvasLayer
var _web_started: bool = false
signal web_start_clicked


## Browser start screen: logo + "Click to start" (unlocks audio), then the intro plays with sound.
func _web_click_to_start() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 60
	add_child(layer)
	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.008, 0.012, 0.04)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var cc: CenterContainer = CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(cc)
	var vb: VBoxContainer = VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 18)
	cc.add_child(vb)
	if ResourceLoader.exists("res://assets/generated/neurograph_logo.png"):
		var lg: TextureRect = TextureRect.new()
		lg.texture = load("res://assets/generated/neurograph_logo.png")
		lg.custom_minimum_size = Vector2(140, 140)
		lg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		lg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		vb.add_child(lg)
	var t: Label = Label.new()
	t.text = "NEUROGRAPH XR"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 44)
	t.add_theme_color_override("font_color", Color(0.6, 0.88, 1.0))
	vb.add_child(t)
	var s: Label = Label.new()
	s.text = "Learn how AI works by exploring it in 3D"
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
	vb.add_child(s)
	var b: Button = Button.new()
	b.text = "▶   Click to start   (sound on)"
	b.custom_minimum_size = Vector2(320, 56)
	b.add_theme_font_size_override("font_size", 20)
	b.theme = app_theme
	b.pressed.connect(func() -> void: web_start_clicked.emit())
	vb.add_child(b)
	var n: Label = Label.new()
	n.text = "Browser demo  ·  for VR, the local AI tutor and voice questions, get the desktop app on GitHub"
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.add_theme_font_size_override("font_size", 13)
	n.add_theme_color_override("font_color", Color(0.6, 0.7, 0.85))
	vb.add_child(n)
	await web_start_clicked
	_web_started = true
	layer.queue_free()


## Plays the animated welcome intro on top of everything; the start menu appears when it ends.
func _play_intro() -> void:
	await get_tree().process_frame   # make sure the window size is known before drawing
	if IS_WEB and not _web_started:
		await _web_click_to_start()   # browsers only allow sound after the visitor clicks once
	if intro_layer == null:
		intro_layer = CanvasLayer.new()
		intro_layer.layer = 50
		var intro_parent: Node = self
		if ui_vp != null:
			intro_parent = ui_vp   # in VR the intro plays on the floating screen
		intro_parent.add_child(intro_layer)
		intro = Intro.new()
		intro_layer.add_child(intro)
		intro.theme = app_theme
		intro.finished.connect(func() -> void: _show_menu())
		intro.ripple_made.connect(func() -> void: _play_sfx(sfx_pop, -14.0))
	else:
		intro.restart()
	if demo_running:
		_stop_demo()
	menu_panel.visible = false


func _view_menu_pick(id: int) -> void:
	match id:
		13:
			_play_intro()
		0:
			_set_mode(Mode.GRAPH)
		1:
			_set_mode(Mode.NETWORK)
		3:
			_toggle_explode()
		4:
			forward_pass = not forward_pass
		5:
			auto_rotate = not auto_rotate
		6:
			_reset_view()
		8:
			legend_on = not legend_on
		9:
			_toggle_music()
		10:
			_toggle_voice()
		11:
			_switch_course()
		12:
			_save_screenshot()


func _build_chrome(layer: CanvasLayer) -> void:
	# the old crowded panel is replaced; keep its two labels and move them
	var old: Control = left_panel
	info_label.get_parent().remove_child(info_label)
	status_label.get_parent().remove_child(status_label)
	old.queue_free()

	var bar: PanelContainer = PanelContainer.new()
	bar.anchor_right = 1.0
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.05, 0.1, 0.78)
	sb.border_color = Color(0.25, 0.55, 0.9, 0.5)
	sb.border_width_bottom = 1
	sb.set_content_margin_all(8)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	bar.add_theme_stylebox_override("panel", sb)
	layer.add_child(bar)
	left_panel = bar
	var hb: HBoxContainer = HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	bar.add_child(hb)
	if ResourceLoader.exists("res://assets/generated/neurograph_logo.png"):
		var tl: TextureRect = TextureRect.new()
		tl.texture = load("res://assets/generated/neurograph_logo.png")
		tl.custom_minimum_size = Vector2(30, 30)
		tl.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tl.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		hb.add_child(tl)
	var title: Label = Label.new()
	title.text = "NEUROGRAPH XR"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
	hb.add_child(title)
	course_label = Label.new()
	course_label.modulate = Color(0.75, 0.85, 1.0, 0.8)
	hb.add_child(course_label)
	var sp: Control = Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(sp)
	mastery_label = Label.new()
	mastery_label.modulate = Color(1.0, 0.86, 0.35)
	hb.add_child(mastery_label)
	_flat_btn(hb, "▶  Tour", func() -> void: _toggle_demo(), true)
	quiz_top_btn = _flat_btn(hb, "?  Quiz", func() -> void: _toggle_quiz())
	_menu_btn(hb, "Labs ▾", ["Token Lab", "Sampling Lab", "Attention Lab"], func(id: int) -> void:
		if id == 0:
			_toggle_lab()
		elif id == 1:
			_toggle_sampling()
		else:
			_toggle_attention())
	ask_top_btn = _flat_btn(hb, "💬  Ask AI", func() -> void: ask_on = not ask_on)
	learn_top_btn = _flat_btn(hb, "➜  Learn next", func() -> void: _learn_next())
	_menu_btn(hb, "View ▾", ["Concept graph", "Neural network", "-", "Explode / assemble", "Forward-pass animation", "Auto-spin on/off", "Reset view", "-", "Filter by category", "Music on/off", "Narration voice on/off", "Switch course", "Screenshot", "Replay intro"], _view_menu_pick)
	_flat_btn(hb, "☰  Menu", func() -> void: _show_menu())

	# concept card: only visible while something is selected
	info_panel = PanelContainer.new()
	info_panel.position = Vector2(16, 70)
	info_panel.custom_minimum_size = Vector2(340, 0)
	info_panel.add_theme_stylebox_override("panel", _panel_style())
	var iv: VBoxContainer = VBoxContainer.new()
	iv.add_theme_constant_override("separation", 6)
	info_panel.add_child(iv)
	card_cat = Label.new()
	card_cat.add_theme_font_size_override("font_size", 12)
	card_cat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	iv.add_child(card_cat)
	card_title = Label.new()
	card_title.add_theme_font_size_override("font_size", 24)
	card_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card_title.custom_minimum_size = Vector2(320, 0)
	card_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	iv.add_child(card_title)
	card_rule_ref = ColorRect.new()
	card_rule_ref.custom_minimum_size = Vector2(0, 2)
	card_rule_ref.color = Color(0.3, 0.55, 0.9, 0.5)
	card_rule_ref.mouse_filter = Control.MOUSE_FILTER_IGNORE
	iv.add_child(card_rule_ref)
	info_label.custom_minimum_size = Vector2(320, 0)
	info_label.add_theme_font_size_override("font_size", 15)
	info_label.add_theme_color_override("font_color", Color(0.86, 0.92, 1.0))
	iv.add_child(info_label)
	nb_box = VBoxContainer.new()
	nb_box.add_theme_constant_override("separation", 5)
	iv.add_child(nb_box)
	layer.add_child(info_panel)

	# short, temporary messages under the bar
	toast_panel = PanelContainer.new()
	toast_panel.anchor_left = 0.5
	toast_panel.anchor_right = 0.5
	toast_panel.offset_left = -190   # shifted right so it never covers the concept card on the left
	toast_panel.offset_right = 370
	toast_panel.offset_top = 62
	toast_panel.add_theme_stylebox_override("panel", _panel_style())
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size = Vector2(580, 0)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_panel.add_child(status_label)
	toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(toast_panel)

	# one quiet hint at the bottom
	hint_label = Label.new()
	hint_label.text = "Click any concept to learn about it     ·     drag to rotate     ·     scroll to zoom"
	hint_label.anchor_left = 0.0
	hint_label.anchor_right = 1.0
	hint_label.anchor_top = 1.0
	hint_label.anchor_bottom = 1.0
	hint_label.offset_top = -46
	hint_label.offset_bottom = -14
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.modulate = Color(0.85, 0.93, 1.0, 0.95)
	hint_label.add_theme_constant_override("outline_size", 8)
	hint_label.add_theme_color_override("font_outline_color", Color(0.0, 0.02, 0.06, 0.95))
	hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hint_label)

	# hover tooltip that follows the mouse
	tip_panel = PanelContainer.new()
	tip_panel.add_theme_stylebox_override("panel", _panel_style())
	tip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip_label = Label.new()
	tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip_label.custom_minimum_size = Vector2(250, 0)
	tip_panel.add_child(tip_label)
	tip_panel.visible = false
	layer.add_child(tip_panel)

	legend_panel.offset_top = 70
	answer_label.text = "Ask anything about this course. Pick a suggestion or type your own question."
	question_edit.placeholder_text = "Ask a question..."
	status_label.text = ""


func _rebuild_card() -> void:
	for c in nb_box.get_children():
		c.queue_free()
	if _card_id == "" or _card_id == "-" or not g_adj.has(_card_id):
		return
	var cl: Label = Label.new()
	cl.text = "Tap a connected concept to jump there:"
	cl.modulate = Color(0.7, 0.85, 1.0, 0.8)
	nb_box.add_child(cl)
	var seen: Array = []
	for adj in g_adj[_card_id]:
		var oid: String = String(adj[0])
		if seen.has(oid) or seen.size() >= 6:
			continue
		seen.append(oid)
		var b: Button = Button.new()
		b.text = "%s  %s" % ["→" if adj[2] == "out" else "←", _title_of(oid)]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = String(adj[1])
		b.add_theme_color_override("font_color", (g_items[oid] as Dictionary)["color"])
		b.pressed.connect(func() -> void: _select(g_items[oid]))
		nb_box.add_child(b)
		var rl: Label = Label.new()
		rl.text = "     " + String(adj[1])
		rl.add_theme_font_size_override("font_size", 11)
		rl.modulate = Color(0.7, 0.8, 0.95, 0.6)
		nb_box.add_child(rl)
	var row: HBoxContainer = HBoxContainer.new()
	nb_box.add_child(row)
	var title: String = _title_of(_card_id)
	_flat_btn(row, "✦ Explain simply", func() -> void:
		ask_on = true
		_ask("Explain %s in simple words" % title), true)
	_flat_btn(row, "✕ Close", func() -> void:
		selected = {}
		_refresh_materials()
		_rebuild_pulses()
		_update_texts())


## Called every frame: decides which on-screen pieces are visible, so only what is relevant shows.
func _update_chrome(delta: float) -> void:
	if left_panel == null or info_panel == null:
		return
	_sync_toolbar()
	if menu_panel.visible and menu_logo != null and menu_logo.scale.x <= 1.02:   # the logo gently breathes
		menu_logo.pivot_offset = menu_logo.size * 0.5
		menu_logo.scale = Vector2.ONE * (1.0 + 0.025 * sin(time_s * 1.6))
	var intro_on: bool = intro != null and intro.visible
	var menu_open: bool = menu_panel.visible or intro_on
	var lab_open: bool = lab_panel.visible or sl_panel.visible or al_panel.visible
	var busy: bool = demo_running or quiz_active or demo_panel.visible
	var free: bool = not busy and not menu_open and not lab_open
	left_panel.visible = not menu_open and not demo_running and not lab_open
	# every lab panel is shrunk to fit the window, so nothing is ever cut off
	var vsz: Vector2 = _ui_vp().get_visible_rect().size
	for lp in [lab_panel, sl_panel, al_panel]:
		var pnl: PanelContainer = lp
		if pnl.visible:
			var need: Vector2 = pnl.get_combined_minimum_size().max(pnl.size)
			var fit: float = clampf(minf((vsz.y - 24.0) / maxf(need.y, 1.0), (vsz.x - 24.0) / maxf(need.x, 1.0)), 0.45, 1.0)
			pnl.pivot_offset = pnl.size * 0.5
			pnl.scale = Vector2(fit, fit)
	info_panel.visible = free and not selected.is_empty()
	legend_panel.visible = free and legend_on and mode == Mode.GRAPH
	bottom_box.visible = free and ask_on
	hint_label.visible = free and selected.is_empty() and not ask_on
	course_label.text = "·  " + _course_key()
	var total: int = (graph_data.get("nodes", []) as Array).size()
	mastery_label.text = "★ %d / %d" % [mastered.size(), total] if mastered.size() > 0 else ""
	if status_label.text != _toast_prev:
		_toast_prev = status_label.text
		_toast_t = 4.5
	_toast_t -= delta
	toast_panel.visible = status_label.text != "" and _toast_t > 0.0 and not menu_open and not demo_running
	# hover tooltip
	var over_ui: bool = _ui_vp().gui_get_hovered_control() != null
	if over_ui and hover_id != "":
		hover_id = ""
		_refresh_materials()
	var tip_ok: bool = free and mode == Mode.GRAPH and hover_id != "" and g_items.has(hover_id) and not over_ui
	tip_panel.visible = tip_ok
	if tip_ok:
		var hi: Dictionary = g_items[hover_id]
		tip_label.text = "%s\n%s" % [String(hi["title"]).to_upper(), _short(_node_desc(hover_id), 110)]
		var vs: Vector2 = _ui_vp().get_visible_rect().size
		var mp: Vector2 = _ui_mouse_pos() + Vector2(18, 18)
		tip_panel.position = Vector2(minf(mp.x, vs.x - 290.0), minf(mp.y, vs.y - 110.0))
	# concept card: rebuild its clickable connections when the selection changes
	var cid: String = String(selected.get("id", "")) if mode == Mode.GRAPH else "-"
	if cid != _card_id:
		_card_id = cid
		_rebuild_card()


func _fill_chips() -> void:
	for c in chips_row.get_children():
		c.queue_free()
	var qs: Array = _demo("chips", GRAPH_CHIPS) if mode == Mode.GRAPH else net_data.get("chips", NET_CHIPS)
	for q in qs:
		var text: String = String(q)
		_add_button(chips_row, "💡 " + text, func() -> void: _ask(text))


func _add_button(parent: Node, text: String, cb: Callable) -> void:
	var b: Button = Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	parent.add_child(b)


func _setup_xr() -> void:
	if preview_vr_ui or IS_WEB:   # desktop preview of the VR screen: never take over the headset
		return
	var xr: XRInterface = XRServer.find_interface("OpenXR")
	if xr == null or not (xr.is_initialized() or xr.initialize()):
		print("OpenXR not available - desktop mode")
		return
	get_viewport().use_xr = true
	if XRInterface.XR_ENV_BLEND_MODE_OPAQUE in xr.get_supported_environment_blend_modes():
		xr.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_OPAQUE
	env.glow_enabled = false   # keep VR fast
	# lighter nebula sky (2 noise octaves instead of 4): the sky is computed per pixel for BOTH eyes
	if sky_mat != null:
		var vr_sky: Shader = Shader.new()
		vr_sky.code = SKY_SHADER.replace("i < 4", "i < 2")
		sky_mat.shader = vr_sky
	xr_active = true
	xr_origin = XROrigin3D.new()
	add_child(xr_origin)
	xr_camera = XRCamera3D.new()
	xr_origin.add_child(xr_camera)
	xr_camera.current = true
	xr_left = _make_controller(&"left_hand")
	xr_right = _make_controller(&"right_hand")
	xr_right.button_pressed.connect(_on_right_button)
	xr_right.button_released.connect(_on_right_button_up)
	xr_left.button_pressed.connect(_on_left_button)
	var ray: MeshInstance3D = MeshInstance3D.new()
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = 0.004
	cyl.bottom_radius = 0.004
	cyl.height = 4.0
	ray.mesh = cyl
	ray.rotation_degrees = Vector3(90, 0, 0)
	ray.position = Vector3(0, 0, -2.0)
	var rm: StandardMaterial3D = StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Color(0.3, 0.9, 1.0)
	ray.material_override = rm
	xr_right.add_child(ray)
	vr_ray = ray
	vr_label = Label3D.new()
	vr_label.pixel_size = 0.0012
	vr_label.font_size = 40
	vr_label.width = 900.0
	vr_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vr_label.outline_size = 10
	vr_label.position = Vector3(1.05, 1.5, -1.3)
	vr_label.rotation_degrees = Vector3(0, -25, 0)
	vr_label.visible = false   # replaced by the full desktop UI on the floating VR screen
	add_child(vr_label)
	camera.current = false
	content.scale = Vector3.ONE * VR_SCALE
	content.position = VR_CONTENT_POS
	floor_mesh.position = Vector3(0, 0, 0)
	floor_mat.set_shader_parameter("cell", 0.5)
	_setup_vr_ui()
	# as soon as the headset reports where you are, the model is moved in front of you (see _vr_auto_place)
	if xr.has_signal("pose_recentered"):
		xr.connect("pose_recentered", func() -> void: _vr_place_content(true))


## Places the model in front of the player's REAL head position and sizes it to fit the view.
## recenter = false keeps the spot and only re-fits the size (e.g. after switching graph <-> network).
func _vr_place_content(recenter: bool = true) -> void:
	if not xr_active or content == null:
		return
	if recenter and xr_camera != null:
		var head: Vector3 = xr_camera.global_position
		var f: Vector3 = -xr_camera.global_transform.basis.z
		f.y = 0.0
		f = f.normalized() if f.length() > 0.1 else Vector3.FORWARD
		vr_anchor = head + f * VR_VIEW_DIST + Vector3(0.0, -0.15, 0.0)
		vr_anchor.y = maxf(vr_anchor.y, 0.6)
		vr_yaw = atan2(-f.x, -f.z)
		if ui_sheet != null:   # the UI screen floats between you and the model, slightly below eye level
			ui_sheet.global_position = head + f * VR_UI_DIST + Vector3(0.0, -0.08, 0.0)
			ui_sheet.rotation = Vector3(0.0, vr_yaw, 0.0)
	var extent: float = graph_radius if mode == Mode.GRAPH else maxf(float(n_layers.size()) * 1.2, 3.0)
	vr_scale = clampf(VR_MODEL_RADIUS / maxf(extent, 0.1), 0.02, 0.3)
	content.position = vr_anchor
	content.scale = Vector3.ONE * vr_scale
	content.rotation = Vector3(0.0, vr_yaw, 0.0)
	if vr_label != null:   # info panel floats to the right of the model, turned towards you
		var yb: Basis = Basis(Vector3.UP, vr_yaw)
		vr_label.position = vr_anchor + yb.x * (VR_MODEL_RADIUS + 0.55) + Vector3(0.0, 0.25, 0.25)
		vr_label.rotation = Vector3(0.0, vr_yaw - deg_to_rad(25.0), 0.0)


## Waits until the headset is really tracked, then places the model once.
func _vr_auto_place(delta: float) -> void:
	if _vr_placed or xr_camera == null:
		return
	if xr_camera.global_position.y < 0.3:   # no head pose yet
		return
	_vr_wait += delta
	if _vr_wait > 0.4:
		_vr_placed = true
		_vr_place_content(true)


func _make_controller(tracker: StringName) -> XRController3D:
	var c: XRController3D = XRController3D.new()
	c.tracker = tracker
	xr_origin.add_child(c)
	var m: MeshInstance3D = MeshInstance3D.new()
	var sm: SphereMesh = SphereMesh.new()
	sm.radius = 0.03
	sm.height = 0.06
	m.mesh = sm
	c.add_child(m)
	return c


# ───────────────────────── modes ─────────────────────────
func _clear_content() -> void:
	for c in content.get_children():
		c.queue_free()
	items.clear()
	cat_lbls.clear()
	g_items.clear()
	g_edges.clear()
	g_adj.clear()
	n_layers.clear()
	n_neurons.clear()
	n_conns.clear()
	pulses.clear()
	selected = {}
	highlighted.clear()
	hover_id = ""
	filter_cat = ""
	path_ids.clear()
	path_edges.clear()
	focus_ids.clear()
	_spread_applied = -1.0
	edge_mesh = MeshInstance3D.new()
	edge_mesh.mesh = ImmediateMesh.new()
	edge_mesh.material_override = edge_mat
	content.add_child(edge_mesh)


func _default_dist() -> float:
	if mode == Mode.GRAPH:
		return 1.5 * graph_radius
	return 10.0 + 6.0 * spread_target


func _set_mode(m: int) -> void:
	mode = m
	tour_active = false
	_reset_calc_state()
	spread_target = 0.0
	spread = 0.0
	_clear_content()
	if mode == Mode.GRAPH:
		_build_graph()
		status_label.text = "Knowledge graph"
		sky_a_goal = Color(0.05, 0.25, 0.8)
		sky_b_goal = Color(0.4, 0.1, 0.6)
		question_edit.placeholder_text = "Ask about the graph..."
	else:
		_build_network()
		status_label.text = "Neural network  -  open View to explode the layers"
		sky_a_goal = Color(0.5, 0.1, 0.7)
		sky_b_goal = Color(0.85, 0.35, 0.1)
		question_edit.placeholder_text = "Ask about the network..."
	legend_panel.visible = mode == Mode.GRAPH
	_fill_chips()
	dist_goal = _default_dist()
	_apply_spread()
	if xr_active and _vr_placed:
		_vr_place_content(false)   # graph and network have different sizes: re-fit
	_refresh_materials()
	_update_texts()


func _reset_view() -> void:
	_stop_demo()
	yaw = 0.5
	pitch = 0.3
	spread_target = 0.0
	selected = {}
	highlighted.clear()
	filter_cat = ""
	path_ids.clear()
	path_edges.clear()
	tour_active = false
	_answer_text = ""
	answer_label.text = ""
	content.rotation = Vector3.ZERO
	if xr_active:
		_vr_place_content(true)   # left Y: model jumps back in front of you
	dist_goal = _default_dist()
	_refresh_materials()
	_rebuild_edges()
	_rebuild_pulses()
	_update_texts()


func _toggle_explode() -> void:
	_play_sfx(sfx_explode)
	spread_target = 0.0 if spread_target > 0.5 else 1.0
	if mode == Mode.NETWORK:
		dist_goal = _default_dist()


func _set_filter(cat: String) -> void:
	filter_cat = "" if filter_cat == cat else cat
	_refresh_materials()


# ───────────────────────── knowledge graph ─────────────────────────
func _build_graph() -> void:
	if graph_data.is_empty():
		return
	var nodes: Array = graph_data["nodes"]
	var edges: Array = graph_data["edges"]
	var cats: Dictionary = graph_data["categories"]
	for n in nodes:
		g_adj[n["id"]] = []
	for e in edges:
		g_edges.append([e[0], e[1], e[2]])
		g_adj[e[0]].append([e[1], e[2], "out"])
		g_adj[e[1]].append([e[0], e[2], "in"])
	var pos: Dictionary = _layout(nodes, edges)
	var degs: Array = []
	for dn in nodes:
		degs.append((g_adj[dn["id"]] as Array).size())
	degs.sort()
	label_min_deg = 9999   # concept names show on hover / selection; the colour groups carry their own labels
	for n in nodes:
		var id: String = n["id"]
		var deg: int = (g_adj[id] as Array).size()
		var r: float = 0.3 + 0.03 * float(deg)
		var col: Color = Color.html(cats.get(n["category"], "#ffffff"))
		var mi: MeshInstance3D = MeshInstance3D.new()
		var sm: SphereMesh = SphereMesh.new()
		sm.radius = r
		sm.height = r * 2.0
		sm.radial_segments = 32
		sm.rings = 16
		mi.mesh = sm
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = col
		mat.metallic = 0.3
		mat.roughness = 0.25
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = 0.35
		mat.rim_enabled = true
		mat.rim = 0.6
		mi.material_override = mat
		content.add_child(mi)
		var lab: Label3D = Label3D.new()
		lab.text = n["label"]
		lab.font_size = 26
		lab.pixel_size = 0.0008          # with fixed_size every label has the same readable size on screen
		lab.fixed_size = true
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lab.outline_size = 12
		lab.no_depth_test = true
		lab.position = Vector3(0, r + 0.30, 0)
		lab.visible = deg >= label_min_deg
		mi.add_child(lab)
		var item: Dictionary = {"id": id, "node": mi, "radius": r + 0.2, "mat": mat, "color": col, "title": n["label"], "base": pos[id], "label": lab, "deg": deg, "cat": n["category"]}
		items.append(item)
		g_items[id] = item
	_make_cat_labels(cats, nodes, pos)


func _make_cat_labels(cats: Dictionary, nodes: Array, pos: Dictionary) -> void:
	for cat in cats.keys():
		var sum: Vector3 = Vector3.ZERO
		var cnt: int = 0
		for n in nodes:
			if n["category"] == cat:
				sum += pos[n["id"]]
				cnt += 1
		if cnt == 0:
			continue
		var base: Vector3 = sum / float(cnt)
		var col: Color = Color.html(cats[cat])
		var lab: Label3D = Label3D.new()
		lab.text = String(cat).to_upper()
		lab.font_size = 26
		lab.pixel_size = 0.0009
		lab.fixed_size = true
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lab.outline_size = 16
		lab.outline_modulate = Color(0.0, 0.02, 0.06, 0.95)
		lab.modulate = col.lightened(0.35)
		lab.no_depth_test = true
		var out_dir: Vector3 = Vector3(base.x, 0.0, base.z)
		var lbase: Vector3 = base + (out_dir.normalized() * 3.2 if out_dir.length() > 0.5 else Vector3.ZERO) + Vector3(0, 1.8, 0)
		lab.position = lbase
		content.add_child(lab)
		cat_lbls.append({"n": lab, "base": lbase})


func _layout(nodes: Array, edges: Array) -> Dictionary:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	var p: Dictionary = {}
	# every category gets its own region (anchor) so groups form clear, separate clusters
	var cat_names: Array = (graph_data.get("categories", {}) as Dictionary).keys()
	var anchors: Dictionary = {}
	for ci in cat_names.size():
		var ang: float = TAU * float(ci) / float(maxi(cat_names.size(), 1))
		anchors[cat_names[ci]] = Vector3(cos(ang) * 10.0, (float(ci % 2) - 0.5) * 6.0, sin(ang) * 10.0)
	var cat_of: Dictionary = {}
	for n in nodes:
		cat_of[n["id"]] = n["category"]
		var v: Vector3 = Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		p[n["id"]] = (anchors.get(n["category"], Vector3.ZERO) as Vector3) + v * 2.0
	graph_radius = 9.0 + 0.2 * maxf(0.0, float(nodes.size()) - 34.0)
	graph_scale = graph_radius / 9.0
	var ids: Array = p.keys()
	var k: float = 2.6
	var temp: float = 1.0
	for it in 250:
		var disp: Dictionary = {}
		for id in ids:
			disp[id] = Vector3.ZERO
		for i in ids.size():
			for j in range(i + 1, ids.size()):
				var d: Vector3 = p[ids[i]] - p[ids[j]]
				var l: float = maxf(d.length(), 0.05)
				var f: Vector3 = d / l * (k * k / l)
				disp[ids[i]] += f
				disp[ids[j]] -= f
		for e in edges:
			var d2: Vector3 = p[e[0]] - p[e[1]]
			var l2: float = maxf(d2.length(), 0.05)
			var f2: Vector3 = d2 / l2 * (l2 * l2 / k)
			disp[e[0]] -= f2
			disp[e[1]] += f2
		for id in ids:
			var dd: Vector3 = disp[id] + ((anchors.get(cat_of[id], Vector3.ZERO) as Vector3) - (p[id] as Vector3)) * 0.9 - (p[id] as Vector3) * 0.15
			var dl: float = dd.length()
			if dl > 0.001:
				p[id] += dd / dl * minf(dl, temp)
		temp = maxf(0.02, temp * 0.98)
	var maxr: float = 0.01
	for id in ids:
		maxr = maxf(maxr, (p[id] as Vector3).length())
	for id in ids:
		p[id] = (p[id] as Vector3) * (graph_radius / maxr)
	return p


# ───────────────────────── neural network ─────────────────────────
func _build_network() -> void:
	if net_data.is_empty():
		return
	var layers: Array = net_data["layers"]
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 11
	var sm: SphereMesh = SphereMesh.new()
	sm.radius = 0.14
	sm.height = 0.28
	sm.radial_segments = 16
	sm.rings = 8
	var li: int = 0
	for L in layers:
		var col: Color = Color.html(L["color"])
		var pivot: Node3D = Node3D.new()
		content.add_child(pivot)
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = col
		mat.metallic = 0.3
		mat.roughness = 0.3
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = 0.35
		var units: int = int(L["units"])
		var cols: int = int(ceil(sqrt(float(units))))
		var rows: int = int(ceil(float(units) / float(cols)))
		var neurons: Array = []
		var mats: Array = []
		for u in units:
			var cx: int = u % cols
			var cy: int = int(floor(float(u) / float(cols)))
			var m: MeshInstance3D = MeshInstance3D.new()
			m.mesh = sm
			var nmat: StandardMaterial3D = mat.duplicate() as StandardMaterial3D
			m.material_override = nmat
			mats.append(nmat)
			m.position = Vector3(0, (float(cy) - float(rows - 1) * 0.5) * 0.55, (float(cx) - float(cols - 1) * 0.5) * 0.55)
			pivot.add_child(m)
			neurons.append(m)
		var extent: float = maxf(float(cols), float(rows)) * 0.55 * 0.5
		var lab: Label3D = Label3D.new()
		lab.text = "%s\n%s" % [L["name"], L["shape"]]
		lab.font_size = 52
		lab.pixel_size = 0.005
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lab.outline_size = 14
		lab.no_depth_test = true
		lab.position = Vector3(0, extent + 0.8, 0)
		pivot.add_child(lab)
		var item: Dictionary = {"id": str(li), "node": pivot, "radius": extent + 0.5, "mat": mat, "color": col, "title": L["name"], "base": Vector3.ZERO, "layer": li, "mats": mats}
		items.append(item)
		n_layers.append(item)
		n_neurons.append(neurons)
		li += 1
	for i in range(layers.size() - 1):
		var a_n: int = (n_neurons[i] as Array).size()
		var b_n: int = (n_neurons[i + 1] as Array).size()
		for a in a_n:
			for c in 3:
				n_conns.append([i, a, rng.randi() % b_n])
	_compute_network()


# ───────────────────────── explode / edges / pulses ─────────────────────────
func _apply_spread() -> void:
	var e: float = spread * spread * (3.0 - 2.0 * spread)
	if mode == Mode.GRAPH:
		for it in items:
			(it["node"] as Node3D).position = (it["base"] as Vector3) * (1.0 + e * 0.9)
		for cl in cat_lbls:
			((cl["n"]) as Node3D).position = (cl["base"] as Vector3) * (1.0 + e * 0.9)
	else:
		var n: int = n_layers.size()
		for i in n:
			var x: float = (float(i) - float(n - 1) * 0.5) * (2.2 + e * 3.5)
			((n_layers[i] as Dictionary)["node"] as Node3D).position = Vector3(x, 0, 0)
	_spread_applied = spread
	_rebuild_edges()


func _edge_is_hot(e: Array) -> bool:
	var sel_id: String = selected.get("id", "")
	if not path_edges.is_empty():
		return path_edges.has(str(e[0]) + "|" + str(e[1]))
	return sel_id == e[0] or sel_id == e[1] or (highlighted.has(e[0]) and highlighted.has(e[1]))


func _rebuild_edges() -> void:
	if edge_mesh == null:
		return
	var im: ImmediateMesh = edge_mesh.mesh as ImmediateMesh
	im.clear_surfaces()
	if mode == Mode.GRAPH:
		if g_edges.is_empty():
			return
		im.surface_begin(Mesh.PRIMITIVE_LINES, edge_mat)
		for e in g_edges:
			var a: Dictionary = g_items[e[0]]
			var b: Dictionary = g_items[e[1]]
			var hot: bool = _edge_is_hot(e)
			var dim: bool = (filter_cat != "" and (a["cat"] != filter_cat or b["cat"] != filter_cat)) or (not focus_ids.is_empty() and not (focus_ids.has(a["id"]) and focus_ids.has(b["id"])))
			var alpha: float = 1.0 if hot else (0.06 if dim else 0.32)
			var ca: Color = (a["color"] as Color).lerp(Color.WHITE, 0.35 if hot else 0.0)
			var cb: Color = (b["color"] as Color).lerp(Color.WHITE, 0.35 if hot else 0.0)
			ca.a = alpha
			cb.a = alpha
			im.surface_set_color(ca)
			im.surface_add_vertex((a["node"] as Node3D).position)
			im.surface_set_color(cb)
			im.surface_add_vertex((b["node"] as Node3D).position)
		im.surface_end()
	else:
		if n_conns.is_empty():
			return
		im.surface_begin(Mesh.PRIMITIVE_LINES, edge_mat)
		var sel_layer: int = selected.get("layer", -1)
		for c in n_conns:
			var li: int = c[0]
			var la: Dictionary = n_layers[li]
			var lb: Dictionary = n_layers[li + 1]
			var na: Node3D = (n_neurons[li] as Array)[c[1]]
			var nb: Node3D = (n_neurons[li + 1] as Array)[c[2]]
			var hot: bool = sel_layer == li or sel_layer == li + 1 or (calc_net and li + 1 == calc_layer)
			var alpha: float = 0.55 if hot else 0.15
			var ca: Color = la["color"]
			var cb: Color = lb["color"]
			ca.a = alpha
			cb.a = alpha
			im.surface_set_color(ca)
			im.surface_add_vertex((la["node"] as Node3D).position + na.position)
			im.surface_set_color(cb)
			im.surface_add_vertex((lb["node"] as Node3D).position + nb.position)
		im.surface_end()


## Small glowing "data packets" that travel along the edges of the selected node / retrieved facts.
func _rebuild_pulses() -> void:
	for p in pulses:
		(p["node"] as Node).queue_free()
	pulses.clear()
	var sm: SphereMesh = SphereMesh.new()
	sm.radius = 0.11
	sm.height = 0.22
	sm.radial_segments = 8
	sm.rings = 4
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.4, 1.4, 1.4)
	if mode == Mode.NETWORK:
		if calc_net and calc_layer >= 1:
			for ci in n_conns.size():
				if int((n_conns[ci] as Array)[0]) == calc_layer - 1 and ci % 2 == 0:
					var pm: MeshInstance3D = MeshInstance3D.new()
					pm.mesh = sm
					pm.material_override = mat
					content.add_child(pm)
					pulses.append({"node": pm, "conn": ci, "off": fmod(float(ci) * 0.137, 1.0)})
		return
	for ei in g_edges.size():
		if not _edge_is_hot(g_edges[ei]):
			continue
		for k in 2:
			var mi: MeshInstance3D = MeshInstance3D.new()
			mi.mesh = sm
			mi.material_override = mat
			content.add_child(mi)
			pulses.append({"node": mi, "ei": ei, "off": float(k) * 0.5})


func _is_dim(it: Dictionary) -> bool:
	if mode != Mode.GRAPH:
		return false
	if not focus_ids.is_empty() and not focus_ids.has(it["id"]):
		return true
	return filter_cat != "" and it["cat"] != filter_cat


func _refresh_materials() -> void:
	var sel_id: String = selected.get("id", "")
	var neighbours: Array = []
	if mode == Mode.GRAPH and sel_id != "":
		for adj in g_adj[sel_id]:
			neighbours.append(adj[0])
	for it in items:
		var id: String = it["id"]
		var dim: bool = _is_dim(it)
		var energy: float = 0.35
		if id == sel_id:
			energy = 2.6
		elif focus_ids.has(id):
			energy = 2.2
		elif highlighted.has(id):
			energy = 1.8
		elif neighbours.has(id):
			energy = 1.0
		elif id == hover_id:
			energy = 1.5
		if dim and id != sel_id:
			energy = 0.03
		var grey: bool = (dim and id != sel_id) or (calc_graph and mode == Mode.GRAPH and id != sel_id and float(calc_energy.get(id, 0.1)) < 0.2)
		if calc_graph and mode == Mode.GRAPH and id != sel_id:
			energy = float(calc_energy.get(id, 0.1))
		var mat: StandardMaterial3D = it["mat"]
		mat.emission_energy_multiplier = energy
		if it.has("mats") and not calc_net:
			for mm in it["mats"]:
				(mm as StandardMaterial3D).emission_energy_multiplier = energy
		if it.has("cat"):
			mat.albedo_color = Color(0.2, 0.22, 0.27) if grey else it["color"]
		if it.has("label"):
			var vis: bool = int(it["deg"]) >= label_min_deg or id == sel_id or id == hover_id or neighbours.has(id) or highlighted.has(id) or (calc_graph and float(calc_energy.get(id, 0.0)) > 0.5) or (filter_cat != "" and it["cat"] == filter_cat) or focus_ids.has(id) or bool(it.get("poplabel", false))
			var lab3: Label3D = it["label"]
			lab3.visible = vis and not (dim and id != sel_id)
			lab3.modulate = Color(1.0, 0.86, 0.35) if mastered.has(id) else Color.WHITE   # gold = mastered
	var show_cats: bool = focus_ids.is_empty() and selected.is_empty() and not calc_graph and not quiz_active
	for cl in cat_lbls:
		((cl["n"]) as Label3D).visible = show_cats
	_rebuild_edges()


# ───────────────────────── selection / info ─────────────────────────
func _select(item: Dictionary) -> void:
	if quiz_active:
		# on desktop only the 4 offered options count; a stray click on another sphere is not a wrong answer
		if not quiz_btns.is_empty() and not quiz_btns.has(String(item.get("id", ""))):   # VR now has the same A-D buttons
			if not quiz_busy and item.has("id"):
				_pop(String(item["id"]))
				quiz_fb.text = "That is %s - it is not one of the options. Pick A, B, C or D." % _title_of(String(item["id"]))
				quiz_fb.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
				quiz_fb.visible = true
				_place_caption()
			return
		_quiz_answer(item)
		return
	if not demo_running:   # a normal click hands the camera back from "Learn next"
		cam_override = false
		demo_cam = false
	_play_sfx(sfx_select)
	selected = item
	path_ids.clear()
	path_edges.clear()
	_refresh_materials()
	_rebuild_pulses()
	_update_texts()


func _describe_selected() -> String:
	if selected.is_empty():
		if mode == Mode.GRAPH:
			if xr_active:
				return _mastery_line() + "LEFT STICK press: guided tour      HOLD RIGHT STICK: ask the AI by voice      RIGHT GRIP: switch course\n\nRight trigger: select      A: explode      B: switch view\nLeft stick: move      Right stick: turn and zoom"
			return _mastery_line() + "Hover a node to preview it, click to select it.\nCtrl+click a second node to find the shortest path between two concepts.\nClick a category on the right to filter.   D = guided tour,  Q = quiz,  L = token lab,  H = menu."
		return "Click a layer to inspect it. Press E to explode the network."
	if mode == Mode.GRAPH:
		var id: String = selected["id"]
		var node_data: Dictionary = {}
		for n in graph_data["nodes"]:
			if n["id"] == id:
				node_data = n
		return String(node_data["desc"])
	var L: Dictionary = (net_data["layers"] as Array)[selected["layer"]]
	var total: int = 0
	for l2 in net_data["layers"]:
		total += int(l2["params"])
	return "%s\nOutput shape: %s\nParameters: %d (network total %d)\n\n%s" % [L["name"], L["shape"], int(L["params"]), total, L["desc"]]


func _update_texts() -> void:
	var info: String = _describe_selected()
	info_label.text = info
	var head_title: String = ""
	var head_sub: String = ""
	var head_col: Color = Color(0.6, 0.8, 1.0)
	if mode == Mode.GRAPH and not selected.is_empty() and g_items.has(String(selected["id"])):
		var gi: Dictionary = g_items[String(selected["id"])]
		head_title = String(gi["title"])
		var nconn: int = (g_adj[String(selected["id"])] as Array).size()
		head_sub = "●  %s   ·   %d connection%s" % [String(gi["cat"]).to_upper(), nconn, "" if nconn == 1 else "s"]
		head_col = (gi["color"] as Color).lightened(0.3)
	if card_title:
		card_title.visible = head_title != ""
		card_cat.visible = head_title != ""
		card_rule_ref.visible = head_title != ""
		card_title.text = head_title
		card_title.add_theme_color_override("font_color", head_col)
		card_cat.text = head_sub
		card_cat.add_theme_color_override("font_color", head_col)
	if vr_label:
		vr_label.text = (head_title + "\n\n" if head_title != "" else "") + info + ("\n\nAI: " + _answer_text if _answer_text != "" else "")


# ───────────────────────── AI (Ollama + graph retrieval) ─────────────────────────
func _on_question_submitted(q: String) -> void:
	question_edit.release_focus()
	_ask(q)
	question_edit.clear()


## Very small stemmer so "models" matches "model", "cleaning" matches "clean", etc.
func _stem(w: String) -> String:
	for suf in ["ing", "ed", "es", "s"]:
		if w.length() > 4 and w.ends_with(suf):
			return w.substr(0, w.length() - suf.length())
	return w


func _retrieve(q: String) -> Array:
	var words: Array = []
	for w in q.to_lower().split(" ", false):
		var cw: String = w.strip_edges().trim_suffix("?").trim_suffix(".").trim_suffix(",")
		if cw.length() > 2 and not STOP_WORDS.has(cw):
			words.append(_stem(cw))
	var scored: Array = []
	for n in graph_data["nodes"]:
		var label: String = String(n["label"]).to_lower()
		var hay: String = label + " " + String(n["desc"]).to_lower()
		var s: int = 0
		for w in words:
			if label.contains(w):
				s += 3
			elif hay.contains(w):
				s += 1
		if s > 0:
			scored.append([s, n["id"]])
	scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var out: Array = []
	for i in mini(4, scored.size()):
		out.append(scored[i][1])
	# the selected node is only added when the question refers to it ("this", "it", "selected") or nothing matched
	var refers: bool = q.to_lower().contains("this") or q.to_lower().contains("selected") or q.to_lower().contains(" it")
	if not selected.is_empty() and mode == Mode.GRAPH and (out.is_empty() or refers) and not out.has(selected["id"]):
		out.append(selected["id"])
	if out.size() > 0:
		for adj in g_adj[out[0]]:
			if not out.has(adj[0]) and out.size() < 8:
				out.append(adj[0])
	return out


func _build_facts(q: String) -> String:
	var facts: String = ""
	highlighted.clear()
	if mode == Mode.GRAPH:
		var ids: Array = _retrieve(q)
		highlighted = ids.duplicate()
		for n in graph_data["nodes"]:
			if ids.has(n["id"]):
				facts += "- %s (%s): %s\n" % [n["label"], n["category"], n["desc"]]
		for e in g_edges:
			if ids.has(e[0]) and ids.has(e[1]):
				facts += "- %s %s %s\n" % [(g_items[e[0]] as Dictionary)["title"], e[2], (g_items[e[1]] as Dictionary)["title"]]
	else:
		for L in net_data["layers"]:
			facts += "- %s, output %s, %d params: %s\n" % [L["name"], L["shape"], int(L["params"]), L["desc"]]
	return facts


## Browser version: the retrieval half of GraphRAG still runs (nodes glow), the answer is the graph's own facts.
func _web_answer() -> void:
	var lines: PackedStringArray = []
	var first: String = ""
	for id in highlighted.slice(0, 4):
		if not g_items.has(String(id)):
			continue
		var b: String = _brief(String(id), 160)
		lines.append("•  %s:  %s" % [_title_of(String(id)), b])
		if first == "":
			first = "%s. %s" % [_title_of(String(id)), b]
	_show_answer("From the knowledge graph (glowing):\n" + "\n".join(lines) + "\n\n🌐 Browser demo: download the desktop app for the full AI tutor and voice questions.")
	if not demo_running:
		_speak_answer(first)


func _ask(q: String) -> void:
	q = q.strip_edges()
	if q == "":
		return
	if _ai_busy and not narr_record:
		status_label.text = "The AI is still answering, please wait..."
		return
	_last_facts = _build_facts(q)
	if narr_record:   # silent recording run: pick the concepts, but do not call the AI
		return
	if mode == Mode.GRAPH and highlighted.is_empty():
		_refresh_materials()
		_show_answer("I could not find anything about that in the knowledge graph, so I will not guess.\n" + String(_demo("unknown_hint", "Try terms like: overfitting, GraphRAG, gradient boosting, feature engineering, LSTM, Ollama.")))
		_voice_asked = false
		if not demo_running:
			_speak_answer(_answer_text)
		return
	_stop_answer_voice()   # a new question: stop reading the previous answer
	_refresh_materials()
	_rebuild_pulses()
	if IS_WEB:   # browser demo: no local LLM -> answer straight from the retrieved graph facts
		_web_answer()
		return
	var prompt: String = "You are a friendly tutor for %s inside a VR learning application. Answer in at most 4 short sentences, using ONLY the facts below. If the facts are not enough, say so.\n\nFACTS:\n%s\nQUESTION: %s" % [String(COURSES[course_idx]["name"]), _last_facts, q]
	var body: String = JSON.stringify({"model": OLLAMA_MODEL, "prompt": prompt, "stream": false})
	var err: int = http.request(OLLAMA_URL, ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)
	if err != OK:
		_show_answer("Could not start the request (error %d)." % err)
		return
	_ai_busy = true
	_show_answer("Q: %s\n\nThinking... (retrieved nodes are glowing)" % q)


func _on_ai_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_ai_busy = false
	# every Ask-AI answer is read out (voice, suggestion buttons, typed, Explain simply) -
	# except inside the guided tour, which has its own narrator
	var spoken_q: bool = _voice_asked or (not demo_running and not narr_record)
	_voice_asked = false
	if result != OK or code != 200:
		_show_answer("Ollama is not reachable. Install it and run:  ollama pull %s\n\nRelevant facts from the graph:\n%s" % [OLLAMA_MODEL, _last_facts])
		if spoken_q:
			_speak_answer("Sorry, the local AI is not running right now. The related facts are on the screen.")
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if parsed is Dictionary and parsed.has("response"):
		var answer: String = String(parsed["response"]).strip_edges()
		_show_answer(answer)
		if spoken_q:
			_speak_answer(answer)   # you asked out loud -> the answer is spoken too (text stays on screen)
		else:
			_speak(answer)
	else:
		_show_answer("Unexpected AI response.")


# ═════════════════════ VOICE QUESTIONS (hold to speak -> local Whisper -> GraphRAG + Ollama) ═════════════════════
# Desktop: hold the 🎤 button in the Ask AI bar.   VR: hold the RIGHT joystick (press it down), speak, release.
# Speech-to-text runs offline in tools/stt_server.py (faster-whisper on the CPU), started automatically.
const STT_URL: String = "http://127.0.0.1:11435/transcribe"
const STT_SCRIPT: String = "res://tools/stt_server.py"
const VOICE_MAX_SEC: float = 20.0
var mic_player: AudioStreamPlayer
var mic_rec: AudioEffectRecord
var mic_bus: int = -1
var voice_rec: bool = false
var _voice_t0: int = 0
var stt_http: HTTPRequest
var _stt_pid: int = -1
var _stt_busy: bool = false
var voice_btn: Button


var IS_WEB: bool = OS.has_feature("web")   # running in a browser (web export)


func _setup_voice() -> void:
	if IS_WEB:
		# browser: no local speech engine / microphone recording; answers are read by the browser's voice
		tts_http = HTTPRequest.new()
		add_child(tts_http)
		answer_player = AudioStreamPlayer.new()
		add_child(answer_player)
		if voice_btn:
			voice_btn.visible = false
		return
	# 1) the local speech engine (exits by itself if one is already running)
	var stt_path: String = _stt_script_path()
	if FileAccess.file_exists(stt_path):
		var args: PackedStringArray = [stt_path, "--parent", str(OS.get_process_id())]
		_stt_pid = OS.create_process("pythonw", args)   # pythonw = no console window over the game
		if _stt_pid <= 0:
			_stt_pid = OS.create_process("python", args)
	# 2) microphone -> "VoiceMic" bus (with a recorder) -> muted "VoiceSink": recorded, never played back
	var sink: int = AudioServer.get_bus_count()
	AudioServer.add_bus()
	AudioServer.set_bus_name(sink, "VoiceSink")
	AudioServer.set_bus_mute(sink, true)
	mic_bus = AudioServer.get_bus_count()
	AudioServer.add_bus()
	AudioServer.set_bus_name(mic_bus, "VoiceMic")
	AudioServer.set_bus_send(mic_bus, "VoiceSink")
	mic_rec = AudioEffectRecord.new()
	mic_rec.format = AudioStreamWAV.FORMAT_16_BITS
	AudioServer.add_bus_effect(mic_bus, mic_rec)
	stt_http = HTTPRequest.new()
	stt_http.timeout = 60.0
	stt_http.request_completed.connect(_on_stt_done)
	add_child(stt_http)
	# 3) spoken answers
	tts_http = HTTPRequest.new()
	tts_http.timeout = 20.0
	tts_http.request_completed.connect(_on_tts_done)
	add_child(tts_http)
	answer_player = AudioStreamPlayer.new()
	answer_player.volume_db = 2.0
	answer_player.finished.connect(_play_next_answer_audio)
	add_child(answer_player)


# ── spoken answers: same neural voice as the tour, streamed sentence by sentence ──
const TTS_URL: String = "http://127.0.0.1:11435/speak"
var tts_http: HTTPRequest
var answer_player: AudioStreamPlayer
var _say_chunks: Array = []      # text still to turn into audio
var _say_audio: Array = []       # audio ready to play, in order
var _say_inflight: String = ""
var _voice_asked: bool = false   # the current question was spoken -> speak the answer too


func _answer_speaking() -> bool:
	return (answer_player != null and answer_player.playing) or not _say_audio.is_empty() or _say_inflight != ""


func _clean_for_speech(t: String) -> String:
	var s: String = t
	for ch in ["*", "#", "`", "_", "•", "|"]:
		s = s.replace(ch, " ")
	s = s.replace("->", " to ").replace("→", " to ").replace("GraphRAG", "Graph RAG").replace("e.g.", "for example").replace("i.e.", "that is")
	s = s.replace("\n", " ")
	while s.contains("  "):
		s = s.replace("  ", " ")
	return s.strip_edges()


## First sentence alone (so the voice starts almost at once), the rest in chunks of ~250 characters.
func _speech_chunks(t: String) -> Array:
	var re: RegEx = RegEx.new()
	re.compile("[^.!?]+[.!?]+[\"')\\]]*|[^.!?]+$")
	var sentences: Array = []
	for m in re.search_all(t):
		var sx: String = m.get_string().strip_edges()
		if sx != "":
			sentences.append(sx)
	var out: Array = []
	var cur: String = ""
	for i in sentences.size():
		if i == 0:
			# the voice is made one clip at a time and longer text takes longer: keep the FIRST clip short
			# (split a long first sentence at its first comma) so speaking starts almost at once
			var first: String = sentences[0]
			var cut: int = first.find(", ", 22)
			if first.length() > 70 and cut > 0 and cut < 75:
				out.append(first.substr(0, cut + 1))
				sentences[0] = first.substr(cut + 2)
				cur = String(sentences[0])
			else:
				out.append(first)
			continue
		if cur != "" and cur.length() + String(sentences[i]).length() > 250:
			out.append(cur)
			cur = ""
		cur = (cur + " " + String(sentences[i])).strip_edges()
	if cur != "":
		out.append(cur)
	return out


func _speak_answer(t: String) -> void:
	_stop_answer_voice()
	if IS_WEB:   # browser: use the browser's built-in speech voice
		var wv: PackedStringArray = DisplayServer.tts_get_voices_for_language("en")
		if not wv.is_empty() and t.strip_edges() != "":
			DisplayServer.tts_stop()
			DisplayServer.tts_speak(_spoken(_clean_for_speech(t)), wv[0], 90, 1.0, 1.0)
		return
	_say_chunks = _speech_chunks(_clean_for_speech(t))
	_fetch_next_speech()
	if not _say_chunks.is_empty() or _say_inflight != "":
		status_label.text = "🔊  Speaking the answer   ·   %s again to interrupt" % ("hold the right stick" if xr_active else "hold 🎤")


func _fetch_next_speech() -> void:
	if _say_inflight != "" or _say_chunks.is_empty():
		return
	_say_inflight = String(_say_chunks.pop_front())
	var err: int = tts_http.request(TTS_URL, PackedStringArray(["Content-Type: text/plain; charset=utf-8"]), HTTPClient.METHOD_POST, _say_inflight)
	if err != OK:
		_speech_fallback()


func _on_tts_done(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if _say_inflight == "":
		return   # stopped meanwhile
	if result != OK or code != 200 or body.size() < 200:
		_speech_fallback()   # offline: the neural voice needs internet -> system voice
		return
	var mp3: AudioStreamMP3 = AudioStreamMP3.new()
	mp3.data = body
	_say_audio.append(mp3)
	_say_inflight = ""
	_play_next_answer_audio()
	_fetch_next_speech()   # prepare the next sentence while this one plays


func _play_next_answer_audio() -> void:
	if answer_player.playing or _say_audio.is_empty():
		return
	answer_player.stream = _say_audio.pop_front()
	answer_player.play()


## No neural voice available: read the rest with the Windows voice.
func _speech_fallback() -> void:
	var rest: String = (_say_inflight + " " + " ".join(PackedStringArray(_say_chunks))).strip_edges()
	_say_inflight = ""
	_say_chunks.clear()
	var voices: PackedStringArray = DisplayServer.tts_get_voices_for_language("en")
	if rest != "" and not voices.is_empty():
		DisplayServer.tts_speak(_spoken(rest), voices[0], 90, 1.0, 1.0)


func _stop_answer_voice() -> void:
	_say_chunks.clear()
	_say_audio.clear()
	if _say_inflight != "":
		tts_http.cancel_request()
		_say_inflight = ""
	if answer_player != null:
		answer_player.stop()


## In the editor the script is in res://tools; in the downloadable app it sits next to the .exe (tools/stt_server.py).
func _stt_script_path() -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path(STT_SCRIPT)
	return OS.get_executable_path().get_base_dir().path_join("tools/stt_server.py")


func _notification(what: int) -> void:
	if (what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE) and _stt_pid > 0:
		OS.kill(_stt_pid)   # stop the speech engine together with the app
		_stt_pid = -1


## In the headset, record from the headset's own microphone (matched by common headset device names).
const HEADSET_MIC_HINTS: Array = ["headset", "virtual audio", "vr", "xr", "quest", "oculus", "index", "pico", "reverb", "vive"]


func _pick_vr_mic() -> void:
	for dev in AudioServer.get_input_device_list():
		var d: String = String(dev).to_lower()
		for hint in HEADSET_MIC_HINTS:
			if d.contains(String(hint)):
				if AudioServer.input_device != dev:
					AudioServer.input_device = dev
				return


func _voice_start() -> void:
	if voice_rec or mic_rec == null:
		return
	if _stt_busy or _ai_busy:
		status_label.text = "Still answering the last question - one moment..."
		return
	if quiz_active:
		status_label.text = "Voice questions are off during the quiz - no peeking!"
		return
	if demo_running:
		_stop_demo()
	menu_panel.visible = false
	lab_panel.visible = false
	sl_panel.visible = false
	al_panel.visible = false
	ask_on = true
	_stop_voice()   # silence the narrator so the microphone only hears you
	if xr_active:
		_pick_vr_mic()
	if mic_player == null:
		mic_player = AudioStreamPlayer.new()
		mic_player.stream = AudioStreamMicrophone.new()
		mic_player.bus = "VoiceMic"
		add_child(mic_player)
	mic_player.play()
	mic_rec.set_recording_active(true)
	voice_rec = true
	_voice_t0 = Time.get_ticks_msec()
	_play_sfx(sfx_pop, -10.0)
	if voice_btn:
		voice_btn.text = "●  Listening... release to send"
		voice_btn.modulate = Color(1.0, 0.55, 0.55)
	_voice_level_text()


func _voice_stop() -> void:
	if not voice_rec:
		return
	voice_rec = false
	var dur: float = float(Time.get_ticks_msec() - _voice_t0) / 1000.0
	mic_rec.set_recording_active(false)
	var wav: AudioStreamWAV = mic_rec.get_recording() if dur >= 0.6 else null   # a quick tap has no audio yet
	mic_player.stop()
	if voice_btn:
		voice_btn.text = "🎤  Hold to speak"
		voice_btn.modulate = Color.WHITE
	if wav == null or wav.get_length() < 0.4:
		_show_answer("Keep holding while you speak - that was too short.\n" + _voice_how())
		return
	var path: String = "user://voice_question.wav"
	if wav.save_to_wav(path) != OK:
		_show_answer("Could not save the recording.")
		return
	var url: String = STT_URL + "?prompt=" + _stt_glossary().uri_encode()
	var err: int = stt_http.request_raw(url, PackedStringArray(["Content-Type: audio/wav"]), HTTPClient.METHOD_POST, FileAccess.get_file_as_bytes(path))
	if err != OK:
		_show_answer("Could not reach the speech engine (error %d)." % err)
		return
	_stt_busy = true
	_play_sfx(sfx_select, -10.0)
	_show_answer("🎤  Got it - turning your voice into text ...")


func _voice_how() -> String:
	return "Hold the RIGHT joystick down, ask your question, then let go." if xr_active else "Hold the 🎤 button, ask your question, then let go."


## Course words Whisper should expect (GraphRAG, LSTM, tokenizer ...): makes technical terms come out right.
func _stt_glossary() -> String:
	var names: PackedStringArray = []
	for n in graph_data.get("nodes", []):
		names.append(String(n["label"]))
		if names.size() >= 60:
			break
	return "Glossary: " + ", ".join(names) + "."


## Live microphone level while recording, so you can see it hears you.
func _voice_level_text() -> void:
	var db: float = AudioServer.get_bus_peak_volume_left_db(mic_bus, 0) if mic_bus >= 0 else -80.0
	var lv: int = clampi(int((db + 54.0) / 4.5), 0, 12)
	var secs: float = float(Time.get_ticks_msec() - _voice_t0) / 1000.0
	answer_label.text = "🎤  LISTENING   %s%s   %.0fs\n\nAsk your question now, then release.  (max %d s)" % ["▮".repeat(lv), "▯".repeat(12 - lv), secs, int(VOICE_MAX_SEC)]


func _update_voice() -> void:
	if not voice_rec:
		return
	_voice_level_text()
	if float(Time.get_ticks_msec() - _voice_t0) / 1000.0 > VOICE_MAX_SEC:
		_voice_stop()


func _on_stt_done(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	_stt_busy = false
	if result != OK or code != 200:
		_show_answer("The speech engine is not running yet.\nWait a few seconds and try again. If it keeps failing, open a terminal and run:\n    pip install faster-whisper\nthen restart the app.")
		if _stt_pid <= 0 or not OS.is_process_running(_stt_pid):   # try to (re)start it for the next attempt
			_stt_pid = OS.create_process("pythonw", [_stt_script_path(), "--parent", str(OS.get_process_id())])
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	var text: String = String((parsed as Dictionary).get("text", "")).strip_edges() if parsed is Dictionary else ""
	if text.length() < 3:
		_show_answer("I didn't catch that - please speak a little louder and closer.\n" + _voice_how())
		return
	question_edit.text = text
	_voice_asked = true
	_ask(text)
	question_edit.clear()


func _show_answer(t: String) -> void:
	_answer_text = t
	answer_label.text = t
	if answer_scroll:
		answer_scroll.scroll_vertical = 0   # every new answer starts at its first line
	_update_texts()


# ───────────────────────── input / loop ─────────────────────────
func _process(delta: float) -> void:
	time_s += delta
	stars.rotate_y(delta * 0.01)
	_update_environment(delta)
	_update_tour(delta)
	_update_music_duck(delta)
	_update_voice()
	_update_chrome(delta)
	_animate_net_pulses()
	if spread != spread_target:
		spread = move_toward(spread, spread_target, delta * 0.9)
	if spread != _spread_applied:
		_apply_spread()
	_animate_items(delta)
	if xr_active:
		_vr_auto_place(delta)
		_vr_ui_update(delta)
		_vr_fix_labels()
		_vr_stick_controls(delta)
	else:
		if auto_rotate:
			yaw += delta * 0.15
		_update_camera(delta)


func _animate_items(delta: float) -> void:
	var k: float = 1.0 - exp(-delta * 10.0)
	if mode == Mode.GRAPH:
		var sel_id: String = selected.get("id", "")
		for it in items:
			var target: float = 1.0
			if it["id"] == sel_id:
				target = 1.35 + 0.08 * sin(time_s * 4.0)
			elif it["id"] == hover_id:
				target = 1.2
			elif _is_dim(it):
				target = 0.6
			if calc_graph and it["id"] != sel_id:
				target = float(calc_scale.get(it["id"], 0.7))
			var pp: float = float(it.get("pop", 0.0))
			if pp > 0.01:   # "pop" when its name is spoken
				target *= 1.0 + 0.8 * pp
				it["pop"] = pp * exp(-delta * 1.6)
			var node: Node3D = it["node"]
			node.scale = Vector3.ONE * lerpf(node.scale.x, target, k)
		for p in pulses:
			var e: Array = g_edges[p["ei"]]
			var a: Vector3 = (g_items[e[0]]["node"] as Node3D).position
			var b: Vector3 = (g_items[e[1]]["node"] as Node3D).position
			var t: float = fmod(time_s * 0.6 + float(p["off"]), 1.0)
			(p["node"] as Node3D).position = a.lerp(b, t)
	elif forward_pass and not calc_net and not n_layers.is_empty():
		fwd_t += delta * 1.6
		var n: int = n_layers.size()
		var head: float = fmod(fwd_t, float(n + 2))
		var sel_layer: int = selected.get("layer", -1)
		for i in n:
			var e_val: float = 0.35 + 2.2 * clampf(1.0 - absf(head - float(i)), 0.0, 1.0)
			if i == sel_layer:
				e_val = 2.6
			for mm in (n_layers[i] as Dictionary)["mats"]:
				(mm as StandardMaterial3D).emission_energy_multiplier = e_val


## VR sticks.  LEFT stick: X = move left/right, Y = move up/down (hold LEFT GRIP: Y = forward/back).
## RIGHT stick: X = rotate, Y = zoom in/out.
func _vr_stick_controls(delta: float) -> void:
	if demo_running and demo_cam:
		# the demo "camera" moves the model in front of you instead
		demo_yaw += delta * 0.05
		var sc: float = clampf(vr_scale * _default_dist() / maxf(dist_goal, 3.0), 0.02, 0.6)
		var k: float = 1.0 - exp(-delta * 2.0)
		var s2: float = lerpf(content.scale.x, sc, k)
		content.scale = Vector3.ONE * s2
		content.rotation.y = lerp_angle(content.rotation.y, vr_yaw + demo_yaw - 0.5, k)
		var goal: Vector3 = vr_anchor - Basis(Vector3.UP, content.rotation.y) * (cam_focus_goal * s2)
		content.position = content.position.lerp(goal, k)
		return
	var st: Vector2 = xr_left.get_vector2("primary")
	var sr: Vector2 = xr_right.get_vector2("primary")
	var dz: float = 0.35   # larger dead zone: a resting thumb or a slightly drifting stick no longer moves / resizes the model
	if voice_rec:
		sr = Vector2.ZERO   # the right stick is held down for talking: don't turn / zoom by accident
	if _ui_over_control():
		# pointing at the screen: right stick scrolls (answers, menus) instead of turning the model
		if absf(sr.y) > dz and _wheel_t <= 0.0:
			_ui_wheel(sr.y > 0.0)
			_wheel_t = 0.09
		sr = Vector2.ZERO
	if st.length() > dz:
		var cam_basis: Basis = xr_camera.global_transform.basis
		var right: Vector3 = Vector3(cam_basis.x.x, 0.0, cam_basis.x.z).normalized()
		var fwd: Vector3 = Vector3(-cam_basis.z.x, 0.0, -cam_basis.z.z).normalized()
		var speed: float = 0.9 * delta
		var move: Vector3 = right * st.x * speed
		if xr_left.is_button_pressed("grip_click"):
			move += fwd * st.y * speed
		else:
			move += Vector3.UP * st.y * speed
		content.global_position += move
		content.global_position.y = maxf(content.global_position.y, 0.2)
	if absf(sr.x) > dz:
		content.rotate_y(sr.x * delta * 1.5)   # stick right -> model turns right
	if absf(sr.y) > dz:
		var s: float = clampf(content.scale.x * (1.0 - sr.y * delta * 1.2), 0.03, 0.5)   # stick up -> bigger / closer
		content.scale = Vector3.ONE * s


func _update_camera(delta: float) -> void:
	if camera == null or xr_active:
		return
	dist = lerpf(dist, dist_goal, 1.0 - exp(-delta * 6.0))
	if demo_cam:
		demo_yaw += delta * 0.05
		yaw = lerp_angle(yaw, demo_yaw, 1.0 - exp(-delta * 1.8))
		pitch = lerpf(pitch, demo_pitch, 1.0 - exp(-delta * 1.8))
	var focus_target: Vector3 = Vector3(0.0, 0.9, 0.0)   # look a little above the graph centre so it sits lower, clear of the top bar
	if cam_override:
		focus_target = cam_focus_goal
	elif not selected.is_empty():
		focus_target = (selected["node"] as Node3D).position * 0.5 + Vector3(0.0, 0.6, 0.0)
	cam_focus = cam_focus.lerp(focus_target, 1.0 - exp(-delta * 4.0))
	var offset: Vector3 = Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * dist
	camera.position = cam_focus + offset
	camera.look_at(cam_focus, Vector3.UP)


func _pick(origin: Vector3, dir: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var best_t: float = INF
	var s: float = content.global_transform.basis.get_scale().x
	for it in items:
		var c: Vector3 = (it["node"] as Node3D).global_position
		var r: float = float(it["radius"]) * s
		var oc: Vector3 = origin - c
		var b: float = oc.dot(dir)
		var disc: float = b * b - (oc.dot(oc) - r * r)
		if disc < 0.0:
			continue
		var t: float = -b - sqrt(disc)
		if t > 0.0 and t < best_t:
			best_t = t
			best = it
	return best


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			dist_goal = maxf(3.0, dist_goal * 0.9)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			dist_goal = minf(90.0, dist_goal * 1.1)
		elif mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				_dragging = true
				_drag_moved = 0.0
			else:
				_dragging = false
				if mb.button_index == MOUSE_BUTTON_LEFT and _drag_moved < 6.0 and not xr_active:
					var hit: Dictionary = _pick(camera.project_ray_origin(mb.position), camera.project_ray_normal(mb.position))
					if (mb.ctrl_pressed or mb.shift_pressed) and not hit.is_empty() and not selected.is_empty() and mode == Mode.GRAPH:
						_show_path(hit)
						return
					if hit.is_empty():
						if not demo_running and not quiz_active:
							cam_override = false
							demo_cam = false
						selected = {}
						_refresh_materials()
						_rebuild_pulses()
						_update_texts()
					else:
						_select(hit)
	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		if _dragging:
			_drag_moved += mm.relative.length()
			if _drag_moved > 6.0:
				auto_rotate = false
				demo_cam = false
			yaw -= mm.relative.x * 0.006
			pitch = clampf(pitch + mm.relative.y * 0.006, -1.4, 1.4)
		elif not xr_active:
			var h: Dictionary = _pick(camera.project_ray_origin(mm.position), camera.project_ray_normal(mm.position))
			var nid: String = "" if h.is_empty() else String(h["id"])
			if nid != hover_id:
				hover_id = nid
				Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if nid != "" else Input.CURSOR_ARROW)
				_refresh_materials()
	elif event is InputEventKey and event.pressed and not event.echo:
		var k: InputEventKey = event
		if menu_panel.visible and k.keycode >= KEY_1 and k.keycode <= KEY_6:   # home screen: number keys pick a card
			var ai: int = k.keycode - KEY_1
			if ai < menu_actions.size():
				(menu_actions[ai] as Callable).call()
			return
		match k.keycode:
			KEY_1: _set_mode(Mode.GRAPH)
			KEY_2: _set_mode(Mode.NETWORK)
			KEY_E: _toggle_explode()
			KEY_F: forward_pass = not forward_pass
			KEY_R: _reset_view()
			KEY_T: auto_rotate = not auto_rotate
			KEY_M: _toggle_music()
			KEY_P: _save_screenshot()
			KEY_G: _toggle_tour()
			KEY_D: _toggle_demo()
			KEY_Q: _toggle_quiz()
			KEY_C: _switch_course()
			KEY_L: _toggle_lab()
			KEY_K: _toggle_sampling()
			KEY_N: _start_recording()
			KEY_A: _toggle_attention()
			KEY_H: _show_menu()
			KEY_SPACE:
				if quiz_waiting:
					quiz_next.emit()
				else:
					demo_skip = true
			KEY_ENTER, KEY_KP_ENTER:
				if quiz_waiting:
					quiz_next.emit()
			KEY_ESCAPE: _stop_demo()
			KEY_V: _toggle_voice()


func _on_right_button(button: String) -> void:
	match button:
		"trigger_click":
			var xf: Transform3D = xr_right.global_transform
			_vr_trigger(true, xf.origin, -xf.basis.z.normalized())
		"ax_button": _toggle_explode()
		"by_button": _set_mode(Mode.NETWORK if mode == Mode.GRAPH else Mode.GRAPH)
		"primary_click": _voice_start()   # hold the right joystick = ask by voice (quiz is on the screen menu)
		"grip_click": _switch_course()


func _on_right_button_up(button: String) -> void:
	if button == "primary_click":
		_voice_stop()
	elif button == "trigger_click":
		var xf: Transform3D = xr_right.global_transform
		_vr_trigger(false, xf.origin, -xf.basis.z.normalized())


func _on_left_button(button: String) -> void:
	match button:
		"ax_button":
			if not selected.is_empty():
				_ask("Explain " + String(selected["title"]) + " and how it connects to other concepts")
		"by_button": _reset_view()
		"primary_click", "menu_button": _toggle_demo()
