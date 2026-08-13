extends PanelContainer
## 산책 수첩 (P1: 디버그 패널 겸용 — GDD §7). F1 토글.
## 목업 걸음 기입 + 화력 4상태 슬라이더 스텁 + 초대장 다시 보기.

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
	box.add_child(pantry_label)
	State.pantry_changed.connect(func() -> void:
		pantry_label.text = "재료 창고: %d" % State.pantry.size())
	pantry_label.text = "재료 창고: %d" % State.pantry.size()
	# 화력 스텁 — 디버그 전환 (감쇠는 P2)
	var fire_row := HBoxContainer.new()
	box.add_child(fire_row)
	for s in [["잉걸불", "ember"], ["중불", "mid"], ["센불", "strong"], ["푸른불", "blue"]]:
		var b := Button.new()
		b.text = s[0]
		b.pressed.connect(func() -> void: State.set_fire(s[1]))
		fire_row.add_child(b)
	var invite := Button.new()
	invite.text = "초대장 보기"
	invite.pressed.connect(func() -> void:
		get_tree().current_scene.invite_panel.show())
	box.add_child(invite)

func _walk_button(label: String, ing_name: String, tags: Array, count: int) -> Button:
	var b := Button.new()
	b.text = label
	b.pressed.connect(func() -> void:
		State.add_ingredients(ing_name, tags, count))
	return b

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F1:
		visible = not visible
