# StarField.gd
# Godot 4.4 / GDScript
# ▶ 요구사항 반영:
#   - 별은 "화면 밖 오른쪽"에서만 생성되고,
#   - "화면 밖 왼쪽"에 도달하면(수명 종료로) 사라집니다.
#   - 따라서 화면 중간에서 갑자기 생성되거나 사라지는 일이 없습니다.
# ▶ 설계 방식:
#   - GPUParticles2D 사용, emission_shape=BOX + emission_shape_offset로 방출 지점을
#     화면 우측 밖(+margin)으로 이동.
#   - lifetime = (화면너비 + 양쪽 margin) / 속도 로 계산 → 왼쪽 밖에서 자연 소멸.
#   - preprocess=0으로 초기 충전 금지(처음엔 비어 있다가 우측에서 들어옴).
#   - 수평 이동(왼쪽)만, 수직 떨림/가속 없음.
#   - 총 별 개수 50 미만 유지(먼층 15, 가까운층 20 = 35).

extends Control

@export var bg_color: Color = Color(0.05, 0.03, 0.08, 1.0)  # 어두운 우주 보랏빛
@export var base_speed: float = 180.0                       # px/s 기준
@export var far_speed_mul: float = 0.5
@export var near_speed_mul: float = 1.0

# 별 개수(총합<50 유지)
@export var far_amount: int = 15
@export var near_amount: int = 20

# 별 크기(픽셀)
@export var far_size_px: float = 1.5
@export var near_size_px: float = 2.0

# 내부: 화면 밖 여유 마진(생성/소멸 지점)
@export var edge_margin_px: float = 64.0

# 내부 노드
var _bg: ColorRect
var _far: GPUParticles2D
var _near: GPUParticles2D

func _ready() -> void:
	_set_full_rect(self)

	# 어두운 우주 배경
	_bg = ColorRect.new()
	_bg.color = bg_color
	_set_full_rect(_bg)
	add_child(_bg)
	_bg.z_as_relative = false
	_bg.z_index = -20000

	# 파티클 레이어(먼/가까운)
	_far = _make_star_layer(far_amount, far_size_px, base_speed * far_speed_mul)
	_near = _make_star_layer(near_amount, near_size_px, base_speed * near_speed_mul)

	add_child(_far)
	add_child(_near)

	# 레이어 z (배경 위, 다른 요소 뒤)
	_far.z_as_relative = false
	_near.z_as_relative = false
	_far.z_index = -15000
	_near.z_index = -14900

# ── 레이어 생성 ───────────────────────────────────────────────────────────
func _make_star_layer(amount: int, size_px: float, speed: float) -> GPUParticles2D:
	var view: Rect2 = get_viewport_rect()
	var vw: float = max(view.size.x, 1.0)
	var vh: float = max(view.size.y, 1.0)
	var margin: float = edge_margin_px

	# 별 텍스처(작은 흰 점)
	var img = Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 1))
	var dot = ImageTexture.create_from_image(img)

	# 수명 = (오른쪽 밖 → 왼쪽 밖) 이동 시간
	var travel_w: float = vw + margin * 2.0
	var spd: float = max(speed, 1.0)
	var lifetime_calc: float = travel_w / spd

	var p = GPUParticles2D.new()
	p.amount = amount
	p.lifetime = lifetime_calc
	p.one_shot = false
	p.preprocess = 0.0            # ★ 초기 충전 금지(중간 생성 방지)
	p.local_coords = false        # 전역 좌표

	# 컬링 방지용 가시영역(좌우 바깥까지 넉넉히)
	p.visibility_rect = Rect2(-vw, -vh * 0.5, vw * 3.0, vh * 2.0)

	var pm = ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	# 방출 상자: 얇은 세로 띠(우측 밖)
	pm.emission_box_extents = Vector3(2.0, vh * 0.55, 0.0)
	# 화면 중앙 기준으로 우측 끝 + margin 만큼 오프셋 (Emitter는 중앙)
	pm.emission_shape_offset = Vector3(vw * 0.5 + margin, 0.0, 0.0)

	# 수평으로 왼쪽 이동
	pm.direction = Vector3(-1, 0, 0)
	pm.spread = 0.0

	# 속도(조금의 분산 허용)
	pm.initial_velocity_min = spd * 0.95
	pm.initial_velocity_max = spd * 1.05

	# 불필요한 가속/회전/감쇠 OFF
	pm.gravity = Vector3(0, 0, 0)
	pm.linear_accel_min = 0.0
	pm.linear_accel_max = 0.0
	pm.angular_velocity_min = 0.0
	pm.angular_velocity_max = 0.0
	pm.damping_min = 0.0
	pm.damping_max = 0.0
	pm.radial_accel_min = 0.0
	pm.radial_accel_max = 0.0
	pm.tangential_accel_min = 0.0
	pm.tangential_accel_max = 0.0

	# 별 크기
	pm.scale_min = size_px
	pm.scale_max = size_px

	p.process_material = pm
	p.texture = dot
	p.emitting = true

	# Emitter는 화면 중앙에 두되, emission_shape_offset으로 우측 밖에서만 생성
	p.position = Vector2(vw * 0.5, vh * 0.5)
	return p

# ── 공개 API ──────────────────────────────────────────────────────────────
# GameLayer 등에서 별 속도를 동기화할 때 호출하세요.
func set_speed_px(sec_speed: float) -> void:
	base_speed = max(sec_speed, 0.0)
	_update_layer_speeds_and_lifetimes()

func set_parallax(far_mul: float, near_mul: float) -> void:
	far_speed_mul = max(far_mul, 0.0)
	near_speed_mul = max(near_mul, 0.0)
	_update_layer_speeds_and_lifetimes()

# ── 내부 갱신 ─────────────────────────────────────────────────────────────
func _update_layer_speeds_and_lifetimes() -> void:
	var view: Rect2 = get_viewport_rect()
	var vw: float = max(view.size.x, 1.0)
	var margin: float = edge_margin_px

	# FAR
	if _far and _far.process_material is ParticleProcessMaterial:
		var spd_f: float = max(base_speed * far_speed_mul, 1.0)
		var pmf: ParticleProcessMaterial = _far.process_material
		pmf.initial_velocity_min = spd_f * 0.95
		pmf.initial_velocity_max = spd_f * 1.05
		_far.lifetime = (vw + margin * 2.0) / spd_f
		# 방출 오프셋도 화면 크기 변화 시 재계산(보통은 고정)
		pmf.emission_shape_offset = Vector3(vw * 0.5 + margin, 0.0, 0.0)

	# NEAR
	if _near and _near.process_material is ParticleProcessMaterial:
		var spd_n: float = max(base_speed * near_speed_mul, 1.0)
		var pmn: ParticleProcessMaterial = _near.process_material
		pmn.initial_velocity_min = spd_n * 0.95
		pmn.initial_velocity_max = spd_n * 1.05
		_near.lifetime = (vw + margin * 2.0) / spd_n
		pmn.emission_shape_offset = Vector3(vw * 0.5 + margin, 0.0, 0.0)

# ── 유틸 ──────────────────────────────────────────────────────────────────
func _set_full_rect(ctrl: Control) -> void:
	ctrl.anchor_left = 0
	ctrl.anchor_top = 0
	ctrl.anchor_right = 1
	ctrl.anchor_bottom = 1
	ctrl.offset_left = 0
	ctrl.offset_top = 0
	ctrl.offset_right = 0
	ctrl.offset_bottom = 0
