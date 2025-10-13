# ObstacleController.gd
# Godot 4.4 / GDScript
# 진행 방향(왼쪽)으로 이동하는 장애물을 전담 관리하는 컴포넌트
# - 내부에 ColorRect(장애물)를 생성/이동/리셋
# - 외부에서 속도 변경, 충돌용 사각형/중심 좌표를 얻도록 API 제공
extends Control

@export var obstacle_size: Vector2 = Vector2(36, 36)
@export var obstacle_color: Color = Color(1.0, 0.35, 0.35)

var _rect: ColorRect
var _ground_y: float = 0.0
var _speed: float = 0.0

func _ready() -> void:
	# 이 노드 자체는 레이아웃에 영향 없게 두고, 자식 ColorRect만 사용
	pass

# 초기 설정: 지면 Y, 화면 너비, 시작 속도
func setup(ground_y: float, view_w: float, start_speed: float) -> void:
	_ground_y = ground_y
	_speed = start_speed

	if _rect == null:
		_rect = ColorRect.new()
		_rect.color = obstacle_color
		_rect.custom_minimum_size = obstacle_size
		add_child(_rect)

	reset_position(view_w)

# 매 프레임 호출: 왼쪽으로 이동 + 화면 밖이면 리셋
func update_obstacle(delta: float, view_w: float) -> void:
	if _rect == null:
		return
	_rect.position.x -= _speed * delta
	if _rect.position.x + obstacle_size.x < -8.0:
		reset_position(view_w)

# 화면 오른쪽 바깥으로 재배치
func reset_position(view_w: float) -> void:
	if _rect == null:
		return
	_rect.position = Vector2(view_w + 80.0, _ground_y - obstacle_size.y)

# 속도 제어
func set_speed(v: float) -> void:
	_speed = v

func add_speed(d: float) -> void:
	_speed += d

func get_speed() -> float:
	return _speed

# 충돌/이펙트용 (Control의 get_rect와 이름 충돌 방지)
func get_obstacle_rect() -> Rect2:
	if _rect == null:
		return Rect2()
	return Rect2(_rect.position, obstacle_size)

func get_obstacle_center() -> Vector2:
	if _rect == null:
		return Vector2.ZERO
	return _rect.position + obstacle_size * 0.5
