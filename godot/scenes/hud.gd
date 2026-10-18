extends CanvasLayer

# Presentation of the sim clock. Day and season are derived from the tick the
# same way the sim derives them: 7200 ticks a day, 10 days a season, day 0 of
# Sprout at tick 0. The names are the play calendar, not spring/summer/autumn.
#
# The Reason label is only the sim's failure string. Carried goods, stockpile
# contents and build progress go on Detail. Nothing is prefixed onto Reason.

const TICKS_PER_DAY := 7200
const DAYS_PER_SEASON := 10
const SEASONS: PackedStringArray = ["Sprout", "High Sun", "Stitchfall", "Deep Bell"]

signal build_kind_chosen(kind: int)
signal craft_chosen(slot: int)
signal haul_asked
signal take_asked
signal heal_asked
signal sleep_asked

var _build_buttons: Array = []

@onready var line: Label = $Line


func _ready() -> void:
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.set_anchors_preset(Control.PRESET_TOP_WIDE)
	line.offset_left = 14.0
	line.offset_top = 8.0
	line.offset_right = -14.0
	line.offset_bottom = 42.0
	line.add_theme_font_size_override("font_size", 20)
	line.add_theme_color_override("font_color", Color(0.97, 0.94, 0.86))
	line.add_theme_color_override("font_outline_color", Color(0.10, 0.07, 0.04))
	line.add_theme_constant_override("outline_size", 6)
	line.autowrap_mode = TextServer.AUTOWRAP_OFF
	line.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_add_reason_line()
	_add_detail_line()
	_add_bar()
	show_state(0, false, 0, "")
	show_detail("")


func _add_reason_line() -> void:
	# Own line for the sim's failure string. Nothing is prefixed onto it.
	var reason := Label.new()
	reason.name = "Reason"
	reason.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reason.set_anchors_preset(Control.PRESET_TOP_WIDE)
	reason.offset_left = 14.0
	reason.offset_top = 44.0
	reason.offset_right = -14.0
	reason.offset_bottom = 80.0
	reason.add_theme_font_size_override("font_size", 20)
	reason.add_theme_color_override("font_color", Color(0.97, 0.94, 0.86))
	reason.add_theme_color_override("font_outline_color", Color(0.10, 0.07, 0.04))
	reason.add_theme_constant_override("outline_size", 6)
	reason.autowrap_mode = TextServer.AUTOWRAP_OFF
	reason.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	reason.text = ""
	add_child(reason)


func _add_detail_line() -> void:
	var detail := Label.new()
	detail.name = "Detail"
	detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	detail.offset_left = -460.0
	detail.offset_top = 8.0
	detail.offset_right = -14.0
	detail.offset_bottom = 320.0
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	detail.add_theme_font_size_override("font_size", 20)
	detail.add_theme_color_override("font_color", Color(0.97, 0.94, 0.86))
	detail.add_theme_color_override("font_outline_color", Color(0.10, 0.07, 0.04))
	detail.add_theme_constant_override("outline_size", 6)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	detail.text = ""
	add_child(detail)


func _add_bar() -> void:
	var bar := HBoxContainer.new()
	bar.name = "Bar"
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_left = 12.0
	bar.offset_top = -52.0
	bar.offset_right = -12.0
	bar.offset_bottom = -10.0
	bar.add_theme_constant_override("separation", 8)
	add_child(bar)
	var buildings := ["campfire", "lean-to", "stockpile"]
	for i in buildings.size():
		var button := _button(buildings[i])
		button.pressed.connect(_on_build.bind(i))
		bar.add_child(button)
		_build_buttons.append(button)
	bar.add_child(_gap())
	var recipes := ["knife", "meal", "bandage"]
	for i in recipes.size():
		var button := _button(recipes[i])
		button.pressed.connect(_on_craft.bind(i))
		bar.add_child(button)
	bar.add_child(_gap())
	var haul := _button("haul")
	haul.pressed.connect(func() -> void: haul_asked.emit())
	bar.add_child(haul)
	var take := _button("take")
	take.pressed.connect(func() -> void: take_asked.emit())
	bar.add_child(take)
	bar.add_child(_gap())
	var heal := _button("heal")
	heal.name = "Heal"
	heal.pressed.connect(func() -> void: heal_asked.emit())
	bar.add_child(heal)
	var sleep := _button("sleep")
	sleep.pressed.connect(func() -> void: sleep_asked.emit())
	bar.add_child(sleep)


func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.custom_minimum_size = Vector2(108.0, 36.0)
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", Color(0.16, 0.10, 0.05))
	button.add_theme_color_override("font_hover_color", Color(0.16, 0.10, 0.05))
	return button


func _gap() -> Control:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(16.0, 0.0)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return gap


func _on_build(kind: int) -> void:
	build_kind_chosen.emit(kind)


func _on_craft(slot: int) -> void:
	craft_chosen.emit(slot)


func set_build_highlight(kind: int) -> void:
	for i in _build_buttons.size():
		var button: Button = _build_buttons[i]
		button.modulate = Color(1.0, 0.82, 0.28) if i == kind else Color.WHITE


func set_heal_highlight(on: bool) -> void:
	var heal := get_node_or_null("Bar/Heal") as Button
	if heal != null:
		heal.modulate = Color(1.0, 0.82, 0.28) if on else Color.WHITE


func show_state(tick: int, paused: bool, selected: int, failure_text: String) -> void:
	# `/` is float division. Tick is never negative, so truncating matches the sim's day().
	var day_index := int(float(tick) / float(TICKS_PER_DAY))
	var season_index := int(float(day_index) / float(DAYS_PER_SEASON)) % 4
	var season: String = SEASONS[season_index]
	var text := "tick %d  day %d  season %s" % [tick, day_index, season]
	if paused:
		text += "  PAUSED"
	text += "  selected %d  B build  C craft  H haul  T take  F eat  J heal  R sleep" % selected
	line.text = text
	# The sim's string is the whole line. No name, no prefix, no second wording.
	var reason := get_node_or_null("Reason") as Label
	if reason != null:
		reason.text = failure_text
		reason.visible = failure_text != ""


func show_detail(text: String) -> void:
	var detail := get_node_or_null("Detail") as Label
	if detail == null:
		return
	detail.text = text
	detail.visible = text != ""
