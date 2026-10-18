extends Node

# Review frames for milestone 1b. Instances the real scene and drives the
# sim through SimHost. Every building mesh is whatever the last poll
# returned. This driver does not write building rows.

const KIND_CAMPFIRE := 0
const KIND_LEAN_TO := 1
const KIND_STOCKPILE := 2
const ITEM_GRAIN := 0
const ITEM_WOOD := 1
const ITEM_FIBER := 3
const ITEM_WATER := 4
const ITEM_MEAL := 6
const RECIPE_MEAL := 1
const BUILD_TICKS := 60
const STATION_RANGE := 2.0
const PEG := Vector2(16.0, 16.0)
const SEED := 1
const HALF_PROGRESS := 30

var _main: Node
var _host: Object
var _owner := 0
var _out := ""
var _dead := false
var _fire: Dictionary = {}
var _lean: Dictionary = {}
var _pile: Dictionary = {}


func _ready() -> void:
	_out = _absolute(OS.get_environment("LATCHSOIL_SCREENSHOT"))
	OS.set_environment("LATCHSOIL_SCREENSHOT", "")
	OS.set_environment("LATCHSOIL_SCREENSHOT_FRAMES", "100000")
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	_drive()


func _drive() -> void:
	await get_tree().process_frame
	if _dead:
		return
	if not bool(_main.get("running")):
		_die("latchsoil: blockout scene did not boot")
		return
	# The scene's clock stops here. Later ticks are step() on its host.
	_main.set("running", false)
	var rig := _main.get_node("CameraRig") as Node3D
	rig.set_process(false)
	rig.set_physics_process(false)
	_host = _main.get("host")
	_owner = int(_main.get("owner_id"))
	if _host == null:
		_die("latchsoil: scene has no host")
		return
	_host.call("new_game", SEED)
	if not _pull():
		return
	print("latchsoil: new_game seed %d tick %s" % [SEED, str(_snap().get("tick", "missing"))])
	var people := _people()
	if people.size() < 3:
		_die("latchsoil: need 3 people, snapshot has %d" % people.size())
		return
	_print_people("cast")
	var blocked := _blocked_cells()
	var caster: Dictionary = people[0]
	var at_fire := _near_site(_pos(caster), blocked, STATION_RANGE)
	if at_fire.x < 0.0:
		_die("latchsoil: no campfire cell within station range")
		return
	blocked[_cell_key(at_fire)] = true
	var at_lean := _spiral(Vector2(24.0, 12.0), blocked, [at_fire])
	if at_lean.x < 0.0:
		_die("latchsoil: no lean-to cell")
		return
	blocked[_cell_key(at_lean)] = true
	var at_pile := _spiral(Vector2(8.0, 20.0), blocked, [at_fire, at_lean])
	if at_pile.x < 0.0:
		_die("latchsoil: no stockpile cell")
		return
	print("latchsoil: place campfire (%.1f, %.1f) lean-to (%.1f, %.1f) stockpile (%.1f, %.1f)" % [at_fire.x, at_fire.y, at_lean.x, at_lean.y, at_pile.x, at_pile.y])
	if not _submit_place(people[0], KIND_CAMPFIRE, at_fire):
		return
	if not _submit_place(people[1], KIND_LEAN_TO, at_lean):
		return
	if not _submit_place(people[2], KIND_STOCKPILE, at_pile):
		return
	if not _step():
		return
	_fire = _building_of_kind(KIND_CAMPFIRE)
	_lean = _building_of_kind(KIND_LEAN_TO)
	_pile = _building_of_kind(KIND_STOCKPILE)
	if _fire.is_empty() or _lean.is_empty() or _pile.is_empty():
		_die("latchsoil: place did not add three buildings (%s)" % _failure_line())
		return
	print("latchsoil: placed fire %s lean %s pile %s" % [str(_fire), str(_lean), str(_pile)])
	var half_taken := false
	var finished_taken := false
	for _i in 800:
		if _dead:
			return
		var progress := _progress(_fire)
		if progress < 0:
			_die("latchsoil: campfire progress missing from snapshot")
			return
		if not half_taken and progress >= HALF_PROGRESS and progress < BUILD_TICKS:
			print("latchsoil: captured campfire progress %d" % progress)
			if not await _shoot("half", "1b-half.png", _point(_fire), 12.0, [_index_of(people[0])], _fire):
				return
			half_taken = true
		if progress >= BUILD_TICKS:
			if not half_taken:
				_die("latchsoil: campfire reached %d without a 1..59 frame" % progress)
				return
			print("latchsoil: campfire finished progress %d" % progress)
			if not await _shoot("finished", "1b-finished.png", _point(_fire), 12.0, [_index_of(people[0])], _fire):
				return
			finished_taken = true
			break
		if not _step():
			return
		if _any_failure():
			_die("latchsoil: build failed (%s)" % _failure_line())
			return
		_fire = _building_of_kind(KIND_CAMPFIRE)
	if not finished_taken:
		_die("latchsoil: campfire did not finish (progress %d)" % _progress(_fire))
		return
	if not _until_finished():
		return
	if not _supply_and_cook(people):
		return
	var center := (_point(_fire) + _point(_lean) + _point(_pile)) / 3.0
	var cast := [_index_of(people[0]), _index_of(people[1]), _index_of(people[2])]
	if not await _shoot("stockpile", "1b-stockpile.png", _point(_pile), 8.0, cast, _pile):
		return
	if not await _shoot("holding", "1b-holding.png", center, 42.0, cast, _pile):
		return
	if _out != "" and _out != _frame_path("1b-holding.png"):
		var image := get_viewport().get_texture().get_image()
		if image == null or image.save_png(_out) != OK:
			_die("latchsoil: could not write the render output")
			return
		print("latchsoil: screenshot %s" % _out.get_file())
	print("latchsoil: frames done")
	get_tree().quit(0)


func _until_finished() -> bool:
	for _i in 800:
		_lean = _building_of_kind(KIND_LEAN_TO)
		_pile = _building_of_kind(KIND_STOCKPILE)
		if _progress(_lean) >= BUILD_TICKS and _progress(_pile) >= BUILD_TICKS:
			print("latchsoil: all buildings finished")
			_print_buildings("built")
			return true
		if not _step():
			return false
		if _any_failure():
			_die("latchsoil: later build failed (%s)" % _failure_line())
			return false
	_die("latchsoil: lean-to or stockpile did not finish")
	return false


func _supply_and_cook(people: Array) -> bool:
	var wood_node := _nearest_node(ITEM_WOOD, _pos(people[1]))
	var fiber_node := _nearest_node(ITEM_FIBER, _pos(people[2]))
	var water_node := _nearest_node(ITEM_WATER, _pos(people[0]))
	if wood_node.is_empty() or fiber_node.is_empty() or water_node.is_empty():
		_die("latchsoil: snapshot has no wood, fiber, or water node")
		return false
	print("latchsoil: gather wood node %s fiber node %s water node %s" % [str(wood_node), str(fiber_node), str(water_node)])
	if not _submit_gather(people[1], wood_node):
		return false
	if not _submit_gather(people[2], fiber_node):
		return false
	if not _submit_gather(people[0], water_node):
		return false
	var wood_haul := false
	var fiber_haul := false
	var water_move := false
	var settled := false
	var aside_a := _aside(_point(_pile), Vector2(3.0, 0.0))
	var aside_b := _aside(_point(_pile), Vector2(-3.0, 1.0))
	for _i in 2400:
		if not _step():
			return false
		if _any_failure():
			_die("latchsoil: supply failed (%s)" % _failure_line())
			return false
		var cook := _person(_index_of(people[0]))
		var hauler_wood := _person(_index_of(people[1]))
		var hauler_fiber := _person(_index_of(people[2]))
		if cook.is_empty() or hauler_wood.is_empty() or hauler_fiber.is_empty():
			_die("latchsoil: a person left the snapshot")
			return false
		if not wood_haul and _count_item(hauler_wood.get("carried", null), ITEM_WOOD) >= 2:
			if not _submit_haul(people[1], ITEM_WOOD, _pile):
				return false
			wood_haul = true
			print("latchsoil: haul wood carried %s" % str(hauler_wood.get("carried", "missing")))
		if not fiber_haul and _count_item(hauler_fiber.get("carried", null), ITEM_FIBER) >= 2:
			if not _submit_haul(people[2], ITEM_FIBER, _pile):
				return false
			fiber_haul = true
			print("latchsoil: haul fiber carried %s" % str(hauler_fiber.get("carried", "missing")))
		if not water_move and _count_item(cook.get("carried", null), ITEM_WATER) >= 1:
			if not _submit_move(people[0], _point(_fire)):
				return false
			water_move = true
			print("latchsoil: return to campfire carried %s" % str(cook.get("carried", "missing")))
		_pile = _building_of_kind(KIND_STOCKPILE)
		var stocked := _count_item(_pile.get("contents", null), ITEM_WOOD) >= 2 and _count_item(_pile.get("contents", null), ITEM_FIBER) >= 2
		var at_fire := water_move and _order_idle(cook) and _dist(cook, _fire) <= STATION_RANGE
		if stocked and at_fire and not settled:
			if not _submit_move(people[1], aside_a):
				return false
			if not _submit_move(people[2], aside_b):
				return false
			if not _submit_craft(people[0], RECIPE_MEAL):
				return false
			settled = true
			print("latchsoil: craft meal at campfire, stockpile %s" % str(_pile.get("contents", "missing")))
		if settled and _count_item(cook.get("carried", null), ITEM_MEAL) >= 1 and int(cook.get("job", -2)) == -1 and _order_idle(hauler_wood) and _order_idle(hauler_fiber):
			print("latchsoil: meal crafted carried %s" % str(cook.get("carried", "missing")))
			_print_buildings("reached")
			_print_people("reached")
			return true
	_die("latchsoil: supply or craft did not finish")
	return false


func _shoot(tag: String, file_name: String, at: Vector3, size: float, selected: Array, focus: Dictionary) -> bool:
	var selection: Array = []
	for index in selected:
		var person := _person(int(index))
		if person.is_empty():
			_die("latchsoil: %s selection missing person %s" % [tag, str(index)])
			return false
		selection.append({"index": int(person.get("index", -1)), "generation": int(person.get("generation", -1))})
	_main.set("selection", selection)
	_main.set("build_mode", false)
	_main.set("craft_mode", false)
	if focus.is_empty():
		_main.set("building_sel", {})
	else:
		_main.set("building_sel", {"index": int(focus.get("index", -1)), "generation": int(focus.get("generation", -1))})
	_main.call("_refresh_view")
	_aim(at, size)
	_print_frame(tag)
	return await _save(_frame_path(file_name))


func _print_frame(tag: String) -> void:
	var snap := _snap()
	print("latchsoil: frame %s tick %s hash %s" % [tag, str(snap.get("tick", "missing")), str(snap.get("hash", "missing"))])
	var buildings = snap.get("buildings", null)
	if not buildings is Array:
		print("latchsoil: frame %s buildings missing from snapshot" % tag)
	else:
		print("latchsoil: frame %s buildings %d" % [tag, buildings.size()])
		for row in buildings:
			if row is Dictionary:
				print("latchsoil: frame %s building %s" % [tag, str(row)])
				if not row.has("progress"):
					print("latchsoil: frame %s building progress missing from snapshot" % tag)
				if not row.has("contents"):
					print("latchsoil: frame %s building contents missing from snapshot" % tag)
			else:
				print("latchsoil: frame %s building row is not a dictionary" % tag)
	_print_people("frame %s" % tag)
	var detail := _main.get_node("HUD").get_node_or_null("Detail") as Label
	if detail == null:
		print("latchsoil: frame %s hud detail missing" % tag)
	else:
		print("latchsoil: frame %s hud detail %s" % [tag, detail.text.replace("\n", " | ")])


func _print_buildings(tag: String) -> void:
	var buildings = _snap().get("buildings", null)
	if not buildings is Array:
		print("latchsoil: %s buildings missing from snapshot" % tag)
		return
	for row in buildings:
		print("latchsoil: %s building %s" % [tag, str(row)])


func _print_people(tag: String) -> void:
	var people = _snap().get("people", null)
	if not people is Array:
		print("latchsoil: %s people missing from snapshot" % tag)
		return
	for row in people:
		if not row is Dictionary:
			print("latchsoil: %s person row is not a dictionary" % tag)
			continue
		var carried = row.get("carried", null)
		if carried == null:
			print("latchsoil: %s person %s carried missing from snapshot" % [tag, str(row.get("index", "?"))])
		else:
			print("latchsoil: %s person %s carried %s" % [tag, str(row.get("index", "?")), str(carried)])
		print("latchsoil: %s person %s at (%.2f, %.2f) job %s failure %s dest %s path %d" % [
			tag,
			str(row.get("index", "?")),
			float(row.get("x", 0.0)),
			float(row.get("y", 0.0)),
			str(row.get("job", "missing")),
			str(row.get("failure_text", "missing")),
			str(row.get("dest", "missing")),
			_len(row.get("path", [])),
		])


func _submit_place(actor: Dictionary, kind: int, at: Vector2) -> bool:
	var code = _host.call("submit_place", int(actor.get("index", -1)), int(actor.get("generation", -1)), kind, at.x, at.y)
	print("latchsoil: submit_place kind %d actor %s at (%.1f, %.1f) -> %s" % [kind, str(actor.get("index", "?")), at.x, at.y, str(code)])
	if code == null or int(code) != 0:
		_die("latchsoil: submit_place returned %s" % str(code))
		return false
	return true


func _submit_gather(actor: Dictionary, node: Dictionary) -> bool:
	var code = _host.call("submit_gather", int(actor.get("index", -1)), int(actor.get("generation", -1)), int(node.get("index", -1)), int(node.get("generation", -1)))
	print("latchsoil: submit_gather actor %s node %s -> %s" % [str(actor.get("index", "?")), str(node.get("index", "?")), str(code)])
	if code == null or int(code) != 0:
		_die("latchsoil: submit_gather returned %s" % str(code))
		return false
	return true


func _submit_haul(actor: Dictionary, item_id: int, building: Dictionary) -> bool:
	var code = _host.call("submit_haul", int(actor.get("index", -1)), int(actor.get("generation", -1)), item_id, int(building.get("index", -1)), int(building.get("generation", -1)))
	print("latchsoil: submit_haul actor %s item %d to %s -> %s" % [str(actor.get("index", "?")), item_id, str(building.get("index", "?")), str(code)])
	if code == null or int(code) != 0:
		_die("latchsoil: submit_haul returned %s" % str(code))
		return false
	return true


func _submit_move(actor: Dictionary, at: Vector3) -> bool:
	var code = _host.call("submit_move", int(actor.get("index", -1)), int(actor.get("generation", -1)), at.x, at.z)
	print("latchsoil: submit_move actor %s to (%.1f, %.1f) -> %s" % [str(actor.get("index", "?")), at.x, at.z, str(code)])
	if code == null or int(code) != 0:
		_die("latchsoil: submit_move returned %s" % str(code))
		return false
	return true


func _submit_craft(actor: Dictionary, recipe: int) -> bool:
	var code = _host.call("submit_craft", int(actor.get("index", -1)), int(actor.get("generation", -1)), recipe)
	print("latchsoil: submit_craft actor %s recipe %d -> %s" % [str(actor.get("index", "?")), recipe, str(code)])
	if code == null or int(code) != 0:
		_die("latchsoil: submit_craft returned %s" % str(code))
		return false
	return true


func _step() -> bool:
	_host.call("step")
	return _pull()


func _pull() -> bool:
	var snap = _host.call("poll", _owner)
	if not snap is Dictionary or int(snap.get("error", -1)) != 0:
		_die("latchsoil: poll failed (%s)" % str(snap))
		return false
	_main.set("last_snap", snap)
	return true


func _snap() -> Dictionary:
	var snap = _main.get("last_snap")
	if snap is Dictionary:
		return snap
	return {}


func _people() -> Array:
	var rows = _snap().get("people", [])
	var out: Array = []
	if rows is Array:
		for row in rows:
			if row is Dictionary:
				out.append(row)
	out.sort_custom(func(a, b): return int(a.get("index", 0)) < int(b.get("index", 0)))
	return out


func _person(index: int) -> Dictionary:
	var rows = _snap().get("people", [])
	if rows is Array:
		for row in rows:
			if row is Dictionary and int(row.get("index", -1)) == index:
				return row
	return {}


func _building_of_kind(kind: int) -> Dictionary:
	var rows = _snap().get("buildings", [])
	if rows is Array:
		for row in rows:
			if row is Dictionary and int(row.get("kind", -1)) == kind:
				return row
	return {}


func _nearest_node(yield_item: int, from: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_d := 1000000.0
	var rows = _snap().get("nodes", [])
	if not rows is Array:
		return {}
	for row in rows:
		if not row is Dictionary or int(row.get("yield_item", -1)) != yield_item:
			continue
		var d := from.distance_to(Vector2(float(row.get("x", 0.0)), float(row.get("y", 0.0))))
		if d < best_d:
			best = row
			best_d = d
	return best


func _blocked_cells() -> Dictionary:
	var blocked := {}
	blocked["16,16"] = true
	var nodes = _snap().get("nodes", [])
	if nodes is Array:
		for row in nodes:
			if row is Dictionary and row.has("x") and row.has("y"):
				blocked[_cell_key(Vector2(float(row.get("x", 0.0)), float(row.get("y", 0.0))))] = true
	return blocked


func _near_site(origin: Vector2, blocked: Dictionary, max_dist: float) -> Vector2:
	var offsets: Array[Vector2] = [
		Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1),
		Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1),
		Vector2(2, 0), Vector2(-2, 0), Vector2(0, 2), Vector2(0, -2),
	]
	for off in offsets:
		var at := Vector2(origin.x + off.x, origin.y + off.y)
		if origin.distance_to(at) <= max_dist and _site_ok(at, blocked):
			return at
	if _site_ok(origin, blocked):
		return origin
	return Vector2(-1.0, -1.0)


func _spiral(prefer: Vector2, blocked: Dictionary, apart: Array) -> Vector2:
	var origin := Vector2(round(prefer.x), round(prefer.y))
	for radius in range(0, 8):
		for dz in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if radius > 0 and absi(dx) != radius and absi(dz) != radius:
					continue
				var at := origin + Vector2(dx, dz)
				if not _site_ok(at, blocked):
					continue
				var clear := true
				for other in apart:
					if at.distance_to(other) < 4.0:
						clear = false
						break
				if clear:
					return at
	return Vector2(-1.0, -1.0)


func _site_ok(at: Vector2, blocked: Dictionary) -> bool:
	if at.x < 1.0 or at.y < 1.0 or at.x > 30.0 or at.y > 30.0:
		return false
	if blocked.has(_cell_key(at)):
		return false
	return true


func _aside(pile: Vector3, offset: Vector2) -> Vector3:
	var x := clampf(pile.x + offset.x, 2.0, 29.0)
	var z := clampf(pile.z + offset.y, 2.0, 29.0)
	if Vector2(x, z).distance_to(PEG) < 1.5:
		x = clampf(x + 3.0, 2.0, 29.0)
	return Vector3(x, 0.0, z)


func _cell_key(at: Vector2) -> String:
	return "%d,%d" % [int(floor(at.x)), int(floor(at.y))]


func _pos(row: Dictionary) -> Vector2:
	return Vector2(float(row.get("x", 0.0)), float(row.get("y", 0.0)))


func _point(row: Dictionary) -> Vector3:
	return Vector3(float(row.get("x", 0.0)), 0.0, float(row.get("y", 0.0)))


func _index_of(row: Dictionary) -> int:
	return int(row.get("index", -1))


func _progress(row: Dictionary) -> int:
	if row.is_empty() or not row.has("progress"):
		return -1
	return int(row.get("progress", -1))


func _count_item(carried, item_id: int) -> int:
	if not carried is Array:
		return -1
	var total := 0
	for pair in carried:
		if pair is Array and pair.size() >= 2 and int(pair[0]) == item_id:
			total += int(pair[1])
	return total


func _dist(person: Dictionary, building: Dictionary) -> float:
	return _pos(person).distance_to(Vector2(float(building.get("x", 0.0)), float(building.get("y", 0.0))))


func _order_idle(person: Dictionary) -> bool:
	return _len(person.get("path", [])) == 0 and _len(person.get("dest", [])) == 0 and int(person.get("failure", -1)) == -1


func _len(value) -> int:
	if value is Array or value is PackedFloat32Array or value is PackedFloat64Array or value is PackedInt32Array:
		return value.size()
	return 0


func _any_failure() -> bool:
	return _failure_line() != ""


func _failure_line() -> String:
	var rows = _snap().get("people", [])
	if not rows is Array:
		return ""
	var bits: PackedStringArray = []
	for row in rows:
		if row is Dictionary and str(row.get("failure_text", "")) != "":
			bits.append("%s:%s" % [str(row.get("index", "?")), str(row.get("failure_text", ""))])
	return ", ".join(bits)


func _aim(at: Vector3, size: float) -> void:
	var rig := _main.get_node("CameraRig") as Node3D
	rig.position = at
	rig.set("ortho_size", size)
	rig.set("yaw_deg", 45.0)
	rig.call("_apply_camera")
	rig.force_update_transform()


func _absolute(path: String) -> String:
	if path == "" or path.is_absolute_path():
		return path
	var cwd := OS.get_environment("PWD")
	if cwd == "":
		return path
	return cwd.path_join(path)


func _frame_path(file_name: String) -> String:
	if _out == "":
		return file_name
	return _out.get_base_dir().path_join(file_name)


func _save(path: String) -> bool:
	var image: Image = null
	for _i in 8:
		await RenderingServer.frame_post_draw
		if _dead:
			return false
		image = get_viewport().get_texture().get_image()
		if _drawn(image):
			break
	if not _drawn(image):
		_die("latchsoil: viewport was empty")
		return false
	var err := image.save_png(path)
	if err != OK:
		_die("latchsoil: could not save frame")
		return false
	print("latchsoil: frame file %s" % path.get_file())
	return true


func _drawn(image: Image) -> bool:
	if image == null or image.is_empty() or image.get_width() < 2 or image.get_height() < 2:
		return false
	var a := image.get_pixel(8, 8)
	var b := image.get_pixel(image.get_width() / 2, image.get_height() / 2)
	var c := image.get_pixel(image.get_width() - 8, image.get_height() - 8)
	return a != b or b != c


func _die(message: String) -> void:
	if _dead:
		return
	_dead = true
	push_error(message)
	print(message)
	get_tree().quit(1)
