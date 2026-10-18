extends CanvasLayer

# Presentation of the sim clock. Day and season are derived from the tick the
# same way the sim derives them: 7200 ticks a day, 10 days a season, day 0 of
# Sprout at tick 0. The names are the play calendar, not spring/summer/autumn.

const TICKS_PER_DAY := 7200
const DAYS_PER_SEASON := 10
const SEASONS: PackedStringArray = ["Sprout", "High Sun", "Stitchfall", "Deep Bell"]

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
	show_state(0, false, 0, "")


func _add_reason_line() -> void:
	# Own line for the sim's failure string. Nothing is prefixed onto it.
	var reason := Label.new()
	reason.name = "Reason"
	reason.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reason.set_anchors_preset(Control.PRESET_TOP_WIDE)
	reason.offset_left = 14.0
	reason.offset_top = 44.0
	reason.offset_right = -14.0
	reason.offset_bottom = 132.0
	reason.add_theme_font_size_override("font_size", 20)
	reason.add_theme_color_override("font_color", Color(0.97, 0.94, 0.86))
	reason.add_theme_color_override("font_outline_color", Color(0.10, 0.07, 0.04))
	reason.add_theme_constant_override("outline_size", 6)
	reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reason.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	reason.text = ""
	add_child(reason)


func show_state(tick: int, paused: bool, selected: int, failure_text: String) -> void:
	# `/` is float division. Tick is never negative, so truncating matches the sim's day().
	var day_index := int(float(tick) / float(TICKS_PER_DAY))
	var season_index := int(float(day_index) / float(DAYS_PER_SEASON)) % 4
	var season: String = SEASONS[season_index]
	var text := "tick %d  day %d  %s" % [tick, day_index, season]
	if paused:
		text += "  PAUSED"
	text += "  selected %d  F eat" % selected
	line.text = text
	# The sim's string is the whole line. No name, no prefix, no second wording.
	var reason := get_node_or_null("Reason") as Label
	if reason != null:
		reason.text = failure_text
		reason.visible = failure_text != ""
