# PlayerController.gd
# Godot 4.4 / GDScript
# ▶ 3개 라인 + 중력 점프
# ▶ 원근 스케일: [위 0.9, 가운데 1.0, 아래 1.1]
# ▶ 요구 반영: "라인에 정확히 도착하기 '직전'까지만" 스케일 보간.
#    - 라인 이동 시작 시점의 스케일부터 목표 라인의 스케일까지 진행률 기반 보간
#    - 목표 라인에 도착하는 프레임에서 즉시 보간 종료(= 목표 스케일로 스냅)
# ▶ z-index 최상단 유지

extends Control

# --- 라인/스케일 ---
@export var use_lanes: bool = true
@export var lane_snap_speed: float = 900.0
@export var scale_lerp_speed: float = 6.0   # (참고값) 이제는 진행률 보간이라 직접 사용하진 않음
var _lanes: Array = []
var _lane_index: int = 1
var _lane_target_y: float = 0.0

# 원근 스케일
var _lane_scales: Array = [1.0, 1.0, 1.0]
var _target_scale: float = 1.0
var _current_scale: float = 1.0

# 라인 이동 보간 상태
var _lane_move_active: bool = false
var _lane_move_start_y: float = 0.0
var _lane_move_total_dy: float = 0.0
var _lane_move_start_scale: float = 1.0

# --- 점프/중력 ---
@export var gravity: float = 900.0
@export var jump_force: float = -500.0

# --- 스킨(에셋) ---
@export var ship_image_path: String = "res://assets/ship_blue.png"
@export var ship_scale: float = 0.15
@export var body_color: Color = Color(0.3, 0.8, 1.0)
@export var wing_color: Color = Color(0.25, 0.9, 1.0)
@export var tail_color: Color = Color(0.2, 0.6, 0.9)
@export var cockpit_color: Color = Color(0.1, 0.3, 0.6, 0.85)

# --- 내부 상태 ---
var _ground_y: float = 0.0
var _vel_y: float = 0.0
var _is_jumping: bool = false
var _ship_size: Vector2 = Vector2(44, 44)
var _base_x: float = 0.0

# --- 비주얼 노드 ---
var _sprite: Sprite2D
var _fuselage: Polygon2D
var _wing_l: Polygon2D
var _wing_r: Polygon2D
var _tail: Polygon2D
var _canopy: Polygon2D

func _ready() -> void:
	# 최상단 렌더링
	z_as_relative = false
	z_index = 4096
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
	rotation = 0.0
	_lane_target_y = position.y

	_current_scale = 1.0
	_target_scale = 1.0
	scale = Vector2(_current_scale, _current_scale)
	_lane_move_active = false
	_apply_topmost_z_to_children()

func set_lanes(lanes_y: Array, start_lane_index: int) -> void:
	_lanes = lanes_y.duplicate()
	_lane_index = clamp(start_lane_index, 0, _lanes.size() - 1)
	if _lanes.size() > 0:
		var y = float(_lanes[_lane_index])
		position.y = y
		_lane_target_y = y
		_vel_y = 0.0
		_is_jumping = false
		_current_scale = _get_lane_scale(_lane_index)
		_target_scale = _current_scale
		scale = Vector2(_current_scale, _current_scale)
		_lane_move_active = false

# 외부에서 라인별 스케일 지정 가능
func set_lane_scales(arr: Array) -> void:
	if arr.size() >= 3:
		_lane_scales = [float(arr[0]), float(arr[1]), float(arr[2])]
		_current_scale = _get_lane_scale(_lane_index)
		_target_scale = _current_scale
		scale = Vector2(_current_scale, _current_scale)

func change_lane(delta_idx: int) -> void:
	if _lanes.size() == 0:
		return
	var new_index: int = clamp(_lane_index + delta_idx, 0, _lanes.size() - 1)
	if new_index == _lane_index:
		return

	_lane_index = new_index
	_lane_target_y = float(_lanes[_lane_index])

	# ★ 라인 이동 "시작 시점" 스냅샷을 저장 → 진행률 기반 스케일 보간
	_lane_move_active = true
	_lane_move_start_y = position.y
	_lane_move_total_dy = _lane_target_y - _lane_move_start_y
	_lane_move_start_scale = _current_scale
	_target_scale = _get_lane_scale(_lane_index)

func update_player(delta: float) -> void:
	# X 고정, 회전 없음
	position.x = _base_x
	rotation = 0.0

	# 점프 물리
	if _is_jumping:
		_vel_y += gravity * delta
		position.y += _vel_y * delta
		var floor_y: float = _get_current_floor_y()
		if position.y >= floor_y:
			position.y = floor_y
			_vel_y = 0.0
			_is_jumping = false
	else:
		# 라인 타겟으로 스무스 이동
		var dy: float = _lane_target_y - position.y
		if dy != 0.0:
			var step: float = lane_snap_speed * delta
			# 다음 스텝이 목표를 넘어가면 "그 프레임에서" 정확히 도착 처리 + 보간 종료
			if abs(dy) <= step:
				position.y = _lane_target_y
				if _lane_move_active:
					_current_scale = _target_scale
					scale = Vector2(_current_scale, _current_scale)
					_lane_move_active = false
			else:
				position.y += step * sign(dy)
				# ★ 진행률 기반 스케일 보간 (도착 '직전'까지만)
				if _lane_move_active:
					var total: float = max(abs(_lane_move_total_dy), 0.0001)
					var progressed: float = clamp(abs(position.y - _lane_move_start_y) / total, 0.0, 1.0)
					# progressed==1.0에 도달하는 프레임은 위 if(abs(dy)<=step) 분기에서 처리되어 보간이 끝남
					var s: float = lerp(_lane_move_start_scale, _target_scale, progressed)
					_current_scale = s
					scale = Vector2(s, s)
		else:
			# 이미 타겟에 있는 경우: 스케일도 목표값으로 정돈, 보간 비활성화
			if _lane_move_active:
				_current_scale = _target_scale
				scale = Vector2(_current_scale, _current_scale)
				_lane_move_active = false

func jump() -> void:
	if not _is_jumping:
		_vel_y = jump_force
		_is_jumping = true
		# 점프 중에는 라인 이동 보간이 없으므로 스케일은 유지

func is_on_floor() -> bool:
	return position.y >= _get_current_floor_y() and _vel_y == 0.0

# 충돌 박스(스케일 반영)
func get_player_rect() -> Rect2:
	var size_scaled: Vector2 = _ship_size * _current_scale
	return Rect2(position, size_scaled)

func get_player_center() -> Vector2:
	var size_scaled: Vector2 = _ship_size * _current_scale
	return position + size_scaled * 0.5

func get_lane_index() -> int:
	return _lane_index

func set_gravity(v: float) -> void:
	gravity = v

func set_jump_force(v: float) -> void:
	jump_force = v

# -------- 내부 구현 --------
func _get_current_floor_y() -> float:
	if use_lanes and _lanes.size() > 0:
		return float(_lanes[_lane_index])
	return _ground_y - _ship_size.y

func _get_lane_scale(idx: int) -> float:
	if idx >= 0 and idx < _lane_scales.size():
		return float(_lane_scales[idx])
	return 1.0

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
	_sprite.z_as_relative = false
	_sprite.z_index = 4096
	_sprite.rotate(0.13)
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
	_fuselage.z_as_relative = false
	_fuselage.z_index = 4096
	add_child(_fuselage)

	_wing_l = Polygon2D.new()
	_wing_l.color = wing_color
	_wing_l.polygon = PackedVector2Array([
		Vector2(cx - w * 0.10, h * 0.45),
		Vector2(cx - w * 0.50, h * 0.55),
		Vector2(cx - w * 0.22, h * 0.60),
		Vector2(cx - w * 0.12, h * 0.53),
	])
	_wing_l.z_as_relative = false
	_wing_l.z_index = 4096
	add_child(_wing_l)

	_wing_r = Polygon2D.new()
	_wing_r.color = wing_color
	_wing_r.polygon = PackedVector2Array([
		Vector2(cx + w * 0.10, h * 0.45),
		Vector2(cx + w * 0.50, h * 0.55),
		Vector2(cx + w * 0.22, h * 0.60),
		Vector2(cx + w * 0.12, h * 0.53),
	])
	_wing_r.z_as_relative = false
	_wing_r.z_index = 4096
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
	_tail.z_as_relative = false
	_tail.z_index = 4096
	add_child(_tail)

	_canopy = Polygon2D.new()
	_canopy.color = cockpit_color
	_canopy.polygon = PackedVector2Array([
		Vector2(cx,            h * 0.08),
		Vector2(cx - w * 0.08, h * 0.32),
		Vector2(cx,            h * 0.36),
		Vector2(cx + w * 0.08, h * 0.32),
	])
	_canopy.z_as_relative = false
	_canopy.z_index = 4096
	add_child(_canopy)

func _apply_topmost_z_to_children() -> void:
	for c in get_children():
		if c is CanvasItem:
			(c as CanvasItem).z_as_relative = false
			(c as CanvasItem).z_index = 4096
