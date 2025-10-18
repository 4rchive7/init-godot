# ObstacleController.gd
# Godot 4.4 / GDScript
# ─────────────────────────────────────────────────────────
# ✔ "한 라인에 고정"되는 장애물 컨트롤러
#    - set_lanes_y()로 라인 Y셋을 받고
#    - set_lane_index()로 어느 라인에 속할지 고정
#    - reset_position()은 항상 그 라인의 Y로만 배치
# ─────────────────────────────────────────────────────────
extends Control

@export var obstacle_size: Vector2 = Vector2(36, 36)
@export var obstacle_color: Color = Color(1.0, 0.35, 0.35)
@export var accel_per_sec: float = 12.0
@export var max_speed: float = 1200.0

var _rect: ColorRect
var _speed: float = 0.0
var _view_w: float = 0.0

var _lanes: Array = []     # 각 라인의 상단 y
var _lane_index: int = 1   # 기본: 중앙 라인

func setup(ground_y: float, view_w: float, start_speed: float) -> void:
	_speed = start_speed
	_view_w = view_w
	if _rect == null:
		_rect = ColorRect.new()
		_rect.color = obstacle_color
		_rect.custom_minimum_size = obstacle_size
		add_child(_rect)
	# lanes가 없으면 단일 라인으로라도 동작
	if _lanes.size() == 0:
		_lanes = [ground_y - obstacle_size.y]
	reset_position(_view_w)

func set_lanes_y(lanes_y: Array) -> void:
	_lanes = lanes_y.duplicate()

func set_lane_index(idx: int) -> void:
	_lane_index = clamp(idx, 0, max(0, _lanes.size() - 1))

func update_obstacle(delta: float, view_w: float) -> void:
	if _rect == null:
		return
	_view_w = view_w
	_speed += accel_per_sec * delta
	if _speed > max_speed:
		_speed = max_speed
	_rect.position.x -= _speed * delta
	if _rect.position.x + obstacle_size.x < -8.0:
		reset_position(_view_w)

func reset_position(view_w: float) -> void:
	if _rect == null:
		return
	var y: float = 0.0
	if _lanes.size() == 0:
		y = 0.0
	else:
		var idx: int = clamp(_lane_index, 0, _lanes.size() - 1)
		y = float(_lanes[idx])
	_rect.position = Vector2(view_w + 80.0, y)

func set_speed(v: float) -> void:
	_speed = min(v, max_speed)

func add_speed(d: float) -> void:
	_speed = min(_speed + d, max_speed)

func get_speed() -> float:
	return _speed

func get_lane_index() -> int:
	return _lane_index

func get_obstacle_rect() -> Rect2:
	if _rect == null:
		return Rect2()
	return Rect2(_rect.position, obstacle_size)

func get_obstacle_center() -> Vector2:
	if _rect == null:
		return Vector2.ZERO
	return _rect.position + obstacle_size * 0.5
