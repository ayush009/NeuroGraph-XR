class_name Intro
extends Control
## NeuroGraph XR - cinematic studio-style opening (about 11 s), like a film studio sting:
##   0.0 - 2.0 s   production card:  "AN ORIGINAL PRODUCTION ... presents"  (fades in and out of black)
##   2.0 - 6.4 s   flip-book montage of the course concepts, cards flicking faster and faster, screen shake, music building
##   6.6 s         white flash + shockwave: the logo mark SLAMS in
##   7.0 - 8.6 s   title "NEUROGRAPH XR" revealed letter by letter while the narrator says "Welcome to NeuroGraph X R"
##   9.0 s         tagline  |  10.0 s learning pipeline  |  10.5 s "Click anywhere to begin"
## Interactive: mouse parallax, clicks send shockwaves, Enter / Space / Esc skips, click after the title continues.

signal finished
signal ripple_made

const STUDIO_LINE: String = "AN ORIGINAL PRODUCTION"      # <- put your name or institute here
const PALETTE: Array = [Color("#3fa7ff"), Color("#35d6a0"), Color("#ff8a3d"), Color("#b583ff"), Color("#ff4f79"), Color("#ffd23f")]
const PIPELINE: Array = ["Text", "Tokens", "Embeddings", "Attention", "Answer"]
const CARD_TITLES: Array = ["TOKENS", "EMBEDDINGS", "ATTENTION", "TRANSFORMER", "KNOWLEDGE GRAPH", "RAG", "PROBABILITIES"]
const TITLE: String = "NEUROGRAPH XR"
const TAGLINE: String = "Learn how AI works by exploring it in 3D"
const T_MONTAGE: float = 1.5
const T_SLAM: float = 5.0
const T_TITLE: float = 5.4
const T_CAN_BEGIN: float = 7.2
const T_READY: float = 8.4
const SWELL: String = "res://assets/generated/audio/epic_swell.mp3"
const HIT: String = "res://assets/generated/audio/epic_hit.mp3"
const VOICE: String = "res://assets/narration/intro_welcome.mp3"
const LOGO: String = "res://assets/generated/neurograph_logo.png"

var t: float = 0.0
var leaving: bool = false
var leave_t: float = 0.0
var logo: Texture2D
var font: Font
var ripples: Array = []
var sparks: Array = []
var slots: Array = []            # montage cards: {start, dur, kind, rot, drift}
var swell_player: AudioStreamPlayer
var voice_player: AudioStreamPlayer
var boom_player: AudioStreamPlayer
var tick_player: AudioStreamPlayer
var vignette: GradientTexture2D
var last_slot: int = -1
var swell_started: bool = false
var voice_started: bool = false
var slammed: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	font = ThemeDB.fallback_font
	if ResourceLoader.exists(LOGO):
		logo = load(LOGO)
	for nm in ["tokens", "embeddings", "attention", "transformer", "graph", "rag", "prob"]:
		var ap: String = "res://assets/generated/hd_%s.png" % nm
		if not ResourceLoader.exists(ap):
			ap = "res://assets/generated/card_%s.png" % nm
		art.append(load(ap) if ResourceLoader.exists(ap) else null)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 21
	var tm: float = T_MONTAGE
	var d: float = 0.62
	var k: int = 0
	while tm < T_SLAM - 0.1:
		slots.append({"start": tm, "dur": d, "kind": k % CARD_TITLES.size(), "rot": rng.randf_range(-0.14, 0.14), "drift": rng.randf_range(-30.0, 30.0)})
		tm += d
		d = maxf(0.11, d * 0.84)
		k += 1
	swell_player = AudioStreamPlayer.new()
	swell_player.volume_db = -15.0     # background kept quiet
	add_child(swell_player)
	voice_player = AudioStreamPlayer.new()
	voice_player.volume_db = 3.0
	add_child(voice_player)
	if ResourceLoader.exists(SWELL):
		swell_player.stream = load(SWELL)
	if ResourceLoader.exists(VOICE):
		voice_player.stream = load(VOICE)
	boom_player = AudioStreamPlayer.new()
	boom_player.volume_db = -1.0
	add_child(boom_player)
	tick_player = AudioStreamPlayer.new()
	tick_player.volume_db = -14.0
	add_child(tick_player)
	if ResourceLoader.exists(HIT):
		boom_player.stream = load(HIT)
	_build_3d()
	if ResourceLoader.exists("res://assets/generated/audio/intro_tick.mp3"):
		tick_player.stream = load("res://assets/generated/audio/intro_tick.mp3")
	var g: Gradient = Gradient.new()
	g.offsets = PackedFloat32Array([0.3, 1.0])
	g.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0.7)])
	vignette = GradientTexture2D.new()
	vignette.gradient = g
	vignette.fill = GradientTexture2D.FILL_RADIAL
	vignette.fill_from = Vector2(0.5, 0.5)
	vignette.fill_to = Vector2(1.0, 1.0)
	vignette.width = 256
	vignette.height = 256
	_fit()


var art: Array = []
var vp: SubViewport
var cam3: Camera3D
var title3: MeshInstance3D
var sweep3: OmniLight3D
var embers: CPUParticles3D
var use_3d: bool = false


## A real 3D title: extruded metal letters with reflections, a moving light sweep and bloom (rendered live).
func _build_3d() -> void:
	vp = SubViewport.new()
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(vp)
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	var sky: Sky = Sky.new()
	var psm: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.02, 0.04, 0.14)
	psm.sky_energy_multiplier = 0.9
	psm.sky_curve = 0.12
	psm.sky_horizon_color = Color(0.55, 0.72, 1.0)
	psm.ground_horizon_color = Color(0.45, 0.35, 0.7)
	psm.ground_bottom_color = Color(0.01, 0.01, 0.04)
	sky.sky_material = psm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 1.0
	env.glow_bloom = 0.12
	env.glow_hdr_threshold = 0.8
	var we: WorldEnvironment = WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var tm: TextMesh = TextMesh.new()
	tm.text = TITLE
	var heavy: SystemFont = SystemFont.new()          # a bold, wide "movie title" face (falls back safely if missing)
	heavy.font_names = PackedStringArray(["Impact", "Arial Black", "Segoe UI Black", "Bahnschrift", "Arial"])
	heavy.font_weight = 900
	heavy.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	var spaced: FontVariation = FontVariation.new()   # extra space between letters so they never fuse
	spaced.base_font = heavy
	spaced.spacing_glyph = 34
	tm.font = spaced
	tm.font_size = 150
	tm.depth = 0.32
	tm.pixel_size = 0.0048
	tm.curve_step = 0.1
	title3 = MeshInstance3D.new()
	title3.mesh = tm
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.62, 0.74, 1.0)
	mat.metallic = 1.0
	mat.metallic_specular = 1.0
	mat.roughness = 0.22
	mat.clearcoat_enabled = true
	mat.clearcoat = 1.0
	mat.clearcoat_roughness = 0.05
	mat.rim_enabled = true
	mat.rim = 0.8
	mat.rim_tint = 0.6
	mat.emission_enabled = true
	mat.emission = Color(0.12, 0.35, 0.85)
	mat.emission_energy_multiplier = 0.3
	title3.material_override = mat
	title3.position = Vector3(0, 0.0, 0)
	vp.add_child(title3)
	cam3 = Camera3D.new()
	cam3.fov = 40.0
	cam3.position = Vector3(0, 0, 9.0)
	vp.add_child(cam3)
	cam3.current = true
	var l1: OmniLight3D = OmniLight3D.new()
	l1.position = Vector3(-4, 2, 3)
	l1.light_color = Color(0.3, 0.7, 1.0)
	l1.light_energy = 3.0
	l1.omni_range = 14.0
	vp.add_child(l1)
	var l2: OmniLight3D = OmniLight3D.new()
	l2.position = Vector3(4, -1, 3)
	l2.light_color = Color(0.75, 0.45, 1.0)
	l2.light_energy = 3.0
	l2.omni_range = 14.0
	vp.add_child(l2)
	var back: OmniLight3D = OmniLight3D.new()          # warm backlight: bright edges behind the letters
	back.position = Vector3(0, 0.4, -2.5)
	back.light_color = Color(1.0, 0.75, 0.45)
	back.light_energy = 5.0
	back.omni_range = 12.0
	vp.add_child(back)
	embers = CPUParticles3D.new()                      # drifting golden embers around the title
	embers.amount = 90
	embers.lifetime = 3.2
	embers.emitting = false
	embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	embers.emission_box_extents = Vector3(3.2, 0.7, 0.6)
	embers.direction = Vector3(0, 1, 0)
	embers.spread = 35.0
	embers.gravity = Vector3.ZERO
	embers.initial_velocity_min = 0.25
	embers.initial_velocity_max = 0.9
	embers.scale_amount_min = 0.4
	embers.scale_amount_max = 1.3
	var em_mesh: SphereMesh = SphereMesh.new()
	em_mesh.radius = 0.011
	em_mesh.height = 0.022
	em_mesh.radial_segments = 8
	em_mesh.rings = 4
	var em_mat: StandardMaterial3D = StandardMaterial3D.new()
	em_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	em_mat.albedo_color = Color(1.0, 0.85, 0.5)
	em_mat.emission_enabled = true
	em_mat.emission = Color(1.0, 0.7, 0.3)
	em_mat.emission_energy_multiplier = 3.0
	em_mesh.material = em_mat
	embers.mesh = em_mesh
	embers.position = Vector3(0, 0.0, 0.3)
	vp.add_child(embers)
	sweep3 = OmniLight3D.new()
	sweep3.light_color = Color(1.0, 1.0, 1.0)
	sweep3.light_energy = 7.0
	sweep3.omni_range = 12.0
	sweep3.position = Vector3(-8, 0.5, 2.5)
	vp.add_child(sweep3)
	use_3d = true


func _update_3d() -> void:
	if not use_3d:
		return
	var st: float = t - T_SLAM
	if st > -0.1 and vp.render_target_update_mode != SubViewport.UPDATE_ALWAYS:
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if st < -0.1:
		return
	if not embers.emitting:
		embers.emitting = true
	cam3.position.z = lerpf(8.6, 5.4, _ease_out(st / 2.6))
	var punch: float = pow(1.0 - clampf(st / 0.45, 0.0, 1.0), 2.0)
	title3.scale = Vector3.ONE * (1.0 + 1.3 * punch)              # the title is hurled at the camera, then settles
	cam3.h_offset = randf_range(-1.0, 1.0) * 0.35 * exp(-maxf(st, 0.0) * 6.0)
	cam3.v_offset = randf_range(-1.0, 1.0) * 0.35 * exp(-maxf(st, 0.0) * 6.0)
	title3.rotation.y = 0.5 * pow(1.0 - _ease_out(st / 2.4), 2.0) + 0.03 * sin(t * 0.8)
	title3.rotation.x = 0.04 * sin(t * 0.6)
	sweep3.position.x = lerpf(-8.0, 8.0, clampf((st - 0.9) / 1.9, 0.0, 1.0))
	sweep3.light_energy = 7.0 if st > 0.9 and st < 2.9 else 1.0
	(title3.material_override as StandardMaterial3D).emission_energy_multiplier = 0.4 + 1.6 * clampf(1.0 - st / 1.2, 0.0, 1.0)


func _fit() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size
	if vp != null and size.x > 64.0 and Vector2i(size) != vp.size:
		vp.size = Vector2i(size)


func restart() -> void:
	scale = Vector2.ONE
	t = 0.0
	leaving = false
	leave_t = 0.0
	modulate.a = 1.0
	ripples.clear()
	sparks.clear()
	swell_started = false
	voice_started = false
	slammed = false
	last_slot = -1
	if use_3d:
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		embers.emitting = false
	boom_player.stop()
	swell_player.stop()
	voice_player.stop()
	swell_player.volume_db = -15.0
	voice_player.volume_db = 3.0
	visible = true
	set_process(true)
	_fit()


func begin_leave() -> void:
	if not leaving:
		leaving = true


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k: InputEventKey = event
		if k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER or k.keycode == KEY_ESCAPE or k.keycode == KEY_SPACE:
			begin_leave()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if t >= T_CAN_BEGIN:
				begin_leave()
			else:
				ripples.append({"p": mb.position, "t": 0.0})
				ripple_made.emit()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible:
		return
	_fit()
	t += delta
	_update_3d()
	# ANTICIPATION: the music is cut dead just before the slam, so the hit lands out of silence
	if not leaving and swell_started and t > T_SLAM - 0.42:
		swell_player.volume_db = lerpf(-15.0, -60.0, clampf((t - (T_SLAM - 0.42)) / 0.18, 0.0, 1.0))
		if t > T_SLAM - 0.2:
			swell_player.stop()
	# IMPACT: the whole screen shakes and settles right after the hit
	if not leaving:
		pivot_offset = size * 0.5
		var sh: float = t - T_SLAM
		if slammed and sh < 1.0:
			var amp: float = 26.0 * exp(-sh * 6.5)
			position = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * amp
			scale = Vector2.ONE * (1.0 + 0.05 * exp(-sh * 6.5))
		else:
			scale = Vector2.ONE
	if not swell_started and t >= 0.0 and swell_player.stream != null:
		swell_started = true
		swell_player.play()
	if not voice_started and t >= T_SLAM + 0.3 and voice_player.stream != null:
		voice_started = true
		voice_player.play()
	for i in slots.size():                       # a soft tick on every card cut
		if i > last_slot and t >= float(slots[i]["start"]):
			last_slot = i
			if tick_player.stream != null:
				tick_player.pitch_scale = 0.9 + 0.5 * float(i) / float(maxi(slots.size() - 1, 1))
				tick_player.play()
	if not slammed and t >= T_SLAM:
		slammed = true
		if boom_player.stream != null:
			boom_player.play()
		ripples.append({"p": size * Vector2(0.5, 0.27), "t": 0.0, "big": true})
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = 77
		for i in 240:
			var ang: float = rng.randf() * TAU
			sparks.append({"p": size * Vector2(0.5, 0.27), "v": Vector2(cos(ang), sin(ang)) * rng.randf_range(160.0, 1500.0), "t": 0.0, "life": rng.randf_range(0.6, 1.9), "c": PALETTE[i % PALETTE.size()]})
		ripples.append({"p": size * Vector2(0.5, 0.27), "t": -0.12, "big": true})
	for r in ripples:
		r["t"] = float(r["t"]) + delta
	ripples = ripples.filter(func(r: Dictionary) -> bool: return float(r["t"]) < 1.8)
	for sp in sparks:
		sp["t"] = float(sp["t"]) + delta
		sp["p"] = (sp["p"] as Vector2) + (sp["v"] as Vector2) * delta
		sp["v"] = (sp["v"] as Vector2) * (1.0 - delta * 1.6)
	sparks = sparks.filter(func(sp: Dictionary) -> bool: return float(sp["t"]) < float(sp["life"]))
	if leaving:
		leave_t += delta
		var k: float = clampf(1.0 - leave_t / 0.55, 0.0, 1.0)
		modulate.a = k
		pivot_offset = size * 0.5
		scale = Vector2.ONE * (1.0 + 0.18 * pow(1.0 - k, 2.0))   # the whole intro pushes towards you as it fades
		swell_player.volume_db = lerpf(-50.0, -15.0, k)
		voice_player.volume_db = lerpf(-50.0, 3.0, k)
		boom_player.volume_db = lerpf(-50.0, -1.0, k)
		if leave_t >= 0.55:
			boom_player.stop()
			swell_player.stop()
			voice_player.stop()
			visible = false
			set_process(false)
			finished.emit()
	queue_redraw()


## A soft radial glow (stacked translucent circles) - no hard edge like a single big circle.
func _soft_glow(c: Vector2, r: float, col: Color) -> void:
	var steps: int = 14
	for i in steps:
		var f: float = 1.0 - float(i) / float(steps)
		draw_circle(c, r * f, Color(col.r, col.g, col.b, col.a * 2.2 / float(steps)))


func _ease_out(x: float) -> float:
	return 1.0 - pow(1.0 - clampf(x, 0.0, 1.0), 3.0)


func _rn(a: float) -> float:
	return fposmod(sin(a * 12.9898) * 43758.5453, 1.0)


func _text_w(txt: String, fs: int) -> float:
	return font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x


func _ctext(txt: String, cx: float, y: float, fs: int, col: Color) -> void:
	draw_string(font, Vector2(cx - _text_w(txt, fs) * 0.5, y), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _draw() -> void:
	var s: Vector2 = size
	var sc: float = clampf(minf(s.x / 1280.0, s.y / 720.0), 0.6, 1.7)
	var mouse: Vector2 = get_local_mouse_position()
	var par: Vector2 = (mouse - s * 0.5) / s
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.006, 0.01, 0.03))
	# drifting dust motes give depth for the whole intro
	for i in 70:
		var dx: float = fposmod(_rn(float(i)) * s.x + t * (6.0 + 14.0 * _rn(float(i) + 5.0)) - par.x * (20.0 + 60.0 * _rn(float(i) + 9.0)), s.x)
		var dy: float = fposmod(_rn(float(i) + 40.0) * s.y - t * (4.0 + 10.0 * _rn(float(i) + 11.0)) - par.y * 30.0, s.y)
		var tw: float = 0.5 + 0.5 * sin(t * 1.5 + float(i))
		draw_circle(Vector2(dx, dy), (0.8 + 1.8 * _rn(float(i) + 3.0)) * sc, Color(0.6, 0.8, 1.0, (0.05 + 0.2 * tw) * minf(t / 1.5, 1.0)))

	# ── 1. production card: letters drift apart to their final spacing, a light sweeps across ──
	if t < T_MONTAGE + 0.2:
		var a: float = minf(clampf(t / 0.5, 0.0, 1.0), clampf((T_MONTAGE + 0.1 - t) / 0.35, 0.0, 1.0))
		var c: Vector2 = s * 0.5 + par * -10.0
		if logo != null:
			var ls: float = 120.0 * sc * (0.9 + 0.1 * a)
			_soft_glow(c - Vector2(0, 60 * sc), ls * 1.1, Color(0.2, 0.5, 1.0, 0.14 * a))
			draw_texture_rect(logo, Rect2(c - Vector2(ls, ls) * 0.5 - Vector2(0, 60 * sc), Vector2(ls, ls)), false, Color(1, 1, 1, a * 0.9))
		var sfs: int = int(22 * sc)
		var track: float = lerpf(2.0, 12.0, _ease_out(t / T_MONTAGE)) * sc
		var stotal: float = 0.0
		for ch in STUDIO_LINE:
			stotal += _text_w(String(ch), sfs) + track
		var sx: float = c.x - stotal * 0.5
		var sweep_x: float = c.x - 300 * sc + (t - 0.3) * 560.0 * sc
		for ch in STUDIO_LINE:
			var cw: float = _text_w(String(ch), sfs)
			var lit: float = clampf(1.0 - absf(sx + cw * 0.5 - sweep_x) / (90.0 * sc), 0.0, 1.0)
			var col_s: Color = Color(0.82, 0.9, 1.0).lerp(Color(1, 1, 1), lit)
			draw_string(font, Vector2(sx, c.y + 40 * sc), String(ch), HORIZONTAL_ALIGNMENT_LEFT, -1, sfs, Color(col_s.r, col_s.g, col_s.b, a))
			sx += cw + track
		draw_line(Vector2(c.x - 190 * sc * a, c.y + 58 * sc), Vector2(c.x + 190 * sc * a, c.y + 58 * sc), Color(0.4, 0.7, 1.0, a * 0.7), 1.5)
		_ctext("p r e s e n t s", c.x, c.y + 92 * sc, int(17 * sc), Color(0.7, 0.8, 0.95, a * 0.75 * clampf((t - 0.7) / 0.5, 0.0, 1.0)))

	# ── 2. flip-book montage ──
	if t >= T_MONTAGE - 0.05 and t < T_SLAM:
		var prog: float = clampf((t - T_MONTAGE) / (T_SLAM - T_MONTAGE), 0.0, 1.0)
		_soft_glow(s * 0.5, s.y * (0.5 + 0.35 * prog), Color(0.05, 0.12, 0.3, 0.3 * prog + 0.12))
		var shake: Vector2 = Vector2(sin(t * 91.0), cos(t * 77.0)) * (2.0 + 14.0 * prog * prog) * sc
		for i in slots.size():
			var sl: Dictionary = slots[i]
			var st: float = float(sl["start"])
			var tt: float = t - st
			if tt < -0.0 or tt > float(sl["dur"]) + 0.25:
				continue
			var u: float = tt / float(sl["dur"])
			var alpha: float = clampf(1.0 - maxf(0.0, u - 1.0) * 4.0, 0.0, 1.0) * clampf(tt / 0.05, 0.0, 1.0)
			var cs: float = s.y * 0.78 / 470.0                     # cards fill most of the screen height
			var scl: float = ((0.88 + 0.22 * u) * (1.0 + 0.1 * prog) + maxf(0.0, u - 1.0) * 3.2) * cs   # the old card flies past the camera
			var cen: Vector2 = s * Vector2(0.5, 0.47) + shake + par * -24.0 + Vector2(float(sl["drift"]) * u, 0.0)
			_draw_card(int(sl["kind"]), tt, cen, float(sl["rot"]) * (1.0 - u * 0.4), scl, alpha)
			if tt < 0.06:                                      # flash on every cut
				draw_rect(Rect2(Vector2.ZERO, s), Color(1, 1, 1, 0.16 * (1.0 - tt / 0.06)))
		_ctext("T H E   F U T U R E   O F   L E A R N I N G   A I", s.x * 0.5, s.y - 88 * sc, int(15 * sc), Color(0.7, 0.85, 1.0, 0.45 * minf(prog * 3.0, 1.0)))
		# the picture sinks into darkness for a breath before the slam (contrast = impact)
		draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, clampf((t - (T_SLAM - 0.7)) / 0.45, 0.0, 1.0) * 0.93))
		# the energy gathers: streaks rush in from every side towards the centre just before the slam
		var imp: float = clampf((t - (T_SLAM - 1.5)) / 1.5, 0.0, 1.0)
		if imp > 0.0:
			var tgt: Vector2 = s * Vector2(0.5, 0.27)
			for i in 90:
				var dir: Vector2 = Vector2.from_angle(_rn(float(i) + 1.0) * TAU)
				var dist: float = s.length() * 0.55 * pow(1.0 - imp, 2.0) + 20.0
				var tail: float = 30.0 + 120.0 * imp
				var pc: Color = PALETTE[i % PALETTE.size()]
				draw_line(tgt + dir * dist, tgt + dir * (dist + tail), Color(pc.r, pc.g, pc.b, 0.85 * imp), 2.0)
			_soft_glow(tgt, 30.0 * sc + 120.0 * sc * imp, Color(1, 1, 1, 0.3 * imp))

	# ── 3. slam + title ──
	if t >= T_SLAM:
		var st2: float = t - T_SLAM
		var shake2: Vector2 = Vector2(sin(t * 120.0), cos(t * 95.0)) * 14.0 * sc * clampf(1.0 - st2 / 0.5, 0.0, 1.0)
		var gl: float = _ease_out(st2 / 1.2)
		_soft_glow(s * 0.5, s.y * 0.85, Color(0.05, 0.12, 0.34, 0.28 * gl))
		var lc: Vector2 = s * Vector2(0.5, 0.27) + shake2 + par * -16.0
		lc.y += sin(t * 1.4) * 5.0 * sc
		var slam: float = _ease_out(st2 / 0.3)
		var lsize: float = 150.0 * sc * (3.2 - 2.2 * slam)
		var near: float = 1.0 if mouse.distance_to(lc) < 110.0 * sc else 0.0
		var pulse: float = 0.5 + 0.5 * sin(t * 2.2)
		_soft_glow(lc, lsize * (1.0 + 0.1 * pulse + 0.1 * near), Color(0.25, 0.6, 1.0, (0.16 + 0.08 * pulse + 0.1 * near) * slam))
		for k in 14:
			var ang: float = t * 0.7 + float(k) * TAU / 14.0
			var cc: Color = PALETTE[k % PALETTE.size()]
			draw_circle(lc + Vector2(cos(ang), sin(ang)) * lsize * 0.72, 3.0 * sc, Color(cc.r, cc.g, cc.b, 0.8 * slam))
		if logo != null:
			draw_texture_rect(logo, Rect2(lc - Vector2(lsize, lsize) * 0.5, Vector2(lsize, lsize)), false, Color(1, 1, 1, slam))
		# title
		var fs: int = int(70 * sc)
		var spacing: float = 10.0 * sc
		var total: float = 0.0
		for ch in TITLE:
			total += _text_w(String(ch), fs) + spacing
		var x: float = (s.x - total) * 0.5
		var base_y: float = s.y * 0.665
		var sweep: float = (t - (T_SLAM + 2.2)) * 1000.0 * sc + (s.x - total) * 0.5 - 200.0
		if use_3d:
			var va: float = clampf((st2 - 0.12) / 0.5, 0.0, 1.0)
			draw_texture_rect(vp.get_texture(), Rect2(Vector2.ZERO, s), false, Color(1, 1, 1, va))
		for i in TITLE.length():
			var chs: String = TITLE.substr(i, 1)
			var w: float = _text_w(chs, fs)
			var a2: float = clampf((t - T_TITLE - float(i) * 0.11) / 0.4, 0.0, 1.0)
			if use_3d:
				a2 = 0.0
			if a2 > 0.0 and chs != " ":
				var tc: Color = Color("#6fd3ff").lerp(Color("#c08bff"), float(i) / float(TITLE.length() - 1))
				tc = tc.lerp(Color.WHITE, clampf(1.0 - absf(x + w * 0.5 - sweep) / (150.0 * sc), 0.0, 1.0) * 0.85)
				var rise: float = (1.0 - _ease_out(a2)) * 40.0 * sc
				var lp: Vector2 = Vector2(x, base_y + rise) + shake2
				var ca_off: float = 5.0 * sc * clampf(1.0 - (t - T_TITLE - float(i) * 0.11) / 0.5, 0.0, 1.0)   # colour split while a letter lands
				draw_string(font, lp + Vector2(3, 3), chs, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.4 * a2))
				if ca_off > 0.2:
					draw_string(font, lp + Vector2(-ca_off, 0), chs, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.2, 0.3, 0.45 * a2))
					draw_string(font, lp + Vector2(ca_off, 0), chs, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.2, 0.8, 1.0, 0.45 * a2))
				for gl_off in [Vector2(-3, 0), Vector2(3, 0), Vector2(0, -3), Vector2(0, 3)]:   # cheap bloom
					draw_string(font, lp + (gl_off as Vector2) * sc, chs, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(tc.r, tc.g, tc.b, 0.12 * a2))
				draw_string(font, lp, chs, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(tc.r, tc.g, tc.b, a2))
				# faint mirror reflection under the title
				draw_set_transform(Vector2(lp.x, base_y + rise + 34 * sc) + shake2, 0.0, Vector2(1.0, -0.45))
				draw_string(font, Vector2.ZERO, chs, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(tc.r, tc.g, tc.b, 0.1 * a2))
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			x += w + spacing
		var line_y: float = (s.y * 0.5 + 100.0 * sc) if use_3d else base_y + 16 * sc
		var tag_y: float = (s.y * 0.5 + 152.0 * sc) if use_3d else base_y + 62 * sc
		var pipe_y: float = (s.y * 0.5 + 208.0 * sc) if use_3d else base_y + 120 * sc
		var ua: float = clampf((t - (T_SLAM + 1.6)) / 0.8, 0.0, 1.0)
		if ua > 0.0:
			var half: float = total * 0.5 * _ease_out(ua)
			draw_line(Vector2(s.x * 0.5 - half, line_y), Vector2(s.x * 0.5 + half, line_y), Color(0.45, 0.75, 1.0, 0.7), 2.0)
		var ta: float = clampf((t - (T_SLAM + 2.0)) / 0.8, 0.0, 1.0)
		if ta > 0.0:
			_ctext(TAGLINE, s.x * 0.5, tag_y, int(25 * sc), Color(0.82, 0.92, 1.0, ta * 0.92))
		var pa: float = clampf((t - (T_SLAM + 3.0)) / 0.7, 0.0, 1.0)
		if pa > 0.0:
			var pfs: int = int(19 * sc)
			var gap: float = 44.0 * sc
			var widths: Array = []
			var ptotal: float = -gap
			for wd in PIPELINE:
				var ww: float = _text_w(String(wd), pfs)
				widths.append(ww)
				ptotal += ww + gap
			var cx: float = (s.x - ptotal) * 0.5
			var py: float = pipe_y
			var lit: int = int((t - (T_SLAM + 3.0)) * 1.5) % (PIPELINE.size() + 1)
			for i in PIPELINE.size():
				var pc: Color = PALETTE[i % PALETTE.size()]
				if i == lit:
					draw_circle(Vector2(cx + float(widths[i]) * 0.5, py - 7 * sc), 30.0 * sc, Color(pc.r, pc.g, pc.b, 0.2))
				draw_string(font, Vector2(cx, py), String(PIPELINE[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, pfs, Color(pc.r, pc.g, pc.b, pa * (1.0 if i == lit else 0.85)))
				cx += float(widths[i])
				if i < PIPELINE.size() - 1:
					draw_string(font, Vector2(cx + gap * 0.3, py), "→", HORIZONTAL_ALIGNMENT_LEFT, -1, pfs, Color(0.7, 0.8, 1.0, pa * 0.5))
					cx += gap
		if t >= T_READY:
			_ctext("Click anywhere to begin", s.x * 0.5, s.y - s.y * 0.085 - 34 * sc, int(24 * sc), Color(1.0, 0.9, 0.5, 0.8 + 0.2 * sin((t - T_READY) * 3.0)))
		# god rays burst out of the logo
		var ray_a: float = clampf(1.0 - st2 / 1.5, 0.0, 1.0)
		if ray_a > 0.0:
			var rl: float = s.length()
			for i in 26:
				var dir2: Vector2 = Vector2.from_angle(float(i) * TAU / 26.0 + t * 0.12 + _rn(float(i)) * 0.2)
				var perp: Vector2 = dir2.orthogonal()
				var wd: float = (8.0 + 22.0 * _rn(float(i) + 4.0)) * sc * (0.4 + 0.6 * ray_a)
				var rc: Color = PALETTE[i % PALETTE.size()].lerp(Color.WHITE, 0.6)
				draw_colored_polygon(PackedVector2Array([lc, lc + dir2 * rl + perp * wd * 6.0, lc + dir2 * rl - perp * wd * 6.0]), Color(rc.r, rc.g, rc.b, 0.16 * ray_a))
		# anamorphic lens-flare streak at the slam
		var fl: float = clampf(1.0 - st2 / 1.6, 0.0, 1.0)
		if fl > 0.0:
			var fy: float = lc.y
			draw_rect(Rect2(0, fy - 2.0, s.x, 4.0), Color(0.7, 0.9, 1.0, 0.8 * fl))
			draw_rect(Rect2(s.x * 0.5 - s.x * 0.5 * fl, fy - 14.0, s.x * fl, 28.0), Color(0.3, 0.6, 1.0, 0.18 * fl))
			draw_circle(Vector2(lc.x, fy), 90.0 * sc * fl, Color(1, 1, 1, 0.22 * fl))
		# flash at the slam
		draw_rect(Rect2(Vector2.ZERO, s), Color(1, 1, 1, pow(clampf(1.0 - st2 / 0.55, 0.0, 1.0), 1.6)))
	# cinematic finish: vignette and letterbox bars that slide in
	if vignette != null:
		draw_texture_rect(vignette, Rect2(Vector2.ZERO, s), false, Color(1, 1, 1, 0.9))
	var bar_h: float = s.y * 0.085 * _ease_out(t / 1.0)
	draw_rect(Rect2(0, 0, s.x, bar_h), Color(0, 0, 0))
	draw_rect(Rect2(0, s.y - bar_h, s.x, bar_h), Color(0, 0, 0))
	# sparks and shockwaves
	for sp in sparks:
		var f: float = 1.0 - float(sp["t"]) / float(sp["life"])
		var cc2: Color = sp["c"]
		draw_line(sp["p"], (sp["p"] as Vector2) - (sp["v"] as Vector2) * 0.05, Color(cc2.r, cc2.g, cc2.b, f * 0.7), 2.0 * sc)
		draw_circle(sp["p"], 3.0 * sc * f + 1.0, Color(cc2.r, cc2.g, cc2.b, f))
	for r in ripples:
		var rr: float = float(r["t"])
		if rr <= 0.0:
			continue
		var big: bool = r.has("big")
		draw_arc(r["p"], rr * (900.0 if big else 520.0), 0.0, TAU, 72, Color(0.65, 0.92, 1.0, clampf(1.0 - rr / 1.8, 0.0, 1.0) * (0.9 if big else 0.7)), 4.0 if big else 3.0)
	if t > T_MONTAGE and t < T_CAN_BEGIN:
		draw_arc(mouse, 12.0, 0.0, TAU, 24, Color(0.6, 0.9, 1.0, 0.4), 2.0)
	if t > 0.8:
		draw_string(font, Vector2(s.x - 250 * sc, s.y - 22 * sc), "Esc / Enter  -  skip intro", HORIZONTAL_ALIGNMENT_LEFT, -1, int(13 * sc), Color(0.7, 0.8, 0.95, 0.4))


## One flip-book card: a little animated illustration of a course concept.
func _draw_card(kind: int, tt: float, cen: Vector2, rot: float, scl: float, alpha: float) -> void:
	var col: Color = PALETTE[kind % PALETTE.size()]
	var skew: float = -0.22 * clampf(1.0 - tt * 4.5, 0.0, 1.0)    # each card snaps flat as it lands
	draw_set_transform_matrix(Transform2D(rot, Vector2(scl, scl), skew, cen))
	var w: float = 380.0
	var h: float = 470.0
	var rect: Rect2 = Rect2(-w * 0.5, -h * 0.5, w, h)
	draw_rect(Rect2(rect.position + Vector2(10, 12), rect.size), Color(0, 0, 0, 0.45 * alpha))
	draw_rect(rect, Color(0.04, 0.07, 0.13, alpha))
	draw_rect(rect, Color(col.r, col.g, col.b, alpha), false, 3.0)
	draw_rect(Rect2(rect.position, Vector2(w, 64)), Color(col.r, col.g, col.b, 0.22 * alpha))
	_ctext(String(CARD_TITLES[kind]), 0.0, -h * 0.5 + 42.0, 26, Color(1, 1, 1, alpha))
	var ca: Color = Color(1, 1, 1, alpha)
	if kind < art.size() and art[kind] != null:                    # cinematic artwork with a slow push-in
		var tex: Texture2D = art[kind]
		var zoom: float = 1.0 + 0.16 * clampf(tt, 0.0, 1.2)
		var sw: float = float(tex.get_width()) / zoom
		var sh2: float = sw / ((w - 8.0) / (h - 72.0))
		var src: Rect2 = Rect2((float(tex.get_width()) - sw) * 0.5, (float(tex.get_height()) - sh2) * 0.5, sw, sh2)
		draw_texture_rect_region(tex, Rect2(-w * 0.5 + 4.0, -h * 0.5 + 66.0, w - 8.0, h - 70.0), src, Color(1, 1, 1, alpha))
		draw_rect(Rect2(-w * 0.5 + 4.0, h * 0.5 - 90.0, w - 8.0, 86.0), Color(0, 0, 0, 0.0))   # (reserved for captions)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	if kind == 0:                                                   # tokens
		var ws: Array = ["The", "cat", "sat", "on", "the", "mat"]
		for i in ws.size():
			var y: float = -120.0 + float(i) * 50.0
			var cc: Color = PALETTE[i % PALETTE.size()]
			draw_rect(Rect2(-130, y, 150, 38), Color(cc.r, cc.g, cc.b, 0.85 * alpha))
			draw_string(font, Vector2(-118, y + 27), String(ws[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, ca)
			draw_string(font, Vector2(50, y + 27), "→  %d" % (300 + int(_rn(float(i) + 3.0) * 4000.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.7, 0.85, 1.0, alpha))
	elif kind == 1:                                                 # embeddings: clusters of meaning
		for cl in 3:
			var cpos: Vector2 = [Vector2(-80, -50), Vector2(80, -10), Vector2(-10, 90)][cl]
			for m in 16:
				var p: Vector2 = cpos + Vector2(_rn(float(cl * 30 + m)) - 0.5, _rn(float(cl * 30 + m + 99)) - 0.5) * 100.0 + Vector2(sin(tt * 3.0 + float(m)), cos(tt * 3.0 + float(m))) * 3.0
				var cc2: Color = PALETTE[cl]
				draw_circle(p, 7.0, Color(cc2.r, cc2.g, cc2.b, 0.9 * alpha))
	elif kind == 2:                                                 # attention heat map
		for i in 7:
			for j in 7:
				var v: float = clampf(exp(-absf(float(i - j)) * 0.7) * 0.8 + _rn(float(i * 7 + j)) * 0.35, 0.0, 1.0)
				var cc3: Color = Color(0.07, 0.1, 0.18).lerp(Color(1.0, 0.55, 0.15), v)
				draw_rect(Rect2(-119 + float(j) * 34.0, -105 + float(i) * 34.0, 31, 31), Color(cc3.r, cc3.g, cc3.b, alpha))
	elif kind == 3:                                                 # transformer block
		var labels: Array = ["Self-Attention", "Add & Norm", "Feed-Forward", "Add & Norm"]
		var lit: int = int(tt * 7.0) % labels.size()
		for i in labels.size():
			var y2: float = -120.0 + float(i) * 66.0
			var cc4: Color = PALETTE[(i + 3) % PALETTE.size()]
			draw_rect(Rect2(-120, y2, 240, 48), Color(cc4.r, cc4.g, cc4.b, (0.95 if i == lit else 0.45) * alpha))
			_ctext(String(labels[i]), 0.0, y2 + 32.0, 20, ca)
			if i < labels.size() - 1:
				draw_line(Vector2(0, y2 + 48), Vector2(0, y2 + 66), Color(0.7, 0.85, 1.0, alpha), 2.0)
	elif kind == 4:                                                 # knowledge graph
		var pts: Array = []
		for i in 9:
			var ang: float = tt * 0.6 + float(i) * TAU / 9.0
			pts.append(Vector2(cos(ang), sin(ang)) * 115.0)
		for i in 9:
			draw_line(Vector2.ZERO, pts[i], Color(0.7, 0.85, 1.0, 0.5 * alpha), 2.0)
			draw_line(pts[i], pts[(i + 1) % 9], Color(0.5, 0.7, 1.0, 0.35 * alpha), 1.5)
		for i in 9:
			var cc5: Color = PALETTE[i % PALETTE.size()]
			draw_circle(pts[i], 13.0, Color(cc5.r, cc5.g, cc5.b, alpha))
		draw_circle(Vector2.ZERO, 22.0, Color(1.0, 0.85, 0.3, alpha))
	elif kind == 5:                                                 # RAG: documents -> search -> answer
		for i in 3:
			draw_rect(Rect2(-150, -100 + float(i) * 70.0, 70, 56), Color(0.5, 0.7, 1.0, 0.55 * alpha))
			for ln in 3:
				draw_line(Vector2(-142, -86 + float(i) * 70.0 + float(ln) * 12.0), Vector2(-92, -86 + float(i) * 70.0 + float(ln) * 12.0), Color(1, 1, 1, 0.5 * alpha), 2.0)
		draw_arc(Vector2(0, 0), 38.0, 0.0, TAU, 32, Color(1.0, 0.85, 0.3, alpha), 5.0)
		draw_line(Vector2(27, 27), Vector2(60, 60), Color(1.0, 0.85, 0.3, alpha), 6.0)
		draw_rect(Rect2(95, -30, 80, 60), Color(0.2, 0.85, 0.6, 0.9 * alpha))
		_ctext("A", 135.0, 12.0, 34, ca)
		draw_line(Vector2(-75, -70 + 70.0 * fposmod(tt * 2.0, 1.0)), Vector2(-40, 0), Color(1, 1, 1, 0.5 * alpha), 2.0)
	else:                                                           # probabilities (softmax)
		for i in 5:
			var hh: float = 40.0 + 150.0 * (0.5 + 0.5 * sin(tt * 6.0 + float(i) * 1.3)) * (1.0 - float(i) * 0.16)
			var cc6: Color = PALETTE[i % PALETTE.size()]
			draw_rect(Rect2(-125 + float(i) * 52.0, 120.0 - hh, 40, hh), Color(cc6.r, cc6.g, cc6.b, 0.9 * alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
