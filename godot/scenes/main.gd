extends Node3D

# Milestone 1b blockout. Godot presents; the sim decides.
# Time advances only through frame(). This scene never calls step.

const HOST_CLASS := "SimHost"
const SEED := 1
const BUILD_TICKS := 60
const KIND_STOCKPILE := 2
const RECIPE_NAMES: PackedStringArray = ["knife", "meal", "bandage"]
const BUILDING_NAMES: PackedStringArray = ["campfire", "lean-to", "stockpile"]
const ITEM_FALLBACK: PackedStringArray = ["grain", "wood", "stone", "fiber", "water", "knife", "meal", "bandage"]
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
var item_names: Dictionary = {}
var recipe_names: Dictionary = {}
var build_mode := false
var craft_mode := false
var build_kind := 0
var building_sel: Dictionary = {}
var armed_carry_id := -1
var armed_store_id := -1
var ghost_point = null
var _ghost_shown := false
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
	if hud.has_signal("build_kind_chosen"):
		hud.build_kind_chosen.connect(_on_build_kind)
		hud.craft_chosen.connect(_on_craft_slot)
		hud.haul_asked.connect(_on_haul_asked)
		hud.take_asked.connect(_on_take_asked)
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
	_track_ghost()
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
		elif event.keycode == KEY_B:
			_toggle_build()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_C:
			_toggle_craft()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			_exit_modes()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_H:
			_on_haul_asked()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_T:
			_on_take_asked()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_G:
			_cycle_carry(1)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_V:
			_cycle_store(1)
			get_viewport().set_input_as_handled()
		elif event.keycode >= KEY_1 and event.keycode <= KEY_3:
			_on_number(event.keycode - KEY_1)
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
	_store_names(items, item_names)
	var recipes = cat.get("recipes", [])
	if recipes is Array:
		_store_names(recipes, recipe_names)
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
		if build_mode:
			_place_at_click(event.position)
			get_viewport().set_input_as_handled()
			return
		var person: Dictionary = view.pick_person(camera, event.position)
		if not person.is_empty():
			_select(_int_of(person.get("index", -1), -1), _int_of(person.get("generation", -1), -1), event.shift_pressed)
		else:
			var building: Dictionary = view.pick_building(camera, event.position)
			if not building.is_empty():
				_select_building(building)
			elif not event.shift_pressed:
				selection.clear()
				_clear_building()
				_refresh_view()
		get_viewport().set_input_as_handled()
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		if build_mode or craft_mode:
			_exit_modes()
			get_viewport().set_input_as_handled()
			return
		var building: Dictionary = view.pick_building(camera, event.position)
		if not building.is_empty() and _kind_of(building) == KIND_STOCKPILE:
			if event.shift_pressed:
				_order_take_from(building)
			else:
				_order_haul_to(building)
		else:
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


func _toggle_build() -> void:
	build_mode = not build_mode
	if build_mode:
		craft_mode = false
	_refresh_hud()


func _toggle_craft() -> void:
	craft_mode = not craft_mode
	if craft_mode:
		build_mode = false
	_refresh_hud()


func _exit_modes() -> void:
	build_mode = false
	craft_mode = false
	_refresh_hud()


func _on_number(slot: int) -> void:
	if build_mode:
		build_kind = slot
		_refresh_hud()
	elif craft_mode:
		_order_craft(slot)
		craft_mode = false
		_refresh_hud()


func _on_build_kind(kind: int) -> void:
	build_kind = kind
	build_mode = true
	craft_mode = false
	_refresh_hud()


func _on_craft_slot(slot: int) -> void:
	_order_craft(slot)


func _on_haul_asked() -> void:
	_order_haul_to(building_sel)


func _on_take_asked() -> void:
	_order_take_from(building_sel)


func _place_at_click(mouse: Vector2) -> void:
	var at = ghost_point
	if not at is Vector3:
		var point = view.pick_ground(camera, mouse)
		if not point is Vector3:
			return
		at = view.snap_point(point)
	_order_place(at)


func _order_place(at: Vector3) -> void:
	if selection.is_empty():
		_warn_once("place_actor", "latchsoil: place needs a selected person")
		return
	var sel = selection[0]
	var index := _int_of(sel.get("index", -1), -1)
	var generation := _int_of(sel.get("generation", -1), -1)
	var result = _submit("submit_place", [index, generation, build_kind, at.x, at.z])
	if result != null:
		_note_submit(_id_key(index, generation), result)
	_refresh_view()


func _order_craft(slot: int) -> void:
	if slot < 0 or slot >= RECIPE_NAMES.size():
		return
	if selection.is_empty():
		_warn_once("craft_actor", "latchsoil: craft needs a selected person")
		return
	var recipe_id := _recipe_id(slot)
	for sel in selection:
		var index := _int_of(sel.get("index", -1), -1)
		var generation := _int_of(sel.get("generation", -1), -1)
		var result = _submit("submit_craft", [index, generation, recipe_id])
		if result != null:
			_note_submit(_id_key(index, generation), result)
	_refresh_view()


func _order_haul_to(target: Dictionary) -> void:
	if target.is_empty() or _kind_of(target) != KIND_STOCKPILE:
		_warn_once("haul_target", "latchsoil: haul needs a stockpile")
		return
	_sync_arms()
	if armed_carry_id < 0:
		_warn_once("haul_item", "latchsoil: haul needs a carried item")
		return
	if selection.is_empty():
		_warn_once("haul_actor", "latchsoil: haul needs a selected person")
		return
	var to_index := _int_of(target.get("index", -1), -1)
	var to_generation := _int_of(target.get("generation", -1), -1)
	for sel in selection:
		var index := _int_of(sel.get("index", -1), -1)
		var generation := _int_of(sel.get("generation", -1), -1)
		var result = _submit("submit_haul", [index, generation, armed_carry_id, to_index, to_generation])
		if result != null:
			_note_submit(_id_key(index, generation), result)
	_refresh_view()


func _order_take_from(target: Dictionary) -> void:
	var row := _building_by_id(target)
	if row.is_empty() or _int_of(row.get("kind", -1), -1) != KIND_STOCKPILE:
		_warn_once("take_target", "latchsoil: take needs a stockpile")
		return
	if selection.is_empty():
		_warn_once("take_actor", "latchsoil: take needs a selected person")
		return
	var goods := _goods(row.get("contents", []))
	var item_id := armed_store_id
	if not _goods_has(goods, item_id):
		item_id = int(goods[0]["id"]) if not goods.is_empty() else -1
	if item_id < 0:
		_warn_once("take_item", "latchsoil: take needs a stored item")
		return
	armed_store_id = item_id
	var from_index := _int_of(target.get("index", -1), -1)
	var from_generation := _int_of(target.get("generation", -1), -1)
	for sel in selection:
		var index := _int_of(sel.get("index", -1), -1)
		var generation := _int_of(sel.get("generation", -1), -1)
		var result = _submit("submit_take", [index, generation, item_id, from_index, from_generation])
		if result != null:
			_note_submit(_id_key(index, generation), result)
	_refresh_view()


func _submit(method: String, args: Array):
	if host == null or not host.has_method(method):
		_warn_once(method, "latchsoil: %s is not on SimHost" % method)
		return null
	return host.callv(method, args)


func _select_building(pick: Dictionary) -> void:
	building_sel = {
		"index": _int_of(pick.get("index", -1), -1),
		"generation": _int_of(pick.get("generation", -1), -1),
	}
	_refresh_view()


func _clear_building() -> void:
	building_sel = {}


func _cycle_carry(step: int) -> void:
	var person := _first_selected_person()
	var goods := _goods(person.get("carried", [])) if not person.is_empty() else []
	if goods.is_empty():
		return
	var index := _goods_index(goods, armed_carry_id)
	if index < 0:
		index = 0
	else:
		index = posmod(index + step, goods.size())
	armed_carry_id = int(goods[index]["id"])
	_refresh_hud()


func _cycle_store(step: int) -> void:
	var row := _building_by_id(building_sel)
	var goods := _goods(row.get("contents", [])) if not row.is_empty() else []
	if goods.is_empty():
		return
	var index := _goods_index(goods, armed_store_id)
	if index < 0:
		index = 0
	else:
		index = posmod(index + step, goods.size())
	armed_store_id = int(goods[index]["id"])
	_refresh_hud()


func _track_ghost() -> void:
	if not build_mode or not view.has_method("show_ghost"):
		if _ghost_shown and view.has_method("hide_ghost"):
			view.hide_ghost()
		_ghost_shown = false
		ghost_point = null
		return
	var point = view.pick_ground(camera, get_viewport().get_mouse_position())
	if not point is Vector3:
		return
	var snapped: Vector3 = view.snap_point(point)
	ghost_point = snapped
	view.show_ghost(build_kind, snapped)
	_ghost_shown = true


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
	if view.has_method("clear_building_focus"):
		if building_sel.is_empty():
			view.clear_building_focus()
		else:
			view.set_building_focus(_int_of(building_sel.get("index", -1), -1), _int_of(building_sel.get("generation", -1), -1))
	if not last_snap.is_empty() and view.has_method("apply_snapshot"):
		view.apply_snapshot(last_snap, selection, rejects)
	_refresh_hud()


func _refresh_hud() -> void:
	if hud == null or not hud.has_method("show_state"):
		return
	_sync_arms()
	hud.show_state(_int_of(last_snap.get("tick", 0), 0), paused, selection.size(), _failure_text())
	if hud.has_method("show_detail"):
		hud.show_detail(_detail_text())
	if hud.has_method("set_build_highlight"):
		hud.set_build_highlight(build_kind if build_mode else -1)


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


func _detail_text() -> String:
	var lines := PackedStringArray()
	var carry := _carry_line()
	if carry != "":
		lines.append(carry)
	if not selection.is_empty() and armed_carry_id >= 0:
		lines.append("haul %s" % _item_name(armed_carry_id))
	var building := _building_by_id(building_sel)
	if not building.is_empty():
		lines.append(_progress_line(building))
		if _int_of(building.get("kind", -1), -1) == KIND_STOCKPILE:
			lines.append(_holds_line(building))
			if armed_store_id >= 0:
				lines.append("take %s" % _item_name(armed_store_id))
	if build_mode:
		lines.append("placing %s" % _building_name(build_kind))
	if craft_mode:
		lines.append("craft  1 %s  2 %s  3 %s" % [RECIPE_NAMES[0], RECIPE_NAMES[1], RECIPE_NAMES[2]])
	return "\n".join(lines)


func _carry_line() -> String:
	var bits := PackedStringArray()
	for sel in selection:
		if not sel is Dictionary:
			continue
		var person := _person_by_id(sel)
		if person.is_empty():
			continue
		var goods := _goods(person.get("carried", []))
		if goods.is_empty():
			bits.append("nothing")
		else:
			bits.append(", ".join(_goods_text(goods)))
	if bits.is_empty():
		return ""
	return "carries " + " · ".join(bits)


func _progress_line(row: Dictionary) -> String:
	var name := _building_name(_int_of(row.get("kind", -1), -1))
	if not row.has("progress"):
		return name
	return "%s %d/%d" % [name, _int_of(row.get("progress", 0), 0), BUILD_TICKS]


func _holds_line(row: Dictionary) -> String:
	var goods := _goods(row.get("contents", []))
	if goods.is_empty():
		return "holds nothing"
	return "holds " + ", ".join(_goods_text(goods))


func _sync_arms() -> void:
	var person := _first_selected_person()
	var carried := _goods(person.get("carried", [])) if not person.is_empty() else []
	if not _goods_has(carried, armed_carry_id):
		armed_carry_id = int(carried[0]["id"]) if not carried.is_empty() else -1
	var building := _building_by_id(building_sel)
	var stored: Array = []
	if not building.is_empty() and _int_of(building.get("kind", -1), -1) == KIND_STOCKPILE:
		stored = _goods(building.get("contents", []))
	if not _goods_has(stored, armed_store_id):
		armed_store_id = int(stored[0]["id"]) if not stored.is_empty() else -1


func _goods(value) -> Array:
	var out: Array = []
	if not value is Array or value.is_empty():
		return out
	if value[0] is Array or value[0] is PackedInt32Array:
		for pair in value:
			if (pair is Array or pair is PackedInt32Array) and pair.size() >= 2:
				var count := _int_of(pair[1], 0)
				if count > 0:
					out.append({"id": _int_of(pair[0], -1), "count": count})
		return out
	var i := 0
	while i + 1 < value.size():
		var count := _int_of(value[i + 1], 0)
		if count > 0:
			out.append({"id": _int_of(value[i], -1), "count": count})
		i += 2
	return out


func _goods_text(goods: Array) -> PackedStringArray:
	var parts := PackedStringArray()
	for pair in goods:
		parts.append("%s %d" % [_item_name(int(pair["id"])), int(pair["count"])])
	return parts


func _goods_has(goods: Array, item_id: int) -> bool:
	return _goods_index(goods, item_id) >= 0


func _goods_index(goods: Array, item_id: int) -> int:
	for i in goods.size():
		if int(goods[i]["id"]) == item_id:
			return i
	return -1


func _first_selected_person() -> Dictionary:
	if selection.is_empty() or not selection[0] is Dictionary:
		return {}
	return _person_by_id(selection[0])


func _person_by_id(pick: Dictionary) -> Dictionary:
	return _row_by_id(last_snap.get("people", []), pick)


func _building_by_id(pick: Dictionary) -> Dictionary:
	if pick.is_empty():
		return {}
	return _row_by_id(last_snap.get("buildings", []), pick)


func _row_by_id(rows, pick: Dictionary) -> Dictionary:
	if not rows is Array or pick.is_empty():
		return {}
	var index := _int_of(pick.get("index", -1), -1)
	var generation := _int_of(pick.get("generation", -1), -1)
	for row in rows:
		if row is Dictionary and _int_of(row.get("index", -1), -1) == index and _int_of(row.get("generation", -1), -1) == generation:
			return row
	return {}


func _kind_of(pick: Dictionary) -> int:
	var row := _building_by_id(pick)
	if not row.is_empty():
		return _int_of(row.get("kind", -1), -1)
	return -1


func _item_name(item_id: int) -> String:
	if item_names.has(item_id):
		return str(item_names[item_id])
	if item_id >= 0 and item_id < ITEM_FALLBACK.size():
		return ITEM_FALLBACK[item_id]
	return "item %d" % item_id


func _building_name(kind: int) -> String:
	if kind >= 0 and kind < BUILDING_NAMES.size():
		return BUILDING_NAMES[kind]
	return "building"


func _recipe_id(slot: int) -> int:
	if slot < 0 or slot >= RECIPE_NAMES.size():
		return slot
	var want := RECIPE_NAMES[slot]
	var exact := -1
	var fuzzy := -1
	for id in recipe_names.keys():
		var name := str(recipe_names[id]).to_lower().strip_edges()
		if name == want:
			exact = int(id)
		elif fuzzy < 0 and want in name:
			fuzzy = int(id)
	if exact >= 0:
		return exact
	if fuzzy >= 0:
		return fuzzy
	return slot


func _store_names(rows: Array, into: Dictionary) -> void:
	into.clear()
	for row in rows:
		if not row is Dictionary:
			continue
		var id := _int_of(row.get("id", -1), -1)
		if id < 0:
			continue
		into[id] = str(row.get("name", ""))


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
