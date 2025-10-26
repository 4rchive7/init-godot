# TrackDecor.gd
# Godot 4.4 / GDScript
# 역할:
#  - 모든 레인에 가이드 라인(얇은 ColorRect) 표시
#  - 모든 레인에 중앙 레일 장식(texture/scene/fallback box) 반복 스폰 + 스크롤 + 정리
#
# z-index 규칙:
#  (1) 같은 레인 안에서는 먼저 나온(오래된) 오브젝트가 항상 더 앞(z_index 더 큼)
#      → 새로 스폰된 애일수록 더 뒤쪽 (z_index 더 작음)
#  (2) 레인끼리는 아래 레인일수록 더 앞
#      → lane_idx가 클수록 더 높은 z_index
#
# GameLayer 쪽 사용:
#   decor.setup(...)
#   decor.update_decor(delta, speed_px)

extends Control

# ===== 내부 상태 =====
var _view_size: Vector2
var _lanes_y: Array           # 각 레인의 기준 y
var _lane_gap: float          # 레인 간 간격(참고용)

var _lane_guide_thickness: int
var _lane_guide_color: Color

# 장식(차선 데코) 에셋 설정
var _center_asset_res: Resource = null
var _center_asset_scale: float = 0.6
var _center_asset_gap_px: float = 240.0
var _center_asset_y_offset: float = 0.0
var _center_asset_zindex: int = -6000

# 레인 가이드 ColorRect들. 크기 == _lanes_y.size()
var _lane_guides: Array = []

# 각 레인별 스폰된 데코 노드 목록
# 예: _center_props_per_lane[ lane_idx ] = [ { "node": CanvasItem, "w": float }, ... ]
var _center_props_per_lane: Array = []

# 각 레인별 z-index 커서
# 오래된 오브젝트일수록 큰 값(=> 더 앞)
# 새로 스폰할 때마다 1씩 감소시켜서, 나중에 스폰된 애가 뒤로 가도록 함
var _lane_z_cursor: Array = []


func setup(
	view_size: Vector2,
	lanes_y: Array,
	lane_gap: float,
	lane_guide_thickness: int,
	lane_guide_color: Color,
	center_asset_path: String,
	center_asset_scale: float,
	center_asset_gap_px: float,
	center_asset_y_offset: float,
	center_asset_zindex: int
) -> void:
	# 기본 환경 세팅
	_view_size = view_size
	_lanes_y = lanes_y.duplicate()
	_lane_gap = lane_gap

	_lane_guide_thickness = lane_guide_thickness
	_lane_guide_color = lane_guide_color

	_center_asset_scale = center_asset_scale
	_center_asset_gap_px = center_asset_gap_px
	_center_asset_y_offset = center_asset_y_offset
	_center_asset_zindex = center_asset_zindex

	# 에셋 로드 시도
	_center_asset_res = null
	if center_asset_path.strip_edges() != "":
		var res = load(center_asset_path)
		if res != null and (res is Texture2D or res is PackedScene):
			_center_asset_res = res

	# 레인 가이드 생성 / 위치 지정
	_create_lane_guides()

	# 레인별 장식 리스트 / z-index 커서 초기화
	_center_props_per_lane.clear()
	_lane_z_cursor.clear()

	for i in range(_lanes_y.size()):
		_center_props_per_lane.append([])
		# 큰 값에서 시작해서 매 스폰마다 줄여나감
		# (오래된 애일수록 더 큰 cursor값을 가짐 → 더 앞에 보임)
		_lane_z_cursor.append(1000)


# GameLayer._process()에서 매 프레임 호출
# - lane 데코를 스크롤하고 필요하면 새 오브젝트 생성
# - speed_px: 화면이 왼쪽으로 이동하는 속도(px/sec)
func update_decor(delta: float, speed_px: float) -> void:
	var lane_count: int = _lanes_y.size()
	for lane_idx in range(lane_count):
		_scroll_center_props_lane(delta, speed_px, lane_idx)
		_spawn_center_prop_if_needed_lane(lane_idx)


# ==========================================================
# 레인 가이드: 얇은 가로 라인 (시각 보조)
# ==========================================================
func _create_lane_guides() -> void:
	# 기존 노드 정리
	for g in _lane_guides:
		if is_instance_valid(g):
			g.queue_free()
	_lane_guides.clear()

	# lanes_y 갯수만큼 ColorRect 생성
	for i in range(_lanes_y.size()):
		var rect = ColorRect.new()
		rect.color = _lane_guide_color
		rect.set_anchors_preset(Control.PRESET_TOP_LEFT)
		rect.z_as_relative = false
		# 가이드 라인은 장식들보다 조금 뒤에 있어도 상관없으므로
		# base만 준다 (lane/depth 보정 없이)
		rect.z_index = _center_asset_zindex
		add_child(rect)
		_lane_guides.append(rect)

# ==========================================================
# 레인별 장식 스폰 / 스크롤 / 정리
# ==========================================================

# 각 레인에 깔린 데코들을 왼쪽으로 이동시키고, 화면 밖으로 나간 건 제거
func _scroll_center_props_lane(delta: float, speed_px: float, lane_idx: int) -> void:
	var lane_list: Array = _center_props_per_lane[lane_idx]
	if lane_list.size() == 0:
		return

	var i: int = lane_list.size() - 1
	while i >= 0:
		var entry = lane_list[i]
		var node: CanvasItem = entry["node"]
		var w: float = entry["w"]

		if is_instance_valid(node):
			node.position.x -= speed_px * delta
			if node.position.x + w < -8.0:
				node.queue_free()
				lane_list.remove_at(i)
		else:
			lane_list.remove_at(i)

		i -= 1

	_center_props_per_lane[lane_idx] = lane_list


# 필요하면 lane_idx 레인에 새 장식 오브젝트를 오른쪽 끝에 스폰
func _spawn_center_prop_if_needed_lane(lane_idx: int) -> void:
	var lane_list: Array = _center_props_per_lane[lane_idx]

	# 현재 레인에 가장 오른쪽 노드의 x 찾기
	var rightmost_x: float = -1e9
	for entry in lane_list:
		var n: CanvasItem = entry["node"]
		if is_instance_valid(n) and n.position.x > rightmost_x:
			rightmost_x = n.position.x

	# 기본 스폰 x 지점
	var spawn_edge: float = _view_size.x + 80.0

	# 아무것도 없으면 한 번은 박아준다 (게임 시작 시 허전하지 않게)
	if rightmost_x <= -1e8:
		var first_x: float = spawn_edge
		if lane_list.size() == 0 and _center_asset_res == null:
			# fallback 박스만 있는 경우는 화면 중간에도 하나 두자
			first_x = _view_size.x * 0.5
		var first_entry: Dictionary = _spawn_center_prop_lane(first_x, lane_idx)
		if first_entry.size() > 0:
			lane_list.append(first_entry)
		_center_props_per_lane[lane_idx] = lane_list
		return

	# 간격 체크 후 새로 생성
	if (spawn_edge - rightmost_x) >= _center_asset_gap_px:
		var new_entry: Dictionary = _spawn_center_prop_lane(spawn_edge, lane_idx)
		if new_entry.size() > 0:
			lane_list.append(new_entry)
		_center_props_per_lane[lane_idx] = lane_list


# lane_idx 레인 위치(y) 기준으로 실제 장식 노드를 생성해서 반환
# return {} (빈 딕셔너리) 이면 생성 실패로 간주
func _spawn_center_prop_lane(spawn_x: float, lane_idx: int) -> Dictionary:
	if lane_idx < 0 or lane_idx >= _lanes_y.size():
		return {}

	var y: float = float(_lanes_y[lane_idx]) + _center_asset_y_offset

	# zindex 계산
	# lane_idx가 클수록(아래 레인일수록) 더 앞에 보여야 하므로 lane_idx * 1000 가산
	# 그리고 오래된(먼저 생성된) 애일수록 더 앞에 보여야 하므로 lane_z_cursor의 현재값을 더해주고,
	# 사용 후 1 감소
	var zindex_val: int = _calc_new_prop_zindex(lane_idx)

	# 1) Texture2D 기반
	if _center_asset_res is Texture2D:
		var tex: Texture2D = _center_asset_res
		var tr = TextureRect.new()
		tr.texture = tex
		tr.stretch_mode = TextureRect.STRETCH_KEEP
		tr.set_anchors_preset(Control.PRESET_TOP_LEFT)
		tr.position = Vector2(spawn_x, y)
		tr.scale = Vector2(_center_asset_scale, _center_asset_scale)
		tr.z_as_relative = false
		tr.z_index = zindex_val
		add_child(tr)

		var w_tex: float = tex.get_size().x * _center_asset_scale
		return { "node": tr, "w": w_tex }

	# 2) PackedScene 기반
	if _center_asset_res is PackedScene:
		var inst: Node = (_center_asset_res as PackedScene).instantiate()
		if inst is CanvasItem:
			var ci = inst as CanvasItem
			if ci is Control:
				(ci as Control).set_anchors_preset(Control.PRESET_TOP_LEFT)
			ci.position = Vector2(spawn_x, y)
			ci.scale = Vector2(_center_asset_scale, _center_asset_scale)
			ci.z_as_relative = false
			ci.z_index = zindex_val
			add_child(ci)

			var w_scene: float = _estimate_canvasitem_width(ci)
			return { "node": ci, "w": w_scene }
		else:
			# CanvasItem이 아니면 감싸기
			var wrapper = Control.new()
			wrapper.set_anchors_preset(Control.PRESET_TOP_LEFT)
			wrapper.position = Vector2(spawn_x, y)
			wrapper.scale = Vector2(_center_asset_scale, _center_asset_scale)
			wrapper.z_as_relative = false
			wrapper.z_index = zindex_val
			wrapper.add_child(inst)
			add_child(wrapper)

			var w_wrap: float = 128.0 * _center_asset_scale
			return { "node": wrapper, "w": w_wrap }

	# 3) fallback: 그냥 박스(ColorRect)
	var cr = ColorRect.new()
	cr.color = Color(0.6, 0.6, 0.75, 0.9)
	cr.custom_minimum_size = Vector2(128.0, 48.0)
	cr.set_anchors_preset(Control.PRESET_TOP_LEFT)
	cr.position = Vector2(spawn_x, y)
	cr.scale = Vector2(_center_asset_scale, _center_asset_scale)
	cr.z_as_relative = false
	cr.z_index = zindex_val
	add_child(cr)

	var w_box: float = 128.0 * _center_asset_scale
	return { "node": cr, "w": w_box }


# 각 레인에서 새로 생성될 오브젝트의 z_index를 계산하고,
# 다음번 생성용으로 cursor 값을 줄여준다.
func _calc_new_prop_zindex(lane_idx: int) -> int:
	# lane 깊이 우선순위: 아래 레인이 카메라 가까우므로 더 큰 값
	var lane_depth_base: int = lane_idx * 1000

	# 현재 커서값을 읽고, 한 단계 줄여둔다
	var cursor_val: int = _lane_z_cursor[lane_idx]
	_lane_z_cursor[lane_idx] = cursor_val + 1

	# 최종 zindex
	# _center_asset_zindex는 전체 베이스(아주 낮은 음수일 수도 있음)
	# lane_depth_base로 레인 간 차등
	# cursor_val로 "예전 애일수록 앞" 보장
	print(lane_idx, " ", _center_asset_zindex + lane_depth_base + cursor_val, " ", _center_asset_zindex," ",lane_depth_base, " ", cursor_val)
	return _center_asset_zindex + lane_depth_base + cursor_val


# 폭 추정 유틸
func _estimate_canvasitem_width(ci: CanvasItem) -> float:
	# TextureRect
	if ci is TextureRect:
		var texr = ci as TextureRect
		if texr.texture != null:
			return texr.texture.get_size().x * texr.scale.x
		return texr.size.x * texr.scale.x

	# Sprite2D
	if ci is Sprite2D:
		var sp = ci as Sprite2D
		if sp.texture != null:
			return sp.texture.get_size().x * sp.scale.x

	# Control류
	if ci is Control:
		var c = ci as Control
		var base_w: float = c.size.x
		if c.custom_minimum_size.x > base_w:
			base_w = c.custom_minimum_size.x
		return base_w * c.scale.x

	# 그 외에는 대충 스케일 * 128 가정
	return 128.0 * ci.scale.x
