extends Node
## 전역 상태 (P1 최소). autoload 이름: State

signal money_changed(value: int)
signal pantry_changed
signal keeper_says(text: String)

const INTERVENTION_CAP := 10  # 개입 하루 상한 (GDD §3.4-②)

var money: int = 0
var pantry: Array[Dictionary] = []  # {name: String, tags: Array}
var interventions_today: int = 0
var dishes_served: int = 0

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

## 개입 시도. 상한 안이면 카운트하고 true.
## 상한 도달 시 벌 없이 역귀가 받아 간다 (철칙 — 클릭이 무효가 될 뿐 손해 없음).
func try_intervene() -> bool:
	if interventions_today >= INTERVENTION_CAP:
		keeper_says.emit("오늘은 제가 할게요. 좀 쉬세요.")
		return false
	interventions_today += 1
	return true
