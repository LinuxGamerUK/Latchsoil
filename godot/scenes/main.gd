extends Node3D

# Milestone 1a blockout. Godot presents; the sim decides.
# Time advances only through frame(). This scene never calls step.

const HOST_CLASS := "SimHost"
const SEED := 1
const REQUIRED: PackedStringArray = [
	"new_game", "attach", "frame", "poll", "set_paused",
	"submit_move", "submit_gather", "submit_eat",
]

var host: Object
var owner_id := 0
var running := false
var paused := false
var selection: Array = []
var rejects: Dictionary = {}
var last_snap: Dictionary = {}
var grain_id := -1
var _frame_budget := -1
var _shot_path := ""
var _shot_left := 0
var _reported := false
var _keys_checked := false
var _warned := {}

@onready var view: Node3D = $World
@onready var hud: CanvasLayer = $HUD
@onready var camera: Camera3D = $CameraRig/Camera3D


func _ready() -> void:
	_dress_light()
	_read_frame_budget()
	_read_screenshot()
	_boot_sim()


func _process(delta: float) -> void:
	if not running:
		return
	host.call("frame", delta)
	var snap = host.call("poll", owner_id)
	if snap is Dictionary and _int_of(snap.get("error", 0), -1) == 0:
		last_snap = snap
		_check_keys(snap)
		_prune_selection(snap)
		view.apply_snapshot(snap, selection, rejects)
		if not _reported:
			_reported = true
			print("latchsoil: holding tick %d people %d nodes %d" % [
				_int_of(snap.get("tick", 0), 0),
				_count(snap.get("people", [])),
				_count(snap.get("nodes", [])),
			])
	elif snap is Dictionary:
		_warn_once("poll_error", "latchsoil: poll error %s" % str(snap.get("error", "")))
	else:
		_warn_once("poll_type", "latchsoil: poll did not return a dictionary")
	_apply_sun()
	_refresh_hud()
	if _shot_left > 0:
		_shot_left -= 1
		if _shot_left == 0:
			_capture_screenshot()
			return
	if _frame_budget > 0:
		_frame_budget -= 1
		if _frame_budget == 0:
			get_tree().quit(0)


func _unhandled_input(event: InputEvent) -> void:
	if not running:
		return
	if event is InputEventMouseButton and event.pressed:
		_on_click(event)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			paused = not paused
			host.call("set_paused", paused)
			_refresh_hud()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F:
			_order_eat()
			get_viewport().set_input_as_handled()


func _dress_light() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.86, 0.73, 0.55)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.64, 0.80)
	env.ambient_light_energy = 0.5
	$WorldEnvironment.environment = env
	$Sun.rotation_degrees = Vector3(-50.0, -38.0, 0.0)
	$Fill.rotation_degrees = Vector3(-22.0, 150.0, 0.0)
	_apply_sun()
	# A headless dummy renderer has nothing to shadow. The play machine keeps them.
	if DisplayServer.get_name() == "headless":
		$Sun.shadow_enabled = false


func _boot_sim() -> void:
	if not ClassDB.class_exists(HOST_CLASS):
		_fail(3, "latchsoil: the extension did not load (SimHost is not registered)")
		return
	var host_node := ClassDB.instantiate(HOST_CLASS) as Node
	if host_node == null:
		_fail(3, "latchsoil: SimHost did not instantiate as a node")
		return
	host_node.name = "SimHost"
	host = host_node
	add_child(host_node)
	var missing := PackedStringArray()
	for method_name in REQUIRED:
		if not host.has_method(method_name):
			missing.append(method_name)
	if missing.size() > 0:
		_fail(2, "latchsoil: SimHost is missing contract methods: %s" % _csv(missing))
		return
	host.call("new_game", SEED)
	paused = false
	var attached = host.call("attach")
	if not (attached is int or attached is float) or int(attached) == 0:
		_fail(2, "latchsoil: attach failed")
		return
	owner_id = int(attached)
	_read_catalog()
	running = true


func _read_catalog() -> void:
	if not host.has_method("catalog"):
		_warn_once("catalog", "latchsoil: catalog() is not on SimHost")
		return
	var cat = host.call("catalog")
	if not cat is Dictionary:
		_warn_once("catalog_shape", "latchsoil: catalog() did not return a dictionary")
		return
	var items = cat.get("items", [])
	if not items is Array:
		_warn_once("catalog_items", "latchsoil: catalog items is not an array")
		return
	grain_id = _grain_id(items)
	if view.has_method("set_item_names"):
		view.set_item_names(items)


func _grain_id(items: Array) -> int:
	var exact := -1
	var fuzzy: Array = []
	for row in items:
		if not row is Dictionary:
			continue
		var item_name := str(row.get("name", "")).to_lower().strip_edges()
		var id := _int_of(row.get("id", -1), -1)
		if id < 0:
			continue
		if item_name == "grain":
			exact = id
		elif "grain" in item_name:
			fuzzy.append(id)
	if exact >= 0:
		return exact
	if fuzzy.size() == 1:
		return int(fuzzy[0])
	return -1


func _on_click(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_LEFT:
		var person: Dictionary = view.pick_person(camera, event.position)
		if not person.is_empty():
			_select(_int_of(person.get("index", -1), -1), _int_of(person.get("generation", -1), -1), event.shift_pressed)
		elif not event.shift_pressed:
			selection.clear()
			_refresh_view()
		get_viewport().set_input_as_handled()
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		var node: Dictionary = view.pick_node(camera, event.position)
		if not node.is_empty():
			_order_gather(_int_of(node.get("index", -1), -1), _int_of(node.get("generation", -1), -1))
		else:
			var point = view.pick_ground(camera, event.position)
			if point is Vector3:
				_order_move(point)
		get_viewport().set_input_as_handled()


func _select(index: int, generation: int, add: bool) -> void:
	if index < 0:
		return
	if not add:
		selection.clear()
	if _find_sel(index, generation) < 0:
		selection.append({"index": index, "generation": generation})
	_refresh_view()


func _order_move(point: Vector3) -> void:
	for sel in selection:
		var index := _int_of(sel.get("index", -1), -1)
		var generation := _int_of(sel.get("generation", -1), -1)
		var result = host.call("submit_move", index, generation, point.x, point.z)
		_note_submit(_id_key(index, generation), result)
	_refresh_view()


func _order_gather(node_index: int, node_generation: int) -> void:
	for sel in selection:
		var index := _int_of(sel.get("index", -1), -1)
		var generation := _int_of(sel.get("generation", -1), -1)
		var result = host.call("submit_gather", index, generation, node_index, node_generation)
		_note_submit(_id_key(index, generation), result)
	_refresh_view()


func _order_eat() -> void:
	if grain_id < 0:
		# No invented ItemId. A missing grain row is not a failure string.
		_warn_once("grain", "latchsoil: catalog has no grain item; eat was not submitted")
		return
	for sel in selection:
		var index := _int_of(sel.get("index", -1), -1)
		var generation := _int_of(sel.get("generation", -1), -1)
		var result = host.call("submit_eat", index, generation, grain_id)
		_note_submit(_id_key(index, generation), result)
		if (result is int or result is float) and int(result) == 0 and view.has_method("note_eat"):
			view.call("note_eat", index, generation, _int_of(last_snap.get("tick", 0), 0))
	_refresh_view()


func _note_submit(key: String, result) -> void:
	if result is int or result is float:
		if int(result) != 0:
			rejects[key] = true
		else:
			rejects.erase(key)
	else:
		_warn_once("submit_return", "latchsoil: a submit method did not return an int code")


func _prune_selection(snap: Dictionary) -> void:
	# A dirty pull lists only changed rows. Dropping the rest would clear a live selection.
	if not bool(snap.get("full", false)):
		return
	var people = snap.get("people", [])
	if not people is Array:
		return
	var live := {}
	for row in people:
		if row is Dictionary:
			live[_id_key(_int_of(row.get("index", -1), -1), _int_of(row.get("generation", -1), -1))] = true
	var kept: Array = []
	for sel in selection:
		var key := _id_key(_int_of(sel.get("index", -1), -1), _int_of(sel.get("generation", -1), -1))
		if live.has(key):
			kept.append(sel)
		else:
			rejects.erase(key)
	selection = kept


func _refresh_view() -> void:
	if not last_snap.is_empty() and view.has_method("apply_snapshot"):
		view.apply_snapshot(last_snap, selection, rejects)
	_refresh_hud()


func _refresh_hud() -> void:
	if hud == null or not hud.has_method("show_state"):
		return
	hud.show_state(_int_of(last_snap.get("tick", 0), 0), paused, selection.size(), _failure_text())


func _failure_text() -> String:
	var people = last_snap.get("people", [])
	if not people is Array:
		return ""
	# A selection prints only those people's failure_text. Empty means no line.
	# Scan everyone only when nothing is selected. Never reassign a reason.
	if not selection.is_empty():
		for sel in selection:
			if not sel is Dictionary:
				continue
			var text := _failure_of(people, _int_of(sel.get("index", -1), -1), _int_of(sel.get("generation", -1), -1))
			if text != "":
				return text
		return ""
	for row in people:
		if row is Dictionary:
			var text := str(row.get("failure_text", ""))
			if text != "":
				return text
	return ""


func _failure_of(people: Array, index: int, generation: int) -> String:
	for row in people:
		if row is Dictionary and _int_of(row.get("index", -1), -1) == index and _int_of(row.get("generation", -1), -1) == generation:
			return str(row.get("failure_text", ""))
	return ""


func _check_keys(snap: Dictionary) -> void:
	if _keys_checked:
		return
	_keys_checked = true
	var top := ["tick", "people", "buildings", "nodes", "removed", "hash", "full", "error"]
	var missing := PackedStringArray()
	for key in top:
		if not snap.has(key):
			missing.append(key)
	if missing.size() > 0:
		push_error("latchsoil: snapshot missing keys: %s" % _csv(missing))
	_check_row_keys(snap.get("people", []), "person", [
		"index", "generation", "x", "y", "hunger", "thirst", "health",
		"job", "failure", "failure_text", "drafted", "carried", "path", "dest", "target",
	])
	_check_row_keys(snap.get("nodes", []), "node", [
		"index", "generation", "x", "y", "remaining", "yield_item",
	])


func _check_row_keys(rows, label: String, keys: Array) -> void:
	if not rows is Array or rows.is_empty() or not rows[0] is Dictionary:
		return
	var missing := PackedStringArray()
	for key in keys:
		if not rows[0].has(key):
			missing.append(str(key))
	if missing.size() > 0:
		push_error("latchsoil: %s snapshot missing keys: %s" % [label, _csv(missing)])


func _read_frame_budget() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if str(args[i]) == "--frames" and i + 1 < args.size():
			_frame_budget = int(str(args[i + 1]))
			return


func _read_screenshot() -> void:
	# Unset means the scene runs exactly as before. The render script sets the path.
	var path := OS.get_environment("LATCHSOIL_SCREENSHOT")
	if path == "":
		return
	_shot_path = path
	var raw := OS.get_environment("LATCHSOIL_SCREENSHOT_FRAMES")
	var frames := 30
	if raw != "":
		frames = int(raw)
	_shot_left = maxi(frames, 2)


func _capture_screenshot() -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		push_error("latchsoil: screenshot viewport was empty")
		get_tree().quit(1)
		return
	var err := image.save_png(_shot_path)
	if err != OK:
		push_error("latchsoil: screenshot save failed")
		get_tree().quit(1)
		return
	print("latchsoil: screenshot %s" % _shot_path)
	get_tree().quit(0)


func _apply_sun() -> void:
	# The sim clock drives the key light. Night is the last fifth of the day.
	var tick := _int_of(last_snap.get("tick", 0), 0)
	$Sun.light_energy = 0.35 if tick % 7200 >= 5760 else 1.3


func _find_sel(index: int, generation: int) -> int:
	for i in selection.size():
		if _int_of(selection[i].get("index", -1), -1) == index and _int_of(selection[i].get("generation", -1), -1) == generation:
			return i
	return -1


func _id_key(index: int, generation: int) -> String:
	return "%d:%d" % [index, generation]


func _count(rows) -> int:
	if rows is Array:
		return rows.size()
	return 0


func _int_of(value, fallback: int) -> int:
	if value is int or value is float:
		return int(value)
	return fallback


func _csv(parts: PackedStringArray) -> String:
	var text := ""
	for i in parts.size():
		if i > 0:
			text += ", "
		text += parts[i]
	return text


func _warn_once(key: String, message: String) -> void:
	if _warned.has(key):
		return
	_warned[key] = true
	push_warning(message)


func _fail(code: int, message: String) -> void:
	running = false
	set_process(false)
	push_error(message)
	get_tree().quit(code)
