extends Node2D
## P1 오케스트레이션 — 픽셀 퍼펙트 스트립 창(640×180@2x 고정), 실시간 미러링,
## 손님 스폰, 개입 3종, 스모크 테스트 훅(WNW_SMOKE=1).

const CustomerScript := preload("res://scripts/customer.gd")

## 손님 아키타입 5종 (docs/guests_p1.md) — P1은 색 사각형 플레이스홀더
const GUESTS := [
	{"name": "소소", "color": Color8(230, 214, 120)},
	{"name": "잿불이", "color": Color8(130, 124, 120)},
	{"name": "남풍", "color": Color8(120, 180, 220)},
	{"name": "눈여우 상인", "color": Color8(224, 232, 240)},
	{"name": "우산 정령", "color": Color8(150, 120, 190)},
]
const SEAT_XS := [268.0, 314.0, 388.0, 434.0]  # 테이블 양옆
const SPAWN_MIN := 8.0
const SPAWN_MAX := 14.0

@onready var sky: ColorRect = $Sky
@onready var kitchen: Node = $Kitchen
@onready var clock_label: Label = $UI/UIRoot/ClockLabel
@onready var money_label: Label = $UI/UIRoot/MoneyLabel
@onready var keeper_label: Label = $UI/UIRoot/KeeperLabel

var seats: Dictionary = {}  # seat_x -> customer (점유 관리)
var spawn_left := SPAWN_MIN
var keeper_left := 0.0

# 개입 표적 (동적 생성)
var prep_crate: ColorRect
var dish_stack: ColorRect
var ready_dish: ColorRect

func _ready() -> void:
	_setup_font()
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

## 디버그 UI 폰트 — 한글 시스템 폰트 (플레이스홀더. 본 UI는 비트맵 픽셀 폰트로 교체 예정)
func _setup_font() -> void:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Apple SD Gothic Neo", "Malgun Gothic", "Noto Sans KR"])
	var theme := Theme.new()
	theme.default_font = f
	theme.default_font_size = 10
	$UI/UIRoot.theme = theme

func _setup_targets() -> void:
	# 서빙 돕기: 완성 접시 (조리대 위)
	ready_dish = _target(Rect2(156, 86, 12, 10), Color8(240, 240, 230), _on_serve_click)
	# 설거지: 쌓인 그릇 (조리대 위)
	dish_stack = _target(Rect2(116, 82, 14, 14), Color8(160, 170, 180), _on_dish_click)
	# 재료 손질: 재료 상자 (조리대 옆 바닥)
	prep_crate = _target(Rect2(184, 102, 16, 14), Color8(150, 110, 60), _on_prep_click)

func _target(rect: Rect2, color: Color, handler: Callable) -> ColorRect:
	var r := ColorRect.new()
	r.position = rect.position
	r.size = rect.size
	r.color = color
	r.visible = false
	r.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			handler.call())
	add_child(r)
	return r

func _process(delta: float) -> void:
	# 손님 스폰
	spawn_left -= delta
	if spawn_left <= 0.0:
		spawn_left = randf_range(SPAWN_MIN, SPAWN_MAX)
		_spawn_customer()
	# 개입 표적 표시 (있을 때만 보임 — 없는 것을 보여주지 않는다)
	ready_dish.visible = kitchen.ready_dishes > 0
	dish_stack.visible = kitchen.dirty_dishes >= 3
	prep_crate.visible = not State.pantry.is_empty() and not kitchen.boost_next_prep
	# 역귀 말풍선 수명
	if keeper_left > 0.0:
		keeper_left -= delta
		if keeper_left <= 0.0:
			keeper_label.text = ""

func _spawn_customer() -> ColorRect:
	var free: Array = SEAT_XS.filter(func(x: float) -> bool: return not seats.has(x))
	if free.is_empty():
		return null
	var seat: float = free.pick_random()
	var g: Dictionary = GUESTS.pick_random()
	var c: ColorRect = ColorRect.new()
	c.set_script(CustomerScript)
	c.size = Vector2(10, 20)
	c.position = Vector2(650, 116)
	c.color = g.color
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.seat_x = seat
	c.kitchen = kitchen
	c.guest_name = g.name
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

func _tick_clock() -> void:
	var d := Time.get_datetime_dict_from_system()
	clock_label.text = "%02d:%02d" % [d.hour, d.minute]
	sky.color = _sky_color(d.hour)

## 실시간 미러링: 게임 하늘이 실제 시각을 따른다 (GDD §3.4-②).
## 균일 틴트만 사용 — 그라데이션·페더 금지 (픽셀 원칙 8).
func _sky_color(hour: int) -> Color:
	if hour >= 22 or hour < 5:
		return Color8(24, 26, 44)    # 밤
	elif hour < 8:
		return Color8(120, 96, 110)  # 새벽·아침놀
	elif hour < 17:
		return Color8(130, 170, 200) # 낮
	elif hour < 20:
		return Color8(190, 120, 80)  # 노을
	else:
		return Color8(60, 56, 80)    # 초저녁

## 헤드리스 자동 검증: 재료 주입 → 배속 → 서빙·수익 발생 확인 후 종료
func _run_smoke() -> void:
	Engine.time_scale = 10.0
	State.add_ingredients("곡물", ["맑음"], 8)
	await get_tree().create_timer(90.0).timeout
	var ok: bool = State.dishes_served >= 2 and State.money >= 20
	# 개입 상한: 12회 시도 중 정확히 CAP 만큼만 허용돼야 한다
	var granted := 0
	for i in 12:
		if State.try_intervene():
			granted += 1
	ok = ok and granted == State.INTERVENTION_CAP
	print("SMOKE money=%d served=%d pantry=%d ready=%d cap=%d/12 -> %s" % [
		State.money, State.dishes_served, State.pantry.size(),
		kitchen.ready_dishes, granted, "PASS" if ok else "FAIL"])
	get_tree().quit(0 if ok else 1)

## 화면 검수: 대표 상태(재료·손님·완성 접시)를 만들어 스크린샷 저장 후 종료
func _run_shot(path: String) -> void:
	State.add_ingredients("곡물", ["맑음"], 3)
	kitchen.ready_dishes = 1
	kitchen.dirty_dishes = 3
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
