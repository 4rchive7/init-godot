# ObstacleController.gd
# Godot 4.4 / GDScript
# 빨간 박스(장애물) 전담 컨트롤러
# - 화면 오른쪽에서 등장해 왼쪽으로 이동
# - 시간이 지날수록 자동 가속(난이도 상승)
# - 외부에서 히트 등에 따라 추가 가속(set_speed/add_speed)도 그대로 사용 가능

extends Control

@export var obstacle_size: Vector2 = Vector2(36, 36)
@export var obstacle_color: Color = Color(1.0, 0.35, 0.35)

# ===== 난이도(속도 증가) 파라미터 =====
@export var accel_per_sec: float = 12.0     # 초당 선형 가속치(+12 px/s/s 처럼)
@export var max_speed: float = 1200.0       # 속도 상한

var _rect: ColorRect
var _ground_y: float = 0.0
var _speed: float = 0.0

func _ready() -> void:
	# 시각 노드 준비는 setup에서 처리
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

# 매 프레임 호출: 자동 가속 + 이동 + 화면 밖이면 리셋
func update_obstacle(delta: float, view_w: float) -> void:
	if _rect == null:
		return

	# ---- 난이도 상승: 시간 경과에 따른 선형 가속 ----
	if accel_per_sec != 0.0:
		_speed += accel_per_sec * delta
		if _speed > max_speed:
			_speed = max_speed

	# 이동
	_rect.position.x -= _speed * delta

	# 화면 왼쪽 밖으로 완전히 나가면 리셋
	if _rect.position.x + obstacle_size.x < -8.0:
		reset_position(view_w)

# 화면 오른쪽 바깥으로 재배치
func reset_position(view_w: float) -> void:
	if _rect == null:
		return
	_rect.position = Vector2(view_w + 80.0, _ground_y - obstacle_size.y)

# ----- 속도 제어 API (외부에서 히트 등으로 추가 가속 가능) -----
func set_speed(v: float) -> void:
	_speed = v
	if _speed > max_speed:
		_speed = max_speed

func add_speed(d: float) -> void:
	_speed += d
	if _speed > max_speed:
		_speed = max_speed

func get_speed() -> float:
	return _speed

# ----- 충돌/이펙트용 API -----
# (Control의 get_rect()와 이름 충돌 방지)
func get_obstacle_rect() -> Rect2:
	if _rect == null:
		return Rect2()
	return Rect2(_rect.position, obstacle_size)

func get_obstacle_center() -> Vector2:
	if _rect == null:
		return Vector2.ZERO
	return _rect.position + obstacle_size * 0.5
