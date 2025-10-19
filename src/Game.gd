# GameLayer.gd
# Godot 4.4 / GDScript
# SRP: "오케스트레이션"만 담당
#  - 배경/스타필드/HUD/플레이어/중앙 레일 장식
#  - 장애물 로직은 ObstacleController.gd에 100% 위임
#  - 충돌 후 HP/UI/속도리셋/파편 연출만 처리
#  - ✅ 레인 가이드 라인(위/가운데/아래) ColorRect 3개로 표시

extends Control
signal finished

@export_file("*.gd") var starfield_script_path: String = "res://src/StarField.gd"
@export_file("*.gd") var shard_particles_script_path: String = "res://src/ShardParticles.gd"
@export_file("*.gd") var game_hud_script_path: String = "res://src/GameHUD.gd"
@export_file("*.gd") var player_controller_script_path: String = "res://src/PlayerController.gd"
@export_file("*.gd") var obstacle_controller_script_path: String = "res://src/ObstacleController.gd"

@export var bg_color_space: Color = Color(0.02, 0.02, 0.05)
@export var bg_color_ground: Color = Color(0.15, 0.15, 0.18)
@export var player_color: Color = Color(0.3, 0.8, 1.0)
@export var obstacle_color: Color = Color(1.0, 0.35, 0.35)
@export var text_color: Color = Color.WHITE
@export var gameover_text_color: Color = Color(1, 0.4, 0.4)
@export var font_size_label: int = 20
@export var font_size_hint: int = 24
@export var font_size_gameover: int = 64

@export var lane_gap: float = 50.0

# 장애물 파라미터(컨트롤러로 전달)
@export var obstacle_size: Vector2 = Vector2(36, 36)
@export var obstacle_speed_start: float = 260.0
@export var obstacle_accel_per_sec: float = 10.0

@export var obstacle_texture_path: String = "res://assets/car_red.png"
@export var obstacle_tex_scale: float = 0.5
@export var obstacle_tint: Color = Color(1,1,1,1)
@export var collision_inset_px: Vector2 = Vector2(0, 0)

@export var spawn_density_ramp_duration: float = 90.0
@export var min_gap_scale_at_max: float = 0.40
@export var global_spawn_rate_scale: float = 3.0

@export var lane_gap_time_min: float = 0.60
@export var lane_gap_time_max: float = 1.80
@export var lane_gap_time_mul_top: float = 1.00
@export var lane_gap_time_mul_mid: float = 1.00
@export var lane_gap_time_mul_bot: float = 1.00

@export var obstacle_speed_mul_min: float = 0.75
@export var obstacle_speed_mul_max: float = 1.35
@export var no_overtake_min_gap_px: float = 8.0
@export var no_overtake_safety: float = 0.98

# 중앙 레일 장식
@export var center_asset_path: String =""# "res://assets/lane.png"
@export var center_asset_scale: float = 1.0
@export var center_asset_gap_px: float = 480.0
@export var center_asset_y_offset: float = 0.0
@export var center_asset_zindex: int = -10000

# ✅ 레인 가이드 라인(3개) 설정
@export var lane_guide_thickness: int = 2
@export var lane_guide_color: Color = Color(0.6, 0.6, 0.75, 0.65) # 살짝 밝은 보라톤

@export var hp_max: int = 3
@export var gameover_wait: float = 3.0

# ---------- Z Index Plan ----------
const Z_BG = -20000
const Z_STARS = -15000
const Z_CENTER = -10000
const Z_FG_BASE = 0

# 파편 프리셋(플레이어 사망용)
const _PARTICLE_COUNT_DEATH = 24
const _PARTICLE_SIZE_DEATH = Vector2(5, 5)
const _PARTICLE_LIFETIME_DEATH = 0.9
const _PARTICLE_GRAVITY_DEATH = 680.0

# 내부 상태
var _view_size: Vector2
var _ground_y: float = 420.0
var _hp: int = 0
var _is_game_over: bool = false
var _last_player_lane: int = -1

# 노드
var _bg_space: ColorRect
var _starfield: Node
var _shards: Node
var _hud: Node
var _player_ctrl: Node
var _obstacles_ctrl: Node

# ✅ 레인 가이드 라인들 (위/가운데/아래)
var _lane_guides: Array = []   # ColorRect 3개 저장

# 레인/스케일
var _lanes_y: Array = []
var _lane_scales: Array = [0.9, 1.0, 1.1]

# 중앙 레일 에셋
var _center_asset_res: Resource
var _center_props: Array = []            # [{ "node": CanvasItem, "w": float }]

# 타이머
var _gameover_delay_timer: Timer

func _ready() -> void:
	_set_full_rect(self)

	_hp = hp_max
	_view_size = get_viewport_rect().size
	_ground_y = max(160.0, _view_size.y * 0.75)

	# 배경
	_bg_space = ColorRect.new()
	_bg_space.color = bg_color_space
	_set_full_rect(_bg_space)
	_bg_space.z_as_relative = false
	_bg_space.z_index = Z_BG
	add_child(_bg_space)

	# StarField
	if starfield_script_path.strip_edges() != "":
		var SF = load(starfield_script_path)
		if SF != null:
			_starfield = (SF as Script).new()
			if _starfield is CanvasItem:
				var ci = _starfield as CanvasItem
				ci.z_as_relative = false
				ci.z_index = Z_STARS
			add_child(_starfield)

	# Shards
	if shard_particles_script_path.strip_edges() != "":
		var SP = load(shard_particles_script_path)
		if SP != null:
			_shards = (SP as Script).new()
			if _shards is CanvasItem:
				var si = _shards as CanvasItem
				si.z_as_relative = false
				si.z_index = Z_FG_BASE + 100
			add_child(_shards)
			if "set_ground_y" in _shards:
				_shards.set_ground_y(_ground_y)

	# ✅ 기존 한 줄짜리 바닥선(_ground) 제거 → 대신 세 줄 가이드 사용

	# Player
	if player_controller_script_path.strip_edges() != "":
		var PC = load(player_controller_script_path)
		if PC != null:
			_player_ctrl = (PC as Script).new()
			add_child(_player_ctrl)
			if "setup" in _player_ctrl:
				_player_ctrl.setup(_ground_y, Vector2(44, 44), player_color, 220.0)
			_apply_player_zindex()

	# HUD
	if game_hud_script_path.strip_edges() != "":
		var GH = load(game_hud_script_path)
		if GH != null:
			_hud = (GH as Script).new()
			if "text_color" in _hud:
				_hud.text_color = text_color
			if "gameover_text_color" in _hud:
				_hud.gameover_text_color = gameover_text_color
			if "font_size_label" in _hud:
				_hud.font_size_label = font_size_label
			if "font_size_hint" in _hud:
				_hud.font_size_hint = font_size_hint
			if "font_size_gameover" in _hud:
				_hud.font_size_gameover = font_size_gameover
			if _hud is CanvasItem:
				var hi = _hud as CanvasItem
				hi.z_as_relative = false
				hi.z_index = Z_FG_BASE + 200
			add_child(_hud)
			if "set_hp" in _hud:
				_hud.set_hp(_hp, hp_max)
			if "set_hint" in _hud:
				_hud.set_hint("↑/↓ 레인 이동, Space 점프")

	# 레인/플레이어
	_make_lanes()
	# ✅ 레인 가이드 생성/위치 갱신
	_ensure_lane_guides_created()
	_update_lane_guides_positions()

	if _player_ctrl:
		if "set_lanes" in _player_ctrl:
			_player_ctrl.set_lanes(_lanes_y, 1)
		if "set_lane_scales" in _player_ctrl:
			_player_ctrl.set_lane_scales(_lane_scales)
		_apply_player_zindex()

	# 장애물 컨트롤러
	if obstacle_controller_script_path.strip_edges() != "":
		var OC = load(obstacle_controller_script_path)
		if OC != null:
			_obstacles_ctrl = (OC as Script).new()
			add_child(_obstacles_ctrl)
			if "set_environment" in _obstacles_ctrl:
				_obstacles_ctrl.set_environment(_view_size, _lanes_y, _lane_scales, Z_FG_BASE)
			if "set_spawn_config" in _obstacles_ctrl:
				_obstacles_ctrl.set_spawn_config(
					lane_gap_time_min, lane_gap_time_max,
					lane_gap_time_mul_top, lane_gap_time_mul_mid, lane_gap_time_mul_bot,
					spawn_density_ramp_duration, min_gap_scale_at_max, global_spawn_rate_scale
				)
			if "set_speed_config" in _obstacles_ctrl:
				_obstacles_ctrl.set_speed_config(
					obstacle_speed_start, obstacle_accel_per_sec,
					obstacle_speed_mul_min, obstacle_speed_mul_max,
					no_overtake_min_gap_px, no_overtake_safety
				)
			if "set_visual_config" in _obstacles_ctrl:
				_obstacles_ctrl.set_visual_config(
					obstacle_size, obstacle_texture_path, obstacle_tex_scale, obstacle_tint, collision_inset_px
				)
			if "start" in _obstacles_ctrl:
				_obstacles_ctrl.start()

	# 중앙 레일 에셋 로드
	_center_asset_res = null
	if center_asset_path.strip_edges() != "":
		var res = load(center_asset_path)
		if res != null and (res is Texture2D or res is PackedScene):
			_center_asset_res = res

	# 타이머
	_gameover_delay_timer = Timer.new()
	_gameover_delay_timer.one_shot = true
	_gameover_delay_timer.wait_time = gameover_wait
	_gameover_delay_timer.timeout.connect(_on_gameover_delay_done)
	add_child(_gameover_delay_timer)

	set_process(true)
	set_process_input(true)

func _make_lanes() -> void:
	_lanes_y.clear()
	var player_h: float = 44.0
	var center_y: float = _ground_y - player_h
	var top_y: float = center_y - lane_gap
	var bottom_y: float = center_y + lane_gap
	top_y = clamp(top_y, 32.0, _view_size.y - 48.0)
	bottom_y = clamp(bottom_y, 32.0, _view_size.y - 48.0)
	_lanes_y.append(top_y)
	_lanes_y.append(center_y)
	_lanes_y.append(bottom_y)
	# 레인 재계산 시 가이드도 재배치
	_update_lane_guides_positions()

func _process(delta: float) -> void:
	if _is_game_over:
		return

	# 장애물 업데이트
	if _obstacles_ctrl and "update" in _obstacles_ctrl:
		_obstacles_ctrl.update(delta)

	# StarField 속도 동기화
	if _obstacles_ctrl and "get_base_speed" in _obstacles_ctrl:
		var v: float = _obstacles_ctrl.get_base_speed()
		_set_starfield_speed(v)

	# Player
	if _player_ctrl and "update_player" in _player_ctrl:
		_player_ctrl.update_player(delta)
		_check_player_lane_and_update_z()

	# 중앙 레일 장식 스크롤
	_move_and_cleanup_center_props(delta)
	_try_spawn_center_prop()

	# 충돌 체크
	_check_collision()

func _input(event: InputEvent) -> void:
	if _is_game_over:
		return
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_UP:
			if _player_ctrl and "change_lane" in _player_ctrl:
				_player_ctrl.change_lane(-1)
				_check_player_lane_and_update_z()
		elif event.keycode == KEY_DOWN:
			if _player_ctrl and "change_lane" in _player_ctrl:
				_player_ctrl.change_lane(1)
				_check_player_lane_and_update_z()
		elif event.keycode == KEY_SPACE:
			if _player_ctrl and "jump" in _player_ctrl:
				_player_ctrl.jump()

# ── z-index: 장애물은 lane*2, 플레이어는 lane*2+1 ──
func _z_for_lane(lane_idx: int, is_player: bool) -> int:
	var base = Z_FG_BASE + lane_idx * 2
	if is_player:
		return base + 1
	return base

func _apply_player_zindex() -> void:
	if _player_ctrl is CanvasItem:
		var li: int = 1
		if "get_lane_index" in _player_ctrl:
			li = int(_player_ctrl.get_lane_index())
		var ci = _player_ctrl as CanvasItem
		ci.z_as_relative = false
		ci.z_index = _z_for_lane(li, true)
		_last_player_lane = li

func _check_player_lane_and_update_z() -> void:
	if _player_ctrl and "get_lane_index" in _player_ctrl:
		var li: int = int(_player_ctrl.get_lane_index())
		if li != _last_player_lane:
			_apply_player_zindex()

# ── 충돌 및 후처리 ──
func _check_collision() -> void:
	if _player_ctrl == null or _obstacles_ctrl == null:
		return
	if not ("get_lane_index" in _player_ctrl and "get_player_rect" in _player_ctrl):
		return
	if not ("get_collision_index" in _obstacles_ctrl):
		return

	var p_lane: int = int(_player_ctrl.get_lane_index())
	var p_rect: Rect2 = _player_ctrl.get_player_rect()

	var hit_idx: int = _obstacles_ctrl.get_collision_index(p_rect, p_lane)
	if hit_idx >= 0:
		var center = Vector2.ZERO
		if "consume_hit" in _obstacles_ctrl:
			center = _obstacles_ctrl.consume_hit(hit_idx)
		if _shards and "spawn_directional_shards" in _shards:
			_shards.spawn_directional_shards(
				center, Vector2(-1, 0),
				3, Vector2(6, 6), 0.45, 520.0,
				obstacle_color, 260.0, 380.0, 18.0
			)

		_hp -= 1
		if _hp < 0:
			_hp = 0
		if _hud and "set_hp" in _hud:
			_hud.set_hp(_hp, hp_max)
		if _hud and "tint_hp_hit" in _hud:
			_hud.tint_hp_hit()

		if "reset_speed_to_start" in _obstacles_ctrl:
			_obstacles_ctrl.reset_speed_to_start()
		if "get_base_speed" in _obstacles_ctrl:
			_set_starfield_speed(_obstacles_ctrl.get_base_speed())

		if _hp <= 0:
			_trigger_game_over()
		else:
			var t = Timer.new()
			t.one_shot = true
			t.wait_time = 0.2
			t.timeout.connect(func() -> void:
				if _hud and "tint_hp_normal" in _hud:
					_hud.tint_hp_normal()
				t.queue_free()
			)
			add_child(t)
			t.start()

# ── 중앙 레일 에셋 ──
func _move_and_cleanup_center_props(delta: float) -> void:
	if _center_props.size() == 0:
		return
	var speed: float = 0.0
	if _obstacles_ctrl and "get_base_speed" in _obstacles_ctrl:
		speed = _obstacles_ctrl.get_base_speed()
	var i: int = _center_props.size() - 1
	while i >= 0:
		var entry = _center_props[i]
		var node: CanvasItem = entry["node"]
		var w: float = entry["w"]
		if is_instance_valid(node):
			node.position.x -= speed * delta
			if node.position.x + w < -8.0:
				node.queue_free()
				_center_props.remove_at(i)
		else:
			_center_props.remove_at(i)
		i -= 1

func _try_spawn_center_prop() -> void:
	if _center_asset_res == null:
		return
	var rightmost_x: float = -1e9
	for entry in _center_props:
		var n: CanvasItem = entry["node"]
		if is_instance_valid(n):
			rightmost_x = max(rightmost_x, n.position.x)
	var spawn_edge: float = _view_size.x + 80.0
	if rightmost_x > -1e8 and (spawn_edge - rightmost_x) < center_asset_gap_px:
		return
	_spawn_center_prop(spawn_edge)

func _spawn_center_prop(spawn_x: float) -> void:
	if _lanes_y.size() < 2:
		return
	var y: float = float(_lanes_y[1]) + center_asset_y_offset

	if _center_asset_res is Texture2D:
		var tex: Texture2D = _center_asset_res
		var tr = TextureRect.new()
		tr.texture = tex
		tr.stretch_mode = TextureRect.STRETCH_KEEP
		tr.set_anchors_preset(Control.PRESET_TOP_LEFT)
		tr.position = Vector2(spawn_x, y)
		tr.scale = Vector2(center_asset_scale, center_asset_scale)
		tr.z_as_relative = false
		tr.z_index = Z_CENTER
		add_child(tr)
		var w: float = tex.get_size().x * center_asset_scale
		_center_props.append({ "node": tr, "w": w })
		return

	if _center_asset_res is PackedScene:
		var inst: Node = (_center_asset_res as PackedScene).instantiate()
		if inst is CanvasItem:
			var ci = inst as CanvasItem
			if ci is Control:
				(ci as Control).set_anchors_preset(Control.PRESET_TOP_LEFT)
			ci.position = Vector2(spawn_x, y)
			ci.scale = Vector2(center_asset_scale, center_asset_scale)
			ci.z_as_relative = false
			ci.z_index = Z_CENTER
			add_child(ci)
			var w_scene: float = _estimate_canvasitem_width(ci)
			_center_props.append({ "node": ci, "w": w_scene })
		else:
			var wrapper = Control.new()
			wrapper.set_anchors_preset(Control.PRESET_TOP_LEFT)
			wrapper.position = Vector2(spawn_x, y)
			wrapper.scale = Vector2(center_asset_scale, center_asset_scale)
			wrapper.z_as_relative = false
			wrapper.z_index = Z_CENTER
			wrapper.add_child(inst)
			add_child(wrapper)
			var w_wrap: float = 128.0 * center_asset_scale
			_center_props.append({ "node": wrapper, "w": w_wrap })
		return

	var cr = ColorRect.new()
	cr.color = Color(0.6, 0.6, 0.75, 0.9)
	var base_w: float = 128.0
	cr.custom_minimum_size = Vector2(base_w, 48.0)
	cr.set_anchors_preset(Control.PRESET_TOP_LEFT)
	cr.position = Vector2(spawn_x, y)
	cr.scale = Vector2(center_asset_scale, center_asset_scale)
	cr.z_as_relative = false
	cr.z_index = Z_CENTER
	add_child(cr)
	_center_props.append({ "node": cr, "w": base_w * center_asset_scale })

func _estimate_canvasitem_width(ci: CanvasItem) -> float:
	if ci is TextureRect:
		var texr = ci as TextureRect
		if texr.texture != null:
			return texr.texture.get_size().x * texr.scale.x
		return texr.size.x * texr.scale.x
	if ci is Sprite2D:
		var sp = ci as Sprite2D
		if sp.texture != null:
			return sp.texture.get_size().x * sp.scale.x
	if ci is Control:
		var c = ci as Control
		return max(c.size.x, c.custom_minimum_size.x) * c.scale.x
	return 128.0 * ci.scale.x

# ── 게임오버 ──
func _trigger_game_over() -> void:
	_is_game_over = true
	_set_starfield_speed(0.0)
	if _player_ctrl and "get_player_center" in _player_ctrl and _shards and "spawn_radial_shards" in _shards:
		var pc = _player_ctrl.get_player_center()
		_shards.spawn_radial_shards(pc, _PARTICLE_COUNT_DEATH, _PARTICLE_SIZE_DEATH, _PARTICLE_LIFETIME_DEATH, _PARTICLE_GRAVITY_DEATH, player_color, 420.0, 620.0)
	if _player_ctrl:
		_player_ctrl.queue_free()
	if _hud and "show_game_over" in _hud:
		_hud.show_game_over()
	if _hud and "set_hint" in _hud:
		_hud.set_hint(str(int(gameover_wait)) + "초 뒤 메인으로...")
	_gameover_delay_timer.start()

func _on_gameover_delay_done() -> void:
	emit_signal("finished")

# ── StarField 연동 ──
func _set_starfield_speed(v: float) -> void:
	if _starfield and "set_speed_px" in _starfield:
		_starfield.set_speed_px(v)

# ── 유틸 ──
func _set_full_rect(ctrl: Control) -> void:
	ctrl.anchor_left = 0
	ctrl.anchor_top = 0
	ctrl.anchor_right = 1
	ctrl.anchor_bottom = 1
	ctrl.offset_left = 0
	ctrl.offset_top = 0
	ctrl.offset_right = 0
	ctrl.offset_bottom = 0

# =========================
# ✅ 레인 가이드 유틸
# =========================
func _ensure_lane_guides_created() -> void:
	# 이미 있으면 스킵
	if _lane_guides.size() == 3:
		return
	# 기존 것 정리
	for g in _lane_guides:
		if is_instance_valid(g):
			g.queue_free()
	_lane_guides.clear()

	# 위/가운데/아래 3줄 생성
	var i: int = 0
	while i < 3:
		var line = ColorRect.new()
		line.color = lane_guide_color
		line.custom_minimum_size = Vector2(_view_size.x, lane_guide_thickness)
		line.set_anchors_preset(Control.PRESET_TOP_LEFT)
		line.z_as_relative = false
		line.z_index = Z_CENTER   # 별보다 위, 장애물/플레이어보다 아래
		add_child(line)
		_lane_guides.append(line)
		i += 1

func _update_lane_guides_positions() -> void:
	if _lane_guides.size() != 3 or _lanes_y.size() != 3:
		return
	# 각 라인의 y에 얇은 선 배치
	var i: int = 0
	while i < 3:
		var line: ColorRect = _lane_guides[i]
		if is_instance_valid(line):
			line.custom_minimum_size = Vector2(_view_size.x, lane_guide_thickness)
			line.position = Vector2(0, float(_lanes_y[i]))
		i += 1
