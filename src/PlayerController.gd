# PlayerController.gd
# Godot 4.4 / GDScript
# ▶ 3개 라인 + 중력 점프
# ▶ 원근 스케일: [위 0.9, 가운데 1.0, 아래 1.1]
# ▶ "라인에 정확히 도착하기 직전까지만" 스케일 보간
# ▶ z-index 최상단 유지
# ▶ Near-miss 가속 시, 플레이어 뒤쪽으로 직사각형 방출 파티클: play_boost_trail(mult: float)

extends Control

# ───────── 내부 로컬 클래스: 타원 그림자 ─────────
class ShadowOval:
	extends Node2D
	var radius: float = 20.0
	var color: Color = Color(0,0,0,0.35)
	func _draw() -> void:
		draw_circle(Vector2.ZERO, radius, color)

# --- 라인/스케일 ---
@export var use_lanes: bool = true
@export var lane_snap_speed: float = 900.0
@export var scale_lerp_speed: float = 6.0
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

# --- Boost Trail(가속 파티클) 기본 설정 ---
@export var boost_fx_amount_base: int = 40                # 입자 수 ↓
@export var boost_fx_lifetime: float = 0.5               # 짧은 수명
@export var boost_fx_spread_deg: float = 2.0               # 삼각형 퍼짐 억제
@export var boost_fx_particle_min_size: float = 4.0               # 삼각형 퍼짐 억제
@export var boost_fx_particle_max_size: float = 6.0               # 삼각형 퍼짐 억제
@export var boost_fx_color_head: Color = Color(0.8, 0.6, 1.0, 0.95)  # 보라
@export var boost_fx_color_tail: Color = Color(0.8, 0.6, 1.0, 0.0)   # 보라→투명

# 거리 제한(최대 비행거리 px)
const BOOST_MAX_DISTANCE_PX: float = 70.0
@export var boost_max_velocity_multiplier: float = 2.0               # 삼각형 퍼짐 억제
@export var boost_min_velocity_multiplier: float = 4.0               # 삼각형 퍼짐 억제

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
var _shadow: ShadowOval

# ── Boost Trail 노드 ──
var _boost_fx: GPUParticles2D

func _ready() -> void:
	z_as_relative = false
	z_index = 4096
	pivot_offset = _ship_size * 0.5
	set_process(true)

# GameLayer에서 호출
# setup(ground_y, size, color, start_x)
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

	_ensure_shadow()
	_ensure_boost_particles()

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
		_update_shadow_shape()
		_update_boost_fx_anchor()
		_update_boost_fx_emission_rect()

func set_lane_scales(arr: Array) -> void:
	if arr.size() >= 3:
		_lane_scales = [float(arr[0]), float(arr[1]), float(arr[2])]
		_current_scale = _get_lane_scale(_lane_index)
		_target_scale = _current_scale
		scale = Vector2(_current_scale, _current_scale)
		_update_shadow_shape()
		_update_boost_fx_emission_rect()

func change_lane(delta_idx: int) -> void:
	if _lanes.size() == 0:
		return
	var new_index: int = clamp(_lane_index + delta_idx, 0, _lanes.size() - 1)
	if new_index == _lane_index:
		return

	_lane_index = new_index
	_lane_target_y = float(_lanes[_lane_index])

	_lane_move_active = true
	_lane_move_start_y = position.y
	_lane_move_total_dy = _lane_target_y - _lane_move_start_y
	_lane_move_start_scale = _current_scale
	_target_scale = _get_lane_scale(_lane_index)

func update_player(delta: float) -> void:
	position.x = _base_x
	rotation = 0.0

	if _is_jumping:
		_vel_y += gravity * delta
		position.y += _vel_y * delta
		var floor_y: float = _get_current_floor_y()
		if position.y >= floor_y:
			position.y = floor_y
			_vel_y = 0.0
			_is_jumping = false
	else:
		var dy: float = _lane_target_y - position.y
		if dy != 0.0:
			var step: float = lane_snap_speed * delta
			if abs(dy) <= step:
				position.y = _lane_target_y
				if _lane_move_active:
					_current_scale = _target_scale
					scale = Vector2(_current_scale, _current_scale)
					_lane_move_active = false
			else:
				position.y += step * sign(dy)
				if _lane_move_active:
					var total: float = max(abs(_lane_move_total_dy), 0.0001)
					var progressed: float = clamp(abs(position.y - _lane_move_start_y) / total, 0.0, 1.0)
					var s: float = lerp(_lane_move_start_scale, _target_scale, progressed)
					_current_scale = s
					scale = Vector2(s, s)

	_update_boost_fx_anchor()
	_update_boost_fx_emission_rect()

func jump() -> void:
	if not _is_jumping:
		_vel_y = jump_force
		_is_jumping = true

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

# ───────── 외부 공개 API: Near-miss 가속 이펙트 ─────────
# GameLayer에서 근접 가속 직후 호출:
#   if _player_ctrl and "play_boost_trail" in _player_ctrl:
#       _player_ctrl.play_boost_trail(near_miss_speed_boost_ratio)
func play_boost_trail(boost_multiplier: float = 1.0) -> void:
	_ensure_boost_particles()
	var mult: float = clamp(boost_multiplier, 0.5, 3.0)

	# 입자 수는 배수에 따라 소폭 조정, 이동거리는 최대 30px 이하 보장
	_boost_fx.amount = int(float(boost_fx_amount_base) * mult)
	_boost_fx.lifetime = boost_fx_lifetime
	# ❌ lifetime_randomness 는 GPUParticles2D에 없음 → randomness 사용
	_boost_fx.randomness = 0.65

	var pm: ParticleProcessMaterial = _boost_fx.process_material as ParticleProcessMaterial
	if pm != null:
		# 거리 캡: v * t <= 30px  → t는 고정, v 범위를 그에 맞춰 제한
		var t: float = max(_boost_fx.lifetime, 0.02)
		var v_cap: float = BOOST_MAX_DISTANCE_PX / t
		# 입자 크기 2배 (가시성↑)
		pm.scale_min = boost_fx_particle_min_size
		pm.scale_max = boost_fx_particle_max_size
		# 다양한 거리(서로 다른 속도), 하지만 최대 30px 근처로 제한
		pm.initial_velocity_min = v_cap * boost_min_velocity_multiplier
		pm.initial_velocity_max = v_cap * boost_max_velocity_multiplier

	# 원샷 재생
	_boost_fx.one_shot = true
	_boost_fx.emitting = false
	_boost_fx.restart()
	_boost_fx.emitting = true

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
		# 그림자/파티클은 유지, 나머지 비주얼만 정리
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
	_sprite.position = Vector2(0, -20)
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

	_ensure_shadow()

func _apply_topmost_z_to_children() -> void:
	for c in get_children():
		if c is CanvasItem:
			(c as CanvasItem).z_as_relative = false
			(c as CanvasItem).z_index = 4096
	if _shadow:
		_shadow.z_as_relative = false
		_shadow.z_index = 4095
	if _boost_fx:
		_boost_fx.z_as_relative = false
		_boost_fx.z_index = 4095

# ───────── 그림자 ─────────
func _ensure_shadow() -> void:
	if _shadow == null:
		_shadow = ShadowOval.new()
		_shadow.position = Vector2(60, 40)  # 로컬 좌표
		_shadow.z_as_relative = false
		_shadow.z_index = 4095
		add_child(_shadow)
	_update_shadow_shape()

func _update_shadow_shape() -> void:
	if _shadow == null:
		return
	var base: float = max(_ship_size.x, _ship_size.y)
	_shadow.radius = base * 0.45
	_shadow.scale = Vector2(1.0, 0.2)
	_shadow.queue_redraw()

# ───────── Boost Trail 파티클 ─────────
func _ensure_boost_particles() -> void:
	if _boost_fx != null:
		return

	_boost_fx = GPUParticles2D.new()
	_boost_fx.emitting = false
	_boost_fx.one_shot = true
	_boost_fx.amount = boost_fx_amount_base
	_boost_fx.lifetime = boost_fx_lifetime
	_boost_fx.randomness = 0.65      # ✨ 노드 레벨 랜덤
	_boost_fx.local_coords = true
	_boost_fx.z_as_relative = false
	_boost_fx.z_index = 4095

	var pm: ParticleProcessMaterial = ParticleProcessMaterial.new()

	# 진행 방향: 화면 왼쪽(-X)으로 분출 → 뒤쪽 트레일
	pm.direction = Vector3(-1, 0, 0)
	pm.spread = boost_fx_spread_deg
	pm.gravity = Vector3(0, 0, 0)
	pm.damping = Vector2.ZERO

	# 입자 크기(2배 정도)
	pm.scale_min = 1.2
	pm.scale_max = 2.2

	# 색상 페이드: 보라색 → 투명, Gradient → GradientTexture1D
	var grad = Gradient.new()
	grad.colors = PackedColorArray([boost_fx_color_head, boost_fx_color_tail])
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	var grad_tex = GradientTexture1D.new()
	grad_tex.gradient = grad
	pm.color_ramp = grad_tex

	# 방출 모양: 직사각형 (박스)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	# 실제 크기는 아래 업데이트 함수에서 설정

	_boost_fx.process_material = pm

	_update_boost_fx_anchor()
	_update_boost_fx_emission_rect()
	add_child(_boost_fx)

# 배의 뒤쪽 중앙에 파티클 위치 유지
func _update_boost_fx_anchor() -> void:
	if _boost_fx == null:
		return
	var sz: Vector2 = _ship_size * max(_current_scale, 0.0001)
	var offset_x: float = -sz.x * 0.08
	var offset_y: float = sz.y * 0.50
	_boost_fx.position = Vector2(offset_x, offset_y)

# 방출 시작점을 넓혀 직사각형 영역에서 분사
func _update_boost_fx_emission_rect() -> void:
	if _boost_fx == null:
		return
	var pm: ParticleProcessMaterial = _boost_fx.process_material as ParticleProcessMaterial
	if pm == null:
		return
	var sz: Vector2 = _ship_size * max(_current_scale, 0.0001)
	# 너비는 배 폭의 30%, 높이는 배 높이의 40% 정도로 넓게
	var rect_w: float = sz.x * 0.30
	var rect_h: float = sz.y * 0.40
	pm.emission_box_extents = Vector3(rect_w * 0.5, rect_h * 0.5, 0.0)
