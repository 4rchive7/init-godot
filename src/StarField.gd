# StarField.gd
# Godot 4.4 / GDScript
# 우주 배경(보라빛 검은색) + 화면 오른쪽에서 왼쪽으로 흐르는 별 파티클 (최대 48개 < 50)
# 상위 노드가 Control/CanvasLayer 어디든 붙여서 재사용 가능.

extends Control

@export var space_color: Color = Color(0.04, 0.01, 0.07) # 보라빛 검은색
@export var star_speed: float = 180.0                     # 별 이동 속도(px/s)
@export var star_amount: int = 48                         # 동시 최대 별 개수(50 미만)
@export var star_min_size: float = 0.8
@export var star_max_size: float = 2.2
@export var star_alpha: float = 0.95

var _bg: ColorRect
var _stars: GPUParticles2D

func _ready() -> void:
	_set_full_rect(self)
	_make_background()
	_make_star_particles()
	set_process(false) # 파티클은 GPU가 알아서 움직임

func _make_background() -> void:
	_bg = ColorRect.new()
	_bg.color = space_color
	_set_full_rect(_bg)
	add_child(_bg)

func _make_star_particles() -> void:
	var view_size: Vector2 = get_viewport_rect().size

	# 별 텍스처(작은 흰 점) 생성
	var img: Image = Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 1))
	var star_tex: ImageTexture = ImageTexture.create_from_image(img)

	_stars = GPUParticles2D.new()
	_stars.texture = star_tex
	_stars.emitting = true
	_stars.amount = clamp(star_amount, 0, 49)  # 안전빵으로 50 미만 보장
	_stars.one_shot = false

	# 오른쪽 가장자리에서 화면 전체 높이로 방출
	_stars.position = Vector2(view_size.x + 2.0, view_size.y * 0.5)
	var lifetime: float = (view_size.x + 32.0) / max(star_speed, 1.0)
	_stars.lifetime = lifetime
	_stars.preprocess = lifetime * 0.6

	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(-1, 0, 0)                  # 왼쪽으로 진행
	pm.spread = 8.0                                   # 살짝 퍼짐
	pm.gravity = Vector3(0, 0, 0)                     # 중력 없음
	pm.initial_velocity_min = star_speed
	pm.initial_velocity_max = star_speed * 1.15
	pm.angular_velocity_min = -1.2
	pm.angular_velocity_max = 1.2
	pm.scale_min = star_min_size
	pm.scale_max = star_max_size
	pm.color = Color(1, 1, 1, star_alpha)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(2.0, view_size.y * 0.5, 0.0) # 세로 전체

	_stars.process_material = pm
	add_child(_stars)
	# 배경 바로 위 레이어로 배치(다른 UI/캐릭터보다 뒤에 두고 싶으면 move_child로 조정)
	move_child(_stars, 1)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_on_resized()

func _on_resized() -> void:
	if _bg != null:
		_set_full_rect(_bg)
	if _stars == null:
		return
	var view_size: Vector2 = get_viewport_rect().size
	_stars.position = Vector2(view_size.x + 2.0, view_size.y * 0.5)
	var lifetime: float = (view_size.x + 32.0) / max(star_speed, 1.0)
	_stars.lifetime = lifetime
	_stars.preprocess = min(_stars.preprocess, lifetime)
	var pm: ParticleProcessMaterial = _stars.process_material
	if pm:
		pm.emission_box_extents = Vector3(2.0, view_size.y * 0.5, 0.0)

# ---- 유틸 ----
func _set_full_rect(ctrl: Control) -> void:
	ctrl.anchor_left = 0
	ctrl.anchor_top = 0
	ctrl.anchor_right = 1
	ctrl.anchor_bottom = 1
	ctrl.offset_left = 0
	ctrl.offset_top = 0
	ctrl.offset_right = 0
	ctrl.offset_bottom = 0
