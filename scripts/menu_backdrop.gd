class_name MenuBackdrop
extends Control
## Living background of the home screen: deep gradient, slow aurora glows, a drifting network that leans towards the mouse.

const N: int = 54
const PALETTE: Array = [Color("#3fa7ff"), Color("#35d6a0"), Color("#ff8a3d"), Color("#b583ff"), Color("#ff4f79"), Color("#ffd23f")]

var t: float = 0.0
var pos: PackedVector2Array = PackedVector2Array()
var vel: PackedVector2Array = PackedVector2Array()
var rad: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 99
	for i in N:
		pos.append(Vector2(rng.randf(), rng.randf()))
		vel.append(Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * 0.012)
		rad.append(rng.randf_range(2.0, 5.0))


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	t += delta
	var s: Vector2 = size
	if s.x < 10.0:
		return
	var mouse: Vector2 = get_local_mouse_position()
	for i in N:
		var p: Vector2 = pos[i] + vel[i] * delta
		if p.x < 0.0 or p.x > 1.0:
			vel[i].x = -vel[i].x
		if p.y < 0.0 or p.y > 1.0:
			vel[i].y = -vel[i].y
		var px: Vector2 = Vector2(p.x * s.x, p.y * s.y)
		var d: Vector2 = mouse - px
		if d.length() < 260.0 and d.length() > 1.0:
			p += Vector2(d.x / s.x, d.y / s.y) * delta * 0.5
		pos[i] = p.clamp(Vector2.ZERO, Vector2.ONE)
	queue_redraw()


func _glow(c: Vector2, r: float, col: Color) -> void:
	for i in 16:
		var f: float = 1.0 - float(i) / 16.0
		draw_circle(c, r * f, Color(col.r, col.g, col.b, col.a * 2.0 / 16.0))


func _draw() -> void:
	var s: Vector2 = size
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(s.x, 0), s, Vector2(0, s.y)]),
		PackedColorArray([Color(0.008, 0.012, 0.04), Color(0.012, 0.016, 0.05), Color(0.03, 0.04, 0.11), Color(0.02, 0.035, 0.1)]))
	# slow aurora glows
	for k in 3:
		var c: Color = PALETTE[(k * 2) % PALETTE.size()]
		var ctr: Vector2 = Vector2(s.x * (0.25 + 0.25 * k + 0.08 * sin(t * 0.2 + float(k))), s.y * (0.3 + 0.3 * sin(t * 0.15 + float(k) * 2.0) * 0.5 + 0.2))
		_glow(ctr, s.y * (0.4 + 0.04 * sin(t * 0.3 + float(k))), Color(c.r, c.g, c.b, 0.07))
	_glow(Vector2(s.x * 0.5, s.y * 0.24), s.y * 0.32, Color(0.2, 0.5, 1.0, 0.09 + 0.02 * sin(t * 1.3)))
	var mouse: Vector2 = get_local_mouse_position()
	var px: PackedVector2Array = PackedVector2Array()
	for i in N:
		px.append(Vector2(pos[i].x * s.x, pos[i].y * s.y))
	for i in N:
		for j in range(i + 1, N):
			var d: float = px[i].distance_to(px[j])
			if d < 170.0:
				draw_line(px[i], px[j], Color(0.4, 0.65, 1.0, (1.0 - d / 170.0) * 0.16), 1.2)
	for i in N:
		var c2: Color = PALETTE[i % PALETTE.size()]
		var near: float = clampf(1.0 - px[i].distance_to(mouse) / 260.0, 0.0, 1.0)
		draw_circle(px[i], rad[i] * (1.0 + near), Color(c2.r, c2.g, c2.b, 0.35 + 0.5 * near))
		if near > 0.0:
			draw_line(mouse, px[i], Color(1, 1, 1, near * 0.35), 1.4)
	draw_arc(mouse, 10.0, 0.0, TAU, 20, Color(0.6, 0.9, 1.0, 0.35), 1.6)
