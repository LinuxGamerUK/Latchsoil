extends Node

# Review driver for the milestone 1a blockout. It instances the real scene and
# calls that scene's methods. It does not draw rings, ribbons, markers, or HUD
# lines of its own, and it does not invent a failure string.

const WALK_TICKS := 8
const CLOSE_SIZE := 12.0
const HOLDING_SIZE := 42.0
const DEST_X := 24.0
const DEST_Y := 22.0
const OUTSIDE_X := 40.0
const OUTSIDE_Y := 16.0
const ACTOR := 0

var _main: Node
var _shots := ""
var _render_out := ""
var _dead := false
var _last_image: Image


func _ready() -> void:
	# The render script sets this so the blockout scene would capture once and
	# quit. Clear it before that scene's _ready reads it. This driver writes
	# the path itself, after the three review shots.
	_render_out = OS.get_environment("LATCHSOIL_SCREENSHOT")
	OS.set_environment("LATCHSOIL_SCREENSHOT", "")
	OS.set_environment("LATCHSOIL_SCREENSHOT_FRAMES", "100000")
	_shots = _prepare_shots_dir()
	if _shots == "":
		return
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	if not bool(_main.get("running")):
		_die("latchsoil: blockout scene did not boot")
		return
	_drive()


func _drive() -> void:
	# Resume just before the first _process, then stop the scene's own clock.
	# Time after this comes only from frame() on the scene's host.
	await get_tree().process_frame
	if _dead:
		return
	_main.set("running", false)

	var host: Object = _main.get("host")
	var owner := int(_main.get("owner_id"))
	# The instantiated scene already called new_game and attach in _boot_sim.
	# Call new_game again so this driver owns the seed, on that same host.
	# new_game keeps owners, so the attach from boot stays valid.
	host.call("new_game", 1)
	if not _pull(host, owner):
		return

	var person := _person(0)
	if person.is_empty():
		_die("latchsoil: person 0 missing after new_game")
		return
	var generation := int(person.get("generation", -1))
	var start := Vector2(float(person.get("x", 0.0)), float(person.get("y", 0.0)))
	# Selection helper used by the click handler after a person pick.
	_main.call("_select", ACTOR, generation, false)
	if int(_main.get("selection").size()) != 1:
		_die("latchsoil: _select did not select one person")
		return

	var code = host.call("submit_move", ACTOR, generation, DEST_X, DEST_Y)
	if code == null or int(code) != 0:
		_die("latchsoil: submit_move returned %s" % str(code))
		return
	for _i in WALK_TICKS:
		host.call("frame", 0.1)
	if not _pull(host, owner):
		return
	_main.call("_refresh_view")

	person = _person(ACTOR)
	var tick := int(_main.get("last_snap").get("tick", -1))
	var walked := Vector2(float(person.get("x", 0.0)), float(person.get("y", 0.0)))
	var path_n := _path_points(person)
	if tick != WALK_TICKS or path_n < 1 or walked.distance_to(start) < 0.4 or walked.distance_to(Vector2(DEST_X, DEST_Y)) < 2.0:
		_die("latchsoil: move was not in flight (tick %d path %d at %s from %s)" % [tick, path_n, walked, start])
		return
	if not _order_visible("move"):
		return
	print("latchsoil: walk tick %d path %d at (%.2f, %.2f) label %s" % [tick, path_n, walked.x, walked.y, _label_text()])

	if not await _save_aimed("shot-a", "shot-a-close-selected.png", CLOSE_SIZE, true):
		return

	var peg: Vector3 = _main.get_node("World").call("peg_position")
	_aim(HOLDING_SIZE, peg)
	if not await _save("shot-b", "shot-b-holding-selected.png"):
		return

	code = host.call("submit_move", ACTOR, generation, OUTSIDE_X, OUTSIDE_Y)
	if code == null or int(code) != 0:
		_die("latchsoil: outside submit_move returned %s" % str(code))
		return
	var reason := ""
	for _i in 4:
		host.call("frame", 0.1)
		if not _pull(host, owner):
			return
		_main.call("_refresh_view")
		reason = _hud_reason()
		if reason != "":
			break
	person = _person(ACTOR)
	var sim_reason := str(person.get("failure_text", ""))
	if sim_reason != "no path" or reason != sim_reason:
		_die("latchsoil: failure line is '%s' (sim '%s'), expected no path" % [reason, sim_reason])
		return
	if _path_points(person) != 0:
		_die("latchsoil: refused move still has a path")
		return
	print("latchsoil: fail tick %d hud '%s'" % [int(_main.get("last_snap").get("tick", -1)), reason])

	if not await _save_aimed("shot-c", "shot-c-failure.png", CLOSE_SIZE, false):
		return

	if _render_out != "" and _last_image != null:
		var copy_err := _last_image.save_png(_render_out)
		if copy_err != OK:
			_die("latchsoil: screenshot save failed")
			return
		print("latchsoil: screenshot %s" % _render_out)

	print("latchsoil: shots done")
	get_tree().quit(0)


func _pull(host: Object, owner: int) -> bool:
	var snap = host.call("poll", owner)
	if not snap is Dictionary or int(snap.get("error", -1)) != 0:
		_die("latchsoil: poll failed (%s)" % str(snap))
		return false
	_main.set("last_snap", snap)
	return true


func _person(index: int) -> Dictionary:
	var rows = _main.get("last_snap").get("people", [])
	if rows is Array:
		for row in rows:
			if row is Dictionary and int(row.get("index", -1)) == index:
				return row
	return {}


func _path_points(person: Dictionary) -> int:
	var path = person.get("path", [])
	var n := 0
	if path is PackedFloat32Array or path is PackedFloat64Array or path is Array:
		n = int(path.size())
	return n / 2


func _order_visible(expected_label: String) -> bool:
	var body := _actor_body()
	if body == null:
		_die("latchsoil: selected body was not drawn")
		return false
	var ring := body.get_node_or_null("Ring")
	var label := body.get_node_or_null("JobLabel") as Label3D
	if ring == null or not ring.visible or label == null or label.text != expected_label:
		_die("latchsoil: ring or job label missing (label '%s')" % _label_text())
		return false
	if label.visible != _expect_label_visible():
		_die("latchsoil: job label visibility wrong at ortho %.1f (visible %s, text '%s')" % [_view_ortho(), label.visible, label.text])
		return false
	var key := "%d:%d" % [ACTOR, int(body.get_meta("generation"))]
	var view := _main.get_node("World")
	var ribbon = view.get("path_meshes").get(key)
	var marker = view.get("dest_markers").get(key)
	if ribbon == null or not ribbon.visible or marker == null or not marker.visible:
		_die("latchsoil: path ribbon or destination marker was not drawn")
		return false
	return true


func _actor_body() -> Node:
	var view := _main.get_node("World")
	var people: Dictionary = view.get("people")
	for key in people.keys():
		var body: Node = people[key]
		if int(body.get_meta("index")) == ACTOR:
			return body
	return null


func _label_text() -> String:
	var body := _actor_body()
	if body == null:
		return ""
	var label := body.get_node_or_null("JobLabel") as Label3D
	if label == null:
		return ""
	return label.text


func _hud_reason() -> String:
	var reason := _main.get_node_or_null("HUD/Reason") as Label
	if reason == null or not reason.visible:
		return ""
	return reason.text


func _aim(size: float, at: Vector3) -> void:
	var rig := _main.get_node("CameraRig") as Node3D
	# The rig pans itself while keys are down. A review frame must not drift.
	rig.set_process(false)
	rig.set_physics_process(false)
	rig.position = at
	rig.set("ortho_size", size)
	rig.set("yaw_deg", 45.0)
	rig.call("_apply_camera")
	rig.force_update_transform()


func _actor_focus(include_order: bool) -> Vector3:
	var body := _actor_body()
	var at := Vector3(16.0, 0.0, 16.0)
	if body != null:
		at = body.global_position
	if not include_order or body == null:
		return at
	var key := "%d:%d" % [ACTOR, int(body.get_meta("generation"))]
	var marker: Node3D = _main.get_node("World").get("dest_markers").get(key)
	if marker != null and marker.visible:
		return at.lerp(marker.global_position, 0.28)
	return at


func _save_aimed(tag: String, file_name: String, size: float, include_order: bool) -> bool:
	for _i in 4:
		_aim(size, _actor_focus(include_order))
		await RenderingServer.frame_post_draw
		if _dead:
			return false
		var camera := _main.get_node("CameraRig/Camera3D") as Camera3D
		var body := _actor_body()
		if body == null or camera == null:
			break
		var screen := camera.unproject_position(body.global_position)
		var view := get_viewport().get_visible_rect().size
		if screen.x > 80.0 and screen.y > 80.0 and screen.x < view.x - 80.0 and screen.y < view.y - 80.0:
			break
	return await _save(tag, file_name)


func _save(tag: String, file_name: String) -> bool:
	var path := _shots.path_join(file_name)
	var image: Image = null
	for _i in 8:
		await RenderingServer.frame_post_draw
		if _dead:
			return false
		image = get_viewport().get_texture().get_image()
		if _drawn(image):
			break
	if not _drawn(image):
		_die("latchsoil: viewport was empty for %s" % file_name)
		return false
	var err := image.save_png(path)
	if err != OK:
		_die("latchsoil: could not save %s" % path)
		return false
	_last_image = image
	if not _print_poses(tag):
		return false
	print("%s %s" % [tag, path])
	return true


func _print_poses(tag: String) -> bool:
	# Captured after the workaround that re-pinned the body is gone. The
	# snapshot x,y must match the body global x,z or the scene is still wrong.
	var rows = _main.get("last_snap").get("people", [])
	var people: Dictionary = _main.get_node("World").get("people")
	if not rows is Array:
		_die("latchsoil: pose %s has no people" % tag)
		return false
	var worst := 0.0
	var found := 0
	for row in rows:
		if not row is Dictionary:
			continue
		var index := int(row.get("index", -1))
		var generation := int(row.get("generation", -1))
		var key := "%d:%d" % [index, generation]
		var body: Node3D = people.get(key)
		var sx := float(row.get("x", 0.0))
		var sy := float(row.get("y", 0.0))
		if body == null:
			_die("latchsoil: pose %s person %d has no body" % [tag, index])
			return false
		var bx := body.global_position.x
		var bz := body.global_position.z
		var delta := Vector2(sx - bx, sy - bz).length()
		worst = maxf(worst, delta)
		found += 1
		print("latchsoil: pose %s person %d snap (%.4f, %.4f) body (%.4f, %.4f) delta %.4f" % [tag, index, sx, sy, bx, bz, delta])
	if found == 0:
		_die("latchsoil: pose %s compared no people" % tag)
		return false
	var actor := _actor_body()
	var label: Label3D = null
	var ring: Node3D = null
	if actor != null:
		label = actor.get_node_or_null("JobLabel") as Label3D
		ring = actor.get_node_or_null("Ring") as Node3D
	var label_on := label != null and label.visible
	var ring_on := ring != null and ring.visible
	var ribbon_on := false
	var marker_on := false
	var label_text := ""
	if label != null:
		label_text = label.text
	if actor != null:
		var actor_key := "%d:%d" % [ACTOR, int(actor.get_meta("generation"))]
		var view := _main.get_node("World")
		var ribbon = view.get("path_meshes").get(actor_key)
		var marker = view.get("dest_markers").get(actor_key)
		ribbon_on = ribbon != null and ribbon.visible
		marker_on = marker != null and marker.visible
	print("latchsoil: pose %s ortho %.2f label '%s' visible %s ring %s ribbon %s marker %s" % [
		tag, _view_ortho(), label_text, label_on, ring_on, ribbon_on, marker_on
	])
	if worst > 0.05:
		_die("latchsoil: body left the snapshot by %.4f m" % worst)
		return false
	if label_on != _expect_label_visible():
		_die("latchsoil: job label visibility wrong at capture %s" % tag)
		return false
	return true


func _expect_label_visible() -> bool:
	var hide_above := 30.0
	var stored = _main.get_node("World").get("label_hide_above")
	if stored is float or stored is int:
		hide_above = float(stored)
	return _view_ortho() <= hide_above


func _view_ortho() -> float:
	return float(_main.get_node("CameraRig").get("ortho_size"))


func _drawn(image: Image) -> bool:
	if image == null or image.is_empty() or image.get_width() < 2 or image.get_height() < 2:
		return false
	var a := image.get_pixel(8, 8)
	var b := image.get_pixel(image.get_width() / 2, image.get_height() / 2)
	var c := image.get_pixel(image.get_width() - 8, image.get_height() - 8)
	return a != b or b != c


func _prepare_shots_dir() -> String:
	var raw := OS.get_environment("LATCHSOIL_SHOTS_DIR")
	if raw == "":
		raw = "user://"
	var path := raw
	if raw.begins_with("user://") or raw.begins_with("res://"):
		path = ProjectSettings.globalize_path(raw)
	var err := DirAccess.make_dir_recursive_absolute(path)
	if err != OK and err != ERR_ALREADY_EXISTS:
		_die("latchsoil: could not create shots directory")
		return ""
	return path


func _die(message: String) -> void:
	if _dead:
		return
	_dead = true
	push_error(message)
	print(message)
	get_tree().quit(1)
