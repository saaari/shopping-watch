extends Node2D
## P1 오케스트레이션 — 픽셀 퍼펙트 스트립(640×180@2x 고정).
## 씬은 res/ 텍스처로 코드에서 조립한다 (데이터 주도).
## 검수 훅: WNW_SMOKE=1 (헤드리스 자동 검증) / WNW_SHOT=경로 (스크린샷).

const CustomerScript := preload("res://scripts/customer.gd")

const FEET_Y := 140.0
const CHAR_H := 30.0
const OFFLINE_LETTER_COIN := 15  # 고정 편지 — 화력·부재 길이와 곱셈 금지 (GDD §3.4-④)

## 화력 → 노선(손님 풀). 누적형 — 불이 세질수록 먼 노선이 추가된다 (GDD §4.1)
const FIRE_POOL := {
	"ember": ["soso", "jaebul"],
	"mid": ["soso", "jaebul", "nampung"],
	"strong": ["soso", "jaebul", "nampung", "fox"],
	"blue": ["soso", "jaebul", "nampung", "fox", "umbrella"],
}
const FIRE_LABEL := {
	"ember": "오늘의 불: 잉걸불 — 완행이 섭니다",
	"mid": "오늘의 불: 중불 — 급행이 섭니다",
	"strong": "오늘의 불: 센불 — 특급이 섭니다",
	"blue": "오늘의 불: 푸른 불 — 유령 노선이 정차합니다",
}
const FIRE_SPAWN := {  # [min, max] 스폰 간격(게임초) — 잉걸불도 살아 있어야 한다
	"ember": [450.0, 650.0], "mid": [280.0, 400.0],
	"strong": [220.0, 340.0], "blue": [240.0, 340.0],
}
## 손님 취향 계열 (여정 카드) — 메뉴에 있으면 가중 ×3 (메뉴 = 미끼)
const FAVS := {"soso": "아침", "nampung": "볶음", "fox": "국물", "umbrella": "국물"}

## 장면형 업그레이드 (순수 % 금지 — 전부 보이는 변화, GDD §4.6)
const UPGRADES := [
	{"key": "lantern", "name": "승강장 등불", "price": 150,
	 "desc": "역이 밝아지고 손님 발걸음이 잦아진다"},
	{"key": "stove", "name": "대합실 난로", "price": 400,
	 "desc": "잿불이가 불을 쬐러 자주 온다"},
	{"key": "table3", "name": "테이블 하나 더", "price": 800,
	 "desc": "자리가 늘어난다"},
]

## 정적 장식 배치표 — 벽(y<100) → 바닥(y>=100) 순서 = 그리기 순서
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
var timetable_label: Label
var seats: Dictionary = {}
var seat_xs: Array = [260.0, 312.0, 380.0, 432.0]
var spawn_left := 10.0
var keeper_left := 0.0
var frames_cache: Dictionary = {}

var prep_crate: TextureRect
var dish_stack: TextureRect
var ready_dish: TextureRect

var menu_panel: PanelContainer
var shop_panel: PanelContainer
var invite_panel: PanelContainer
var guest_log: Array = []  # 시뮬 계측용

func _ready() -> void:
	_setup_font()
	_build_scene()
	_setup_targets()
	_build_panels()
	_tick_clock()
	var t := Timer.new()
	t.wait_time = 10.0
	t.timeout.connect(_tick_clock)
	add_child(t)
	t.start()
	State.money_changed.connect(func(v: int) -> void: money_label.text = "코인 %d" % v)
	State.keeper_says.connect(_keeper_say)
	State.fire_changed.connect(_on_fire_changed)
	_on_fire_changed(State.fire_state)
	var smoke := OS.get_environment("WNW_SMOKE") == "1"
	var shot := OS.get_environment("WNW_SHOT")
	var sim := OS.get_environment("WNW_SIM") != ""
	if not smoke and shot.is_empty() and not sim:
		_load_and_greet()
		var auto := Timer.new()  # 상시 저장 (강제 종료 대비)
		auto.wait_time = 60.0
		auto.timeout.connect(func() -> void: State.save_game())
		add_child(auto)
		auto.start()
		get_tree().create_timer(10.0).timeout.connect(func() -> void: invite_panel.show())
	if smoke:
		_run_smoke()
	elif not shot.is_empty():
		_run_shot(shot)
	elif OS.get_environment("WNW_SIM") != "":
		_run_sim(int(OS.get_environment("WNW_SIM")))

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and OS.get_environment("WNW_SMOKE") != "1":
		State.save_game()  # 퇴근 버튼 — 끄는 것은 폐점이 아니라 인계

func _load_and_greet() -> void:
	var away := State.load_game()
	_apply_upgrades()
	_on_fire_changed(State.fire_state)
	if away > 600.0:  # 10분 이상 부재 — 고정 편지 (부재 요약)
		State.add_money(OFFLINE_LETTER_COIN)
		_keeper_say("돌아왔구나. 부재 중 손님들이 다녀갔어요 (+%d)" % OFFLINE_LETTER_COIN, 6.0)
	elif away >= 0.0:
		_keeper_say("다녀오셨어요.", 3.0)

## ---- 씬 조립 ----

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
	sky = ColorRect.new()
	sky.size = Vector2(640, 180)
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sky)
	var plaster := ColorRect.new()
	plaster.size = Vector2(640, 68)
	plaster.color = Color8(226, 208, 170)
	plaster.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(plaster)
	_tile("tile_wall", Rect2(0, 68, 640, 32))
	_tile("tile_floor", Rect2(0, 100, 640, 80))
	hearth = Sprite2D.new()
	hearth.texture = _tex("hearth_%s" % State.fire_state)
	hearth.centered = false
	hearth.position = Vector2(10, 52)
	add_child(hearth)
	for d in DECOR:
		_decor(d[0], d[1])
	keeper = AnimatedSprite2D.new()
	keeper.sprite_frames = _char_frames("keeper", ["walk", "cook"])
	keeper.centered = false
	keeper.position = Vector2(148, 96)
	keeper.play("walk")
	add_child(keeper)
	# 클릭 존: 메뉴판 → 메뉴, 역귀 → 상점
	_clickzone(Rect2(52, 26, 30, 42), func() -> void: menu_panel.visible = not menu_panel.visible)
	_clickzone(Rect2(148, 96, 28, 30), func() -> void: shop_panel.visible = not shop_panel.visible)

func _clickzone(rect: Rect2, handler: Callable) -> void:
	var c := Control.new()
	c.position = rect.position
	c.size = rect.size
	c.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			handler.call())
	add_child(c)

## 업그레이드 적용 — 전부 장면의 변화로 나타난다
var upgrade_nodes: Dictionary = {}
func _apply_upgrades() -> void:
	if State.upgrades.get("lantern", false) and not upgrade_nodes.has("lantern"):
		upgrade_nodes["lantern"] = [_decor("prop_lantern", Vector2(258, 0)),
									_decor("prop_lantern", Vector2(452, 0))]
	if State.upgrades.get("stove", false) and not upgrade_nodes.has("stove"):
		upgrade_nodes["stove"] = [_decor("stove", Vector2(348, 94))]
	if State.upgrades.get("table3", false) and not upgrade_nodes.has("table3"):
		upgrade_nodes["table3"] = [_decor("table", Vector2(496, 104))]
		seat_xs.append_array([480.0, 532.0])

func set_fire_state(state_name: String) -> void:
	hearth.texture = _tex("hearth_%s" % state_name)

func _on_fire_changed(s: String) -> void:
	set_fire_state(s)
	if timetable_label:
		timetable_label.text = FIRE_LABEL[s]

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
	ready_dish = _target("prop_dish", Vector2(106, 59), _on_serve_click)
	dish_stack = _target("prop_dishstack", Vector2(180, 94), _on_dish_click)
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

## ---- UI 패널 (시간표·메뉴판·상점·초대장) ----

func _build_panels() -> void:
	var root: Control = $UI/UIRoot
	timetable_label = Label.new()
	timetable_label.position = Vector2(200, 2)
	timetable_label.size = Vector2(240, 16)
	timetable_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(timetable_label)

	# 메뉴판 — 하루 한 번의 결정 (30초 규격). 미선택 유지 = 무벌
	menu_panel = _panel(root, Vector2(180, 30), "내일의 메뉴판")
	for i in 3:
		var ob := OptionButton.new()
		for r_name in State.RECIPES:
			ob.add_item("%s (%s)" % [r_name, State.RECIPES[r_name]])
		ob.selected = State.RECIPES.keys().find(State.menu[i])
		ob.item_selected.connect(func(idx: int) -> void:
			State.set_menu_slot(i, State.RECIPES.keys()[idx])
			_keeper_say("내일은 이 메뉴로!"))
		menu_panel.get_child(0).add_child(ob)

	# 상점 — 장면형 업그레이드
	shop_panel = _panel(root, Vector2(360, 30), "역귀의 장부")
	for u in UPGRADES:
		var b := Button.new()
		b.text = "%s — %d코인 · %s" % [u.name, u.price, u.desc]
		b.pressed.connect(func() -> void: _buy(u, b))
		if State.upgrades.get(u.key, false):
			b.text = "%s — 설치됨" % u.name
			b.disabled = true
		shop_panel.get_child(0).add_child(b)

	# 초대장 — 전방 예고만 (반사실 금지)
	invite_panel = _panel(root, Vector2(380, 100), "초대장")
	var msg := Label.new()
	msg.text = "내일 비가 온대요.\n빗속을 걸으면 — 우산 정령이\n유령 노선을 타고 온대요."
	invite_panel.get_child(0).add_child(msg)
	var row := HBoxContainer.new()
	invite_panel.get_child(0).add_child(row)
	var go := Button.new()
	go.text = "걸었다 치기 (디버그)"
	go.pressed.connect(func() -> void:
		State.add_ingredients("빗물 채소", ["비", "저녁"], 3)
		State.set_fire("blue")
		invite_panel.hide()
		_keeper_say("푸른 불! 오늘 유령 노선이 정차합니다"))
	row.add_child(go)
	var later := Button.new()
	later.text = "나중에"
	later.pressed.connect(func() -> void: invite_panel.hide())
	row.add_child(later)

func _panel(root: Control, pos: Vector2, title: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.position = pos
	p.visible = false
	var box := VBoxContainer.new()
	p.add_child(box)
	var t := Label.new()
	t.text = title
	box.add_child(t)
	root.add_child(p)
	return p

func _buy(u: Dictionary, btn: Button) -> void:
	if State.upgrades.get(u.key, false) or State.money < u.price:
		if State.money < u.price:
			_keeper_say("코인이 조금 모자라요")
		return
	State.add_money(-u.price)
	State.upgrades[u.key] = true
	_apply_upgrades()
	State.save_game()
	btn.text = "%s — 설치됨" % u.name
	btn.disabled = true
	_keeper_say("%s 설치! 역이 좋아졌어요" % u.name)

## ---- 루프 ----

func _process(delta: float) -> void:
	spawn_left -= delta
	if spawn_left <= 0.0:
		var r: Array = FIRE_SPAWN[State.fire_state]
		spawn_left = randf_range(r[0], r[1])
		_spawn_customer()
	ready_dish.visible = kitchen.ready_dishes > 0
	dish_stack.visible = kitchen.dirty_dishes >= 3
	prep_crate.visible = not State.pantry.is_empty() and not kitchen.boost_next_prep
	if kitchen.cooking and keeper.animation != "cook":
		keeper.play("cook")
	elif not kitchen.cooking and keeper.animation != "walk":
		keeper.play("walk")
	if keeper_left > 0.0:
		keeper_left -= delta
		if keeper_left <= 0.0:
			keeper_label.text = ""

## 화력 풀 × 메뉴 미끼 가중 추첨
func _pick_guest() -> String:
	var pool: Array = FIRE_POOL[State.fire_state]
	var menu_cats: Array = State.menu.map(func(r: String) -> String: return State.RECIPES.get(r, ""))
	var weights: Array = []
	var total := 0.0
	for g in pool:
		var w := 3.0 if menu_cats.has(FAVS.get(g, "")) else 1.0
		if g == "jaebul" and State.upgrades.get("stove", false):
			w *= 2.0  # 난로 — 잿불이가 불 쬐러 자주 옴
		weights.append(w)
		total += w
	var roll := randf() * total
	for i in pool.size():
		roll -= weights[i]
		if roll <= 0.0:
			return pool[i]
	return pool[-1]

func _spawn_customer() -> Node2D:
	var free: Array = seat_xs.filter(func(x: float) -> bool: return not seats.has(x))
	if free.is_empty():
		return null
	var seat: float = free.pick_random()
	var gname := _pick_guest()
	guest_log.append(gname)
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

func _keeper_say(text: String, dur: float = 2.5) -> void:
	keeper_label.text = text
	keeper_left = dur

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

## 실시간 미러링 — 균일 틴트만 (그라데이션·페더 금지)
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

## ---- 검수 훅 ----

func _run_smoke() -> void:
	Engine.time_scale = 100.0
	State.add_ingredients("곡물", ["맑음"], 8)
	await get_tree().create_timer(4000.0).timeout
	var ok: bool = State.dishes_served >= 2 and State.money >= 20
	var granted := 0
	for i in 12:
		if State.try_intervene():
			granted += 1
	ok = ok and granted == State.INTERVENTION_CAP
	# 화력 풀 필터
	State.set_fire("ember")
	ok = ok and FIRE_POOL[State.fire_state] == ["soso", "jaebul"]
	State.set_fire("blue")
	ok = ok and FIRE_POOL[State.fire_state].size() == 5
	# 저장/불러오기 왕복
	State.money = 123
	State.upgrades = {"stove": true}
	State.save_game("user://smoke_save.json")
	State.money = 0
	State.upgrades = {}
	var away := State.load_game("user://smoke_save.json")
	ok = ok and State.money == 123 and State.upgrades.get("stove", false) and away >= 0.0
	print("SMOKE served=%d cap=%d/12 pool_ok save_ok=%s -> %s" % [
		State.dishes_served, granted, str(State.money == 123), "PASS" if ok else "FAIL"])
	get_tree().quit(0 if ok else 1)

## 재미 QA 시뮬레이션 — 가상 플레이어가 N일을 플레이 (하루 = 근무 8시간 = 28,800 게임초)
## 지표: 주방 가동률 / 착석 손님 중 굶는 비율 / 빈 화면 비율 / 수익 / 손님 다양성
func _run_sim(days: int) -> void:
	Engine.time_scale = 600.0
	State.money = 0
	State.upgrades = {}
	State.dishes_served = 0
	var fires := ["mid", "blue", "strong", "mid", "strong"]
	var baits := ["국밥", "볶음국수", "주먹밥", "국밥", "볶음국수"]
	for day in days:
		State.interventions_today = 0
		State.set_fire(fires[day % fires.size()])
		State.set_menu_slot(0, baits[day % baits.size()])
		var coins0 := State.money
		var served0 := State.dishes_served
		guest_log.clear()
		State.add_ingredients("곡물", ["맑음"], randi_range(5, 9))  # 아침 장보기
		if State.fire_state == "blue":
			State.add_ingredients("빗물 채소", ["비", "저녁"], 3)
		var kitchen_active := 0
		var waiting_total := 0
		var seated_total := 0
		var empty_scene := 0
		var clicks := 0
		var bought: Array = []
		for s in 480:  # 60게임초 간격 480샘플
			await get_tree().create_timer(60.0).timeout
			if kitchen.prepping or kitchen.cooking:
				kitchen_active += 1
			var seated := 0
			var waiting := 0
			for c in seats.values():
				if c.state != c.S.LEAVING:
					seated += 1
					if c.state == c.S.WAITING:
						waiting += 1
			seated_total += seated
			waiting_total += waiting
			if seated == 0:
				empty_scene += 1
			if clicks < 10 and randf() < 0.3:  # 플레이어 개입 흉내
				if ready_dish.visible:
					_on_serve_click(); clicks += 1
				elif dish_stack.visible:
					_on_dish_click(); clicks += 1
				elif prep_crate.visible:
					_on_prep_click(); clicks += 1
			for u in UPGRADES:  # 여유 20코인 남기고 구매
				if not State.upgrades.get(u.key, false) and State.money >= u.price + 20:
					State.add_money(-u.price)
					State.upgrades[u.key] = true
					_apply_upgrades()
					bought.append(u.key)
		var gc := {}
		for g in guest_log:
			gc[g] = gc.get(g, 0) + 1
		print("SIMDAY %s" % JSON.stringify({
			"day": day + 1, "fire": State.fire_state, "bait": baits[day % baits.size()],
			"coins": State.money - coins0, "served": State.dishes_served - served0,
			"kitchen_pct": kitchen_active * 100 / 480,
			"starve_pct": (waiting_total * 100 / seated_total) if seated_total > 0 else 0,
			"empty_pct": empty_scene * 100 / 480,
			"clicks": clicks, "spawns": guest_log.size(), "guests": gc,
			"bought": bought, "pantry_left": State.pantry.size(),
		}))
	get_tree().quit()

func _run_shot(path: String) -> void:
	State.add_ingredients("곡물", ["맑음"], 3)
	kitchen.ready_dishes = 1
	kitchen.dirty_dishes = 3
	kitchen.pot_servings = 8  # 솥이 끓는 중 (cooking은 파생 상태)
	kitchen.dish_left = 60.0
	State.upgrades = {"lantern": true, "stove": true, "table3": true}
	_apply_upgrades()
	for i in 3:
		var c := _spawn_customer()
		if c != null:
			c.position.x = c.seat_x
	State.add_money(30)
	invite_panel.show()
	_keeper_say("서빙 고마워요! 팁 +2")
	keeper_left = 99.0
	await get_tree().create_timer(1.0).timeout
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()
