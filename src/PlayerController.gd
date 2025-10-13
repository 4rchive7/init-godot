# PlayerController.gd
# Godot 4.4 / GDScript
# 우주선(전투기) 플레이어 컨트롤러
# - Godot4 기본 노드로 파츠를 조합해 전투기 실루엣 구성 (Polygon2D 여러 개)
# - 점프 시 엔진 불꽃 GPUParticles2D (이전 파티클 로직 그대로)
# - 중력/점프/바닥 충돌, 기수(피치) 기울기 연출

extends Control

@export var gravity: float = 900.0
@export var jump_force: float = -500.0

@export var ship_size: Vector2 = Vector2(48, 48)             # 전체 외곽 박스
@export var body_color: Color = Color(0.3, 0.8, 1.0)          # 동체 기본색
@export var wing_color: Color = Color(0.25, 0.9, 1.0)         # 날개 강조색
@export var tail_color: Color = Color(0.2, 0.6, 0.9)          # 꼬리/보조익
@export var cockpit_color: Color = Color(0.1, 0.3, 0.6, 0.85) # 캐노피(반투명)

# 엔진 불꽃 색
@export var flame_head: Color = Color(1, 0.7, 0.3, 0.95)
@export var flame_tail: Color = Color(0.2, 0.2, 0.2, 0.0)

# 기체 피치(기울기) 한계
@export var pitch_up_rad: float = -0.28    # 상승 시 위로 들림(음수)
@export var pitch_down_rad: float = 0.35   # 하강 시 아래로 숙임(양수)

var _ground_y: float = 0.0
var _vel_y: float = 0.0
var _is_jumping: bool = false

# 비주얼 파츠
var _fuselage: Polygon2D
var _wing_left: Polygon2D
var _wing_right: Polygon2D
var _tail: Polygon2D
var _canopy: Polygon2D

# 엔진 불꽃
var _flame: GPUParticles2D

func _ready() -> void:
	# 이 노드의 회전 중심을 기체 중앙으로(위치는 '좌상단' 기준이지만 회전은 중앙 기준)
	pivot_offset = ship_size * 0.5

func setup(ground_y: float, size: Vector2, color: Color, start_x: float) -> void:
	# 외부 API는 이전 파일과 호환: size/color는 본체 색으로 사용
	_ground_y = ground_y
	vel_reset()
	ship_size = size
	body_color = color
	pivot_offset = ship_size * 0.5

	_build_ship_polygons()
	_build_engine_flame()

	# 시작 위치(좌상단 기준), 지면 위에 놓기
	position = Vector2(start_x, _ground_y - ship_size.y)

func update_player(delta: float) -> void:
	_vel_y += gravity * delta
	position.y += _vel_y * delta

	# 간단 피치(속도 기반 기울기)
	var t: float = clamp(_vel_y / 650.0, -1.0, 1.0)  # -1..1
	var pitch: float = lerp(pitch_up_rad, pitch_down_rad, (t + 1.0) * 0.5)
	rotation = pitch

	var floor_y: float = _ground_y - ship_size.y
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

func is_on_floor() -> bool:
	return position.y >= (_ground_y - ship_size.y) and _vel_y == 0.0

func get_player_rect() -> Rect2:
	# 좌상단 기준의 외곽 박스 반환 (기존 GameLayer와 호환)
	return Rect2(Vector2(position.x - ship_size.x * 0.5 + ship_size.x * 0.5, position.y), ship_size)
	# ↑ 위 라인은 사실상 Rect2(Vector2(position.x, position.y), ship_size)와 동일.
	# (과거 호환을 위해 수식만 유지)

func get_player_center() -> Vector2:
	return position + ship_size * 0.5

func set_gravity(v: float) -> void:
	gravity = v

func set_jump_force(v: float) -> void:
	jump_force = v

# ---------------- 내부 구현 ----------------
func vel_reset() -> void:
	_vel_y = 0.0
	_is_jumping = false

func _clear_old_parts() -> void:
	var children = get_children()
	for c in children:
		if c is Polygon2D or c is GPUParticles2D:
			c.queue_free()

func _build_ship_polygons() -> void:
	_clear_old_parts()

	# 좌표계: 이 노드의 좌상단(0,0) ~ (w,h)
	var w: float = ship_size.x
	var h: float = ship_size.y
	var cx: float = w * 0.5

	# --- 동체(Fuselage): 뾰족한 기수 + 하부
	_fuselage = Polygon2D.new()
	_fuselage.color = body_color
	_fuselage.polygon = PackedVector2Array([
		Vector2(cx, 0),                # 기수
		Vector2(cx - w * 0.12, h * 0.22),
		Vector2(cx - w * 0.16, h * 0.55),
		Vector2(cx - w * 0.10, h),     # 좌측 하부
		Vector2(cx + w * 0.10, h),     # 우측 하부
		Vector2(cx + w * 0.16, h * 0.55),
		Vector2(cx + w * 0.12, h * 0.22),
	])
	add_child(_fuselage)

	# --- 좌/우 주익(Wings)
	_wing_left = Polygon2D.new()
	_wing_left.color = wing_color
	_wing_left.polygon = PackedVector2Array([
		Vector2(cx - w * 0.10, h * 0.45),
		Vector2(cx - w * 0.50, h * 0.55),
		Vector2(cx - w * 0.22, h * 0.60),
		Vector2(cx - w * 0.12, h * 0.53),
	])
	add_child(_wing_left)

	_wing_right = Polygon2D.new()
	_wing_right.color = wing_color
	_wing_right.polygon = PackedVector2Array([
		Vector2(cx + w * 0.10, h * 0.45),
		Vector2(cx + w * 0.50, h * 0.55),
		Vector2(cx + w * 0.22, h * 0.60),
		Vector2(cx + w * 0.12, h * 0.53),
	])
	add_child(_wing_right)

	# --- 꼬리/수직미익(Tail/Fin)
	_tail = Polygon2D.new()
	_tail.color = tail_color
	_tail.polygon = PackedVector2Array([
		Vector2(cx - w * 0.06, h * 0.70),
		Vector2(cx,               h * 0.58),
		Vector2(cx + w * 0.06, h * 0.70),
		Vector2(cx + w * 0.03, h * 0.95),
		Vector2(cx - w * 0.03, h * 0.95),
	])
	add_child(_tail)

	# --- 캐노피/조종석(Canopy)
	_canopy = Polygon2D.new()
	_canopy.color = cockpit_color
	_canopy.polygon = PackedVector2Array([
		Vector2(cx,               h * 0.08),
		Vector2(cx - w * 0.08, h * 0.32),
		Vector2(cx,               h * 0.36),
		Vector2(cx + w * 0.08, h * 0.32),
	])
	add_child(_canopy)

func _build_engine_flame() -> void:
	# 간단한 흰 점 텍스처
	var img = Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 1))
	var tex = ImageTexture.create_from_image(img)

	_flame = GPUParticles2D.new()
	_flame.amount = 60
	_flame.emitting = false
	_flame.lifetime = 0.25
	_flame.preprocess = 0.05
	_flame.local_coords = true
	# 엔진 위치: 하단 중앙
	_flame.position = Vector2(ship_size.x * 0.5, ship_size.y)

	var pm = ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.gravity = Vector3(0, 100, 0)
	pm.initial_velocity_min = 200
	pm.initial_velocity_max = 260
	pm.scale_min = 0.6
	pm.scale_max = 1.2

	# Gradient → GradientTexture1D 로 램프 생성 (이전 버그 해결)
	var grad = Gradient.new()
	grad.add_point(0.0, flame_head)
	grad.add_point(1.0, flame_tail)
	var ramp = GradientTexture1D.new()
	ramp.gradient = grad
	pm.color_ramp = ramp

	_flame.process_material = pm
	_flame.texture = tex
	add_child(_flame)
