extends PanelContainer
## 산책 수첩 (P1: 디버그 패널 겸용 — GDD §7).
## 목업 걸음을 기입해 재료를 주입한다. F1 토글.

func _ready() -> void:
	visible = false
	position = Vector2(4, 22)
	var box := VBoxContainer.new()
	add_child(box)
	var title := Label.new()
	title.text = "산책 수첩 (F1)"
	box.add_child(title)
	box.add_child(_walk_button("5,000보 걷기 (맑음)", "곡물", ["맑음"], 5))
	box.add_child(_walk_button("3,000보 걷기 (비·저녁)", "빗물 채소", ["비", "저녁"], 3))
	var pantry_label := Label.new()
	pantry_label.name = "PantryLabel"
	box.add_child(pantry_label)
	State.pantry_changed.connect(func() -> void:
		pantry_label.text = "재료 창고: %d" % State.pantry.size())
	pantry_label.text = "재료 창고: 0"

func _walk_button(label: String, ing_name: String, tags: Array, count: int) -> Button:
	var b := Button.new()
	b.text = label
	b.pressed.connect(func() -> void:
		State.add_ingredients(ing_name, tags, count))
	return b

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F1:
		visible = not visible
