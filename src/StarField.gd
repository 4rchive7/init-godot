# StarField.gd
# Godot 4.4 / GDScript
# ─────────────────────────────────────────────────────────
# 우주 배경(더 어두운 톤) + 별 파티클(오른쪽→왼쪽 직선 이동)
# - 장애물이 빨라질수록 별도 같은 비율로 빨라짐
# - 히트 슬로우(Engine.time_scale) 동안 별도 같이 느려지고,
#   복구될 때까지 그대로 유지(프레임마다 time_scale을 곱해 반영)
# - 별이 위/아래로 흔들리지 않도록 Y 성분 완전 차단(spread=0, gravity=0)
# - 동시 표시 수 50 미만 유지
# ─────────────────────────────────────────────────────────

extends Control

# 더 어두운 우주색 (상하 그라디언트)
@export var bg_top: Color = Color(0.01, 0.01, 0.025, 1.0)
@export var bg_bottom: Color = Color(0.0, 0.0, 0.0, 1.0)

# 별 개수(동시 표시 최대) — 50 미만 유지
@export var max_visible_stars: int = 46

# 별 기본 이동 속도(px/s) — 장애물 기본 속도일 때의 별 속도
@export var base_star_speed: float = 140.0

# 장애물 기본 속도(px/s) — ObstacleController의 시작 속도와 맞추면 1배율
@export var base_obstacle_speed: float = 260.0

# 배율 상/하한
@export var min_speed_multiplier: float = 0.35
@export var max_speed_multiplier: float = 4.0

# 별 크기 범위
@export var star_scale_min: float = 0.6
@export var star_scale_max: float = 1.8

# 내부
var _bg: ColorRect
var _stars: GPUParticles2D
var _pm: ParticleProcessMaterial
var _view_size: Vector2
var _obstacle_node: Node = null

func _ready() -> void:
	_set_full_rect(self)
	_view_size = get_viewport_rect().size

	_make_background()
	_make_stars()
	_find_obstacle_node()

	connect("resized", Callable(self, "_on_resized"))
	set_process(true)

func _process(_delta: float) -> void:
	# 장애물 속도 비율 × 전역 time_scale 을 매 프레임 반영
	var mult: float = 1.0
	var ob_speed: float = _get_obstacle_speed()
	if base_obstacle_speed > 0.0 and ob_speed > 0.0:
		mult = ob_speed / base_obstacle_speed

	# 히트 슬로우 시 별도 함께 느려지고, time_scale 복구 전까지 유지
	mult *= Engine.time_scale

	mult = clamp(mult, min_speed_multiplier, max_speed_multiplier)
	_apply_speed_multiplier(mult)

# ───────────────────── 배경 ─────────────────────
func _make_background() -> void:
	if is_instance_valid(_bg):
		_bg.queue_free()
	_bg = ColorRect.new()
	_set_full_rect(_bg)

	var grad = Gradient.new()
	grad.add_point(0.0, bg_top)
	grad.add_point(1.0, bg_bottom)
	var grad_tex = GradientTexture2D.new()
	grad_tex.gradient = grad
	grad_tex.width = 4
	grad_tex.height = 4

	var mat = ShaderMaterial.new()
	var shader = Shader.new()
	shader.code = """
		shader_type canvas_item;
		uniform sampler2D grad_tex : source_color, filter_linear_mipmap;
		void fragment() {
			COLOR = texture(grad_tex, vec2(0.5, UV.y));
		}
	"""
	mat.shader = shader
	mat.set_shader_parameter("grad_tex", grad_tex)
	_bg.material = mat

	add_child(_bg)
	move_child(_bg, 0)

# ───────────────────── 별 파티클 ─────────────────────
func _make_stars() -> void:
	if is_instance_valid(_stars):
		_stars.queue_free()

	_stars = GPUParticles2D.new()
	_stars.local_coords = false
	_stars.emitting = true
	_stars.amount = max_visible_stars         # 동시 표시 상한 (50 미만)
	_stars.lifetime = 2.0
	_stars.preprocess = 0.2
	add_child(_stars)
	move_child(_stars, 1)

	_pm = ParticleProcessMaterial.new()

	# 방출 영역: 화면 오른쪽 좁은 세로 박스
	_pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_pm.emission_box_extents = Vector3(2.0, max(8.0, _view_size.y * 0.5), 0.0)

	# 이동 방향: 왼쪽으로 "정확히" 직선 (Y 흔들림 방지)
	_pm.direction = Vector3(-1, 0, 0)
	_pm.spread = 0.0                # 각도 퍼짐 0 → 위/아래 성분 없음
	_pm.gravity = Vector3(0, 0, 0)  # 중력 없음
	_pm.damping = Vector2(0.0, 0.0)
	_pm.angular_velocity_min = 0.0
	_pm.angular_velocity_max = 0.0
	_pm.orbit_velocity = Vector2(0.0, 0.0)
	_pm.radial_accel = Vector2(0.0, 0.0)
	_pm.tangential_accel = Vector2(0.0, 0.0)

	# 크기/스케일
	_pm.scale_min = star_scale_min
	_pm.scale_max = star_scale_max

	# 보라빛 꼬리
	var ramp = Gradient.new()
	ramp.add_point(0.0, Color(0.90, 0.78, 1.0, 0.95))
	ramp.add_point(1.0, Color(0.45, 0.25, 0.65, 0.0))
	var ramp_tex = GradientTexture1D.new()
	ramp_tex.gradient = ramp
	_pm.color_ramp = ramp_tex

	# 별 점 텍스처
	var img = Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 1))
	var dot_tex = ImageTexture.create_from_image(img)

	_stars.process_material = _pm
	_stars.texture = dot_tex

	# 초기 속도 적용
	_apply_speed_multiplier(1.0)

func _apply_speed_multiplier(mult: float) -> void:
	# 별 이동 속도
	var star_v: float = max(1.0, base_star_speed * mult)
	_pm.initial_velocity_min = star_v * 0.9
	_pm.initial_velocity_max = star_v * 1.1

	# lifetime을 화면 너비에 맞춰 조정 → 동시 표시 수는 amount로 제한되므로 50 미만 유지
	var travel_time: float = _view_size.x / star_v
	_stars.lifetime = clamp(travel_time * 1.05, 0.4, 8.0)

	# 방출 위치를 화면 오른쪽 가장자리에 고정
	_stars.position = Vector2(_view_size.x + 4.0, _view_size.y * 0.5)

func _get_obstacle_speed() -> float:
	# 캐시 재탐색
	if _obstacle_node == null or not is_instance_valid(_obstacle_node):
		_find_obstacle_node()
	if _obstacle_node != null and "get_speed" in _obstacle_node:
		return float(_obstacle_node.get_speed())
	return 0.0

func _find_obstacle_node() -> void:
	var p = get_parent()
	if p == null:
		return
	for n in p.get_children():
		if n == self:
			continue
		if "get_speed" in n:
			_obstacle_node = n
			return

# 외부에서 직접 배속 지정이 필요할 때(선택)
func set_speed_multiplier(mult: float) -> void:
	mult = clamp(mult, min_speed_multiplier, max_speed_multiplier)
	_apply_speed_multiplier(mult)

func sync_with_obstacle_speed(obstacle_speed: float) -> void:
	if base_obstacle_speed <= 0.0:
		return
	var mult: float = clamp(obstacle_speed / base_obstacle_speed, min_speed_multiplier, max_speed_multiplier)
	# 전역 time_scale도 반영(히트 슬로우 시 시각 일치)
	mult *= Engine.time_scale
	_apply_speed_multiplier(mult)

# ───────────────────── 기타 ─────────────────────
func _on_resized() -> void:
	_view_size = get_viewport_rect().size
	_make_background()
	if _pm != null and _stars != null:
		_pm.emission_box_extents = Vector3(2.0, max(8.0, _view_size.y * 0.5), 0.0)
		_stars.position = Vector2(_view_size.x + 4.0, _view_size.y * 0.5)

func _set_full_rect(ctrl: Control) -> void:
	ctrl.anchor_left = 0
	ctrl.anchor_top = 0
	ctrl.anchor_right = 1
	ctrl.anchor_bottom = 1
	ctrl.offset_left = 0
	ctrl.offset_top = 0
	ctrl.offset_right = 0
	ctrl.offset_bottom = 0
