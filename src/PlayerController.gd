# PlayerController.gd# Godot 4.4 / GDScript
# ▶ 기존 “파란 우주선”의 동작(중력/점프, 스웨이, 피치, 충돌 API)은 그대로 유지
# ▶ 점프 때 나오는 기존 엔진 효과는 제거
# ▶ 우주선 뒤(왼쪽)에서 보라색 파티클이 "항상 약하게" 나오다가, 점프 시 "강한 버스트"가 왕창 나옴
# ▶ 씬 없이 코드로 에셋(Texture2D) 적용 가능

extends Control

# --- 물리 ---
@export var gravity: float = 900.0
@export var jump_force: float = -500.0

# --- 스킨(에셋) ---
@export var ship_image_path: String = "res://assets/ship_blue.png"
@export var ship_scale: float = 0.15
# 폴백(폴리곤)용 색
@export var body_color: Color = Color(0.3, 0.8, 1.0)
@export var wing_color: Color = Color(0.25, 0.9, 1.0)
@export var tail_color: Color = Color(0.2, 0.6, 0.9)
@export var cockpit_color: Color = Color(0.1, 0.3, 0.6, 0.85)

# --- 연출(유지) ---
@export var pitch_up_rad: float = -0.28
@export var pitch_down_rad: float = 0.35
@export var sway_amplitude: float = 10.0
@export var sway_speed: float = 2.2

# --- 보라색 트레일/버스트 컬러 ---
@export var trail_head: Color = Color(0.82, 0.62, 1.0, 0.9)
@export var trail_tail: Color = Color(0.45, 0.20, 0.65, 0.0)
@export var burst_head: Color = Color(0.95, 0.75, 1.0, 0.95)
@export var burst_tail: Color = Color(0.55, 0.25, 0.75, 0.0)

# --- 내부 상태 ---
var _ground_y: float = 0.0
var _vel_y: float = 0.0
var _is_jumping: bool = false
var _ship_size: Vector2 = Vector2(44, 44)

# 스웨이용
var _base_x: float = 0.0
var _time: float = 0.0

# --- 비주얼 노드 ---
var _sprite: Sprite2D
# 폴백 폴리곤
var _fuselage: Polygon2D
var _wing_l: Polygon2D
var _wing_r: Polygon2D
var _tail: Polygon2D
var _canopy: Polygon2D
# 파티클(보라색 트레일 + 버스트)
var _trail: GPUParticles2D
var _burst: GPUParticles2D

func _ready() -> void:
	pivot_offset = _ship_size * 0.5
	set_process(true)

# GameLayer에서 호출 — 기존 시그니처 유지
func setup(ground_y: float, size: Vector2, color: Color, start_x: float) -> void:
	_clear_visuals()

	_ground_y = ground_y
	_vel_y = 0.0
	_is_jumping = false

	var tex: Texture2D = null
	if ship_image_path.strip_edges() != "":
		var loaded = load(ship_image_path)
		if loaded is Texture2D:
			tex = loaded

	if tex != null:
		_build_sprite(tex)
	else:
		_build_polygon_ship(size, color)

	_build_thrusters_purple()  # ← 보라색 트레일/버스트 생성

	# 시작 위치 및 스웨이 기준
	_base_x = start_x
	position = Vector2(_base_x, _ground_y - _ship_size.y)
	pivot_offset = _ship_size * 0.5
	_time = 0.0

func update_player(delta: float) -> void:
	# 중력/위치
	_vel_y += gravity * delta
	position.y += _vel_y * delta

	# 좌우 스웨이
	_time += delta
	var sway: float = sin(_time * sway_speed) * sway_amplitude
	position.x = _base_x + sway

	# 속도 기반 피치
	var t: float = clamp(_vel_y / 650.0, -1.0, 1.0)
	var pitch: float = lerp(pitch_up_rad, pitch_down_rad, (t + 1.0) * 0.5)
	rotation = pitch

	# 바닥 충돌
	var floor_y: float = _ground_y - _ship_size.y
	if position.y >= floor_y:
		position.y = floor_y
		_vel_y = 0.0
		_is_jumping = false
		# 점프 때만 버스트, 평소엔 트레일은 계속 나오므로 여기서 끌 필요 없음

func jump() -> void:
	if not _is_jumping:
		_vel_y = jump_force
		_is_jumping = true
		# ▶ 점프 시: 보라색 '버스트'만 왕창 분사
		if _burst:
			_burst.restart()  # one_shot + restart 로 순간 분사

# ---------- GameLayer 충돌 API ----------
func is_on_floor() -> bool:
	return position.y >= (_ground_y - _ship_size.y) and _vel_y == 0.0

func get_player_rect() -> Rect2:
	return Rect2(position, _ship_size)

func get_player_center() -> Vector2:
	return position + _ship_size * 0.5

func set_gravity(v: float) -> void:
	gravity = v

func set_jump_force(v: float) -> void:
	jump_force = v

# ---------------- 내부 구현 ----------------
func _clear_visuals() -> void:
	for c in get_children():
		if c is Sprite2D or c is Polygon2D or c is GPUParticles2D:
			c.queue_free()
	_sprite = null
	_fuselage = null
	_wing_l = null
	_wing_r = null
	_tail = null
	_canopy = null
	_trail = null
	_burst = null

func _build_sprite(tex: Texture2D) -> void:
	_sprite = Sprite2D.new()
	_sprite.texture = tex
	_sprite.centered = false
	_sprite.position = Vector2(0, -10)
	_sprite.scale = Vector2(ship_scale, ship_scale)
	_sprite.rotate(0.15)
	add_child(_sprite)
	_ship_size = tex.get_size() * ship_scale

func _build_polygon_ship(size: Vector2, color: Color) -> void:
	_ship_size = size
	body_color = color

	var w: float = _ship_size.x
	var h: float = _ship_size.y
	var cx: float = w * 0.5

	_fuselage = Polygon2D.new()
	_fuselage.color = body_color
	_fuselage.polygon = PackedVector2Array([
		Vector2(cx, 0),
		Vector2(cx - w * 0.12, h * 0.22),
		Vector2(cx - w * 0.16, h * 0.55),
		Vector2(cx - w * 0.10, h),
		Vector2(cx + w * 0.10, h),
		Vector2(cx + w * 0.16, h * 0.55),
		Vector2(cx + w * 0.12, h * 0.22),
	])
	add_child(_fuselage)

	_wing_l = Polygon2D.new()
	_wing_l.color = wing_color
	_wing_l.polygon = PackedVector2Array([
		Vector2(cx - w * 0.10, h * 0.45),
		Vector2(cx - w * 0.50, h * 0.55),
		Vector2(cx - w * 0.22, h * 0.60),
		Vector2(cx - w * 0.12, h * 0.53),
	])
	add_child(_wing_l)

	_wing_r = Polygon2D.new()
	_wing_r.color = wing_color
	_wing_r.polygon = PackedVector2Array([
		Vector2(cx + w * 0.10, h * 0.45),
		Vector2(cx + w * 0.50, h * 0.55),
		Vector2(cx + w * 0.22, h * 0.60),
		Vector2(cx + w * 0.12, h * 0.53),
	])
	add_child(_wing_r)

	_tail = Polygon2D.new()
	_tail.color = tail_color
	_tail.polygon = PackedVector2Array([
		Vector2(cx - w * 0.06, h * 0.70),
		Vector2(cx,             h * 0.58),
		Vector2(cx + w * 0.06, h * 0.70),
		Vector2(cx + w * 0.03, h * 0.95),
		Vector2(cx - w * 0.03, h * 0.95),
	])
	add_child(_tail)

	_canopy = Polygon2D.new()
	_canopy.color = cockpit_color
	_canopy.polygon = PackedVector2Array([
		Vector2(cx,            h * 0.08),
		Vector2(cx - w * 0.08, h * 0.32),
		Vector2(cx,            h * 0.36),
		Vector2(cx + w * 0.08, h * 0.32),
	])
	add_child(_canopy)

func _make_ramp(c1: Color, c2: Color) -> GradientTexture1D:
	var grad = Gradient.new()
	grad.add_point(0.0, c1)
	grad.add_point(1.0, c2)
	var ramp = GradientTexture1D.new()
	ramp.gradient = grad
	return ramp

func _build_thrusters_purple() -> void:
	# 2x2 도트 텍스처
	var img = Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 1))
	var dot_tex = ImageTexture.create_from_image(img)

	# ── 보라색 "항상 약하게" 나오는 트레일 ──
	_trail = GPUParticles2D.new()
	_trail.amount = 14
	_trail.emitting = true
	_trail.lifetime = 0.7
	_trail.preprocess = 0.1
	_trail.local_coords = true
	_trail.position = Vector2(0.0, _ship_size.y * 0.5)

	var pm_trail = ParticleProcessMaterial.new()
	pm_trail.direction = Vector3(-1, 0, 0)
	pm_trail.gravity = Vector3(0, 0, 0)
	pm_trail.initial_velocity_min = 70
	pm_trail.initial_velocity_max = 120
	pm_trail.scale_min = 0.5
	pm_trail.scale_max = 1.0
	pm_trail.color_ramp = _make_ramp(trail_head, trail_tail)
	_trail.process_material = pm_trail
	_trail.texture = dot_tex
	add_child(_trail)

	# ── 보라색 "점프 때 왕창" 버스트 ──
	_burst = GPUParticles2D.new()
	_burst.amount = 140
	_burst.emitting = false
	_burst.one_shot = true
	_burst.explosiveness = 1.0
	_burst.lifetime = 0.4
	_burst.local_coords = true
	_burst.position = Vector2(0.0, _ship_size.y * 0.5)

	var pm_burst = ParticleProcessMaterial.new()
	pm_burst.direction = Vector3(-1, 0, 0)
	pm_burst.gravity = Vector3(0, 0, 0)
	pm_burst.initial_velocity_min = 320
	pm_burst.initial_velocity_max = 520
	pm_burst.scale_min = 0.6
	pm_burst.scale_max = 1.3
	pm_burst.color_ramp = _make_ramp(burst_head, burst_tail)
	_burst.process_material = pm_burst
	_burst.texture = dot_tex
	add_child(_burst)
