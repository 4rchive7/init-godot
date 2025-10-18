# PlayerController.gd
# Godot 4.4 / GDScript
# ▶ 요구사항 반영
#   - 3개 라인 유지(위/가운데/아래)
#   - "점프는 예전처럼" 중력 기반(가속도)으로 복구 (jump_force, gravity 사용)
#   - 좌우 흔들림/회전/파티클 등 시각 효과는 유지 제거(정적 비주얼)
#   - 씬 없이 코드로 에셋(Texture2D) 적용 가능, 없으면 폴리곤 전투기 폴백
#
# GameLayer와의 기존 API 유지:
#   setup(ground_y, size, color, start_x)
#   set_lanes(lanes_y, start_lane_index)
#   change_lane(delta_idx)
#   update_player(delta)
#   jump()
#   is_on_floor(), get_player_rect(), get_player_center()
#   set_gravity(v), set_jump_force(v)

extends Control

# --- 라인 모드 ---
@export var use_lanes: bool = true
var _lanes: Array = []          # 각 라인의 상단 y(position.y)
var _lane_index: int = 1        # 0,1,2 (기본: 가운데)

# --- 점프/중력(복구된 물리) ---
@export var gravity: float = 900.0       # + 아래로 가속
@export var jump_force: float = -500.0   # 위로 초기속도(음수)

# --- 스킨(에셋) ---
@export var ship_image_path: String = "res://assets/ship_blue.png"
@export var ship_scale: float = 0.15
# 폴백(폴리곤)용 색
@export var body_color: Color = Color(0.3, 0.8, 1.0)
@export var wing_color: Color = Color(0.25, 0.9, 1.0)
@export var tail_color: Color = Color(0.2, 0.6, 0.9)
@export var cockpit_color: Color = Color(0.1, 0.3, 0.6, 0.85)

# --- 내부 상태 ---
var _ground_y: float = 0.0              # 라인 미사용 시 바닥
var _vel_y: float = 0.0
var _is_jumping: bool = false
var _ship_size: Vector2 = Vector2(44, 44)
var _base_x: float = 0.0                # X 고정(스웨이 제거)

# --- 비주얼 노드 ---
var _sprite: Sprite2D
# 폴백 폴리곤
var _fuselage: Polygon2D
var _wing_l: Polygon2D
var _wing_r: Polygon2D
var _tail: Polygon2D
var _canopy: Polygon2D

func _ready() -> void:
	pivot_offset = _ship_size * 0.5
	set_process(true)

# GameLayer에서 호출
func setup(ground_y: float, size: Vector2, color: Color, start_x: float) -> void:
	_clear_visuals()

	_ground_y = ground_y
	_vel_y = 0.0
	_is_jumping = false

	var tex: Resource = null
	if ship_image_path.strip_edges() != "":
		tex = load(ship_image_path)
	if tex != null and tex is Texture2D:
		_build_sprite(tex as Texture2D)
	else:
		_build_polygon_ship(size, color)

	_base_x = start_x
	position = Vector2(_base_x, _ground_y - _ship_size.y)
	pivot_offset = _ship_size * 0.5
	rotation = 0.0  # 회전 제거

func set_lanes(lanes_y: Array, start_lane_index: int) -> void:
	_lanes = lanes_y.duplicate()
	_lane_index = clamp(start_lane_index, 0, _lanes.size() - 1)
	if _lanes.size() > 0:
		position.y = float(_lanes[_lane_index])
		_vel_y = 0.0
		_is_jumping = false

func change_lane(delta_idx: int) -> void:
	if _lanes.size() == 0:
		return
	_lane_index = clamp(_lane_index + delta_idx, 0, _lanes.size() - 1)
	# 새 라인의 바닥 레벨 갱신. 플레이어가 바닥 아래로 내려가 있으면 끌어올림.
	var floor_y: float = _get_current_floor_y()
	if position.y > floor_y:
		position.y = floor_y
		_vel_y = 0.0
		_is_jumping = false

func update_player(delta: float) -> void:
	# X 고정, 회전 없음
	position.x = _base_x
	rotation = 0.0

	# --- 예전처럼: 중력 기반 점프 물리 ---
	_vel_y += gravity * delta
	position.y += _vel_y * delta

	# 현재 라인의 바닥에 착지
	var floor_y: float = _get_current_floor_y()
	if position.y >= floor_y:
		position.y = floor_y
		_vel_y = 0.0
		_is_jumping = false

func jump() -> void:
	if not _is_jumping:
		_vel_y = jump_force
		_is_jumping = true

func is_on_floor() -> bool:
	return position.y >= _get_current_floor_y() and _vel_y == 0.0

func get_player_rect() -> Rect2:
	return Rect2(position, _ship_size)

func get_player_center() -> Vector2:
	return position + _ship_size * 0.5

func set_gravity(v: float) -> void:
	gravity = v

func set_jump_force(v: float) -> void:
	jump_force = v

# -------- 내부 구현 --------
func _get_current_floor_y() -> float:
	# 라인 모드일 때 각 라인의 상단 y가 바닥
	if use_lanes and _lanes.size() > 0:
		return float(_lanes[_lane_index])
	# 라인 미사용 대비(후방 호환)
	return _ground_y - _ship_size.y

func _clear_visuals() -> void:
	for c in get_children():
		if c is Sprite2D or c is Polygon2D:
			c.queue_free()
	_sprite = null
	_fuselage = null
	_wing_l = null
	_wing_r = null
	_tail = null
	_canopy = null

func _build_sprite(tex: Texture2D) -> void:
	_sprite = Sprite2D.new()
	_sprite.texture = tex
	_sprite.centered = false
	_sprite.position = Vector2.ZERO
	_sprite.scale = Vector2(ship_scale, ship_scale)
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
