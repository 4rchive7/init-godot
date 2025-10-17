# PlayerController.gd
# Godot 4.4 / GDScript
# ▶ 기존 “파란 우주선”의 모든 동작(중력/점프, 스웨이, 피치, 엔진 불꽃, 충돌 API)을 그대로 유지하면서
# ▶ "모습"만 사용자 에셋(Texture2D)으로 교체하는 버전 (씬 필요 없음 / 코드로 로드)
#
# 사용법:
# 1) ship_image_path 에 프로젝트 내 경로(res://...)를 넣으면 그 텍스처를 씁니다.
# 2) 텍스처를 못 찾으면 이전처럼 폴리곤 전투기(파란 배)로 자동 폴백합니다.
# 3) GameLayer에서는 이전과 동일한 API로 사용 가능:
#    setup(ground_y, size, color, start_x), update_player(delta), jump(),
#    is_on_floor(), get_player_rect(), get_player_center(), set_gravity(), set_jump_force()

extends Control

# --- 물리 ---
@export var gravity: float = 900.0
@export var jump_force: float = -500.0

# --- 스킨(에셋) ---
@export var ship_image_path: String = "res://assets/ship_blue.png"     # 예: "res://assets/ships/ship_blue.png"
@export var ship_scale: float = 0.15         # 요청: 1/4 크기
# 폴백(폴리곤)용 색
@export var body_color: Color = Color(0.3, 0.8, 1.0)
@export var wing_color: Color = Color(0.25, 0.9, 1.0)
@export var tail_color: Color = Color(0.2, 0.6, 0.9)
@export var cockpit_color: Color = Color(0.1, 0.3, 0.6, 0.85)

# --- 연출(그대로 유지) ---
@export var pitch_up_rad: float = -0.28      # 상승 시 기수 위로
@export var pitch_down_rad: float = 0.35     # 하강 시 기수 아래로
@export var sway_amplitude: float = 10.0     # 좌우 흔들림 픽셀
@export var sway_speed: float = 2.2          # 흔들림 속도(라디안/초)

# --- 엔진 불꽃(그대로 유지) ---
@export var flame_head: Color = Color(1, 0.7, 0.3, 0.95)
@export var flame_tail: Color = Color(0.2, 0.2, 0.2, 0.0)

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
# 엔진 불꽃
var _flame: GPUParticles2D

func _ready() -> void:
	# 회전 중심을 중앙으로
	pivot_offset = _ship_size * 0.5
	set_process(true)

# GameLayer에서 호출 — 기존 시그니처 그대로
# size: 폴백(폴리곤)일 때만 사용, 텍스처가 있으면 텍스처 크기 기반으로 자동 결정
# color: 폴백 동체 색 (스프라이트 사용 시 무시)
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

	_build_engine_flame()

	# 시작 위치 및 스웨이 기준
	_base_x = start_x
	position = Vector2(_base_x, _ground_y - _ship_size.y)
	pivot_offset = _ship_size * 0.5
	_time = 0.0

func update_player(delta: float) -> void:
	# 중력/점프
	_vel_y += gravity * delta
	position.y += _vel_y * delta

	# 좌우 스웨이(그대로 유지)
	_time += delta
	var sway: float = sin(_time * sway_speed) * sway_amplitude
	position.x = _base_x + sway

	# 속도 기반 피치(그대로 유지)
	var t: float = clamp(_vel_y / 650.0, -1.0, 1.0)
	var pitch: float = lerp(pitch_up_rad, pitch_down_rad, (t + 1.0) * 0.5)
	rotation = pitch

	# 바닥 충돌
	var floor_y: float = _ground_y - _ship_size.y
	if position.y >= floor_y:
		position.y = floor_y
		_vel_y = 0.0
		_is_jumping = false
		if _flame:
			_flame.emitting = false

func jump() -> void:
	if not _is_jumping:
		_vel_y = jump_force
		_is_jumping = true
		if _flame:
			_flame.emitting = true

# ---------- GameLayer와의 충돌 API (그대로) ----------
func is_on_floor() -> bool:
	return position.y >= (_ground_y - _ship_size.y) and _vel_y == 0.0

func get_player_rect() -> Rect2:
	# 좌상단 기준 외곽 박스 — GameLayer 충돌 로직과 호환
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
	_flame = null

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
	# 텍스처가 없을 때 — 기존 파란 전투기 실루엣(동작 동일)
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

func _build_engine_flame() -> void:
	# 작은 도트 텍스처
	var img = Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 1))
	var tex = ImageTexture.create_from_image(img)

	_flame = GPUParticles2D.new()
	_flame.amount = 60
	_flame.emitting = false
	_flame.lifetime = 0.25
	_flame.preprocess = 0.05
	_flame.local_coords = true
	# 엔진 위치: 하단 중앙 (텍스처든 폴리곤이든 _ship_size 기준)
	_flame.position = Vector2(_ship_size.x * 0.5, _ship_size.y)

	var pm = ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.gravity = Vector3(0, 100, 0)
	pm.initial_velocity_min = 200
	pm.initial_velocity_max = 260
	pm.scale_min = 0.6
	pm.scale_max = 1.2

	var grad = Gradient.new()
	grad.add_point(0.0, flame_head)
	grad.add_point(1.0, flame_tail)
	var ramp = GradientTexture1D.new()
	ramp.gradient = grad
	pm.color_ramp = ramp

	_flame.process_material = pm
	_flame.texture = tex
	add_child(_flame)
