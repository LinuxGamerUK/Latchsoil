extends Node

# Review frames for milestone 2. Instances the real scene and drives the sim
# through SimHost. A mesh is drawn only from the last poll. This driver does
# not invent a sleep or a chill the snapshot does not carry. A wound is set
# through the save, then drawn only after the snapshot carries it and bleeding
# has moved health. No rule wounds anybody until later, so the save is the seam.

const JOB_REST := 7
const SEED := 1
const PEG := Vector2(16.0, 16.0)
const CLOSE_ORTHO := 6.0
const SLEEP_ORTHO := 12.0
const HOLDING_ORTHO := 42.0
const READ_ORTHO := 4.0
const COLD_CLOSE := 0.82
const COLD_FAR := 0.70
const REGION_LEFT_LEG := 4
const REGION_RIGHT_LEG := 5
const BLEED_SET := 1.0

var _main: Node
var _host: Object
var _owner := 0
var _out := ""
var _dead := false


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
	_main.set("running", false)
	var rig := _main.get_node("CameraRig") as Node3D
	rig.set_process(false)
	rig.set_physics_process(false)
	_host = _main.get("host")
	_owner = int(_main.get("owner_id"))
	if _host == null:
		_die("latchsoil: scene has no host")
		return
	print("latchsoil: submit_heal %s submit_work %s" % [str(_host.has_method("submit_heal")), str(_host.has_method("submit_work"))])
	_host.call("new_game", SEED)
	if not _pull():
		return
	print("latchsoil: new_game seed %d tick %s" % [SEED, str(_snap().get("tick", "missing"))])
	_print_people("cast")
	var people := _people()
	if people.size() < 1:
		_die("latchsoil: snapshot has no people")
		return
	if not await _separate(people):
		return
	var slept := await _try_sleep()
	var chilled := await _try_cold()
	if not await _shoot("close", "2-close.png", _point(_people()[0]), CLOSE_ORTHO, [_index_of(_people()[0])], {}):
		return
	if not slept:
		print("latchsoil: sleep was not reached; the frame shows the snapshot pose")
		if not await _shoot("awake", "2-awake.png", _point(_people()[0]), SLEEP_ORTHO, [_index_of(_people()[0])], {}):
			return
	if not chilled:
		print("latchsoil: warmth did not fall below %.2f; holding frame is the snapshot" % COLD_FAR)
		var center := _cast_center()
		if not await _shoot("holding", "2-holding.png", center, HOLDING_ORTHO, _cast_indices(), {}):
			return
	if not await _try_wound():
		return
	if _out != "" and not _dead:
		var image := get_viewport().get_texture().get_image()
		if image == null or image.save_png(_out) != OK:
			_die("latchsoil: could not write the render output")
			return
		print("latchsoil: screenshot %s" % _out.get_file())
	print("latchsoil: frames done")
	get_tree().quit(0)


func _separate(people: Array) -> bool:
	var spots: Array[Vector2] = [Vector2(10.0, 16.0), Vector2(18.0, 12.0), Vector2(22.0, 20.0)]
	for i in mini(people.size(), spots.size()):
		if not _submit_move(people[i], spots[i]):
			return false
	for _i in 400:
		if not _step():
			return false
		if _all_idle():
			print("latchsoil: cast separated")
			_print_people("separated")
			return true
		if _any_failure():
			_die("latchsoil: separate failed (%s)" % _failure_line())
			return false
	_die("latchsoil: cast did not finish the separate move")
	return false


func _try_sleep() -> bool:
	var people := _people()
	if people.is_empty():
		return false
	var actor: Dictionary = people[0]
	# Rest completes at fatigue 0. A fresh person finishes on the applying tick
	# and never reads as asleep, so idle ticks have to pass first. The snapshot
	# may not carry fatigue yet; the wait still happens, and the job is the proof.
	for _i in 16:
		actor = _person(_index_of(people[0]))
		if actor.has("fatigue") and _float_of(actor.get("fatigue", 0.0), 0.0) >= 0.08:
			break
		if not _steps(200):
			return false
	actor = _person(_index_of(people[0]))
	print("latchsoil: before rest tick %s fatigue %s" % [str(_snap().get("tick", "missing")), str(actor.get("fatigue", "missing"))])
	_main.set("selection", [_id_of(actor)])
	_main.call("_order_sleep")
	if not _step():
		return false
	actor = _person(_index_of(actor))
	var job := _int_of(actor.get("job", -1), -1)
	print("latchsoil: after submit_work rest job %s failure %s" % [str(actor.get("job", "missing")), str(actor.get("failure_text", "missing"))])
	if job != JOB_REST:
		print("latchsoil: job is not rest; not drawing a sleeper")
		return false
	var neighbour := _person(1) if _people().size() > 1 else {}
	var aim := _point(actor)
	var selected: Array = [_index_of(actor)]
	if not neighbour.is_empty():
		aim = (aim + _point(neighbour)) * 0.5
		selected.append(_index_of(neighbour))
	if not await _shoot("sleep", "2-sleep.png", aim, SLEEP_ORTHO, selected, {}):
		return false
	return true


func _try_cold() -> bool:
	var sample := _people()
	if sample.is_empty():
		return false
	if not sample[0].has("warmth"):
		print("latchsoil: warmth missing from snapshot")
		return false
	print("latchsoil: warmth before night %s" % str(sample[0].get("warmth", "missing")))
	var guard := 0
	while guard < 40:
		guard += 1
		var tick := _int_of(_snap().get("tick", 0), 0)
		var coldest := _coldest()
		var warmth := _float_of(coldest.get("warmth", 1.0), 1.0)
		if warmth < COLD_FAR and _int_of(coldest.get("job", -1), -1) != JOB_REST:
			print("latchsoil: cold reached warmth %.3f tick %d person %s" % [warmth, tick, str(coldest.get("index", "?"))])
			# Same snapshot at both zooms. Phase 1 and phase 4 are opposite peaks.
			print("latchsoil: cold body draws below warmth %.2f, shawl below %.2f; 4 m frame is this snapshot" % [COLD_FAR, COLD_CLOSE])
			# Peak and opposite peak of the same snapshot, so a still shows the shiver.
			_set_shiver(1)
			if not await _shoot("cold", "2-cold.png", _cast_center(), HOLDING_ORTHO, _cast_indices(), {}):
				return false
			_set_shiver(4)
			if not await _shoot("cold-shiver", "2-cold-shiver.png", _cast_center(), HOLDING_ORTHO, _cast_indices(), {}):
				return false
			_set_shiver(1)
			if not await _shoot("cold-4m", "2-cold-4m.png", _point(coldest), READ_ORTHO, [_index_of(coldest)], {}):
				return false
			_set_shiver(4)
			if not await _shoot("cold-4m-shiver", "2-cold-4m-shiver.png", _point(coldest), READ_ORTHO, [_index_of(coldest)], {}):
				return false
			_set_shiver(-1)
			return true
		if not _steps(200):
			return false
		if guard % 5 == 0:
			coldest = _coldest()
			print("latchsoil: warmth drift tick %s person %s warmth %s" % [str(_snap().get("tick", "missing")), str(coldest.get("index", "?")), str(coldest.get("warmth", "missing"))])
	var coldest := _coldest()
	print("latchsoil: warmth after drift %s tick %s" % [str(coldest.get("warmth", "missing")), str(_snap().get("tick", "missing"))])
	return false


func _bleeding_leg() -> Dictionary:
	for person in _people():
		var regions = person.get("regions", null)
		if not regions is Array:
			continue
		for i in regions.size():
			var entry = regions[i]
			if not entry is Dictionary:
				continue
			var slot: int = int(i)
			if entry.has("kind") and (entry.get("kind") is int or entry.get("kind") is float):
				slot = int(entry.get("kind"))
			if slot != 4 and slot != 5:
				continue
			if _float_of(entry.get("bleeding", 0.0), 0.0) > 0.0:
				return person
	return {}


func _shoot(tag: String, file_name: String, at: Vector3, size: float, selected: Array, focus: Dictionary) -> bool:
	var selection: Array = []
	for index in selected:
		var person := _person(int(index))
		if person.is_empty():
			_die("latchsoil: %s selection missing person %s" % [tag, str(index)])
			return false
		selection.append(_id_of(person))
	_main.set("selection", selection)
	_main.set("build_mode", false)
	_main.set("craft_mode", false)
	_main.set("heal_mode", false)
	if focus.is_empty():
		_main.set("building_sel", {})
	else:
		_main.set("building_sel", _id_of(focus))
	_main.call("_refresh_view")
	_aim(at, size)
	_print_frame(tag)
	_print_view(tag)
	return await _save(_frame_path(file_name))


func _print_frame(tag: String) -> void:
	var snap := _snap()
	print("latchsoil: frame %s tick %s hash %s ortho drawn by rig" % [tag, str(snap.get("tick", "missing")), str(snap.get("hash", "missing"))])
	_print_people("frame %s" % tag)
	var reason := _main.get_node("HUD").get_node_or_null("Reason") as Label
	var detail := _main.get_node("HUD").get_node_or_null("Detail") as Label
	if reason == null:
		print("latchsoil: frame %s hud reason missing" % tag)
	else:
		print("latchsoil: frame %s hud reason %s" % [tag, reason.text])
	if detail == null:
		print("latchsoil: frame %s hud detail missing" % tag)
	else:
		print("latchsoil: frame %s hud detail %s" % [tag, detail.text.replace("\n", " | ")])


func _set_shiver(frame: int) -> void:
	var view := _main.get_node("World")
	if frame < 0:
		if view.has_method("thaw_shiver"):
			view.call("thaw_shiver")
		return
	if view.has_method("freeze_shiver"):
		view.call("freeze_shiver", frame)


func _print_view(tag: String) -> void:
	var view := _main.get_node("World")
	var people = view.get("people")
	if not people is Dictionary:
		print("latchsoil: frame %s view people missing" % tag)
		return
	for key in people.keys():
		var body: Node = people[key]
		var pose := body.get_node_or_null("Pose") as Node3D
		var sleep_mat := body.get_node_or_null("SleepMat")
		var hurt := body.get_node_or_null("HurtMark")
		var shawl := body.get_node_or_null("Pose/Shawl")
		var arms := body.get_node_or_null("Pose/Arms")
		var breath := body.get_node_or_null("Pose/Breath")
		print("latchsoil: frame %s view %s pose %s pos %s sleep_mat %s hurt %s cold %s shawl %s arms %s breath %s" % [
			tag,
			str(key),
			str(pose.rotation_degrees if pose != null else "missing"),
			str(pose.position if pose != null else "missing"),
			str(sleep_mat.visible if sleep_mat != null else "missing"),
			str(hurt.visible if hurt != null else "missing"),
			str(body.get_meta("cold", false)),
			str(shawl.visible if shawl != null else "missing"),
			str(arms.visible if arms != null else "missing"),
			str(breath.visible if breath != null else "missing"),
		])


func _print_people(tag: String) -> void:
	var people = _snap().get("people", null)
	if not people is Array:
		print("latchsoil: %s people missing from snapshot" % tag)
		return
	for row in people:
		if not row is Dictionary:
			print("latchsoil: %s person row is not a dictionary" % tag)
			continue
		print("latchsoil: %s person %s keys %s" % [tag, str(row.get("index", "?")), _key_list(row)])
		print("latchsoil: %s person %s at (%.2f, %.2f) job %s failure %s fatigue %s warmth %s skills %s" % [
			tag,
			str(row.get("index", "?")),
			_float_of(row.get("x", 0.0), 0.0),
			_float_of(row.get("y", 0.0), 0.0),
			str(row.get("job", "missing")),
			str(row.get("failure_text", "missing")),
			str(row.get("fatigue", "missing")),
			str(row.get("warmth", "missing")),
			str(row.get("skills", "missing")),
		])
		if row.has("regions"):
			print("latchsoil: %s person %s regions %s" % [tag, str(row.get("index", "?")), str(row.get("regions"))])
		else:
			print("latchsoil: %s person %s regions missing from snapshot" % [tag, str(row.get("index", "?"))])


func _print_regions(tag: String) -> void:
	for person in _people():
		print("latchsoil: %s person %s regions %s" % [tag, str(person.get("index", "?")), str(person.get("regions", "missing"))])


func _submit_move(actor: Dictionary, at: Vector2) -> bool:
	var code = _host.call("submit_move", _int_of(actor.get("index", -1), -1), _int_of(actor.get("generation", -1), -1), at.x, at.y)
	print("latchsoil: submit_move actor %s to (%.1f, %.1f) -> %s" % [str(actor.get("index", "?")), at.x, at.y, str(code)])
	if code == null or int(code) != 0:
		_die("latchsoil: submit_move returned %s" % str(code))
		return false
	return true


func _steps(count: int) -> bool:
	for i in count:
		_host.call("step")
		if i == count - 1 or i % 200 == 199:
			if not _pull():
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
	for row in _people():
		if int(row.get("index", -1)) == index:
			return row
	return {}


func _coldest() -> Dictionary:
	var best: Dictionary = {}
	var best_w := 2.0
	for row in _people():
		if not row.has("warmth"):
			continue
		var warmth := _float_of(row.get("warmth"), 1.0)
		if warmth < best_w:
			best = row
			best_w = warmth
	if best.is_empty() and not _people().is_empty():
		return _people()[0]
	return best


func _all_idle() -> bool:
	for row in _people():
		if _len(row.get("path", [])) > 0 or _len(row.get("dest", [])) > 0:
			return false
	return true


func _any_failure() -> bool:
	return _failure_line() != ""


func _failure_line() -> String:
	var bits: PackedStringArray = []
	for row in _people():
		if str(row.get("failure_text", "")) != "":
			bits.append("%s:%s" % [str(row.get("index", "?")), str(row.get("failure_text", ""))])
	return ", ".join(bits)


func _cast_center() -> Vector3:
	var people := _people()
	if people.is_empty():
		return Vector3(PEG.x, 0.0, PEG.y)
	var sum := Vector3.ZERO
	for row in people:
		sum += _point(row)
	return sum / float(people.size())


func _cast_indices() -> Array:
	var out: Array = []
	for row in _people():
		out.append(_index_of(row))
	return out


func _id_of(row: Dictionary) -> Dictionary:
	return {"index": _int_of(row.get("index", -1), -1), "generation": _int_of(row.get("generation", -1), -1)}


func _index_of(row: Dictionary) -> int:
	return _int_of(row.get("index", -1), -1)


func _point(row: Dictionary) -> Vector3:
	return Vector3(_float_of(row.get("x", 0.0), 0.0), 0.0, _float_of(row.get("y", 0.0), 0.0))


func _key_list(row: Dictionary) -> String:
	var keys: PackedStringArray = []
	for key in row.keys():
		keys.append(str(key))
	keys.sort()
	return ",".join(keys)


func _len(value) -> int:
	if value is Array or value is PackedFloat32Array or value is PackedFloat64Array or value is PackedInt32Array:
		return value.size()
	return 0


func _int_of(value, fallback: int) -> int:
	if value is int or value is float:
		return int(value)
	return fallback


func _float_of(value, fallback: float) -> float:
	if value is int or value is float:
		return float(value)
	return fallback


func _aim(at: Vector3, size: float) -> void:
	var rig := _main.get_node("CameraRig") as Node3D
	rig.position = at
	rig.set("ortho_size", size)
	rig.set("yaw_deg", 45.0)
	rig.call("_apply_camera")
	rig.force_update_transform()
	print("latchsoil: camera ortho %.1f at (%.1f, %.1f)" % [size, at.x, at.z])


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


func _try_wound() -> bool:
	var actor := _standing_person()
	if actor.is_empty():
		_die("latchsoil: no person to wound")
		return false
	if not actor.has("regions") or not actor.has("health"):
		print("latchsoil: snapshot has no regions or health; not drawing a wound")
		_print_regions("wound-check")
		return true
	if not _host.has_method("save_json") or not _host.has_method("load_json"):
		_die("latchsoil: host has no save seam")
		return false
	var index := _index_of(actor)
	print("latchsoil: wound health before save person %s tick %s health %s warmth %s" % [
		str(index),
		str(_snap().get("tick", "missing")),
		_num(actor.get("health", "missing")),
		_num(actor.get("warmth", "missing")),
	])
	_print_regions("wound-before")
	var text := str(_host.call("save_json"))
	if text == "":
		_die("latchsoil: save_json returned empty")
		return false
	var parsed = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		_die("latchsoil: save_json is not a JSON object")
		return false
	var slot := _slot_person(parsed, index)
	if slot.is_empty():
		_die("latchsoil: save has no live person %s" % str(index))
		return false
	var region := _set_leg_bleed(slot, BLEED_SET)
	if region.is_empty():
		_die("latchsoil: save person %s has no leg region (kind 4 or 5)" % str(index))
		return false
	print("latchsoil: the wound was set by hand in the save, because no rule wounds anybody until milestone 5")
	print("latchsoil: wound set person %s leg kind %s bleeding %s region %s" % [
		str(index),
		str(region.get("kind", "missing")),
		_num(region.get("bleeding", "missing")),
		str(region),
	])
	var encoded := _commit_text(text, parsed)
	if encoded == "":
		_die("latchsoil: could not keep the save's rng digits")
		return false
	var code = _host.call("load_json", encoded)
	if code == null or int(code) != 0:
		_die("latchsoil: load_json of the hand-edited save returned %s" % str(code))
		return false
	if not _pull():
		return false
	actor = _person(index)
	var loaded := _leg_row(actor)
	if loaded.is_empty() or abs(_float_of(loaded.get("bleeding", -1.0), -1.0) - BLEED_SET) > 0.001:
		_die("latchsoil: bleeding after load is %s, the save did not carry the hand-set wound" % str(loaded.get("bleeding", "missing")))
		return false
	print("latchsoil: wound after load person %s tick %s health %s region %s" % [
		str(index),
		str(_snap().get("tick", "missing")),
		_num(actor.get("health", "missing")),
		str(loaded),
	])
	if not await _until_standing(index):
		return false
	actor = _person(index)
	var warmth := _float_of(actor.get("warmth", 1.0), 1.0)
	var tick := _int_of(_snap().get("tick", 0), 0)
	var bleed_ticks := _bleed_window(warmth, tick)
	print("latchsoil: wound health before bleed person %s tick %s health %s warmth %s ticks %d region %s" % [
		str(index),
		str(tick),
		_num(actor.get("health", "missing")),
		_num(actor.get("warmth", "missing")),
		bleed_ticks,
		str(_leg_row(actor)),
	])
	if not _steps(bleed_ticks):
		return false
	actor = _person(index)
	loaded = _leg_row(actor)
	print("latchsoil: wound health after bleed person %s tick %s health %s warmth %s job %s region %s" % [
		str(index),
		str(_snap().get("tick", "missing")),
		_num(actor.get("health", "missing")),
		_num(actor.get("warmth", "missing")),
		str(actor.get("job", "missing")),
		str(loaded),
	])
	_print_regions("wound-after")
	var wounded := _bleeding_leg()
	if wounded.is_empty():
		print("latchsoil: no bleeding leg in the snapshot; not drawing a wound")
		return true
	if _int_of(wounded.get("job", -1), -1) == JOB_REST:
		print("latchsoil: bleeding leg is on a sleeper; not drawing a limp over a rest pose")
		return true
	print("latchsoil: bleeding leg person %s" % str(wounded.get("index", "?")))
	if not await _shoot("wound", "2-wound.png", _point(wounded), CLOSE_ORTHO, [_index_of(wounded)], {}):
		return false
	if not await _shoot("wound-4m", "2-wound-4m.png", _point(wounded), READ_ORTHO, [_index_of(wounded)], {}):
		return false
	_print_wound_nodes(_index_of(wounded))
	if not await _try_limp_walk(wounded):
		return false
	return true


func _standing_person() -> Dictionary:
	for person in _people():
		if _int_of(person.get("job", -1), -1) != JOB_REST:
			return person
	if _people().is_empty():
		return {}
	return _people()[0]


func _until_standing(index: int) -> bool:
	for _i in 20:
		var person := _person(index)
		if person.is_empty():
			_die("latchsoil: wounded person left the snapshot")
			return false
		if _int_of(person.get("job", -1), -1) != JOB_REST:
			return true
		print("latchsoil: wounded person still resting at tick %s health %s; stepping so the frame is the standing pose" % [
			str(_snap().get("tick", "missing")),
			_num(person.get("health", "missing")),
		])
		if not _steps(200):
			return false
	_die("latchsoil: wounded person did not stand")
	return false


func _bleed_window(warmth: float, tick: int) -> int:
	# Night drifts warmth toward 0 at 1/1200. Stay above zero so the health
	# drop beside the frame is the bleed, not the cold drain.
	var in_night := tick % 7200 >= 5760
	if not in_night:
		return 720
	var room := int(floor(warmth * 1200.0)) - 40
	if room < 80:
		print("latchsoil: warmth %.3f is close to zero; bleed window is %d ticks and cold may also drain health" % [warmth, maxi(room, 1)])
		return maxi(room, 1)
	return mini(room, 720)


func _set_leg_bleed(slot: Dictionary, value: float) -> Dictionary:
	var regions = slot.get("regions", null)
	if not regions is Array:
		return {}
	var chosen: Dictionary = {}
	for entry in regions:
		if not entry is Dictionary:
			continue
		var kind := int(entry.get("kind", -1))
		if kind != REGION_LEFT_LEG and kind != REGION_RIGHT_LEG:
			continue
		if chosen.is_empty() or kind == REGION_LEFT_LEG:
			chosen = entry
	if chosen.is_empty():
		return {}
	chosen["bleeding"] = value
	return chosen


func _leg_row(person: Dictionary) -> Dictionary:
	var regions = person.get("regions", null)
	if not regions is Array:
		return {}
	var chosen: Dictionary = {}
	for i in regions.size():
		var entry = regions[i]
		if not entry is Dictionary:
			continue
		var slot := int(i)
		if entry.has("kind") and (entry.get("kind") is int or entry.get("kind") is float):
			slot = int(entry.get("kind"))
		if slot != REGION_LEFT_LEG and slot != REGION_RIGHT_LEG:
			continue
		if chosen.is_empty() or slot == REGION_LEFT_LEG:
			chosen = entry
	return chosen


func _slot_person(doc: Dictionary, index: int) -> Dictionary:
	for slot in doc.get("slots", []):
		if typeof(slot) != TYPE_DICTIONARY:
			continue
		if str(slot.get("kind", "")) != "person":
			continue
		if int(slot.get("index", -1)) == index:
			return slot
	return {}


func _commit_text(original: String, doc: Dictionary) -> String:
	# The RNG word does not fit in a JSON number. Put the original digits back
	# after encoding, so the edit does not smash the stream.
	var rng_digits := _json_int_field(original, "rng")
	var seed_digits := _json_int_field(original, "seed")
	if rng_digits == "":
		return ""
	doc["rng"] = 1
	var encoded := _encode_json(doc)
	encoded = encoded.replace("\"rng\":1,", "\"rng\":%s," % rng_digits)
	encoded = encoded.replace("\"rng\":1}", "\"rng\":%s}" % rng_digits)
	if not encoded.contains(rng_digits):
		return ""
	if seed_digits != "":
		var current := _json_int_field(encoded, "seed")
		if current != "" and current != seed_digits:
			encoded = encoded.replace("\"seed\":%s," % current, "\"seed\":%s," % seed_digits)
	return encoded


func _json_int_field(text: String, key: String) -> String:
	var needle := "\"%s\":" % key
	var at := text.find(needle)
	if at < 0:
		return ""
	at += needle.length()
	while at < text.length():
		var ch := text.substr(at, 1)
		if ch != " " and ch != "\n" and ch != "	":
			break
		at += 1
	var end := at
	while end < text.length():
		var ch := text.substr(end, 1)
		if ch < "0" or ch > "9":
			break
		end += 1
	if end == at:
		return ""
	return text.substr(at, end - at)


func _encode_json(value) -> String:
	if value == null:
		return "null"
	var kind := typeof(value)
	if kind == TYPE_BOOL:
		return "true" if value else "false"
	if kind == TYPE_INT:
		return str(value)
	if kind == TYPE_FLOAT:
		if is_nan(value) or is_inf(value):
			return "0"
		# Whole numbers must stay integers. serde rejects 1.0 for a u32.
		if value == floor(value) and abs(value) <= 9223372036854775807.0:
			return str(int(value))
		return str(value)
	if kind == TYPE_STRING:
		return "\"%s\"" % str(value).replace("\\", "\\\\").replace("\"", "\\\"")
	if kind == TYPE_DICTIONARY:
		var parts: PackedStringArray = []
		for key in value.keys():
			parts.append("%s:%s" % [_encode_json(str(key)), _encode_json(value[key])])
		return "{%s}" % ",".join(parts)
	if kind == TYPE_ARRAY or kind == TYPE_PACKED_INT32_ARRAY or kind == TYPE_PACKED_INT64_ARRAY or kind == TYPE_PACKED_FLOAT32_ARRAY or kind == TYPE_PACKED_FLOAT64_ARRAY or kind == TYPE_PACKED_STRING_ARRAY:
		var parts: PackedStringArray = []
		for item in value:
			parts.append(_encode_json(item))
		return "[%s]" % ",".join(parts)
	return "null"


func _print_wound_nodes(index: int) -> void:
	var person := _person(index)
	var view := _main.get_node("World")
	var people = view.get("people")
	if not people is Dictionary:
		print("latchsoil: wound view people missing")
		return
	var key := "%d:%d" % [index, _int_of(person.get("generation", -1), -1)]
	var body: Node = people.get(key, null)
	if body == null:
		print("latchsoil: wound view has no body %s" % key)
		return
	var pose := body.get_node_or_null("Pose") as Node3D
	print("latchsoil: wound view pose %s" % str(pose.rotation_degrees if pose != null else "missing"))
	for slot in [REGION_LEFT_LEG, REGION_RIGHT_LEG]:
		var mark := body.get_node_or_null("Pose/Wounds/R%d" % slot) as Node3D
		var stain := body.get_node_or_null("Pose/Wounds/R%d/Stain" % slot) as Node3D
		var wrap := body.get_node_or_null("Pose/Wounds/R%d/Wrap" % slot) as Node3D
		print("latchsoil: wound view leg %d mark %s stain %s wrap %s" % [
			slot,
			str(mark.visible if mark != null else "missing"),
			str(stain.visible if stain != null else "missing"),
			str(wrap.visible if wrap != null else "missing"),
		])
	var left := body.get_node_or_null("Pose/Feet/Left")
	var right := body.get_node_or_null("Pose/Feet/Right")
	var hurt := body.get_node_or_null("HurtMark")
	var stake := body.get_node_or_null("HurtMark/Stake") as Node3D
	print("latchsoil: wound view left_foot %s right_foot %s hurt %s" % [
		str(left.visible if left != null else "missing"),
		str(right.visible if right != null else "missing"),
		str(hurt.visible if hurt != null else "missing"),
	])
	if left is Node3D:
		print("latchsoil: wound view left_foot pos %s" % str((left as Node3D).position))
	if stake != null:
		print("latchsoil: wound view stake pos %s" % str(stake.position))
	var support := body.get_node_or_null("Pose/SupportLeg")
	print("latchsoil: wound view support %s" % str(support.visible if support != null else "missing"))


func _try_limp_walk(actor: Dictionary) -> bool:
	# A move the sim accepts is a real stride. A refusal is not a frame.
	var dest := Vector2(_float_of(actor.get("x"), 0.0) + 6.0, _float_of(actor.get("y"), 0.0) + 4.0)
	var code = _host.call("submit_move", _index_of(actor), _int_of(actor.get("generation", -1), -1), dest.x, dest.y)
	print("latchsoil: wounded submit_move -> %s" % str(code))
	if code == null or int(code) != 0:
		print("latchsoil: wounded move refused; not drawing a walk the sim did not accept")
		return true
	var index := _index_of(actor)
	for _i in 200:
		if not _step():
			return false
		actor = _person(index)
		if _len(actor.get("path", [])) > 0:
			break
	actor = _person(index)
	print("latchsoil: wounded after move path %s dest %s failure %s job %s" % [
		str(_len(actor.get("path", []))),
		str(actor.get("dest", "missing")),
		str(actor.get("failure_text", "missing")),
		str(actor.get("job", "missing")),
	])
	if actor.is_empty() or _len(actor.get("path", [])) == 0:
		print("latchsoil: wounded person has no path; not drawing a walk")
		return true
	if _float_of(_leg_row(actor).get("bleeding", 0.0), 0.0) <= 0.0:
		print("latchsoil: bleed gone before the stride; not drawing a walk")
		return true
	print("latchsoil: limp walk person %s path %d" % [str(index), _len(actor.get("path", []))])
	return await _shoot("wound-walk", "2-wound-walk.png", _point(actor), READ_ORTHO, [index], {})


func _num(value) -> String:
	if value is int or value is float:
		return "%.4f" % float(value)
	return str(value)


func _die(message: String) -> void:
	if _dead:
		return
	_dead = true
	push_error(message)
	print(message)
	get_tree().quit(1)
