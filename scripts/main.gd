extends Node2D
## P1 오케스트레이션 — 픽셀 퍼펙트 스트립(640×180@2x 고정).
## 씬은 res/ 텍스처로 코드에서 조립한다 (데이터 주도 — 배치 수정이 쉬움).
## 검수 훅: WNW_SMOKE=1 (헤드리스 자동 검증) / WNW_SHOT=경로 (스크린샷).

const CustomerScript := preload("res://scripts/customer.gd")

const GUESTS := ["soso", "jaebul", "nampung", "fox", "umbrella"]
const SEAT_XS := [260.0, 312.0, 380.0, 432.0]  # 테이블 양옆
const FEET_Y := 140.0
const CHAR_H := 30.0
const SPAWN_MIN := 8.0
const SPAWN_MAX := 14.0

## 정적 장식 배치표 — (텍스처, 위치). 벽(y<100) → 바닥(y>=100) 순서 = 그리기 순서.
const DECOR := [
	["menu_board", Vector2(52, 26)],
	["prop_sign", Vector2(98, 30)],
	["shelf", Vector2(168, 26)],
	["window", Vector2(218, 40)],
	["prop_wallclock", Vector2(302, 14)],
	["prop_trainplaque", Vector2(392, 22)],
	["map", Vector2(482, 36)],
	["window", Vector2(524, 40)],
	["door", Vector2(590, 70)],
	["prop_lantern", Vector2(258, 0)],
	["prop_lantern", Vector2(452, 0)],
	["prop_firewood", Vector2(66, 88)],
	["counter", Vector2(86, 84)],
	["prop_kettle", Vector2(88, 62)],
	["barrel", Vector2(232, 86)],
	["table", Vector2(276, 104)],
	["table", Vector2(396, 104)],
	["prop_suitcase", Vector2(556, 108)],
]

@onready var kitchen: Node = $Kitchen
@onready var clock_label: Label = $UI/UIRoot/ClockLabel
@onready var money_label: Label = $UI/UIRoot/MoneyLabel
@onready var keeper_label: Label = $UI/UIRoot/KeeperLabel

var sky: ColorRect
var hearth: Sprite2D
var keeper: AnimatedSprite2D
var seats: Dictionary = {}
var spawn_left := SPAWN_MIN
var keeper_left := 0.0
var frames_cache: Dictionary = {}

# 개입 표적 (판정 = 그림 크기, 있을 때만 보임)
var prep_crate: TextureRect
var dish_stack: TextureRect
var ready_dish: TextureRect

func _ready() -> void:
	_setup_font()
	_build_scene()
	_setup_targets()
	_tick_clock()
	var t := Timer.new()
	t.wait_time = 10.0
	t.timeout.connect(_tick_clock)
	add_child(t)
	t.start()
	State.money_changed.connect(func(v: int) -> void: money_label.text = "코인 %d" % v)
	State.keeper_says.connect(_keeper_say)
	if OS.get_environment("WNW_SMOKE") == "1":
		_run_smoke()
	elif OS.get_environment("WNW_SHOT") != "":
		_run_shot(OS.get_environment("WNW_SHOT"))

func _tex(name: String) -> Texture2D:
	return load("res://res/%s.png" % name)

func _decor(name: String, pos: Vector2) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = _tex(name)
	s.centered = false
	s.position = pos
	add_child(s)
	return s

func _tile(name: String, rect: Rect2) -> void:
	var tr := TextureRect.new()
	tr.texture = _tex(name)
	tr.stretch_mode = TextureRect.STRETCH_TILE
	tr.position = rect.position
	tr.size = rect.size
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tr)

func _build_scene() -> void:
	# 하늘 (실시간 미러링) — 창문 뒤 세계
	sky = ColorRect.new()
	sky.size = Vector2(640, 180)
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sky)
	# 벽: 회벽(플랫) + 징두리 타일
	var plaster := ColorRect.new()
	plaster.position = Vector2(0, 0)
	plaster.size = Vector2(640, 68)
	plaster.color = Color8(226, 208, 170)
	plaster.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(plaster)
	_tile("tile_wall", Rect2(0, 68, 640, 32))
	# 바닥
	_tile("tile_floor", Rect2(0, 100, 640, 80))
	# 화덕 (4상태 스왑 — 화력 시간표의 비주얼 기반)
	hearth = Sprite2D.new()
	hearth.texture = _tex("hearth_mid")
	hearth.centered = false
	hearth.position = Vector2(10, 52)
	add_child(hearth)
	# 정적 장식
	for d in DECOR:
		_decor(d[0], d[1])
	# 역귀 — 조리대 옆, 조리 중엔 냄비를 젓는다
	keeper = AnimatedSprite2D.new()
	keeper.sprite_frames = _char_frames("keeper", ["walk", "cook"])
	keeper.centered = false
	keeper.position = Vector2(148, 96)  # 조리대 오른쪽, 유령이라 살짝 떠 있음
	keeper.play("walk")
	add_child(keeper)

func set_fire_state(state_name: String) -> void:
	hearth.texture = _tex("hearth_%s" % state_name)

## 캐릭터 SpriteFrames 로드 (캐시). 애니메이션당 5프레임, 8fps (저프레임 픽셀 원칙)
func _char_frames(name: String, anims: Array) -> SpriteFrames:
	if frames_cache.has(name):
		return frames_cache[name]
	var sf := SpriteFrames.new()
	for anim in anims:
		if not sf.has_animation(anim):
			sf.add_animation(anim)
		sf.set_animation_speed(anim, 8.0)
		for i in 5:
			sf.add_frame(anim, _tex("%s_%s_%d" % [name, anim, i]))
	frames_cache[name] = sf
	return sf

func _setup_targets() -> void:
	# 서빙 돕기: 완성 접시 (조리대 위)
	ready_dish = _target("prop_dish", Vector2(106, 59), _on_serve_click)
	# 설거지: 쌓인 그릇 (역귀 오른쪽 바닥)
	dish_stack = _target("prop_dishstack", Vector2(180, 94), _on_dish_click)
	# 재료 손질: 채소 상자
	prep_crate = _target("prop_crate", Vector2(208, 92), _on_prep_click)

func _target(tex_name: String, pos: Vector2, handler: Callable) -> TextureRect:
	var r := TextureRect.new()
	r.texture = _tex(tex_name)
	r.position = pos
	r.visible = false
	r.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			handler.call())
	add_child(r)
	return r

func _process(delta: float) -> void:
	spawn_left -= delta
	if spawn_left <= 0.0:
		spawn_left = randf_range(SPAWN_MIN, SPAWN_MAX)
		_spawn_customer()
	ready_dish.visible = kitchen.ready_dishes > 0
	dish_stack.visible = kitchen.dirty_dishes >= 3
	prep_crate.visible = not State.pantry.is_empty() and not kitchen.boost_next_prep
	# 역귀: 조리 중 = 냄비 젓기, 아니면 둥실 대기
	if kitchen.cooking and keeper.animation != "cook":
		keeper.play("cook")
	elif not kitchen.cooking and keeper.animation != "walk":
		keeper.play("walk")
	if keeper_left > 0.0:
		keeper_left -= delta
		if keeper_left <= 0.0:
			keeper_label.text = ""

func _spawn_customer() -> Node2D:
	var free: Array = SEAT_XS.filter(func(x: float) -> bool: return not seats.has(x))
	if free.is_empty():
		return null
	var seat: float = free.pick_random()
	var gname: String = GUESTS.pick_random()
	var c: Node2D = Node2D.new()
	c.set_script(CustomerScript)
	c.setup(_char_frames(gname, ["walk"]))
	c.position = Vector2(650, FEET_Y - CHAR_H)
	c.seat_x = seat
	c.kitchen = kitchen
	c.guest_name = gname
	seats[seat] = c
	c.left.connect(func(cust) -> void:
		seats.erase(cust.seat_x))
	add_child(c)
	return c

func _on_serve_click() -> void:
	for c in seats.values():
		if c.state == c.S.WAITING:
			if State.try_intervene() and c.serve_directly():
				_keeper_say("서빙 고마워요! 팁 +2")
			return

func _on_dish_click() -> void:
	if kitchen.dirty_dishes >= 3 and State.try_intervene():
		kitchen.dirty_dishes = 0
		kitchen.boost_next_cook = true
		_keeper_say("반짝반짝! 다음 요리가 빨라져요")

func _on_prep_click() -> void:
	if not State.pantry.is_empty() and State.try_intervene():
		kitchen.boost_next_prep = true
		_keeper_say("손질을 도와줬어요")

func _keeper_say(text: String) -> void:
	keeper_label.text = text
	keeper_left = 2.5

func _setup_font() -> void:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Apple SD Gothic Neo", "Malgun Gothic", "Noto Sans KR"])
	var theme := Theme.new()
	theme.default_font = f
	theme.default_font_size = 10
	$UI/UIRoot.theme = theme

func _tick_clock() -> void:
	var d := Time.get_datetime_dict_from_system()
	clock_label.text = "%02d:%02d" % [d.hour, d.minute]
	sky.color = _sky_color(d.hour)

## 실시간 미러링 — 균일 틴트만 (그라데이션·페더 금지, 픽셀 원칙 8)
func _sky_color(hour: int) -> Color:
	if hour >= 22 or hour < 5:
		return Color8(24, 26, 44)
	elif hour < 8:
		return Color8(120, 96, 110)
	elif hour < 17:
		return Color8(130, 170, 200)
	elif hour < 20:
		return Color8(190, 120, 80)
	else:
		return Color8(60, 56, 80)

## 헤드리스 자동 검증
func _run_smoke() -> void:
	Engine.time_scale = 10.0
	State.add_ingredients("곡물", ["맑음"], 8)
	await get_tree().create_timer(90.0).timeout
	var ok: bool = State.dishes_served >= 2 and State.money >= 20
	var granted := 0
	for i in 12:
		if State.try_intervene():
			granted += 1
	ok = ok and granted == State.INTERVENTION_CAP
	print("SMOKE money=%d served=%d pantry=%d ready=%d cap=%d/12 -> %s" % [
		State.money, State.dishes_served, State.pantry.size(),
		kitchen.ready_dishes, granted, "PASS" if ok else "FAIL"])
	get_tree().quit(0 if ok else 1)

## 화면 검수: 대표 상태 연출 후 스크린샷
func _run_shot(path: String) -> void:
	State.add_ingredients("곡물", ["맑음"], 3)
	kitchen.ready_dishes = 1
	kitchen.dirty_dishes = 3
	kitchen.cooking = true
	kitchen.cook_left = 60.0
	for i in 2:
		var c := _spawn_customer()
		if c != null:
			c.position.x = c.seat_x
	State.add_money(30)
	_keeper_say("서빙 고마워요! 팁 +2")
	keeper_left = 99.0
	await get_tree().create_timer(1.0).timeout
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()
