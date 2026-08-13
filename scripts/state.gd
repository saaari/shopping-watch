extends Node
## 전역 상태 + 저장. autoload 이름: State

signal money_changed(value: int)
signal pantry_changed
signal keeper_says(text: String)
signal fire_changed(state: String)
signal menu_changed

const INTERVENTION_CAP := 10  # 개입 하루 상한 (GDD §3.4-②)
const SAVE_PATH := "user://save.json"

## 레시피 목업 8종 — 계열이 미끼(손님 편향)를 결정 (GDD §4.4)
const RECIPES := {
	"주먹밥": "아침", "아침죽": "아침",
	"미역국": "국물", "국밥": "국물",
	"볶음국수": "볶음", "채소볶음": "볶음",
	"야식꼬치": "야식", "사과파이": "간식",
}

var money: int = 0
var pantry: Array[Dictionary] = []  # {name: String, tags: Array}
var interventions_today: int = 0
var dishes_served: int = 0
var fire_state: String = "mid"      # ember/mid/strong/blue (P1: 슬라이더 스텁, 감쇠 비구현)
var menu: Array = ["주먹밥", "국밥", "볶음국수"]  # 메뉴판 3칸
var upgrades: Dictionary = {}       # lantern/stove/table3 -> true

func add_money(v: int) -> void:
	money += v
	money_changed.emit(money)

func add_ingredients(name: String, tags: Array, count: int) -> void:
	for i in count:
		pantry.append({"name": name, "tags": tags})
	pantry_changed.emit()

func take_ingredient() -> Dictionary:
	if pantry.is_empty():
		return {}
	var ing: Dictionary = pantry.pop_front()
	pantry_changed.emit()
	return ing

## 개입 시도. 상한 도달 시 벌 없이 역귀가 받아 간다 (철칙).
func try_intervene() -> bool:
	if interventions_today >= INTERVENTION_CAP:
		keeper_says.emit("오늘은 제가 할게요. 좀 쉬세요.")
		return false
	interventions_today += 1
	return true

func set_fire(s: String) -> void:
	fire_state = s
	fire_changed.emit(s)

func set_menu_slot(i: int, recipe: String) -> void:
	menu[i] = recipe
	menu_changed.emit()

## ---- 저장/불러오기 (상시 저장 계약 — 강제 종료 = 퇴근 버튼과 동일) ----

func save_game(path: String = SAVE_PATH) -> void:
	var d := {
		"money": money, "pantry": pantry, "dishes_served": dishes_served,
		"interventions_today": interventions_today,
		"day": Time.get_date_string_from_system(),
		"fire_state": fire_state, "menu": menu, "upgrades": upgrades,
		"last_ts": Time.get_unix_time_from_system(),
	}
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))

## 반환: 부재 시간(초). 저장이 없으면 -1.
func load_game(path: String = SAVE_PATH) -> float:
	if not FileAccess.file_exists(path):
		return -1.0
	var d = JSON.parse_string(FileAccess.open(path, FileAccess.READ).get_as_text())
	if typeof(d) != TYPE_DICTIONARY:
		return -1.0
	money = int(d.get("money", 0))
	var arr: Array[Dictionary] = []
	for it in d.get("pantry", []):
		arr.append(it)
	pantry = arr
	dishes_served = int(d.get("dishes_served", 0))
	# 개입 상한은 하루 단위 — 날짜가 바뀌었으면 리셋
	if d.get("day", "") == Time.get_date_string_from_system():
		interventions_today = int(d.get("interventions_today", 0))
	else:
		interventions_today = 0
	fire_state = str(d.get("fire_state", "mid"))
	menu = d.get("menu", menu)
	upgrades = d.get("upgrades", {})
	money_changed.emit(money)
	pantry_changed.emit()
	return maxf(0.0, Time.get_unix_time_from_system() - float(d.get("last_ts", 0)))
