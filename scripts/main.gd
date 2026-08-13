extends Node2D
## P1 오케스트레이션 — 픽셀 퍼펙트 스트립 (높이 180@2x 고정, 폭은 성장 단계에 따라 확장).
## 씬은 res/ 텍스처로 코드에서 조립한다 (데이터 주도 — 단계 전환 시 전체 재조립).
## 검수 훅: WNW_SMOKE=1 / WNW_SHOT=경로 (+WNW_STAGE=1~5) / WNW_SIM=일수

const CustomerScript := preload("res://scripts/customer.gd")
const BusserScript := preload("res://scripts/busser.gd")

const FEET_Y := 140.0
const CHAR_H := 30.0
const OFFLINE_LETTER_COIN := 15  # 고정 편지 — 화력·부재 길이와 곱셈 금지

## ---- 성장 5단계 — 창이 좌우로 길어지고 테이블·알바생·꾸밈이 늘어난다 ----
const STAGES := [
	{},
	{"name": "간이역 분식", "width": 400, "tables": 1, "staff": 0,
	 "deco": []},
	{"name": "보통역 식당", "width": 476, "tables": 2, "staff": 0,
	 "deco": ["deco_plant"]},
	{"name": "급행 정차역 식당", "width": 552, "tables": 3, "staff": 1,
	 "deco": ["deco_plant", "deco_lamp", "painting"]},
	{"name": "특급 정차역 식당", "width": 628, "tables": 4, "staff": 1,
	 "deco": ["deco_plant", "deco_lamp", "painting", "deco_coatstand", "grandfather_clock", "prop_postcards"]},
	{"name": "종착역 명물 식당", "width": 704, "tables": 5, "staff": 2,
	 "deco": ["deco_plant", "deco_lamp", "painting", "deco_coatstand", "grandfather_clock", "prop_postcards", "deco_fishbowl", "deco_garland", "prop_apples"]},
]
## 확장 해금 (누적 서빙) + 공사비. index = 목표 단계
const EXPANSIONS := [null, null,
	{"served": 20, "price": 200}, {"served": 60, "price": 500},
	{"served": 120, "price": 1200}, {"served": 200, "price": 2500}]

## 화력 → 노선. 신규 손님은 아트가 설치된 경우에만 풀에 합류 (_pick_guest의 필터)
const FIRE_POOL := {
	"ember": ["soso", "jaebul", "moss"],
	"mid": ["soso", "jaebul", "moss", "nampung", "tanuki"],
	"strong": ["soso", "jaebul", "moss", "nampung", "tanuki", "fox", "magpie"],
	"blue": ["soso", "jaebul", "moss", "nampung", "tanuki", "fox", "magpie", "umbrella", "star"],
}
const FIRE_LABEL := {
	"ember": "오늘의 불: 잉걸불 — 완행이 섭니다",
	"mid": "오늘의 불: 중불 — 급행이 섭니다",
	"strong": "오늘의 불: 센불 — 특급이 섭니다",
	"blue": "오늘의 불: 푸른 불 — 유령 노선이 정차합니다",
}
const FIRE_SPAWN := {
	"ember": [450.0, 650.0], "mid": [280.0, 400.0],
	"strong": [220.0, 340.0], "blue": [240.0, 340.0],
}
const FAVS := {"soso": "아침", "nampung": "볶음", "fox": "국물", "umbrella": "국물",
	"moss": "아침", "tanuki": "국물", "magpie": "간식", "star": "야식"}
## 레시피 → 테이블 위 음식 스프라이트
const RECIPE_FOOD := {"국밥": "food_0", "미역국": "food_3", "주먹밥": "food_1",
	"아침죽": "food_0", "볶음국수": "food_2", "채소볶음": "food_2",
	"야식꼬치": "food_4", "사과파이": "food_5"}

const UPGRADES := [
	{"key": "lantern", "name": "승강장 등불", "price": 150,
	 "desc": "역이 밝아지고 손님 발걸음이 잦아진다"},
	{"key": "stove", "name": "대합실 난로", "price": 400,
	 "desc": "잿불이가 불을 쬐러 자주 온다"},
]

@onready var kitchen: Node = $Kitchen
@onready var clock_label: Label = $UI/UIRoot/ClockLabel
@onready var money_label: Label = $UI/UIRoot/MoneyLabel
@onready var keeper_label: Label = $UI/UIRoot/KeeperLabel

var scene_root: Node2D
var sky: ColorRect
var hearth: Sprite2D
var keeper: AnimatedSprite2D
var timetable_label: Label
var stage_label: Label

var tables: Array = []       # {idx, x, plates, stack: Sprite2D, claimed}
var seat_defs: Array = []    # {x, table_idx}
var seats: Dictionary = {}   # seat_x -> customer
var bussers: Array = []
var foods: Dictionary = {}   # customer -> food Sprite2D
var guest_log: Array = []
var clears_by_staff := 0
var clears_by_click := 0
var keeper_clear_left := 180.0

var spawn_left := 10.0
var rush_active := false
var peak_conc := 0
var keeper_left := 0.0
var frames_cache: Dictionary = {}
var expansion_announced := false

var prep_crate: TextureRect
var dish_stack: TextureRect
var ready_dish: TextureRect

var menu_panel: PanelContainer
var shop_panel: PanelContainer
var invite_panel: PanelContainer

func _ready() -> void:
	_setup_font()
	_build_ui_labels()
	_rebuild_scene()
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
		var auto := Timer.new()
		auto.wait_time = 60.0
		auto.timeout.connect(func() -> void: State.save_game())
		add_child(auto)
		auto.start()
		get_tree().create_timer(10.0).timeout.connect(func() -> void: invite_panel.show())
	if smoke:
		_run_smoke()
	elif not shot.is_empty():
		_run_shot(shot)
	elif sim:
		_run_sim(int(OS.get_environment("WNW_SIM")))

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and OS.get_environment("WNW_SMOKE") != "1":
		State.save_game()  # 퇴근 버튼 — 끄는 것은 폐점이 아니라 인계

func _load_and_greet() -> void:
	var away := State.load_game()
	_rebuild_scene()
	_on_fire_changed(State.fire_state)
	_refresh_shop()
	if away > 600.0:
		State.add_money(OFFLINE_LETTER_COIN)
		_keeper_say("돌아왔구나. 부재 중 손님들이 다녀갔어요 (+%d)" % OFFLINE_LETTER_COIN, 6.0)
	elif away >= 0.0:
		_keeper_say("다녀오셨어요.", 3.0)

## ---- 텍스처·배치 도우미 ----

func _has_tex(name: String) -> bool:
	return ResourceLoader.exists("res://res/%s.png" % name)

func _tex(name: String) -> Texture2D:
	return load("res://res/%s.png" % name)

func _decor(name: String, pos: Vector2) -> Sprite2D:
	if not _has_tex(name):
		return null
	var s := Sprite2D.new()
	s.texture = _tex(name)
	s.centered = false
	s.position = pos
	scene_root.add_child(s)
	return s

func _tile(name: String, rect: Rect2) -> void:
	var tr := TextureRect.new()
	tr.texture = _tex(name)
	tr.stretch_mode = TextureRect.STRETCH_TILE
	tr.position = rect.position
	tr.size = rect.size
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scene_root.add_child(tr)

func stage_width() -> float:
	return float(STAGES[State.stage].width)

## ---- 씬 (재)조립 — 단계 데이터 주도 ----

func _rebuild_scene() -> void:
	if scene_root != null:
		scene_root.queue_free()
	seats.clear()
	tables.clear()
	seat_defs.clear()
	bussers.clear()
	foods.clear()
	scene_root = Node2D.new()
	add_child(scene_root)
	var st: Dictionary = STAGES[State.stage]
	var w: float = st.width
	_apply_window(int(w), String(st.name))
	# 배경
	sky = ColorRect.new()
	sky.size = Vector2(w, 180)
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scene_root.add_child(sky)
	sky.color = _sky_color(Time.get_datetime_dict_from_system().hour)
	var plaster := ColorRect.new()
	plaster.size = Vector2(w, 68)
	plaster.color = Color8(226, 208, 170)
	plaster.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scene_root.add_child(plaster)
	_tile("tile_wall", Rect2(0, 68, w, 32))
	_tile("tile_floor", Rect2(0, 100, w, 80))
	# 주방 블록 (고정)
	hearth = Sprite2D.new()
	hearth.texture = _tex("hearth_%s" % State.fire_state)
	hearth.centered = false
	hearth.position = Vector2(10, 52)
	scene_root.add_child(hearth)
	_decor("menu_board", Vector2(52, 26))
	_decor("prop_sign", Vector2(98, 30))
	_decor("shelf", Vector2(168, 26))
	_decor("prop_firewood", Vector2(66, 88))
	_decor("counter", Vector2(86, 84))
	_decor("prop_kettle", Vector2(88, 62))
	_decor("window", Vector2(218, 40))
	# 오른쪽 클러스터 (폭 기준 상대 배치 — 좁은 단계에서는 생략: 소박한 시작)
	if w >= 476:
		_decor("prop_wallclock", Vector2(w / 2.0 - 10, 14))
	if w >= 552:
		_decor("prop_trainplaque", Vector2(w - 248, 22))
	if w >= 520:
		_decor("map", Vector2(w - 158, 36))
	_decor("window", Vector2(w - 116, 40))
	_decor("door", Vector2(w - 50, 70))
	_decor("prop_suitcase", Vector2(w - 84, 108))
	if State.upgrades.get("lantern", false):
		_decor("prop_lantern", Vector2(258, 0))
		_decor("prop_lantern", Vector2(w - 188, 0))
	if State.upgrades.get("stove", false):
		_decor("stove", Vector2(w - 130, 88))
	# 단계 꾸밈 (성장할수록 예뻐진다)
	var deco_slots := [Vector2(238, 96), Vector2(w - 150, 96), Vector2(340, 24),
		Vector2(w - 200, 96), Vector2(410, 20), Vector2(468, 96),
		Vector2(300, 20), Vector2(w - 280, 20), Vector2(530, 24)]
	var di := 0
	for dname in st.deco:
		if di < deco_slots.size():
			_decor(dname, deco_slots[di])
			di += 1
	# 테이블 + 좌석 + 접시 자리
	for i in int(st.tables):
		var tx := 258.0 + i * 76.0
		_decor("table", Vector2(tx, 104))
		var stack := Sprite2D.new()
		stack.centered = false
		stack.position = Vector2(tx + 6, 84)
		stack.visible = false
		scene_root.add_child(stack)
		tables.append({"idx": i, "x": tx, "plates": 0, "stack": stack, "claimed": false})
		seat_defs.append({"x": tx - 18.0, "table_idx": i})
		seat_defs.append({"x": tx + 38.0, "table_idx": i})
		var ti := i
		_clickzone(Rect2(tx + 2, 84, 28, 22), func() -> void: _on_table_click(ti))
	# 역귀
	keeper = AnimatedSprite2D.new()
	keeper.sprite_frames = _char_frames("keeper", ["walk", "cook"])
	keeper.centered = false
	keeper.position = Vector2(148, 96)
	keeper.play("walk")
	scene_root.add_child(keeper)
	# 알바생
	for b in int(st.staff):
		if not _has_tex("busser_walk_0"):
			break
		var bs: Node2D = Node2D.new()
		bs.set_script(BusserScript)
		bs.setup(_char_frames("busser", ["walk"]))
		bs.position = Vector2(190.0 + b * 14.0, FEET_Y - CHAR_H)
		bs.main = self
		scene_root.add_child(bs)
		bussers.append(bs)
	# 개입 표적 + 클릭 존
	_setup_targets()
	_clickzone(Rect2(52, 26, 30, 42), func() -> void: menu_panel.visible = not menu_panel.visible)
	_clickzone(Rect2(148, 96, 28, 30), func() -> void: shop_panel.visible = not shop_panel.visible)

func _apply_window(w: int, title: String) -> void:
	if stage_label:
		stage_label.text = title
	if clock_label:
		clock_label.position.x = w - 48
	if DisplayServer.get_name() == "headless":
		return
	get_tree().root.content_scale_size = Vector2i(w, 180)
	get_window().size = Vector2i(w * 2, 360)
	get_window().title = "Walk n Wok — %s" % title

func _clickzone(rect: Rect2, handler: Callable) -> void:
	var c := Control.new()
	c.position = rect.position
	c.size = rect.size
	c.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			handler.call())
	scene_root.add_child(c)

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
			var tn := "%s_%s_%d" % [name, anim, i]
			if _has_tex(tn):
				sf.add_frame(anim, _tex(tn))
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
	scene_root.add_child(r)
	return r

## ---- 테이블 접시 흐름 ----

func _on_customer_finished(c: Node2D) -> void:
	_remove_food(c)
	if c.table_idx >= 0 and c.table_idx < tables.size():
		var t: Dictionary = tables[c.table_idx]
		t.plates = mini(int(t.plates) + 1, 6)
		_update_stack(t)

func _update_stack(t: Dictionary) -> void:
	var s: Sprite2D = t.stack
	var n := int(t.plates)
	if n <= 0:
		s.visible = false
		return
	var tex_name := "plates_1" if n <= 2 else ("plates_3" if n <= 4 else "plates_6")
	if not _has_tex(tex_name):
		tex_name = "prop_dishstack"
	s.texture = _tex(tex_name)
	s.visible = true

## 알바생/클릭이 테이블을 치운다. 반환: 치운 접시 수
func clear_table(t: Dictionary) -> int:
	var n := int(t.plates)
	t.plates = 0
	t.claimed = false
	_update_stack(t)
	if n > 0:
		clears_by_staff += 1
	return n

func _on_table_click(idx: int) -> void:
	var t: Dictionary = tables[idx]
	if int(t.plates) > 0 and State.try_intervene():
		clears_by_staff -= 1  # clear_table이 스태프로 계수한 것을 클릭으로 정정
		kitchen.dirty_dishes += clear_table(t)
		clears_by_click += 1
		_keeper_say("테이블이 반짝반짝!")

## ---- 식사·계산 연출 ----

func _on_customer_eating(c: Node2D) -> void:
	if c.table_idx < 0 or c.table_idx >= tables.size():
		return
	var recipe: String = State.menu.pick_random()
	var fname: String = RECIPE_FOOD.get(recipe, "food_0")
	if not _has_tex(fname):
		return
	var f := Sprite2D.new()
	f.texture = _tex(fname)
	f.centered = false
	var t: Dictionary = tables[c.table_idx]
	f.position = Vector2(float(t.x) + (2.0 if c.seat_x < float(t.x) else 16.0), 90)
	scene_root.add_child(f)
	foods[c] = f

func _remove_food(c: Node2D) -> void:
	if foods.has(c):
		foods[c].queue_free()
		foods.erase(c)

func _on_customer_paid(c: Node2D, amount: int) -> void:
	var lb := Label.new()
	lb.text = "+%d" % amount
	lb.position = Vector2(c.position.x, c.position.y - 10)
	$UI/UIRoot.add_child(lb)
	var tw := create_tween()
	tw.tween_property(lb, "position:y", lb.position.y - 14.0, 1.2)
	tw.parallel().tween_property(lb, "modulate:a", 0.0, 1.2)  # 오브젝트 전체 페이드 (허용 연출)
	tw.tween_callback(lb.queue_free)

## ---- UI ----

func _build_ui_labels() -> void:
	var root: Control = $UI/UIRoot
	timetable_label = Label.new()
	timetable_label.position = Vector2(140, 2)
	timetable_label.size = Vector2(240, 16)
	root.add_child(timetable_label)
	stage_label = Label.new()
	stage_label.position = Vector2(4, 16)
	stage_label.size = Vector2(160, 14)
	stage_label.text = String(STAGES[State.stage].name)
	root.add_child(stage_label)

func _build_panels() -> void:
	var root: Control = $UI/UIRoot
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
	shop_panel = _panel(root, Vector2(200, 30), "역귀의 장부")
	_refresh_shop()
	invite_panel = _panel(root, Vector2(210, 100), "초대장")
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

## 상점 목록 재구성 — 확장(해금 시) + 가구
func _refresh_shop() -> void:
	if shop_panel == null:
		return
	var box: VBoxContainer = shop_panel.get_child(0)
	var kids := box.get_children()
	for i in range(1, kids.size()):
		kids[i].queue_free()
	if State.stage < 5 and _expansion_unlocked():
		var e: Dictionary = EXPANSIONS[State.stage + 1]
		var b := Button.new()
		b.text = "확장 공사 → %s — %d코인" % [STAGES[State.stage + 1].name, e.price]
		b.pressed.connect(_buy_expansion)
		box.add_child(b)
	for u in UPGRADES:
		var b2 := Button.new()
		if State.upgrades.get(u.key, false):
			b2.text = "%s — 설치됨" % u.name
			b2.disabled = true
		else:
			b2.text = "%s — %d코인 · %s" % [u.name, u.price, u.desc]
			b2.pressed.connect(func() -> void: _buy(u))
		box.add_child(b2)

func _expansion_unlocked() -> bool:
	if State.stage >= 5:
		return false
	return State.dishes_served >= int(EXPANSIONS[State.stage + 1].served)

func _buy_expansion() -> void:
	var e: Dictionary = EXPANSIONS[State.stage + 1]
	if State.money < int(e.price):
		_keeper_say("코인이 조금 모자라요")
		return
	State.add_money(-int(e.price))
	State.stage += 1
	expansion_announced = false
	_rebuild_scene()
	_on_fire_changed(State.fire_state)
	_refresh_shop()
	State.save_game()
	_keeper_say("확장 공사 완료! %s이 되었어요!" % STAGES[State.stage].name, 6.0)

func _buy(u: Dictionary) -> void:
	if State.upgrades.get(u.key, false) or State.money < int(u.price):
		if State.money < int(u.price):
			_keeper_say("코인이 조금 모자라요")
		return
	State.add_money(-int(u.price))
	State.upgrades[u.key] = true
	_rebuild_scene()
	_on_fire_changed(State.fire_state)
	_refresh_shop()
	State.save_game()
	_keeper_say("%s 설치! 역이 좋아졌어요" % u.name)

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

## ---- 루프 ----

func _process(delta: float) -> void:
	_update_rush()
	spawn_left -= delta
	if spawn_left <= 0.0:
		var r: Array = FIRE_SPAWN[State.fire_state]
		# 식당이 유명해질수록 손님 발걸음이 잦다 (단계당 -8%) + 러시 파도
		var fame := 1.0 - 0.08 * (State.stage - 1)
		if rush_active:
			fame *= 0.35
		spawn_left = randf_range(r[0], r[1]) * fame
		_spawn_customer()
	peak_conc = maxi(peak_conc, seats.size())
	ready_dish.visible = kitchen.ready_dishes > 0
	dish_stack.visible = kitchen.dirty_dishes >= 3
	prep_crate.visible = not State.pantry.is_empty() and not kitchen.boost_next_prep
	if kitchen.cooking and keeper.animation != "cook":
		keeper.play("cook")
	elif not kitchen.cooking and keeper.animation != "walk":
		keeper.play("walk")
	# 알바생이 없으면 역귀가 느리게나마 테이블을 치운다 (무벌)
	if bussers.is_empty():
		keeper_clear_left -= delta
		if keeper_clear_left <= 0.0:
			keeper_clear_left = 180.0
			for t in tables:
				if int(t.plates) > 0:
					kitchen.dirty_dishes += clear_table(t)
					break
	# 확장 해금 안내 — 목수의 방문 (전방 이벤트)
	if not expansion_announced and _expansion_unlocked():
		expansion_announced = true
		_refresh_shop()
		_keeper_say("목수가 다녀갔어요 — 확장 견적이 나왔어요! (역귀에게 말 걸기)", 6.0)
	if keeper_left > 0.0:
		keeper_left -= delta
		if keeper_left <= 0.0:
			keeper_label.text = ""

## 점심(12시)·저녁(18시) 러시 — 손님이 파도로 몰려온다 (GDD 정오의 러시)
## 시뮬에서는 _run_sim이 rush_active를 직접 제어한다.
func _update_rush() -> void:
	if OS.get_environment("WNW_SIM") != "":
		return
	var h: int = Time.get_datetime_dict_from_system().hour
	var now_rush: bool = (h == 12) or (h == 18)
	if now_rush and not rush_active:
		_keeper_say("러시 시간이에요! 다들 배가 고픈가 봐요", 4.0)
	rush_active = now_rush

func _pick_guest() -> String:
	var pool: Array = FIRE_POOL[State.fire_state].filter(
		func(g: String) -> bool: return _has_tex("%s_walk_0" % g))
	var menu_cats: Array = State.menu.map(func(r: String) -> String: return State.RECIPES.get(r, ""))
	var weights: Array = []
	var total := 0.0
	for g in pool:
		var wgt := 3.0 if menu_cats.has(FAVS.get(g, "")) else 1.0
		if g == "jaebul" and State.upgrades.get("stove", false):
			wgt *= 2.0
		weights.append(wgt)
		total += wgt
	var roll := randf() * total
	for i in pool.size():
		roll -= weights[i]
		if roll <= 0.0:
			return pool[i]
	return pool[-1]

func _spawn_customer() -> Node2D:
	var free: Array = seat_defs.filter(func(sd: Dictionary) -> bool: return not seats.has(sd.x))
	if free.is_empty():
		return null
	var sd: Dictionary = free.pick_random()
	var gname := _pick_guest()
	guest_log.append(gname)
	var c: Node2D = Node2D.new()
	c.set_script(CustomerScript)
	c.setup(_char_frames(gname, ["walk"]))
	c.position = Vector2(stage_width() + 10.0, FEET_Y - CHAR_H)
	c.seat_x = sd.x
	c.table_idx = sd.table_idx
	c.exit_x = stage_width() + 20.0
	c.kitchen = kitchen
	c.guest_name = gname
	seats[sd.x] = c
	c.left.connect(func(cust) -> void:
		seats.erase(cust.seat_x)
		_remove_food(cust))
	c.started_eating.connect(_on_customer_eating)
	c.finished_meal.connect(_on_customer_finished)
	c.paid.connect(_on_customer_paid)
	scene_root.add_child(c)
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
	if sky != null:
		sky.color = _sky_color(d.hour)

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
	State.set_fire("ember")
	ok = ok and FIRE_POOL[State.fire_state][0] == "soso"
	# 확장 왕복: 해금 → 구매 → 테이블 수·좌석 수 확인
	State.dishes_served = 25
	State.money = 500
	ok = ok and _expansion_unlocked()
	_buy_expansion()
	ok = ok and State.stage == 2 and tables.size() == 2 and seat_defs.size() == 4
	# 접시 흐름: 테이블에 쌓임 → 치우면 개수 반환
	var t: Dictionary = tables[0]
	t.plates = 3
	ok = ok and clear_table(t) == 3 and int(t.plates) == 0
	# 저장 왕복 (stage 포함)
	State.money = 123
	State.save_game("user://smoke_save.json")
	State.money = 0
	State.stage = 1
	State.load_game("user://smoke_save.json")
	ok = ok and State.money == 123 and State.stage == 2
	print("SMOKE served=%d cap=%d/12 stage_ok=%s -> %s" % [
		State.dishes_served, granted, str(State.stage == 2), "PASS" if ok else "FAIL"])
	get_tree().quit(0 if ok else 1)

func _run_shot(path: String) -> void:
	var stg := OS.get_environment("WNW_STAGE")
	if stg != "":
		State.stage = clampi(int(stg), 1, 5)
		State.upgrades = {"lantern": true, "stove": true}
		State.dishes_served = 300
		_rebuild_scene()
		_on_fire_changed(State.fire_state)
	State.add_ingredients("곡물", ["맑음"], 3)
	kitchen.ready_dishes = 2
	kitchen.dirty_dishes = 3
	kitchen.pot_servings = 8
	kitchen.dish_left = 60.0
	for i in mini(seat_defs.size(), 2 + State.stage):
		var c := _spawn_customer()
		if c != null:
			c.position.x = c.seat_x
			if i % 2 == 0:
				c.state = c.S.EATING
				c.eat_left = 100.0
				_on_customer_eating(c)
	if tables.size() >= 2:
		tables[1].plates = 3
		_update_stack(tables[1])
	State.add_money(30)
	_keeper_say("서빙 고마워요! 팁 +2")
	keeper_left = 99.0
	await get_tree().create_timer(1.0).timeout
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()

## ---- 재미 QA 시뮬레이션 (성장판) ----
func _run_sim(days: int) -> void:
	Engine.time_scale = 600.0
	State.money = 0
	State.upgrades = {}
	State.dishes_served = 0
	State.stage = 1
	_rebuild_scene()
	_on_fire_changed(State.fire_state)
	var fires := ["mid", "blue", "strong", "mid", "strong", "blue", "strong"]
	var baits := ["국밥", "볶음국수", "주먹밥", "국밥", "야식꼬치", "볶음국수", "국밥"]
	for day in days:
		print("SIMSTART day=%d stage=%d" % [day + 1, State.stage])
		State.interventions_today = 0
		State.set_fire(fires[day % fires.size()])
		State.set_menu_slot(0, baits[day % baits.size()])
		var coins0 := State.money
		var served0 := State.dishes_served
		var stage0 := State.stage
		guest_log.clear()
		clears_by_staff = 0
		clears_by_click = 0
		var walk_n := randi_range(5, 9) if State.fire_state == "mid" else randi_range(8, 12)
		State.add_ingredients("곡물", ["맑음"], walk_n)
		if State.fire_state == "blue":
			State.add_ingredients("빗물 채소", ["비", "저녁"], 3)
		var kitchen_active := 0
		var waiting_total := 0
		var seated_total := 0
		var empty_scene := 0
		var concurrent_total := 0.0
		var clicks := 0
		var bought: Array = []
		peak_conc = 0
		for s in 480:
			if s % 120 == 0:
				print("SIMTICK d%d s%d money=%d served=%d" % [day + 1, s, State.money, State.dishes_served])
			await get_tree().create_timer(60.0).timeout
			rush_active = (s >= 120 and s < 150) or (s >= 300 and s < 330)
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
			concurrent_total += seats.size()
			if seated == 0:
				empty_scene += 1
			if clicks < 10 and randf() < 0.3:
				var dirty_tables: Array = tables.filter(func(tt: Dictionary) -> bool: return int(tt.plates) > 0)
				if ready_dish.visible:
					_on_serve_click(); clicks += 1
				elif not dirty_tables.is_empty() and bussers.is_empty():
					_on_table_click(int(dirty_tables[0].idx)); clicks += 1
				elif dish_stack.visible:
					_on_dish_click(); clicks += 1
				elif prep_crate.visible:
					_on_prep_click(); clicks += 1
			# 구매 우선순위: 확장 > 가구 (여유 30코인)
			if State.stage < 5 and _expansion_unlocked() \
					and State.money >= int(EXPANSIONS[State.stage + 1].price) + 30:
				var target: String = String(STAGES[State.stage + 1].name)
				_buy_expansion()
				bought.append("확장→%s" % target)
			else:
				for u in UPGRADES:
					if not State.upgrades.get(u.key, false) and State.money >= int(u.price) + 30:
						State.add_money(-int(u.price))
						State.upgrades[u.key] = true
						bought.append(u.key)
		var gc := {}
		for g in guest_log:
			gc[g] = gc.get(g, 0) + 1
		print("SIMDAY %s" % JSON.stringify({
			"day": day + 1, "stage": "%d→%d" % [stage0, State.stage],
			"fire": State.fire_state,
			"coins": State.money - coins0, "served": State.dishes_served - served0,
			"kitchen_pct": kitchen_active * 100 / 480,
			"starve_pct": (waiting_total * 100 / seated_total) if seated_total > 0 else 0,
			"empty_pct": empty_scene * 100 / 480,
			"avg_conc": snappedf(concurrent_total / 480.0, 0.1),
			"peak_conc": peak_conc,
			"clicks": clicks, "spawns": guest_log.size(), "guests": gc,
			"staff_clears": clears_by_staff, "click_clears": clears_by_click,
			"bought": bought, "pantry_left": State.pantry.size(),
		}))
	get_tree().quit()
