extends Node

# Milestone 1a headless acceptance. This scene is a probe, not a rule: it issues
# orders through SimHost and reads the snapshot dictionary back. If the extension
# is missing it quits 3, so a broken build cannot look green.
#
# Reasons this scene covers, by name: "no material" and "no path".
# The other three reasons in the contract (hungry, wounded, night) are produced
# directly in the sim crate's Rust tests, because a scene cannot set hunger.
# Nothing here fakes those three.

const HOST_CLASS := "SimHost"
const SEED := 7
const ACRE := 32.0
const BESIDE_PEG_M := 3.5
const ARRIVE_M := 1.5
const GATHER_NEAR_M := 1.25
const MOVED_M := 4.0
const HUNGER_PER_TICK := 1.0 / 60.0
const MAX_MOVE_TICKS := 200
const MAX_GATHER_TICKS := 800
const MAX_FAIL_TICKS := 80
const METHODS := [
	"new_game", "submit_move", "submit_gather", "submit_eat",
	"frame", "step", "tick", "state_hash",
	"attach", "snapshot", "rejections", "engine_api",
]

var host: Object
var owner_id := 0
var failed := false
var cleaned := false
var acre_min := 0.0
var acre_max := 32.0
var peg := Vector2(16, 16)


func _ready() -> void:
	if not ClassDB.class_exists(HOST_CLASS):
		print("class: %s is not registered" % HOST_CLASS)
		push_error("latchsoil: the extension did not load (%s is not registered)" % HOST_CLASS)
		get_tree().quit(3)
		return

	host = ClassDB.instantiate(HOST_CLASS)
	add_child(host as Node)

	if not require_methods():
		return
	if not require_engine_api():
		return

	owner_id = int(host.call("attach"))
	if owner_id == 0:
		fail("attach", "attach returned 0")
		return

	run_cast()
	if failed:
		return
	run_move()
	if failed:
		return
	run_gather()
	if failed:
		return
	run_eat_empty()
	if failed:
		return
	run_no_path()
	if failed:
		return
	run_stale()
	if failed:
		return
	run_determinism()
	if failed:
		return

	print("1a: ok")
	cleanup()
	get_tree().quit(0)


func require_methods() -> bool:
	var missing: PackedStringArray = []
	for method_name in METHODS:
		if not method_exists(method_name):
			missing.append(method_name)
	if missing.size() > 0:
		fail("missing-method", ", ".join(missing))
		return false
	return true


func method_exists(method_name: String) -> bool:
	if ClassDB.class_has_method(HOST_CLASS, method_name):
		return true
	return host.has_method(method_name)


func require_engine_api() -> bool:
	var api := str(host.call("engine_api"))
	var info: Dictionary = Engine.get_version_info()
	var running := "%d.%d" % [int(info["major"]), int(info["minor"])]
	var parts := api.split(".")
	var compiled := api
	if parts.size() >= 2:
		compiled = "%s.%s" % [parts[0], parts[1]]
	if compiled != running:
		fail("engine_api", "compiled for %s, running %s" % [api, running])
		return false
	return true


func fail(check: String, detail: String) -> void:
	if failed:
		return
	failed = true
	print("%s: %s" % [check, detail])
	push_error("latchsoil: %s: %s" % [check, detail])
	cleanup()
	get_tree().quit(1)


func ok(check: String) -> void:
	if failed:
		return
	print("%s: ok" % check)


func cleanup() -> void:
	if cleaned:
		return
	cleaned = true
	if host != null and is_instance_valid(host):
		var node := host as Node
		if node.get_parent() == self:
			remove_child(node)
		node.free()
		host = null


func snap() -> Dictionary:
	var pulled = host.call("snapshot", owner_id)
	if not (pulled is Dictionary):
		fail("snapshot", "snapshot returned %s" % type_string(typeof(pulled)))
		return {}
	var s: Dictionary = pulled
	if int(s.get("error", -1)) != 0:
		fail("snapshot", "error %s" % str(s.get("error", "?")))
		return {}
	return s


func hash_string() -> String:
	return str(host.call("state_hash"))


func person_by_index(s: Dictionary, index: int) -> Dictionary:
	for person in s.get("people", []):
		if int(person.get("index", -1)) == index:
			return person
	return {}


func node_by_index(s: Dictionary, index: int) -> Dictionary:
	for node in s.get("nodes", []):
		if int(node.get("index", -1)) == index:
			return node
	return {}


func failure_text_of(person: Dictionary) -> String:
	return str(person.get("failure_text", ""))


func array_size(value) -> int:
	if value == null:
		return 0
	return int(value.size())


func in_acre(point: Vector2) -> bool:
	return (
		point.x >= acre_min and point.x < acre_max
		and point.y >= acre_min and point.y < acre_max
	)


func positions_text(s: Dictionary) -> String:
	var bits: PackedStringArray = []
	for person in s.get("people", []):
		bits.append("p%d=(%.2f,%.2f,g=%d)" % [
			int(person.get("index", -1)),
			float(person.get("x", 0.0)),
			float(person.get("y", 0.0)),
			int(person.get("generation", -1)),
		])
	for node in s.get("nodes", []):
		bits.append("n%d=(%.2f,%.2f,rem=%s,yield=%s)" % [
			int(node.get("index", -1)),
			float(node.get("x", 0.0)),
			float(node.get("y", 0.0)),
			str(node.get("remaining", "?")),
			str(node.get("yield_item", "?")),
		])
	return " ".join(bits)


func carried_count(person: Dictionary, item_id: int) -> int:
	var carried = person.get("carried", [])
	var n := array_size(carried)
	if n == 0:
		return 0
	var total := 0
	var first = carried[0]
	if first is Array or first is PackedInt32Array or first is PackedInt64Array:
		for pair in carried:
			if array_size(pair) >= 2 and int(pair[0]) == item_id:
				total += int(pair[1])
		return total
	var i := 0
	while i + 1 < n:
		if int(carried[i]) == item_id:
			total += int(carried[i + 1])
		i += 2
	return total


func catalog_id(item_name: String) -> int:
	if not host.has_method("catalog") and not ClassDB.class_has_method(HOST_CLASS, "catalog"):
		return -1
	var cat = host.call("catalog")
	if not (cat is Dictionary):
		return -1
	for item in cat.get("items", []):
		if str(item.get("name", "")).to_lower() == item_name:
			return int(item.get("id", -1))
	return -1


func wood_node(s: Dictionary) -> Dictionary:
	for node in s.get("nodes", []):
		if int(node.get("remaining", -1)) == 40:
			return node
	var wood_id := catalog_id("wood")
	if wood_id < 0:
		return {}
	for node in s.get("nodes", []):
		if int(node.get("yield_item", -1)) == wood_id:
			return node
	return {}


func drive_one(use_frame: bool) -> int:
	var before := int(host.call("tick"))
	if use_frame:
		# One contract tick is 100 ms. 0.1 is that step, so one call is one tick
		# at speed 1, matching step. Leftover must not accumulate: 0.1 is the
		# boundary, not a chunk.
		host.call("frame", 0.1)
	else:
		host.call("step")
	return int(host.call("tick")) - before


func run_cast() -> void:
	host.call("new_game", SEED)
	var s := snap()
	if failed:
		return
	if int(s.get("tick", -1)) != 0 or int(host.call("tick")) != 0:
		fail("cast", "tick is %s / %s, expected 0" % [str(s.get("tick")), str(host.call("tick"))])
		return
	for key in ["tick", "people", "buildings", "nodes", "removed", "hash", "full", "error"]:
		if not s.has(key):
			fail("cast", "snapshot missing '%s'" % key)
			return
	if int(s["error"]) != 0:
		fail("cast", "snapshot error %s" % str(s["error"]))
		return
	if not bool(s["full"]):
		fail("cast", "snapshot full is false")
		return

	var people: Array = s["people"]
	var nodes: Array = s["nodes"]
	if people.size() != 3:
		fail("cast", "expected 3 people, got %d (%s)" % [people.size(), positions_text(s)])
		return
	if nodes.size() != 6:
		fail("cast", "expected 6 nodes, got %d (%s)" % [nodes.size(), positions_text(s)])
		return

	var seen := {}
	for person in people:
		var index := int(person.get("index", -1))
		seen[index] = true
		if int(person.get("generation", -1)) != 1:
			fail("cast", "person %d generation %s, expected 1" % [index, str(person.get("generation"))])
			return
		if abs(float(person.get("hunger", -1.0)) - 1.0) > 0.0001:
			fail("cast", "person %d hunger %s, expected 1" % [index, str(person.get("hunger"))])
			return
		if array_size(person.get("carried", [])) != 0:
			fail("cast", "person %d is already carrying %s" % [index, str(person.get("carried"))])
			return
	if not seen.has(0) or not seen.has(1) or not seen.has(2):
		fail("cast", "people indices are not 0, 1, 2 (%s)" % positions_text(s))
		return

	if not infer_acre(people, nodes):
		fail("cast", "cast is not inside a 32 m acre centred on the peg (%s)" % positions_text(s))
		return
	ok("cast")


func infer_acre(people: Array, nodes: Array) -> bool:
	var centroid := Vector2.ZERO
	var positions: Array = []
	for person in people:
		var at := Vector2(float(person.get("x", 0.0)), float(person.get("y", 0.0)))
		positions.append(at)
		centroid += at
	centroid /= float(people.size())
	for node in nodes:
		positions.append(Vector2(float(node.get("x", 0.0)), float(node.get("y", 0.0))))

	# The contract says a 32 m square with the peg at its centre, and that a
	# cell origin is the floor of each axis. It does not number the origin.
	# The two readings are [0, 32) peg (16, 16), and [-16, 16) peg (0, 0).
	var options := [
		{"min": 0.0, "max": 32.0, "peg": Vector2(16, 16)},
		{"min": -16.0, "max": 16.0, "peg": Vector2(0, 0)},
	]
	var found := false
	var best := INF
	for opt in options:
		var inside := true
		for point in positions:
			if point.x < opt["min"] or point.x >= opt["max"] or point.y < opt["min"] or point.y >= opt["max"]:
				inside = false
				break
		if not inside:
			continue
		var distance: float = centroid.distance_to(opt["peg"])
		if distance < best:
			best = distance
			acre_min = opt["min"]
			acre_max = opt["max"]
			peg = opt["peg"]
			found = true
	if not found:
		return false
	for person in people:
		var at := Vector2(float(person.get("x", 0.0)), float(person.get("y", 0.0)))
		if at.distance_to(peg) > BESIDE_PEG_M:
			return false
	return true


func point_about_6m(start: Vector2) -> Vector2:
	var offsets: Array[Vector2] = [Vector2(6, 0), Vector2(-6, 0), Vector2(0, 6), Vector2(0, -6)]
	for offset in offsets:
		var point := start + offset
		if in_acre(point):
			return point
	return Vector2(INF, INF)


func run_move() -> void:
	var via_frame := run_move_via(true)
	if failed:
		return
	var via_step := run_move_via(false)
	if failed:
		return
	if via_frame["tick"] != via_step["tick"] or via_frame["hash"] != via_step["hash"]:
		fail("move", "frame and step disagree: frame tick %s hash %s; step tick %s hash %s" % [
			str(via_frame["tick"]), str(via_frame["hash"]),
			str(via_step["tick"]), str(via_step["hash"]),
		])
		return
	var frame_pos: Vector2 = via_frame["pos"]
	var step_pos: Vector2 = via_step["pos"]
	if frame_pos.distance_to(step_pos) > 0.001:
		fail("move", "frame ended at %s, step ended at %s" % [frame_pos, step_pos])
		return
	ok("move")


func run_move_via(use_frame: bool) -> Dictionary:
	var which := "frame" if use_frame else "step"
	host.call("new_game", SEED)
	var s := snap()
	if failed:
		return {}
	var person := person_by_index(s, 0)
	if person.is_empty():
		fail("move", "person 0 missing before %s" % which)
		return {}
	var start := Vector2(float(person["x"]), float(person["y"]))
	var target := point_about_6m(start)
	if not in_acre(target):
		fail("move", "no point about 6 m from %s stays inside the acre" % start)
		return {}
	var code = host.call("submit_move", 0, int(person["generation"]), target.x, target.y)
	if code == null or int(code) != 0:
		fail("move", "submit_move via %s returned %s" % [which, str(code)])
		return {}

	for _i in MAX_MOVE_TICKS:
		var advanced := drive_one(use_frame)
		if advanced != 1:
			fail("move", "%s advanced %d ticks, expected 1" % [which, advanced])
			return {}
		s = snap()
		if failed:
			return {}
		person = person_by_index(s, 0)
		if person.is_empty():
			fail("move", "person 0 disappeared via %s" % which)
			return {}
		var pos := Vector2(float(person["x"]), float(person["y"]))
		var reason := failure_text_of(person)
		if reason != "":
			fail("move", "%s order failed with '%s'" % [which, reason])
			return {}
		if array_size(person.get("path")) != 0:
			continue
		if pos.distance_to(start) < MOVED_M or pos.distance_to(target) > ARRIVE_M:
			continue
		var toward := target - start
		var delta := pos - start
		if delta.dot(toward) <= 0.0 or pos.distance_to(target) >= start.distance_to(target):
			fail("move", "%s did not move toward %s (start %s end %s)" % [which, target, start, pos])
			return {}
		var tick := int(s.get("tick", -1))
		if tick <= 0 or int(host.call("tick")) != tick:
			fail("move", "%s tick did not advance (snapshot %d host %s)" % [which, tick, str(host.call("tick"))])
			return {}
		var hunger := float(person.get("hunger", 1.0))
		var expected := maxf(0.0, 1.0 - float(tick) * HUNGER_PER_TICK)
		if hunger >= 1.0 or abs(hunger - expected) > 0.02:
			fail("move", "%s hunger %s after %d ticks, expected about %s" % [which, hunger, tick, expected])
			return {}
		if int(person.get("failure", -1)) != -1:
			fail("move", "%s failure discriminant %s after a completed move" % [which, str(person.get("failure"))])
			return {}
		return {
			"pos": pos,
			"tick": tick,
			"hash": hash_string(),
			"hunger": hunger,
		}

	fail("move", "%s order did not complete within %d ticks" % [which, MAX_MOVE_TICKS])
	return {}


func run_gather() -> void:
	host.call("new_game", SEED)
	var s := snap()
	if failed:
		return
	var wood := wood_node(s)
	if wood.is_empty():
		fail("gather", "no wood node in the snapshot (%s)" % positions_text(s))
		return
	var named := catalog_id("wood")
	if named >= 0 and int(wood.get("yield_item", -1)) != named:
		fail("gather", "remaining-40 node yields %s, catalog wood is %d" % [str(wood.get("yield_item")), named])
		return
	var yield_id := int(wood["yield_item"])
	var node_index := int(wood["index"])
	var node_pos := Vector2(float(wood["x"]), float(wood["y"]))
	var start_remaining := int(wood["remaining"])
	var person := person_by_index(s, 0)
	if person.is_empty():
		fail("gather", "person 0 missing")
		return
	var code = host.call("submit_gather", 0, int(person["generation"]), node_index, int(wood["generation"]))
	if code == null or int(code) != 0:
		fail("gather", "submit_gather returned %s" % str(code))
		return

	var prev_dist := Vector2(float(person["x"]), float(person["y"])).distance_to(node_pos)
	var was_near := prev_dist <= GATHER_NEAR_M
	for _i in MAX_GATHER_TICKS:
		if drive_one(false) != 1:
			fail("gather", "step did not advance one tick")
			return
		s = snap()
		if failed:
			return
		person = person_by_index(s, 0)
		var node := node_by_index(s, node_index)
		if person.is_empty() or node.is_empty():
			fail("gather", "person or node disappeared")
			return
		var pos := Vector2(float(person["x"]), float(person["y"]))
		var dist := pos.distance_to(node_pos)
		var carried := carried_count(person, yield_id)
		if carried > 0:
			if not was_near or prev_dist > GATHER_NEAR_M:
				fail("gather", "first unit appeared before the person was within %.2f m (previous %.2f)" % [GATHER_NEAR_M, prev_dist])
				return
			if dist > GATHER_NEAR_M:
				fail("gather", "first unit appeared %.2f m from the node" % dist)
				return
			if int(node.get("remaining", start_remaining)) >= start_remaining:
				fail("gather", "remaining did not decrease (%d -> %s)" % [start_remaining, str(node.get("remaining"))])
				return
			ok("gather")
			run_eat_wood(yield_id, carried)
			return
		var reason := failure_text_of(person)
		if reason != "":
			fail("gather", "gather failed with '%s' before a unit appeared" % reason)
			return
		prev_dist = dist
		if dist <= GATHER_NEAR_M:
			was_near = true

	fail("gather", "no carried unit within %d ticks (node %s)" % [MAX_GATHER_TICKS, node_pos])


func run_eat_wood(item_id: int, carried_before: int) -> void:
	var s := snap()
	if failed:
		return
	var person := person_by_index(s, 0)
	var hunger_before := float(person.get("hunger", 0.0))
	# Wood is not food. The order is accepted, then rules refuse it.
	var code = host.call("submit_eat", 0, int(person["generation"]), item_id)
	if code == null or int(code) != 0:
		fail("eat-wood", "submit_eat returned %s" % str(code))
		return
	if not wait_for_reason(0, "no material", "eat-wood"):
		return
	s = snap()
	if failed:
		return
	person = person_by_index(s, 0)
	if failure_text_of(person) != "no material":
		fail("eat-wood", "failure_text '%s', expected 'no material'" % failure_text_of(person))
		return
	if carried_count(person, item_id) != carried_before:
		fail("eat-wood", "refusal changed carried %s from %d to %d" % [str(item_id), carried_before, carried_count(person, item_id)])
		return
	if float(person.get("hunger", 0.0)) > hunger_before + 0.001:
		fail("eat-wood", "refusal restored hunger (%s -> %s)" % [hunger_before, str(person.get("hunger"))])
		return
	ok("eat-wood")


func run_eat_empty() -> void:
	host.call("new_game", SEED)
	var s := snap()
	if failed:
		return
	var wood := wood_node(s)
	if wood.is_empty():
		fail("eat-empty", "no wood node to name a real item id")
		return
	var item_id := int(wood["yield_item"])
	var person := person_by_index(s, 0)
	if person.is_empty():
		fail("eat-empty", "person 0 missing")
		return
	if array_size(person.get("carried", [])) != 0:
		fail("eat-empty", "person 0 is already carrying %s" % str(person.get("carried")))
		return
	var code = host.call("submit_eat", 0, int(person["generation"]), item_id)
	if code == null or int(code) != 0:
		fail("eat-empty", "submit_eat returned %s" % str(code))
		return
	if not wait_for_reason(0, "no material", "eat-empty"):
		return
	s = snap()
	if failed:
		return
	person = person_by_index(s, 0)
	if failure_text_of(person) != "no material":
		fail("eat-empty", "failure_text '%s', expected 'no material'" % failure_text_of(person))
		return
	ok("eat-empty")


func run_no_path() -> void:
	host.call("new_game", SEED)
	var s := snap()
	if failed:
		return
	var person := person_by_index(s, 0)
	if person.is_empty():
		fail("no-path", "person 0 missing")
		return
	var start := Vector2(float(person["x"]), float(person["y"]))
	# 40 m is wider than the acre, so this point is outside whichever origin
	# the cast settled on.
	var target := start + Vector2(40, 0)
	if in_acre(target):
		fail("no-path", "test point %s is still inside the acre" % target)
		return
	var code = host.call("submit_move", 0, int(person["generation"]), target.x, target.y)
	if code == null or int(code) != 0:
		fail("no-path", "submit_move returned %s; an outside point is accepted and then fails in rules" % str(code))
		return
	if not wait_for_reason(0, "no path", "no-path"):
		return
	ok("no-path")


func wait_for_reason(person_index: int, reason: String, check: String) -> bool:
	var expected_code := 1 if reason == "no path" else 2
	for _i in MAX_FAIL_TICKS:
		if drive_one(false) != 1:
			fail(check, "step did not advance one tick")
			return false
		var s := snap()
		if failed:
			return false
		var person := person_by_index(s, person_index)
		if person.is_empty():
			fail(check, "person %d missing while waiting for '%s'" % [person_index, reason])
			return false
		var text := failure_text_of(person)
		if text == "":
			continue
		if text != reason:
			fail(check, "expected '%s', got '%s'" % [reason, text])
			return false
		if array_size(person.get("path")) != 0:
			fail(check, "'%s' left a path %s" % [reason, str(person.get("path"))])
			return false
		if int(person.get("failure", -999)) != expected_code:
			fail(check, "'%s' discriminant %s, expected %d" % [reason, str(person.get("failure")), expected_code])
			return false
		return true
	fail(check, "'%s' did not appear within %d ticks" % [reason, MAX_FAIL_TICKS])
	return false


func people_sig(s: Dictionary) -> String:
	var bits: PackedStringArray = []
	for index in [0, 1, 2]:
		var person := person_by_index(s, index)
		if person.is_empty():
			bits.append("missing-%d" % index)
			continue
		bits.append("%d:%d:%.5f:%.5f:%.5f:%s:%d" % [
			index,
			int(person.get("generation", -1)),
			float(person.get("x", 0.0)),
			float(person.get("y", 0.0)),
			float(person.get("hunger", -1.0)),
			failure_text_of(person),
			array_size(person.get("carried", [])),
		])
	return "|".join(bits)


func rejection_count(key: String) -> int:
	var rej = host.call("rejections")
	if not (rej is Dictionary) or not rej.has(key):
		fail("stale", "rejections missing '%s' (%s)" % [key, str(rej)])
		return -1
	return int(rej[key])


func run_stale() -> void:
	host.call("new_game", SEED)
	var before := snap()
	if failed:
		return
	var before_hash := hash_string()
	var before_tick := int(host.call("tick"))
	var before_sig := people_sig(before)
	var stale_before := rejection_count("stale")
	var malformed_before := rejection_count("malformed")
	var full_before := rejection_count("queue_full")
	if failed:
		return
	# Index 0 is a live person. Generation 0 is never live, so the pair is stale.
	var code = host.call("submit_move", 0, 0, peg.x, peg.y)
	if code == null or int(code) != 2:
		fail("stale", "submit_move(0, 0) returned %s, expected 2" % str(code))
		return
	if rejection_count("stale") != stale_before + 1:
		fail("stale", "stale counter %d -> %d" % [stale_before, rejection_count("stale")])
		return
	if rejection_count("malformed") != malformed_before or rejection_count("queue_full") != full_before:
		fail("stale", "a stale id moved malformed or queue_full")
		return
	var after := snap()
	if failed:
		return
	if int(host.call("tick")) != before_tick or int(after.get("tick", -1)) != before_tick:
		fail("stale", "tick moved on a rejected command")
		return
	if hash_string() != before_hash:
		fail("stale", "hash changed on a rejected command (%s -> %s)" % [before_hash, hash_string()])
		return
	if people_sig(after) != before_sig:
		fail("stale", "people changed on a rejected command")
		return
	if drive_one(false) != 1:
		fail("stale", "step did not advance one tick")
		return
	var rejected_hash := hash_string()
	host.call("new_game", SEED)
	if drive_one(false) != 1:
		fail("stale", "clean step did not advance one tick")
		return
	if hash_string() != rejected_hash:
		fail("stale", "hash after stale submit+step %s != clean step %s" % [rejected_hash, hash_string()])
		return
	ok("stale")


func scripted_hash(seed_value: int) -> String:
	host.call("new_game", seed_value)
	var s := snap()
	if failed:
		return ""
	var person := person_by_index(s, 0)
	if person.is_empty():
		fail("determinism", "person 0 missing for seed %d" % seed_value)
		return ""
	var target := peg + Vector2(6, 0)
	if not in_acre(target):
		target = peg + Vector2(-6, 0)
	var code = host.call("submit_move", 0, int(person["generation"]), target.x, target.y)
	if code == null or int(code) != 0:
		fail("determinism", "submit_move for seed %d returned %s" % [seed_value, str(code)])
		return ""
	for _i in 12:
		if drive_one(false) != 1:
			fail("determinism", "step did not advance one tick")
			return ""
	return hash_string()


func run_determinism() -> void:
	var first := scripted_hash(SEED)
	if failed:
		return
	var second := scripted_hash(SEED)
	if failed:
		return
	var other := scripted_hash(SEED + 1)
	if failed:
		return
	if first == "" or first != second:
		fail("determinism", "same seed hashes differ: '%s' vs '%s'" % [first, second])
		return
	if first == other:
		fail("determinism", "seed %d and seed %d share state_hash %s" % [SEED, SEED + 1, first])
		return
	ok("determinism")
