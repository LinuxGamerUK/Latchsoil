extends Node

# Headless acceptance. This scene is a probe, not a rule: it issues orders
# through SimHost and reads the snapshot dictionary back. If the extension is
# missing it quits 3, so a broken build cannot look green.
#
# Milestone 1a is the default, so a missing 1b or 2 rule cannot fail that gate.
# Milestone 1b runs only when the check script asks for it: LATCHSOIL_CHECK=1b,
# or a user argument "1b" after --. Milestone 2 is LATCHSOIL_CHECK=2, or "2".
#
# Reasons 1a covers, by name: "no material" and "no path".
# The other three reasons in the contract (hungry, wounded, night) are produced
# directly in the sim crate's Rust tests, because a scene cannot set hunger.
# Nothing here fakes those three.
#
# Reasons 1b covers, by name: "no station" and "no material".
# The line is the snapshot's failure_text. This scene does not keep a second
# wording and does not map a discriminant to a string of its own.
#
# Reasons 2 covers, by name: "no skill", "tired", and "wounded" when a person
# at the sickness line tries to treat themselves. The line is still the
# snapshot's failure_text. A wound is set by editing the save and loading it
# back: no rule wounds anybody until milestone 5, so the check says so.

const HOST_CLASS := "SimHost"
const SEED := 7
const ACRE := 32.0
const BESIDE_PEG_M := 3.5
const ARRIVE_M := 1.5
const GATHER_NEAR_M := 1.25
const MOVED_M := 4.0
# The bridge contract's rate, kept here as the harness's own copy rather than
# read from the sim: a full person is empty after two days of 7200 ticks.
const HUNGER_FULL_TICKS := 14400.0
const HUNGER_PER_TICK := 1.0 / HUNGER_FULL_TICKS
# Grain each person of the starting cast carries: the Harth kit's ration.
const RATION := 4
const MAX_MOVE_TICKS := 200
const MAX_GATHER_TICKS := 800
const MAX_FAIL_TICKS := 80
# Milestone 1b contract numbers, held here rather than read from the sim.
const BUILD_TICKS := 60
const HAUL_TICKS_PER_UNIT := 5
const TAKE_TICKS_PER_UNIT := 3
const STATION_RANGE_M := 2.0
const STOCKPILE_CAPACITY := 200
const MEAL_TICKS := 30
const KNIFE_TICKS := 60
const BANDAGE_TICKS := 40
const CAMPFIRE := 0
const STOCKPILE := 2
const RECIPE_KNIFE := 0
const RECIPE_MEAL := 1
const ITEM_GRAIN := 0
const ITEM_WOOD := 1
const ITEM_STONE := 2
const ITEM_WATER := 4
const ITEM_MEAL := 6
const NO_STATION := 7
# The contract's current save version, held here rather than read from the sim.
# Bump it with the contract: a version move the harness is not told about fails
# loudly, which is the point of keeping a copy at all.
const SAVE_VERSION := 3
const BLEED_HEALTH_PER_TICK := 1.0 / 7200.0
const HEAL_TICKS := 60
const INFECTION_PER_TICK := 1.0 / 28800.0
const INFECTION_SICK := 0.5
const INFECTION_HEALTH_PER_TICK := 1.0 / 14400.0
const SALVE_INFECTION_CUT := 0.5
const MEDICINE_SKILL_MIN := 0.25
const AMBIENT_WARMTH_DAY := 0.9
const AMBIENT_WARMTH_NIGHT := 0.0
const LEANTO_WARMTH := 0.6
# Drift raised, drain reduced, so the rule fires in ordinary play: 0.9 of
# warmth falls to zero in 1080 ticks, inside a 1440-tick night, and the last
# 360 ticks cost about 0.10 health. Do not put 1/2400 and 1/7200 back.
const WARMTH_DRIFT_PER_TICK := 1.0 / 1200.0
const WARMTH_RANGE_M := 3.0
const COLD_HEALTH_PER_TICK := 1.0 / 3600.0
const FATIGUE_REFUSAL := 0.85
const SLEEP_RECOVER_PER_TICK := 1.0 / 2400.0
const SKILL_PER_UNIT := 0.01
const SKILL_TIME_RELIEF := 0.4
const GATHER_TICKS_PER_UNIT := 20
const NIGHT_START := 5760
const TICKS_PER_DAY := 7200
const JOB_HAUL := 0
const JOB_REST := 7
const LEAN_TO := 1
const ITEM_BANDAGE := 7
const ITEM_SALVE := 8
const REGION_HEAD := 0
const REGION_TORSO := 1
const REGION_COUNT := 6
const SKILL_GATHER := 0
const SKILL_MEDICINE := 3
const SKILL_COUNT := 4
const TIRED := 8
const WOUNDED := 6
const MAX_HEAL_TICKS := 200 + HEAL_TICKS
const MAX_SKILL_TICKS := 1200
# No rule wounds anybody until milestone 5. The check says so when it does.
const WOUND_BY_HAND := "the wound was set by hand in the save, because no rule wounds anybody until milestone 5"
# Walk across the acre, then the contract's own work time.
const MAX_BUILD_TICKS := 400 + BUILD_TICKS
const MAX_HAUL_TICKS := 400 + RATION * HAUL_TICKS_PER_UNIT
const MAX_TAKE_TICKS := 200 + RATION * TAKE_TICKS_PER_UNIT
const MAX_CRAFT_TICKS := 200 + MEAL_TICKS
const METHODS_1B := [
	"submit_place", "submit_craft", "submit_haul", "submit_take",
	"save_json", "load_json",
]
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

	if harness_mode() == "1b":
		run_milestone_1b()
		return
	if harness_mode() == "2":
		run_milestone_2()
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
		# The Harth kit's ration. Milestone 1a has no food in the world, so this
		# is the only reason `Eat` can succeed at all.
		var ration := carried_count(person, catalog_id("grain"))
		if ration != 4:
			fail("cast", "person %d carries %d grain, expected 4 (%s)" % [index, ration, str(person.get("carried"))])
			return
		if array_size(person.get("carried", [])) != 1:
			fail("cast", "person %d carries more than grain: %s" % [index, str(person.get("carried"))])
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
	# The cast starts with the Harth ration, so empty the hands by eating it and
	# then ask for one more: 'no material' is about having nothing left to eat.
	var grain_id := catalog_id("grain")
	if grain_id < 0:
		fail("eat-empty", "no grain item in the catalog")
		return
	var person := person_by_index(s, 0)
	if person.is_empty():
		fail("eat-empty", "person 0 missing")
		return
	if carried_count(person, grain_id) != RATION:
		fail("eat-empty", "person 0 carries %s, expected %d grain" % [str(person.get("carried")), RATION])
		return
	for _i in RATION:
		var bite = host.call("submit_eat", 0, int(person["generation"]), grain_id)
		if bite == null or int(bite) != 0:
			fail("eat-empty", "submit_eat returned %s" % str(bite))
			return
		if drive_one(false) != 1:
			fail("eat-empty", "step did not advance one tick")
			return
	s = snap()
	if failed:
		return
	person = person_by_index(s, 0)
	if carried_count(person, grain_id) != 0:
		fail("eat-empty", "ration still carried after %d meals: %s" % [RATION, str(person.get("carried"))])
		return
	var code = host.call("submit_eat", 0, int(person["generation"]), grain_id)
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
	var expected_code := reason_code(reason)
	if expected_code < 0:
		fail(check, "no discriminant for '%s'" % reason)
		return false
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


func harness_mode() -> String:
	var asked := OS.get_environment("LATCHSOIL_CHECK")
	if asked == "1b" or asked == "2":
		return asked
	for arg in OS.get_cmdline_user_args():
		var name := str(arg)
		if name == "1b" or name == "2":
			return name
	return "1a"


func reason_code(reason: String) -> int:
	# Discriminants from the bridge contract, held here. Callers still read
	# failure_text from the snapshot; this scene does not invent the line.
	if reason == "hungry":
		return 0
	if reason == "no path":
		return 1
	if reason == "no material":
		return 2
	if reason == "no skill":
		return 3
	if reason == "afraid":
		return 4
	if reason == "night":
		return 5
	if reason == "wounded":
		return 6
	if reason == "no station":
		return NO_STATION
	if reason == "tired":
		return TIRED
	return -1


func run_milestone_1b() -> void:
	# Surface the 1b methods name. Each check requires the one it calls, so a
	# missing take does not hide a place failure.
	var _surface := METHODS_1B
	run_place()
	if failed:
		return
	run_no_station()
	if failed:
		return
	run_craft_material()
	if failed:
		return
	run_craft_meal()
	if failed:
		return
	run_stockpile()
	if failed:
		return
	run_save()
	if failed:
		return
	print("1b: ok")
	cleanup()
	get_tree().quit(0)


func require_method(method_name: String, check: String) -> bool:
	if method_exists(method_name):
		return true
	fail(check, "SimHost has no %s" % method_name)
	return false


func begin(check: String) -> bool:
	host.call("new_game", SEED)
	var s := snap()
	if failed:
		return false
	var people: Array = s.get("people", [])
	if people.size() < 1 or not infer_acre(people, s.get("nodes", [])):
		fail(check, "cast is not inside a 32 m acre (%s)" % positions_text(s))
		return false
	return true


func resolved_id(check: String, kind: String, row_name: String, expected: int) -> int:
	var found := -1
	if kind == "item":
		found = catalog_id(row_name)
	else:
		found = recipe_id(row_name)
	if found < 0:
		return expected
	if found != expected:
		fail(check, "catalog %s '%s' is %d, contract says %d" % [kind, row_name, found, expected])
		return -1
	return found


func recipe_id(recipe_name: String) -> int:
	if not host.has_method("catalog") and not ClassDB.class_has_method(HOST_CLASS, "catalog"):
		return -1
	var cat = host.call("catalog")
	if not (cat is Dictionary):
		return -1
	for recipe in cat.get("recipes", []):
		if str(recipe.get("name", "")).to_lower() == recipe_name:
			return int(recipe.get("id", -1))
	return -1


func cell_origin(point: Vector2) -> Vector2:
	return Vector2(floor(point.x), floor(point.y))


func peg_cell() -> Vector2:
	return cell_origin(peg)


func cell_is_taken(cell: Vector2, taken: Array) -> bool:
	for point in taken:
		if cell.distance_to(Vector2(point)) < 0.01:
			return true
	return false


func occupied_cells(s: Dictionary) -> Array:
	var taken: Array = [peg_cell()]
	for building in s.get("buildings", []):
		taken.append(cell_origin(Vector2(float(building.get("x", 0.0)), float(building.get("y", 0.0)))))
	for node in s.get("nodes", []):
		taken.append(cell_origin(Vector2(float(node.get("x", 0.0)), float(node.get("y", 0.0)))))
	return taken


func free_cell(origin: Vector2, taken: Array) -> Vector2:
	# Far enough that the person is outside STATION_RANGE_M, so the first
	# snapshot of a new building is the applying tick at progress 0.
	var base := cell_origin(origin)
	var offsets: Array[Vector2] = [
		Vector2(4, 0), Vector2(-4, 0), Vector2(0, 4), Vector2(0, -4),
		Vector2(4, 2), Vector2(-4, 2), Vector2(2, 4), Vector2(-2, 4),
		Vector2(5, -1), Vector2(-5, 1), Vector2(1, -5), Vector2(-1, 5),
		Vector2(6, 2), Vector2(-6, -2), Vector2(3, 5), Vector2(-3, -5),
	]
	for offset in offsets:
		var cell: Vector2 = base + offset
		if not in_acre(cell) or cell.distance_to(peg_cell()) < 0.01 or cell_is_taken(cell, taken):
			continue
		return cell
	return Vector2(INF, INF)


func building_by_index(s: Dictionary, index: int) -> Dictionary:
	for building in s.get("buildings", []):
		if int(building.get("index", -1)) == index:
			return building
	return {}


func building_at(rows: Array, at: Vector2) -> Dictionary:
	for building in rows:
		var pos := Vector2(float(building.get("x", INF)), float(building.get("y", INF)))
		if pos.distance_to(at) < 0.01:
			return building
	return {}


func buildings_of_kind(s: Dictionary, kind: int) -> Array:
	var found: Array = []
	for building in s.get("buildings", []):
		if int(building.get("kind", -1)) == kind:
			found.append(building)
	return found


func store_count(building: Dictionary, item_id: int) -> int:
	if not building.has("contents"):
		return -1
	return carried_count({"carried": building.get("contents", [])}, item_id)


func inventory_sig(carried) -> String:
	var bits: PackedStringArray = []
	for item_id in [ITEM_GRAIN, ITEM_WOOD, ITEM_STONE, ITEM_WATER, ITEM_MEAL]:
		var n := carried_count({"carried": carried}, item_id)
		if n > 0:
			bits.append("%d=%d" % [item_id, n])
	if bits.is_empty():
		return "-"
	return ",".join(bits)


func building_sig(s: Dictionary) -> String:
	var bits: PackedStringArray = []
	for building in s.get("buildings", []):
		var contents := "missing"
		if building.has("contents"):
			contents = inventory_sig(building.get("contents", []))
		bits.append("%s:%s:%s:%s:%s" % [
			str(building.get("index", -1)),
			str(building.get("generation", -1)),
			str(building.get("kind", -1)),
			str(building.get("progress", -1)),
			contents,
		])
	return "|".join(bits)


func node_by_yield(s: Dictionary, item_id: int) -> Dictionary:
	for node in s.get("nodes", []):
		if int(node.get("yield_item", -1)) == item_id:
			return node
	return {}


func gather_one(check: String, item_name: String, item_id: int) -> bool:
	var s := snap()
	if failed:
		return false
	var node := node_by_yield(s, item_id)
	if node.is_empty():
		fail(check, "no %s node in the snapshot" % item_name)
		return false
	var person := person_by_index(s, 0)
	if person.is_empty():
		fail(check, "person 0 missing before gather")
		return false
	var before := carried_count(person, item_id)
	var code = host.call(
		"submit_gather", 0, int(person["generation"]),
		int(node["index"]), int(node["generation"])
	)
	if code == null or int(code) != 0:
		fail(check, "submit_gather %s returned %s" % [item_name, str(code)])
		return false
	for _i in MAX_GATHER_TICKS:
		if drive_one(false) != 1:
			fail(check, "step did not advance one tick")
			return false
		s = snap()
		if failed:
			return false
		person = person_by_index(s, 0)
		if carried_count(person, item_id) > before:
			return true
		var reason := failure_text_of(person)
		if reason != "":
			fail(check, "gather %s failed with '%s'" % [item_name, reason])
			return false
	fail(check, "no %s gathered within %d ticks" % [item_name, MAX_GATHER_TICKS])
	return false


func ensure_in_range(check: String, building: Dictionary) -> bool:
	var at := Vector2(float(building.get("x", 0.0)), float(building.get("y", 0.0)))
	var s := snap()
	if failed:
		return false
	var person := person_by_index(s, 0)
	var pos := Vector2(float(person.get("x", 0.0)), float(person.get("y", 0.0)))
	if pos.distance_to(at) <= STATION_RANGE_M:
		return true
	var code = host.call("submit_move", 0, int(person["generation"]), at.x, at.y)
	if code == null or int(code) != 0:
		fail(check, "submit_move back to the station returned %s" % str(code))
		return false
	for _i in MAX_MOVE_TICKS:
		if drive_one(false) != 1:
			fail(check, "step did not advance one tick")
			return false
		s = snap()
		if failed:
			return false
		person = person_by_index(s, 0)
		pos = Vector2(float(person.get("x", 0.0)), float(person.get("y", 0.0)))
		var reason := failure_text_of(person)
		if reason != "":
			fail(check, "walk back to the station failed with '%s'" % reason)
			return false
		if pos.distance_to(at) <= STATION_RANGE_M:
			return true
	fail(check, "person stayed %.2f m from the station" % pos.distance_to(at))
	return false


func finish_placed(check: String, kind: int, at: Vector2) -> Dictionary:
	if not require_method("submit_place", check):
		return {}
	var before := snap()
	if failed:
		return {}
	var person := person_by_index(before, 0)
	if person.is_empty():
		fail(check, "person 0 missing")
		return {}
	var before_count := buildings_of_kind(before, kind).size()
	var code = host.call("submit_place", 0, int(person["generation"]), kind, at.x, at.y)
	if code == null or int(code) != 0:
		fail(check, "submit_place returned %s" % str(code))
		return {}
	var appeared := {}
	var saw_zero := false
	var saw_mid := false
	var prev := -1
	for _i in MAX_BUILD_TICKS:
		if drive_one(false) != 1:
			fail(check, "step did not advance one tick")
			return {}
		var s := snap()
		if failed:
			return {}
		var rows := buildings_of_kind(s, kind)
		if rows.size() <= before_count:
			continue
		appeared = building_at(rows, at)
		if appeared.is_empty():
			fail(check, "a building of kind %d appeared, but not at %s" % [kind, at])
			return {}
		if not appeared.has("progress"):
			fail(check, "building snapshot has no progress (%s)" % str(appeared.keys()))
			return {}
		var progress := int(appeared["progress"])
		if not saw_zero and not saw_mid and prev < 0 and progress != 0:
			fail(check, "building appeared at progress %d, expected 0" % progress)
			return {}
		if progress == 0:
			saw_zero = true
		if progress > 0 and progress < BUILD_TICKS:
			saw_mid = true
		if progress > BUILD_TICKS:
			fail(check, "progress %d exceeded BUILD_TICKS %d" % [progress, BUILD_TICKS])
			return {}
		if prev >= 0 and progress < prev:
			fail(check, "progress fell %d -> %d" % [prev, progress])
			return {}
		prev = progress
		if progress == BUILD_TICKS:
			if not saw_zero:
				fail(check, "progress reached %d without starting at 0" % BUILD_TICKS)
				return {}
			if not saw_mid:
				fail(check, "progress jumped to %d without a value in between" % BUILD_TICKS)
				return {}
			return appeared
	fail(check, "progress did not reach %d within %d ticks (last %d)" % [BUILD_TICKS, MAX_BUILD_TICKS, prev])
	return {}


func run_place() -> void:
	if not begin("place"):
		return
	var s := snap()
	if failed:
		return
	var person := person_by_index(s, 0)
	var at := free_cell(Vector2(float(person["x"]), float(person["y"])), occupied_cells(s))
	if not at.is_finite():
		fail("place", "no free cell inside the acre")
		return
	var building := finish_placed("place", CAMPFIRE, at)
	if failed or building.is_empty():
		return
	if int(building.get("kind", -1)) != CAMPFIRE:
		fail("place", "kind %s, expected campfire %d" % [str(building.get("kind")), CAMPFIRE])
		return
	if int(building.get("progress", -1)) != BUILD_TICKS:
		fail("place", "progress %s, expected %d" % [str(building.get("progress")), BUILD_TICKS])
		return
	ok("place")


func run_no_station() -> void:
	if not begin("no-station"):
		return
	if not require_method("submit_craft", "no-station"):
		return
	var water_id := resolved_id("no-station", "item", "water", ITEM_WATER)
	var grain_id := resolved_id("no-station", "item", "grain", ITEM_GRAIN)
	var recipe := resolved_id("no-station", "recipe", "meal", RECIPE_MEAL)
	if failed or water_id < 0 or grain_id < 0 or recipe < 0:
		return
	if not gather_one("no-station", "water", water_id):
		return
	var s := snap()
	if failed:
		return
	var person := person_by_index(s, 0)
	var grain_before := carried_count(person, grain_id)
	var water_before := carried_count(person, water_id)
	if grain_before < 1 or water_before < 1:
		fail("no-station", "inputs missing before the craft (grain %d water %d)" % [grain_before, water_before])
		return
	# No campfire. NoMaterial precedes NoStation, so the inputs have to be in
	# hand or the sim is right to say no material instead.
	var code = host.call("submit_craft", 0, int(person["generation"]), recipe)
	if code == null or int(code) != 0:
		fail("no-station", "submit_craft returned %s" % str(code))
		return
	if not wait_for_reason(0, "no station", "no-station"):
		return
	s = snap()
	if failed:
		return
	person = person_by_index(s, 0)
	# The line is the sim's. Do not substitute a local wording.
	if failure_text_of(person) != "no station":
		fail("no-station", "failure_text '%s', expected the sim string 'no station'" % failure_text_of(person))
		return
	if int(person.get("failure", -999)) != NO_STATION:
		fail("no-station", "discriminant %s, expected %d" % [str(person.get("failure")), NO_STATION])
		return
	if carried_count(person, grain_id) != grain_before or carried_count(person, water_id) != water_before:
		fail("no-station", "refusal consumed inputs")
		return
	ok("no-station")


func run_craft_material() -> void:
	if not begin("craft-material"):
		return
	if not require_method("submit_craft", "craft-material"):
		return
	var wood_id := resolved_id("craft-material", "item", "wood", ITEM_WOOD)
	var stone_id := resolved_id("craft-material", "item", "stone", ITEM_STONE)
	var recipe := resolved_id("craft-material", "recipe", "knife", RECIPE_KNIFE)
	if failed or wood_id < 0 or stone_id < 0 or recipe < 0:
		return
	var s := snap()
	if failed:
		return
	var person := person_by_index(s, 0)
	if carried_count(person, wood_id) != 0 or carried_count(person, stone_id) != 0:
		fail("craft-material", "person already carries a knife input (%s)" % str(person.get("carried")))
		return
	var tick_before := int(host.call("tick"))
	var code = host.call("submit_craft", 0, int(person["generation"]), recipe)
	if code == null or int(code) != 0:
		fail("craft-material", "submit_craft returned %s" % str(code))
		return
	if not wait_for_reason(0, "no material", "craft-material"):
		return
	var elapsed := int(host.call("tick")) - tick_before
	if elapsed >= KNIFE_TICKS:
		fail("craft-material", "missing input failed after %d ticks; a knife takes %d and must fail when it starts" % [elapsed, KNIFE_TICKS])
		return
	s = snap()
	if failed:
		return
	person = person_by_index(s, 0)
	if failure_text_of(person) != "no material":
		fail("craft-material", "failure_text '%s', expected 'no material'" % failure_text_of(person))
		return
	if carried_count(person, wood_id) != 0 or carried_count(person, stone_id) != 0:
		fail("craft-material", "refusal changed carried goods %s" % str(person.get("carried")))
		return
	ok("craft-material")


func run_craft_meal() -> void:
	if not begin("craft-meal"):
		return
	if not require_method("submit_craft", "craft-meal"):
		return
	var water_id := resolved_id("craft-meal", "item", "water", ITEM_WATER)
	var grain_id := resolved_id("craft-meal", "item", "grain", ITEM_GRAIN)
	var recipe := resolved_id("craft-meal", "recipe", "meal", RECIPE_MEAL)
	if failed or water_id < 0 or grain_id < 0 or recipe < 0:
		return
	if not gather_one("craft-meal", "water", water_id):
		return
	var s := snap()
	if failed:
		return
	var person := person_by_index(s, 0)
	var at := free_cell(Vector2(float(person["x"]), float(person["y"])), occupied_cells(s))
	if not at.is_finite():
		fail("craft-meal", "no free cell for the campfire")
		return
	var building := finish_placed("craft-meal", CAMPFIRE, at)
	if failed or building.is_empty():
		return
	if not ensure_in_range("craft-meal", building):
		return
	s = snap()
	if failed:
		return
	person = person_by_index(s, 0)
	var grain_before := carried_count(person, grain_id)
	var water_before := carried_count(person, water_id)
	var meal_before := carried_count(person, ITEM_MEAL)
	if grain_before < 1 or water_before < 1:
		fail("craft-meal", "inputs missing beside the finished campfire (grain %d water %d)" % [grain_before, water_before])
		return
	var tick_before := int(host.call("tick"))
	var code = host.call("submit_craft", 0, int(person["generation"]), recipe)
	if code == null or int(code) != 0:
		fail("craft-meal", "submit_craft returned %s" % str(code))
		return
	for _i in MAX_CRAFT_TICKS:
		if drive_one(false) != 1:
			fail("craft-meal", "step did not advance one tick")
			return
		s = snap()
		if failed:
			return
		person = person_by_index(s, 0)
		var reason := failure_text_of(person)
		if reason != "":
			fail("craft-meal", "craft failed with '%s'" % reason)
			return
		if carried_count(person, ITEM_MEAL) <= meal_before:
			continue
		var elapsed := int(host.call("tick")) - tick_before
		if elapsed < MEAL_TICKS:
			fail("craft-meal", "meal appeared after %d ticks, recipe takes %d" % [elapsed, MEAL_TICKS])
			return
		if carried_count(person, grain_id) != grain_before - 1 or carried_count(person, water_id) != water_before - 1:
			fail("craft-meal", "meal did not consume one grain and one water (grain %d water %d)" % [carried_count(person, grain_id), carried_count(person, water_id)])
			return
		ok("craft-meal")
		return
	fail("craft-meal", "meal did not appear within %d ticks" % MAX_CRAFT_TICKS)


func haul_grain_into(check: String, building: Dictionary, grain_id: int, start: int) -> bool:
	if not require_method("submit_haul", check):
		return false
	if not building.has("contents"):
		fail(check, "stockpile snapshot has no contents (%s)" % str(building.keys()))
		return false
	if store_count(building, grain_id) != 0:
		fail(check, "new stockpile already holds %d grain" % store_count(building, grain_id))
		return false
	var s := snap()
	if failed:
		return false
	var person := person_by_index(s, 0)
	if carried_count(person, grain_id) != start:
		fail(check, "carried grain changed before haul (%d, expected %d)" % [carried_count(person, grain_id), start])
		return false
	var code = host.call(
		"submit_haul", 0, int(person["generation"]), grain_id,
		int(building["index"]), int(building["generation"])
	)
	if code == null or int(code) != 0:
		fail(check, "submit_haul returned %s" % str(code))
		return false
	var start_tick := int(host.call("tick"))
	var saw_rise := false
	var index := int(building["index"])
	var last_store := 0
	var last_carried := start
	for _i in MAX_HAUL_TICKS:
		if drive_one(false) != 1:
			fail(check, "step did not advance one tick")
			return false
		s = snap()
		if failed:
			return false
		person = person_by_index(s, 0)
		var current := building_by_index(s, index)
		if person.is_empty() or current.is_empty():
			fail(check, "person or stockpile disappeared during haul")
			return false
		if not current.has("contents"):
			fail(check, "stockpile lost contents (%s)" % str(current.keys()))
			return false
		var store_now := store_count(current, grain_id)
		var carried_now := carried_count(person, grain_id)
		if store_now > STOCKPILE_CAPACITY:
			fail(check, "stockpile holds %d, capacity is %d" % [store_now, STOCKPILE_CAPACITY])
			return false
		if store_now > last_store:
			saw_rise = true
		var reason := failure_text_of(person)
		if reason != "":
			fail(check, "haul failed with '%s'" % reason)
			return false
		last_store = store_now
		last_carried = carried_now
		if store_now == start and carried_now == 0:
			var elapsed := int(host.call("tick")) - start_tick
			if not saw_rise:
				fail(check, "store reached %d without contents rising" % start)
				return false
			if elapsed < start * HAUL_TICKS_PER_UNIT:
				fail(check, "haul of %d finished in %d ticks, contract is %d per unit" % [start, elapsed, HAUL_TICKS_PER_UNIT])
				return false
			return true
	fail(check, "haul incomplete after %d ticks (store %d, carried %d)" % [MAX_HAUL_TICKS, last_store, last_carried])
	return false


func run_stockpile() -> void:
	if not begin("haul"):
		return
	var grain_id := resolved_id("haul", "item", "grain", ITEM_GRAIN)
	if failed or grain_id < 0:
		return
	var s := snap()
	if failed:
		return
	var person := person_by_index(s, 0)
	var start := carried_count(person, grain_id)
	if start != RATION:
		fail("haul", "person 0 carries %d grain, expected %d" % [start, RATION])
		return
	var at := free_cell(Vector2(float(person["x"]), float(person["y"])), occupied_cells(s))
	if not at.is_finite():
		fail("haul", "no free cell for the stockpile")
		return
	var building := finish_placed("haul", STOCKPILE, at)
	if failed or building.is_empty():
		return
	if not haul_grain_into("haul", building, grain_id, start):
		return
	ok("haul")

	if not require_method("submit_take", "take"):
		return
	s = snap()
	if failed:
		return
	person = person_by_index(s, 0)
	building = building_by_index(s, int(building["index"]))
	if building.is_empty() or store_count(building, grain_id) != start:
		fail("take", "store does not hold the hauled grain")
		return
	var code = host.call(
		"submit_take", 0, int(person["generation"]), grain_id,
		int(building["index"]), int(building["generation"])
	)
	if code == null or int(code) != 0:
		fail("take", "submit_take returned %s" % str(code))
		return
	var start_tick := int(host.call("tick"))
	var saw_fall := false
	var saw_hand := false
	var index := int(building["index"])
	var last_store := start
	var last_carried := 0
	var took := false
	for _i in MAX_TAKE_TICKS:
		if drive_one(false) != 1:
			fail("take", "step did not advance one tick")
			return
		s = snap()
		if failed:
			return
		person = person_by_index(s, 0)
		var current := building_by_index(s, index)
		if person.is_empty() or current.is_empty():
			fail("take", "person or stockpile disappeared")
			return
		var store_now := store_count(current, grain_id)
		var carried_now := carried_count(person, grain_id)
		if store_now < last_store:
			saw_fall = true
		if carried_now > 0:
			saw_hand = true
		var reason := failure_text_of(person)
		if reason != "":
			fail("take", "take failed with '%s'" % reason)
			return
		last_store = store_now
		last_carried = carried_now
		if store_now == 0 and carried_now == start:
			var elapsed := int(host.call("tick")) - start_tick
			if not saw_fall or not saw_hand:
				fail("take", "goods did not move back out (store %d carried %d)" % [store_now, carried_now])
				return
			if elapsed < start * TAKE_TICKS_PER_UNIT:
				fail("take", "take of %d finished in %d ticks, contract is %d per unit" % [start, elapsed, TAKE_TICKS_PER_UNIT])
				return
			took = true
			break
	if not took:
		fail("take", "take incomplete after %d ticks (store %d, carried %d)" % [MAX_TAKE_TICKS, last_store, last_carried])
		return
	ok("take")

	s = snap()
	if failed:
		return
	person = person_by_index(s, 0)
	building = building_by_index(s, index)
	if store_count(building, grain_id) != 0:
		fail("take-empty", "store still holds %d grain" % store_count(building, grain_id))
		return
	var carried_before := carried_count(person, grain_id)
	code = host.call(
		"submit_take", 0, int(person["generation"]), grain_id,
		int(building["index"]), int(building["generation"])
	)
	if code == null or int(code) != 0:
		fail("take-empty", "submit_take returned %s" % str(code))
		return
	if not wait_for_reason(0, "no material", "take-empty"):
		return
	s = snap()
	if failed:
		return
	person = person_by_index(s, 0)
	building = building_by_index(s, index)
	if failure_text_of(person) != "no material":
		fail("take-empty", "failure_text '%s', expected 'no material'" % failure_text_of(person))
		return
	if carried_count(person, grain_id) != carried_before or store_count(building, grain_id) != 0:
		fail("take-empty", "refusal changed carried or the store")
		return
	ok("take-empty")


func camera_key(value, path: String) -> String:
	if value is Dictionary:
		for key in value.keys():
			var name := str(key)
			var lower := name.to_lower()
			if lower == "camera" or lower.contains("camera"):
				return path + name
			var nested := camera_key(value[key], path + name + ".")
			if nested != "":
				return nested
	elif value is Array:
		for i in value.size():
			var nested := camera_key(value[i], "%s%d." % [path, i])
			if nested != "":
				return nested
	return ""


func stocked_world(check: String) -> bool:
	var grain_id := resolved_id(check, "item", "grain", ITEM_GRAIN)
	if failed or grain_id < 0:
		return false
	var s := snap()
	if failed:
		return false
	var person := person_by_index(s, 0)
	var start := carried_count(person, grain_id)
	if start < 1:
		fail(check, "person 0 carries no grain to store")
		return false
	var at := free_cell(Vector2(float(person["x"]), float(person["y"])), occupied_cells(s))
	if not at.is_finite():
		fail(check, "no free cell for the stockpile")
		return false
	var building := finish_placed(check, STOCKPILE, at)
	if failed or building.is_empty():
		return false
	return haul_grain_into(check, building, grain_id, start)


func run_save() -> void:
	if not begin("save"):
		return
	if not require_method("save_json", "save") or not require_method("load_json", "save"):
		return
	if not stocked_world("save"):
		return
	var before := snap()
	if failed:
		return
	if str(building_sig(before)) == "":
		fail("save", "refusing to round-trip a world with no buildings")
		return
	var save_text := str(host.call("save_json"))
	if save_text == "":
		fail("save", "save_json returned empty")
		return
	if save_text.to_lower().contains("camera"):
		fail("camera", "save text contains 'camera'")
		return
	var parsed = JSON.parse_string(save_text)
	if parsed == null or not (parsed is Dictionary):
		fail("save", "save_json is not a JSON object")
		return
	var cam := camera_key(parsed, "")
	if cam != "":
		fail("camera", "save key '%s'" % cam)
		return
	ok("camera")
	if int(parsed.get("save_version", -1)) != SAVE_VERSION:
		fail("save", "save_version %s, expected %d" % [str(parsed.get("save_version")), SAVE_VERSION])
		return
	var saved_hash := hash_string()
	var saved_tick := int(host.call("tick"))
	var saved_buildings := building_sig(before)
	var saved_grain := carried_count(person_by_index(before, 0), ITEM_GRAIN)
	if saved_tick <= 0:
		fail("save", "refusing to round-trip a tick-0 world")
		return
	host.call("new_game", SEED)
	if hash_string() == saved_hash:
		fail("save", "new_game left the saved hash %s" % saved_hash)
		return
	var code = host.call("load_json", save_text)
	if code == null or int(code) != 0:
		fail("save", "load_json returned %s" % str(code))
		return
	if hash_string() != saved_hash:
		fail("save", "hash after load %s != saved %s" % [hash_string(), saved_hash])
		return
	var after := snap()
	if failed:
		return
	if int(after.get("tick", -1)) != saved_tick or int(host.call("tick")) != saved_tick:
		fail("save", "tick after load %s / %s, expected %d" % [str(after.get("tick")), str(host.call("tick")), saved_tick])
		return
	if building_sig(after) != saved_buildings:
		fail("save", "buildings after load %s != saved %s" % [building_sig(after), saved_buildings])
		return
	if carried_count(person_by_index(after, 0), ITEM_GRAIN) != saved_grain:
		fail("save", "carried grain after load changed")
		return
	ok("save")


func run_milestone_2() -> void:
	run_bleed()
	if failed:
		return
	run_bandage()
	if failed:
		return
	run_infection()
	if failed:
		return
	run_no_skill()
	if failed:
		return
	run_salve()
	if failed:
		return
	run_self_heal_refused()
	if failed:
		return
	run_tired()
	if failed:
		return
	run_rest()
	if failed:
		return
	run_warmth()
	if failed:
		return
	run_cold()
	if failed:
		return
	run_campfire()
	if failed:
		return
	run_skill()
	if failed:
		return
	run_save_m2()
	if failed:
		return
	print("2: ok")
	cleanup()
	get_tree().quit(0)


func person_now(check: String) -> Dictionary:
	var s := snap()
	if failed:
		return {}
	var person := person_by_index(s, 0)
	if person.is_empty():
		fail(check, "person 0 missing")
		return {}
	return person


func region_of(check: String, person: Dictionary, index: int) -> Dictionary:
	if person.is_empty():
		return {}
	if not person.has("regions"):
		fail(check, "snapshot person has no 'regions' (keys: %s)" % str(person.keys()))
		return {}
	var regions = person["regions"]
	if array_size(regions) != REGION_COUNT:
		fail(check, "snapshot regions has %d entries, expected %d" % [array_size(regions), REGION_COUNT])
		return {}
	var row = regions[index]
	if not (row is Dictionary):
		fail(check, "snapshot region %d is not an object (%s)" % [index, str(row)])
		return {}
	return row


func skill_at(check: String, person: Dictionary, index: int) -> float:
	if person.is_empty():
		return -1.0
	if not person.has("skills"):
		fail(check, "snapshot person has no 'skills' (keys: %s)" % str(person.keys()))
		return -1.0
	var skills = person["skills"]
	if array_size(skills) != SKILL_COUNT:
		fail(check, "snapshot skills has %d values, expected %d in gather, build, craft, medicine order" % [array_size(skills), SKILL_COUNT])
		return -1.0
	return float(skills[index])


func step_n(check: String, n: int) -> bool:
	var before := int(host.call("tick"))
	for _i in n:
		host.call("step")
	var after := int(host.call("tick"))
	if after != before + n:
		fail(check, "stepped %d times but tick went %d -> %d" % [n, before, after])
		return false
	return true


func json_int_field(text: String, key: String) -> String:
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


func encode_json(value) -> String:
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
			parts.append("%s:%s" % [encode_json(str(key)), encode_json(value[key])])
		return "{%s}" % ",".join(parts)
	if kind == TYPE_ARRAY or kind == TYPE_PACKED_INT32_ARRAY or kind == TYPE_PACKED_INT64_ARRAY or kind == TYPE_PACKED_FLOAT32_ARRAY or kind == TYPE_PACKED_FLOAT64_ARRAY or kind == TYPE_PACKED_STRING_ARRAY:
		var parts: PackedStringArray = []
		for item in value:
			parts.append(encode_json(item))
		return "[%s]" % ",".join(parts)
	return "null"


func open_save(check: String) -> Dictionary:
	if not require_method("save_json", check) or not require_method("load_json", check):
		return {}
	var text := str(host.call("save_json"))
	if text == "":
		fail(check, "save_json returned empty")
		return {}
	var parsed = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		fail(check, "save_json is not a JSON object")
		return {}
	var slot := slot_person(parsed, 0)
	if slot.is_empty():
		fail(check, "save has no live person 0")
		return {}
	return {"doc": parsed, "text": text, "slot": slot}


func slot_person(doc: Dictionary, index: int) -> Dictionary:
	for slot in doc.get("slots", []):
		if typeof(slot) != TYPE_DICTIONARY:
			continue
		if str(slot.get("kind", "")) != "person":
			continue
		if int(slot.get("index", -1)) == index:
			return slot
	return {}


func commit_save(check: String, opened: Dictionary) -> bool:
	var original: String = opened["text"]
	var doc: Dictionary = opened["doc"]
	# The RNG word does not fit in a JSON number. Put the original digits back
	# after encoding, so the edit does not smash the stream.
	var rng_digits := json_int_field(original, "rng")
	var seed_digits := json_int_field(original, "seed")
	if rng_digits != "":
		doc["rng"] = 1
	var encoded := encode_json(doc)
	if rng_digits != "":
		encoded = encoded.replace("\"rng\":1,", "\"rng\":%s," % rng_digits)
		encoded = encoded.replace("\"rng\":1}", "\"rng\":%s}" % rng_digits)
	if seed_digits != "":
		var current := json_int_field(encoded, "seed")
		if current != "" and current != seed_digits:
			encoded = encoded.replace("\"seed\":%s," % current, "\"seed\":%s," % seed_digits)
	var code = host.call("load_json", encoded)
	if code == null or int(code) != 0:
		fail(check, "load_json of the hand-edited save returned %s (regions=%s bleeding=%s fatigue=%s warmth=%s skills=%s)" % [
			str(code),
			encoded.contains("\"regions\""),
			encoded.contains("\"bleeding\""),
			encoded.contains("\"fatigue\""),
			encoded.contains("\"warmth\""),
			encoded.contains("\"skills\""),
		])
		return false
	return true


func set_region_field(check: String, slot: Dictionary, index: int, field: String, value) -> bool:
	if not slot.has("regions"):
		fail(check, "save person has no 'regions' (keys: %s)" % str(slot.keys()))
		return false
	var regions = slot["regions"]
	if array_size(regions) != REGION_COUNT:
		fail(check, "save regions has %d entries, expected %d" % [array_size(regions), REGION_COUNT])
		return false
	var region = regions[index]
	if not (region is Dictionary):
		fail(check, "save region %d is not an object (%s)" % [index, str(region)])
		return false
	region[field] = value
	return true


func hand_wound(check: String, bleeding: float, infected: float) -> bool:
	var person := person_now(check)
	if failed:
		return false
	if not person.has("regions"):
		fail(check, "snapshot person has no 'regions' (keys: %s)" % str(person.keys()))
		return false
	var opened := open_save(check)
	if failed or opened.is_empty():
		return false
	if not set_region_field(check, opened["slot"], REGION_TORSO, "bleeding", bleeding):
		return false
	if not set_region_field(check, opened["slot"], REGION_TORSO, "infected", infected):
		return false
	print("%s: %s" % [check, WOUND_BY_HAND])
	if not commit_save(check, opened):
		return false
	person = person_now(check)
	if failed:
		return false
	var region := region_of(check, person, REGION_TORSO)
	if failed:
		return false
	if abs(float(region.get("bleeding", -1.0)) - bleeding) > 0.001:
		fail(check, "bleeding after load is %s, the save did not carry the hand-set wound" % str(region.get("bleeding")))
		return false
	if abs(float(region.get("infected", -1.0)) - infected) > 0.001:
		fail(check, "infected after load is %s, the save did not carry it" % str(region.get("infected")))
		return false
	return true


func set_region_value(check: String, field: String, value: float) -> bool:
	var opened := open_save(check)
	if failed or opened.is_empty():
		return false
	if not set_region_field(check, opened["slot"], REGION_TORSO, field, value):
		return false
	if not commit_save(check, opened):
		return false
	var region := region_of(check, person_now(check), REGION_TORSO)
	if failed:
		return false
	if abs(float(region.get(field, -999.0)) - value) > 0.001:
		fail(check, "%s after load is %s, the save did not carry the hand-set value" % [field, str(region.get(field))])
		return false
	return true


func set_body_number(check: String, key: String, value: float, why: String) -> bool:
	var person := person_now(check)
	if failed:
		return false
	if not person.has(key):
		fail(check, "snapshot person has no '%s' (keys: %s)" % [key, str(person.keys())])
		return false
	var opened := open_save(check)
	if failed or opened.is_empty():
		return false
	opened["slot"][key] = value
	print("%s: %s" % [check, why])
	if not commit_save(check, opened):
		return false
	person = person_now(check)
	if failed:
		return false
	if abs(float(person.get(key, -999.0)) - value) > 0.001:
		fail(check, "%s after load is %s, the save did not carry the hand-set value" % [key, str(person.get(key))])
		return false
	return true


func set_medicine(check: String, value: float) -> bool:
	var person := person_now(check)
	if failed:
		return false
	if skill_at(check, person, SKILL_MEDICINE) < -0.5:
		return false
	var opened := open_save(check)
	if failed or opened.is_empty():
		return false
	var slot: Dictionary = opened["slot"]
	if not slot.has("skills"):
		fail(check, "save person has no 'skills' (keys: %s)" % str(slot.keys()))
		return false
	var skills = slot["skills"]
	if array_size(skills) != SKILL_COUNT:
		fail(check, "save skills has %d values, expected %d" % [array_size(skills), SKILL_COUNT])
		return false
	skills[SKILL_MEDICINE] = value
	print("%s: medicine skill set to %s by hand in the save, the same seam as the wound, because no heal has raised it" % [check, value])
	if not commit_save(check, opened):
		return false
	person = person_now(check)
	if failed:
		return false
	var got := skill_at(check, person, SKILL_MEDICINE)
	if failed:
		return false
	if abs(got - value) > 0.001:
		fail(check, "medicine skill after load is %s, the save did not carry it" % got)
		return false
	return true


func grant_carried(slot: Dictionary, item_id: int, count: int) -> void:
	var carried = slot.get("carried", [])
	if carried == null:
		carried = []
	var updated := false
	for pair in carried:
		if array_size(pair) >= 2 and int(pair[0]) == item_id:
			pair[1] = int(pair[1]) + count
			updated = true
			break
	if not updated:
		carried.append([item_id, count])
	slot["carried"] = carried


func grant_item(check: String, item_id: int, count: int) -> bool:
	var opened := open_save(check)
	if failed or opened.is_empty():
		return false
	grant_carried(opened["slot"], item_id, count)
	if not commit_save(check, opened):
		return false
	var person := person_now(check)
	if failed:
		return false
	if carried_count(person, item_id) < count:
		fail(check, "carried %d of item %d after load, the save did not grant it" % [carried_count(person, item_id), item_id])
		return false
	return true


func require_catalog_item(check: String, item_name: String, expected: int) -> int:
	var found := catalog_id(item_name)
	if found < 0:
		fail(check, "catalog has no '%s'" % item_name)
		return -1
	if found != expected:
		fail(check, "catalog '%s' is %d, contract says %d" % [item_name, found, expected])
		return -1
	return found


# Heal { actor, target, item }. The method follows that field order, as
# submit_take follows Take { actor, item, from }.
func submit_heal_self(check: String, item_id: int) -> bool:
	if not require_method("submit_heal", check):
		return false
	var person := person_now(check)
	if failed:
		return false
	var code = host.call(
		"submit_heal",
		0, int(person["generation"]),
		int(person["index"]), int(person["generation"]),
		item_id
	)
	if code == null or int(code) != 0:
		fail(check, "submit_heal returned %s" % str(code))
		return false
	return true


func expect_work_refusal(check: String, job: int, reason: String) -> bool:
	var person := person_now(check)
	if failed:
		return false
	var code = host.call("submit_work", 0, int(person["generation"]), job)
	if code == null or int(code) != 0:
		fail(check, "submit_work %d returned %s; a refusal is not a command error, the line is failure_text" % [job, str(code)])
		return false
	person = person_now(check)
	if failed:
		return false
	var text := failure_text_of(person)
	if text == "":
		return wait_for_reason(0, reason, check)
	if text != reason:
		fail(check, "expected '%s', got '%s'" % [reason, text])
		return false
	var expected := reason_code(reason)
	if int(person.get("failure", -999)) != expected:
		fail(check, "'%s' discriminant %s, expected %d" % [reason, str(person.get("failure")), expected])
		return false
	return true


func day_and_fed(check: String) -> bool:
	var person := person_now(check)
	if failed:
		return false
	if float(person.get("hunger", 0.0)) < 0.35:
		fail(check, "hunger is %s; hungry would speak before this refusal" % str(person.get("hunger")))
		return false
	if float(person.get("health", 0.0)) <= 0.30:
		fail(check, "health is %s; the old wounded line would speak before this refusal" % str(person.get("health")))
		return false
	var tick := int(host.call("tick"))
	if tick % 7200 >= NIGHT_START:
		fail(check, "tick %d is night; night would speak before this refusal" % tick)
		return false
	return true


func run_bleed() -> void:
	if not begin("bleed"):
		return
	# 1.0 empties a healthy person in a day. 720 ticks is a tenth of that,
	# enough to see and not so long that hunger or cold can explain it.
	if not hand_wound("bleed", 1.0, 0.0):
		return
	var person := person_now("bleed")
	if failed:
		return
	var before := float(person.get("health", -1.0))
	if abs(before - 1.0) > 0.001:
		fail("bleed", "health before the bleed is %s, expected 1" % before)
		return
	if not step_n("bleed", 720):
		return
	person = person_now("bleed")
	if failed:
		return
	var region := region_of("bleed", person, REGION_TORSO)
	if failed:
		return
	var drop := before - float(person.get("health", 0.0))
	var expected := 720.0 * BLEED_HEALTH_PER_TICK
	if abs(drop - expected) > 0.01:
		fail("bleed", "health fell %s in 720 ticks, a wound at 1.0 bleeds %s per tick (%s over 720)" % [drop, BLEED_HEALTH_PER_TICK, expected])
		return
	if abs(float(region.get("bleeding", -1.0)) - 1.0) > 0.001:
		fail("bleed", "bleeding faded to %s on its own; only a bandage stops it" % str(region.get("bleeding")))
		return
	ok("bleed")


func run_bandage() -> void:
	if not begin("bandage"):
		return
	if require_catalog_item("bandage", "bandage", ITEM_BANDAGE) < 0:
		return
	if not hand_wound("bandage", 1.0, 0.0):
		return
	if not grant_item("bandage", ITEM_BANDAGE, 1):
		return
	var person := person_now("bandage")
	if failed:
		return
	var region := region_of("bandage", person, REGION_TORSO)
	if failed:
		return
	if float(region.get("bleeding", 0.0)) < 0.5:
		fail("bandage", "the wound did not survive granting the bandage")
		return
	var start := int(host.call("tick"))
	if not submit_heal_self("bandage", ITEM_BANDAGE):
		return
	var stopped := false
	for _i in MAX_HEAL_TICKS:
		if drive_one(false) != 1:
			fail("bandage", "step did not advance one tick")
			return
		person = person_now("bandage")
		if failed:
			return
		var reason := failure_text_of(person)
		if reason != "":
			fail("bandage", "heal failed with '%s'; bandaging needs no skill" % reason)
			return
		region = region_of("bandage", person, REGION_TORSO)
		if failed:
			return
		if not region.has("bleeding") or not region.has("bandaged"):
			fail("bandage", "region has no bleeding/bandaged (%s)" % str(region.keys()))
			return
		if float(region["bleeding"]) <= 0.001 and bool(region["bandaged"]):
			stopped = true
			break
	if not stopped:
		fail("bandage", "bandage did not stop the bleeding within %d ticks" % MAX_HEAL_TICKS)
		return
	var elapsed := int(host.call("tick")) - start
	if elapsed < HEAL_TICKS:
		fail("bandage", "bleeding stopped after %d ticks, a bandage takes %d" % [elapsed, HEAL_TICKS])
		return
	person = person_now("bandage")
	if failed:
		return
	if carried_count(person, ITEM_BANDAGE) != 0:
		fail("bandage", "bandage still carried after the heal")
		return
	var head := region_of("bandage", person, REGION_HEAD)
	if failed:
		return
	if bool(head.get("bandaged", false)):
		fail("bandage", "bandage wrapped the head, which was not the bleeding region")
		return
	var held := float(person.get("health", 0.0))
	if not step_n("bandage", 720):
		return
	person = person_now("bandage")
	if failed:
		return
	region = region_of("bandage", person, REGION_TORSO)
	if failed:
		return
	if float(region.get("bleeding", 1.0)) > 0.001:
		fail("bandage", "bleeding returned to %s" % str(region.get("bleeding")))
		return
	var later := float(person.get("health", 0.0))
	var open_bleed := 720.0 * BLEED_HEALTH_PER_TICK
	if held - later > 0.02:
		fail("bandage", "health fell %s in 720 ticks after the bandage; a stopped bleed holds, an open one drops %s" % [held - later, open_bleed])
		return
	ok("bandage")


func run_infection() -> void:
	if not begin("infection"):
		return
	# A small bleed, so the person is still alive when the wound goes sick.
	if not hand_wound("infection", 0.05, 0.0):
		return
	if not step_n("infection", 288):
		return
	var region := region_of("infection", person_now("infection"), REGION_TORSO)
	if failed:
		return
	var early := float(region.get("infected", -1.0))
	if early < 288.0 * INFECTION_PER_TICK * 0.5:
		fail("infection", "infected is %s after 288 ticks; a neglected wound accumulates at %s per tick" % [early, INFECTION_PER_TICK])
		return
	if not step_n("infection", 2880 - 288):
		return
	region = region_of("infection", person_now("infection"), REGION_TORSO)
	if failed:
		return
	var infected := float(region.get("infected", -1.0))
	var expected := 2880.0 * INFECTION_PER_TICK
	if abs(infected - expected) > 0.01:
		fail("infection", "infected is %s after 2880 ticks, expected %s" % [infected, expected])
		return
	# The rate is measured. The last stretch is set by hand so hunger does not
	# speak first: a full climb to 0.5 is 14400 ticks, and hunger empties on
	# that same clock.
	print("infection: infected set just under the sick line by hand; the rate above was measured from a fresh neglected wound")
	if not set_region_value("infection", "infected", INFECTION_SICK - 0.01):
		return
	if not step_n("infection", 300):
		return
	var person := person_now("infection")
	if failed:
		return
	region = region_of("infection", person, REGION_TORSO)
	if failed:
		return
	infected = float(region.get("infected", -1.0))
	if infected < INFECTION_SICK:
		fail("infection", "infected is %s after the last stretch, the sick line is %s" % [infected, INFECTION_SICK])
		return
	if not day_and_fed("infection"):
		return
	if not expect_work_refusal("infection", JOB_HAUL, "wounded"):
		return
	person = person_now("infection")
	if failed:
		return
	if int(person.get("failure", -999)) != WOUNDED:
		fail("infection", "wounded discriminant %s, expected %d" % [str(person.get("failure")), WOUNDED])
		return
	var health_before := float(person.get("health", 0.0))
	var bleeding := float(region.get("bleeding", 0.0))
	if not step_n("infection", 1440):
		return
	person = person_now("infection")
	if failed:
		return
	var drop := health_before - float(person.get("health", 0.0))
	var bleed_part := 1440.0 * bleeding * BLEED_HEALTH_PER_TICK
	var sick_part := 1440.0 * INFECTION_HEALTH_PER_TICK
	if abs(drop - (bleed_part + sick_part)) > 0.02:
		fail("infection", "health fell %s over 1440 ticks at the sick line; bleed accounts for %s and infection for %s" % [drop, bleed_part, sick_part])
		return
	ok("infection")


func run_no_skill() -> void:
	if not begin("no-skill"):
		return
	if require_catalog_item("no-skill", "salve", ITEM_SALVE) < 0:
		return
	# 0.3, comfortably below INFECTION_SICK. Heal is labour, and a person at or
	# above the sickness line is refused with wounded, so the actor never
	# reaches the salve's skill gate. This check is that gate, not being sick.
	# Do not put the wound back on the line.
	if not hand_wound("no-skill", 0.1, 0.3):
		return
	if not set_medicine("no-skill", MEDICINE_SKILL_MIN - 0.01):
		return
	if not grant_item("no-skill", ITEM_SALVE, 1):
		return
	var person := person_now("no-skill")
	if failed:
		return
	var region := region_of("no-skill", person, REGION_TORSO)
	if failed:
		return
	var infected_before := float(region.get("infected", -1.0))
	var salve_before := carried_count(person, ITEM_SALVE)
	if not submit_heal_self("no-skill", ITEM_SALVE):
		return
	# First check in the project that reads this line. The wording is the sim's.
	if not wait_for_reason(0, "no skill", "no-skill"):
		return
	person = person_now("no-skill")
	if failed:
		return
	if failure_text_of(person) != "no skill":
		fail("no-skill", "failure_text '%s', expected the sim string 'no skill'" % failure_text_of(person))
		return
	if carried_count(person, ITEM_SALVE) != salve_before:
		fail("no-skill", "a refused salve was consumed")
		return
	region = region_of("no-skill", person, REGION_TORSO)
	if failed:
		return
	if abs(float(region.get("infected", -1.0)) - infected_before) > 0.001:
		fail("no-skill", "a refused salve changed infected from %s to %s" % [infected_before, str(region.get("infected"))])
		return
	ok("no-skill")


func run_salve() -> void:
	if not begin("salve"):
		return
	if require_catalog_item("salve", "salve", ITEM_SALVE) < 0:
		return
	# 0.3, comfortably below INFECTION_SICK, so the actor is well enough to
	# treat themselves. This check is the salve's cut, not being sick. Do not
	# put the wound back on the line: 0.3 minus the cut clamps to 0.
	if not hand_wound("salve", 0.1, 0.3):
		return
	if not set_medicine("salve", MEDICINE_SKILL_MIN):
		return
	if not grant_item("salve", ITEM_SALVE, 1):
		return
	var before_region := region_of("salve", person_now("salve"), REGION_TORSO)
	if failed:
		return
	var infected_before := float(before_region.get("infected", -1.0))
	# From the region's infection as read before the salve, clamped at zero.
	var expected := infected_before - SALVE_INFECTION_CUT
	if expected < 0.0:
		expected = 0.0
	var start := int(host.call("tick"))
	if not submit_heal_self("salve", ITEM_SALVE):
		return
	var applied := false
	for _i in MAX_HEAL_TICKS:
		if drive_one(false) != 1:
			fail("salve", "step did not advance one tick")
			return
		var person := person_now("salve")
		if failed:
			return
		var reason := failure_text_of(person)
		if reason != "":
			fail("salve", "heal failed with '%s' at medicine skill %s" % [reason, MEDICINE_SKILL_MIN])
			return
		var region := region_of("salve", person, REGION_TORSO)
		if failed:
			return
		if not region.has("treated") or not region.has("infected"):
			fail("salve", "region has no treated/infected (%s)" % str(region.keys()))
			return
		if bool(region["treated"]):
			applied = true
			var infected := float(region["infected"])
			if abs(infected - expected) > 0.02:
				fail("salve", "infected is %s after the salve, a cut of %s from %s leaves %s" % [infected, SALVE_INFECTION_CUT, infected_before, expected])
				return
			break
	if not applied:
		fail("salve", "salve did not treat the wound within %d ticks" % MAX_HEAL_TICKS)
		return
	var elapsed := int(host.call("tick")) - start
	# Medicine at the minimum is what lets the salve through, and that skill
	# cuts the heal. The listed 60 is the unskilled time. Do not require 60
	# here: 0.25 keeps 0.9 of it, which is 54.
	var skilled := int(round(float(HEAL_TICKS) * (1.0 - MEDICINE_SKILL_MIN * SKILL_TIME_RELIEF)))
	if skilled < 1:
		skilled = 1
	if elapsed != skilled:
		fail("salve", "salve applied after %d ticks; medicine skill %s keeps %s of a %d-tick heal, which is %d" % [elapsed, MEDICINE_SKILL_MIN, 1.0 - MEDICINE_SKILL_MIN * SKILL_TIME_RELIEF, HEAL_TICKS, skilled])
		return
	var person := person_now("salve")
	if failed:
		return
	if carried_count(person, ITEM_SALVE) != 0:
		fail("salve", "salve still carried after the heal")
		return
	# Treated halves the rate from then on. Unbandaged base is INFECTION_PER_TICK,
	# so 2880 ticks should add about 0.05, not 0.1 and not the bandaged tenth.
	if not step_n("salve", 2880):
		return
	var region := region_of("salve", person_now("salve"), REGION_TORSO)
	if failed:
		return
	var gained := float(region.get("infected", -1.0))
	var halved := 2880.0 * INFECTION_PER_TICK * 0.5
	if abs(gained - halved) > 0.01:
		fail("salve", "infected rose to %s over 2880 ticks after the salve, a halved rate adds %s" % [gained, halved])
		return
	ok("salve")


func run_self_heal_refused() -> void:
	if not begin("self-heal-refused"):
		return
	if require_catalog_item("self-heal-refused", "salve", ITEM_SALVE) < 0:
		return
	# The wound is set by hand at the sickness line because no rule wounds
	# anybody until milestone 5. Heal is labour: at or above that line the
	# actor refuses their own heal with wounded and never reaches the salve.
	# no-skill and salve stay under the line so they can; this check does not.
	print("self-heal-refused: the wound was set by hand at the sickness line, because no rule wounds anybody until milestone 5, and a person at that line must refuse their own heal")
	if not hand_wound("self-heal-refused", 0.1, INFECTION_SICK):
		return
	if not set_medicine("self-heal-refused", MEDICINE_SKILL_MIN):
		return
	if not grant_item("self-heal-refused", ITEM_SALVE, 1):
		return
	if not day_and_fed("self-heal-refused"):
		return
	var person := person_now("self-heal-refused")
	if failed:
		return
	var region := region_of("self-heal-refused", person, REGION_TORSO)
	if failed:
		return
	var infected_before := float(region.get("infected", -1.0))
	if infected_before + 0.001 < INFECTION_SICK:
		fail("self-heal-refused", "infected is %s, the sickness line is %s" % [infected_before, INFECTION_SICK])
		return
	var salve_before := carried_count(person, ITEM_SALVE)
	if salve_before < 1:
		fail("self-heal-refused", "no salve in hand")
		return
	if not submit_heal_self("self-heal-refused", ITEM_SALVE):
		return
	# The refusal is at submit. Do not step: a tick would move the infection
	# on its own, and this check has to say the salve left it unchanged.
	person = person_now("self-heal-refused")
	if failed:
		return
	var text := failure_text_of(person)
	if text != "wounded":
		fail("self-heal-refused", "expected 'wounded', got '%s'" % text)
		return
	if int(person.get("failure", -999)) != WOUNDED:
		fail("self-heal-refused", "wounded discriminant %s, expected %d" % [str(person.get("failure")), WOUNDED])
		return
	if carried_count(person, ITEM_SALVE) != salve_before:
		fail("self-heal-refused", "a refused salve was consumed")
		return
	region = region_of("self-heal-refused", person, REGION_TORSO)
	if failed:
		return
	if abs(float(region.get("infected", -1.0)) - infected_before) > 0.001:
		fail("self-heal-refused", "a refused salve changed infected from %s to %s" % [infected_before, str(region.get("infected"))])
		return
	ok("self-heal-refused")


func run_tired() -> void:
	if not begin("tired"):
		return
	if not set_body_number("tired", "fatigue", FATIGUE_REFUSAL + 0.05, "fatigue was set by hand above the refusal line, because climbing there on the clock also starves the worker and hunger would speak first"):
		return
	var person := person_now("tired")
	if failed:
		return
	if float(person.get("fatigue", 0.0)) <= FATIGUE_REFUSAL:
		fail("tired", "fatigue %s is not above %s" % [str(person.get("fatigue")), FATIGUE_REFUSAL])
		return
	if not day_and_fed("tired"):
		return
	if not expect_work_refusal("tired", JOB_HAUL, "tired"):
		return
	ok("tired")


func lean_to_in_range(person: Dictionary) -> bool:
	var s := snap()
	if failed:
		return false
	var pos := Vector2(float(person.get("x", 0.0)), float(person.get("y", 0.0)))
	for building in buildings_of_kind(s, LEAN_TO):
		if int(building.get("progress", 0)) < BUILD_TICKS:
			continue
		var at := Vector2(float(building.get("x", 0.0)), float(building.get("y", 0.0)))
		if pos.distance_to(at) <= STATION_RANGE_M:
			return true
	return false


func measure_rest(check: String, ticks: int) -> float:
	var person := person_now(check)
	if failed:
		return -1.0
	var start := float(person.get("fatigue", -1.0))
	if not require_method("submit_work", check):
		return -1.0
	var code = host.call("submit_work", 0, int(person["generation"]), JOB_REST)
	if code == null or int(code) != 0:
		fail(check, "submit_work %d returned %s; Rest is job 7" % [JOB_REST, str(code)])
		return -1.0
	if drive_one(false) != 1:
		fail(check, "step did not advance one tick")
		return -1.0
	person = person_now(check)
	if failed:
		return -1.0
	if int(person.get("job", -999)) != JOB_REST:
		fail(check, "rest reports job %s, expected %d" % [str(person.get("job")), JOB_REST])
		return -1.0
	if failure_text_of(person) != "":
		fail(check, "rest failed with '%s'" % failure_text_of(person))
		return -1.0
	if not step_n(check, ticks - 1):
		return -1.0
	person = person_now(check)
	if failed:
		return -1.0
	if failure_text_of(person) != "":
		fail(check, "rest failed with '%s'" % failure_text_of(person))
		return -1.0
	return start - float(person.get("fatigue", start))


func run_rest() -> void:
	if not begin("rest"):
		return
	if not set_body_number("rest", "fatigue", 0.4, "fatigue was set by hand so the recovery has a known start, under the refusal line"):
		return
	var person := person_now("rest")
	if failed:
		return
	if lean_to_in_range(person):
		fail("rest", "a finished lean-to is already in range; the open rate would not be the open rate")
		return
	var open_drop := measure_rest("rest", 240)
	if failed:
		return
	var open_expected := 240.0 * SLEEP_RECOVER_PER_TICK
	if abs(open_drop - open_expected) > 0.02:
		fail("rest", "open rest recovered %s in 240 ticks, expected %s" % [open_drop, open_expected])
		return
	person = person_now("rest")
	if failed:
		return
	var at := free_cell(Vector2(float(person["x"]), float(person["y"])), occupied_cells(snap()))
	if not at.is_finite():
		fail("rest", "no free cell for the lean-to")
		return
	var building := finish_placed("rest", LEAN_TO, at)
	if failed or building.is_empty():
		return
	if not ensure_in_range("rest", building):
		return
	if not set_body_number("rest", "fatigue", 0.4, "fatigue was set by hand again after the build, so the lean-to rate starts where the open rate did"):
		return
	person = person_now("rest")
	if failed:
		return
	if not lean_to_in_range(person):
		fail("rest", "person is not within %s m of the finished lean-to" % STATION_RANGE_M)
		return
	var sheltered := measure_rest("rest", 240)
	if failed:
		return
	var sheltered_expected := 240.0 * SLEEP_RECOVER_PER_TICK * 2.0
	if abs(sheltered - sheltered_expected) > 0.02:
		fail("rest", "rest beside the lean-to recovered %s in 240 ticks, expected %s" % [sheltered, sheltered_expected])
		return
	if sheltered < open_drop * 1.5:
		fail("rest", "lean-to recovery %s is not faster than the open recovery %s" % [sheltered, open_drop])
		return
	ok("rest")


func jump_to_night(check: String, warmth: float) -> bool:
	var person := person_now(check)
	if failed:
		return false
	if not person.has("warmth"):
		fail(check, "snapshot person has no 'warmth' (keys: %s)" % str(person.keys()))
		return false
	var opened := open_save(check)
	if failed or opened.is_empty():
		return false
	opened["doc"]["tick"] = NIGHT_START
	opened["slot"]["warmth"] = warmth
	print("%s: the clock was set to the night range by hand in the save, so the check does not wait out the day" % check)
	if not commit_save(check, opened):
		return false
	if int(host.call("tick")) != NIGHT_START:
		fail(check, "tick after load is %s, expected %d" % [str(host.call("tick")), NIGHT_START])
		return false
	person = person_now(check)
	if failed:
		return false
	if abs(float(person.get("warmth", -1.0)) - warmth) > 0.001:
		fail(check, "warmth after load is %s, the save did not carry it" % str(person.get("warmth")))
		return false
	return true


func campfire_in_warmth(person: Dictionary) -> bool:
	var s := snap()
	if failed:
		return false
	var pos := Vector2(float(person.get("x", 0.0)), float(person.get("y", 0.0)))
	for building in buildings_of_kind(s, CAMPFIRE):
		if int(building.get("progress", 0)) < BUILD_TICKS:
			continue
		var at := Vector2(float(building.get("x", 0.0)), float(building.get("y", 0.0)))
		if pos.distance_to(at) <= WARMTH_RANGE_M:
			return true
	return false


func run_warmth() -> void:
	if not begin("warmth"):
		return
	if not jump_to_night("warmth", 1.0):
		return
	var person := person_now("warmth")
	if failed:
		return
	if campfire_in_warmth(person):
		fail("warmth", "a finished campfire is already within %s m; the night target would not apply" % WARMTH_RANGE_M)
		return
	if not step_n("warmth", 240):
		return
	person = person_now("warmth")
	if failed:
		return
	var warmth := float(person.get("warmth", -1.0))
	var expected := 1.0 - 240.0 * WARMTH_DRIFT_PER_TICK
	if abs(warmth - expected) > 0.02:
		fail("warmth", "warmth is %s after 240 night ticks away from a fire, expected %s on the way to %s" % [warmth, expected, AMBIENT_WARMTH_NIGHT])
		return
	if warmth <= AMBIENT_WARMTH_NIGHT:
		fail("warmth", "warmth %s passed the night target %s" % [warmth, AMBIENT_WARMTH_NIGHT])
		return
	ok("warmth")


func run_cold() -> void:
	if not begin("cold"):
		return
	var person := person_now("cold")
	if failed:
		return
	if not person.has("warmth"):
		fail("cold", "snapshot person has no 'warmth' (keys: %s)" % str(person.keys()))
		return
	# Default warmth, driven from day into night. Do not set warmth near zero:
	# that hands the check the answer, and an open night that never reaches
	# the drain then cannot fail.
	var start_warmth := float(person.get("warmth", -1.0))
	if abs(start_warmth - 1.0) > 0.001:
		fail("cold", "warmth starts at %s, expected the default 1; this check does not set it" % start_warmth)
		return
	var start_health := float(person.get("health", -1.0))
	if abs(start_health - 1.0) > 0.001:
		fail("cold", "health starts at %s, expected 1" % start_health)
		return
	if int(host.call("tick")) != 0:
		fail("cold", "tick starts at %s, expected the start of the day" % str(host.call("tick")))
		return
	if campfire_in_warmth(person) or lean_to_in_range(person):
		fail("cold", "shelter is already in range; a lean-to holds warmth at %s and this night would not reach zero" % LEANTO_WARMTH)
		return
	if not step_n("cold", NIGHT_START):
		return
	person = person_now("cold")
	if failed:
		return
	if int(host.call("tick")) != NIGHT_START:
		fail("cold", "tick is %s at dusk, expected %d" % [str(host.call("tick")), NIGHT_START])
		return
	var at_dusk := float(person.get("warmth", -1.0))
	if abs(at_dusk - AMBIENT_WARMTH_DAY) > 0.02:
		fail("cold", "warmth is %s at the night boundary, a day in the open settles at %s from the default 1" % [at_dusk, AMBIENT_WARMTH_DAY])
		return
	if abs(float(person.get("health", -1.0)) - start_health) > 0.02:
		fail("cold", "health fell to %s during the day, before warmth could reach zero" % str(person.get("health")))
		return
	var first_zero := -1
	var health_at_zero := -1.0
	# Large steps while warmth is well above zero, then one tick at a time so
	# the first zero is the tick the drain starts after. Neither sets warmth.
	while int(host.call("tick")) < TICKS_PER_DAY and first_zero < 0:
		person = person_now("cold")
		if failed:
			return
		var warmth_now := float(person.get("warmth", -1.0))
		if warmth_now == 0.0:
			first_zero = int(host.call("tick"))
			health_at_zero = float(person.get("health", -1.0))
			break
		var room := TICKS_PER_DAY - int(host.call("tick"))
		var batch := 1
		if warmth_now > WARMTH_DRIFT_PER_TICK * 40.0:
			batch = mini(int(floor(warmth_now / WARMTH_DRIFT_PER_TICK)) - 20, room)
			if batch < 1:
				batch = 1
		if batch > 1:
			if not step_n("cold", batch):
				return
			person = person_now("cold")
			if failed:
				return
			if float(person.get("warmth", -1.0)) == 0.0:
				fail("cold", "warmth hit zero inside a %d-tick batch ending at tick %s; drift is faster than %s, so the ticks at zero cannot be counted" % [batch, str(host.call("tick")), WARMTH_DRIFT_PER_TICK])
				return
			continue
		if drive_one(false) != 1:
			fail("cold", "step did not advance one tick")
			return
	if first_zero < 0:
		person = person_now("cold")
		if failed:
			return
		if float(person.get("warmth", -1.0)) == 0.0:
			first_zero = int(host.call("tick"))
			health_at_zero = float(person.get("health", -1.0))
	if first_zero < 0:
		fail("cold", "warmth is %s at tick %s, the end of a %d-tick night; from %s it should reach zero inside the night (drift %s, night target %s)" % [str(person.get("warmth")), str(host.call("tick")), TICKS_PER_DAY - NIGHT_START, at_dusk, WARMTH_DRIFT_PER_TICK, AMBIENT_WARMTH_NIGHT])
		return
	var zero_ticks := TICKS_PER_DAY - first_zero
	if zero_ticks <= 0:
		fail("cold", "warmth reached zero at tick %d with no night left to drain" % first_zero)
		return
	if not step_n("cold", zero_ticks):
		return
	if int(host.call("tick")) != TICKS_PER_DAY:
		fail("cold", "tick is %s after the night, expected %d" % [str(host.call("tick")), TICKS_PER_DAY])
		return
	person = person_now("cold")
	if failed:
		return
	if float(person.get("warmth", -1.0)) != 0.0:
		fail("cold", "warmth left zero during the open night (now %s)" % str(person.get("warmth")))
		return
	var drop := health_at_zero - float(person.get("health", health_at_zero))
	var expected := float(zero_ticks) * COLD_HEALTH_PER_TICK
	if abs(drop - expected) > 0.02:
		fail("cold", "health fell %s over %d ticks at zero, about %s each is %s" % [drop, zero_ticks, COLD_HEALTH_PER_TICK, expected])
		return
	ok("cold")


func run_campfire() -> void:
	if not begin("campfire"):
		return
	var person := person_now("campfire")
	if failed:
		return
	if not person.has("warmth"):
		fail("campfire", "snapshot person has no 'warmth' (keys: %s)" % str(person.keys()))
		return
	var at := free_cell(Vector2(float(person["x"]), float(person["y"])), occupied_cells(snap()))
	if not at.is_finite():
		fail("campfire", "no free cell for the campfire")
		return
	var building := finish_placed("campfire", CAMPFIRE, at)
	if failed or building.is_empty():
		return
	if not ensure_in_range("campfire", building):
		return
	person = person_now("campfire")
	if failed:
		return
	var pos := Vector2(float(person["x"]), float(person["y"]))
	var fire_at := Vector2(float(building["x"]), float(building["y"]))
	if pos.distance_to(fire_at) > WARMTH_RANGE_M:
		fail("campfire", "person is %.2f m from the fire, warmth range is %s" % [pos.distance_to(fire_at), WARMTH_RANGE_M])
		return
	if not jump_to_night("campfire", 1.0):
		return
	person = person_now("campfire")
	if failed:
		return
	if not campfire_in_warmth(person):
		fail("campfire", "the finished campfire did not survive the save inside warmth range")
		return
	if not step_n("campfire", 240):
		return
	person = person_now("campfire")
	if failed:
		return
	var warmth := float(person.get("warmth", -1.0))
	if abs(warmth - 1.0) > 0.01:
		fail("campfire", "warmth is %s after 240 night ticks beside a finished campfire; the fire holds it at 1" % warmth)
		return
	ok("campfire")


func run_skill() -> void:
	if not begin("skill"):
		return
	var person := person_now("skill")
	if failed:
		return
	if skill_at("skill", person, SKILL_GATHER) < -0.5:
		return
	if abs(skill_at("skill", person, SKILL_GATHER)) > 0.001:
		fail("skill", "gather skill starts at %s, expected 0" % skill_at("skill", person, SKILL_GATHER))
		return
	# Empty the hands. Sixteen wood on top of the ration fills the carry cap
	# before the relief is a whole tick; the ration has to go first.
	var grain := catalog_id("grain")
	if grain < 0:
		grain = ITEM_GRAIN
	for _i in RATION:
		person = person_now("skill")
		if failed:
			return
		var bite = host.call("submit_eat", 0, int(person["generation"]), grain)
		if bite == null or int(bite) != 0:
			fail("skill", "submit_eat returned %s" % str(bite))
			return
		if drive_one(false) != 1:
			fail("skill", "step did not advance one tick")
			return
	person = person_now("skill")
	if failed:
		return
	if array_size(person.get("carried", [])) != 0:
		fail("skill", "hands are not empty (%s); a knife would cut the time on its own" % str(person.get("carried")))
		return
	var s := snap()
	if failed:
		return
	var node := wood_node(s)
	if node.is_empty():
		fail("skill", "no wood node")
		return
	var yield_id := int(node["yield_item"])
	var node_index := int(node["index"])
	var start_remaining := int(node["remaining"])
	var code = host.call("submit_gather", 0, int(person["generation"]), node_index, int(node["generation"]))
	if code == null or int(code) != 0:
		fail("skill", "submit_gather returned %s" % str(code))
		return
	var marks: Array = []
	var prev := 0
	for _i in MAX_SKILL_TICKS:
		if drive_one(false) != 1:
			fail("skill", "step did not advance one tick")
			return
		person = person_now("skill")
		if failed:
			return
		var reason := failure_text_of(person)
		if reason != "":
			fail("skill", "gather failed with '%s' after %d units" % [reason, marks.size()])
			return
		var have := carried_count(person, yield_id)
		if have > prev:
			marks.append(int(host.call("tick")))
			prev = have
			if have >= 16:
				break
	if marks.size() < 16:
		fail("skill", "gathered %d units, need 16 so the skill relief is a whole tick" % marks.size())
		return
	var node_now := node_by_index(snap(), node_index)
	if int(node_now.get("remaining", start_remaining)) > start_remaining - marks.size():
		fail("skill", "the node did not give up the units the hands gained")
		return
	var skill := skill_at("skill", person, SKILL_GATHER)
	if failed:
		return
	var expected_skill := float(marks.size()) * SKILL_PER_UNIT
	if abs(skill - expected_skill) > 0.002:
		fail("skill", "gather skill %s after %d units, expected %s" % [skill, marks.size(), expected_skill])
		return
	for index in [1, 2, 3]:
		var other := skill_at("skill", person, index)
		if failed:
			return
		if other > 0.001:
			fail("skill", "skill %d rose to %s while gathering" % [index, other])
			return
	var early: Array = []
	var late: Array = []
	for i in [1, 2, 3]:
		early.append(int(marks[i]) - int(marks[i - 1]))
	for i in [13, 14, 15]:
		late.append(int(marks[i]) - int(marks[i - 1]))
	var early_min: int = early[0]
	for n in early:
		early_min = mini(early_min, int(n))
	var late_max: int = late[0]
	for n in late:
		late_max = maxi(late_max, int(n))
	if early_min < GATHER_TICKS_PER_UNIT:
		fail("skill", "an early unit took %d ticks, listed gather time is %d (intervals %s)" % [early_min, GATHER_TICKS_PER_UNIT, str(early)])
		return
	# Unit 14 starts after 13 gathered units. That is the slowest of the late
	# three, and the relief there is already a whole tick.
	var late_skill := 13.0 * SKILL_PER_UNIT
	var cut := int(floor(float(GATHER_TICKS_PER_UNIT) * SKILL_TIME_RELIEF * late_skill))
	if cut < 1:
		cut = 1
	if late_max > GATHER_TICKS_PER_UNIT - cut:
		fail("skill", "a later unit took %d ticks; at gather skill %s the listed %d must fall by %d (early %s late %s)" % [late_max, late_skill, GATHER_TICKS_PER_UNIT, cut, str(early), str(late)])
		return
	ok("skill")


func rewrite_version(text: String, from_version: int, to_version: int) -> String:
	var pretty := "\"save_version\": %d" % from_version
	var tight := "\"save_version\":%d" % from_version
	if text.contains(pretty):
		return text.replace(pretty, "\"save_version\": %d" % to_version)
	if text.contains(tight):
		return text.replace(tight, "\"save_version\":%d" % to_version)
	return ""


func run_save_m2() -> void:
	if not begin("save"):
		return
	if not require_method("save_json", "save") or not require_method("load_json", "save"):
		return
	if not stocked_world("save"):
		return
	var person := person_now("save")
	if failed:
		return
	if not person.has("regions") or not person.has("fatigue") or not person.has("warmth") or not person.has("skills"):
		fail("save", "snapshot person is missing a milestone 2 field (keys: %s)" % str(person.keys()))
		return
	var opened := open_save("save")
	if failed or opened.is_empty():
		return
	if not set_region_field("save", opened["slot"], REGION_TORSO, "bleeding", 1.0):
		return
	if not set_region_field("save", opened["slot"], REGION_TORSO, "infected", 0.2):
		return
	opened["slot"]["fatigue"] = 0.4
	opened["slot"]["warmth"] = 0.7
	if not opened["slot"].has("skills"):
		fail("save", "save person has no 'skills' (keys: %s)" % str(opened["slot"].keys()))
		return
	var skills = opened["slot"]["skills"]
	if array_size(skills) != SKILL_COUNT:
		fail("save", "save skills has %d values, expected %d" % [array_size(skills), SKILL_COUNT])
		return
	skills[SKILL_GATHER] = 0.1
	skills[SKILL_MEDICINE] = 0.3
	print("save: %s" % WOUND_BY_HAND)
	print("save: fatigue, warmth and skills were set by hand in the save so a round trip that dropped them could not still match")
	if not commit_save("save", opened):
		return
	person = person_now("save")
	if failed:
		return
	var region := region_of("save", person, REGION_TORSO)
	if failed:
		return
	if abs(float(region.get("bleeding", -1.0)) - 1.0) > 0.001 or abs(float(person.get("fatigue", -1.0)) - 0.4) > 0.001 or abs(float(person.get("warmth", -1.0)) - 0.7) > 0.001:
		fail("save", "hand-set body did not survive load (bleeding %s fatigue %s warmth %s)" % [str(region.get("bleeding")), str(person.get("fatigue")), str(person.get("warmth"))])
		return
	if abs(skill_at("save", person, SKILL_GATHER) - 0.1) > 0.001 or abs(skill_at("save", person, SKILL_MEDICINE) - 0.3) > 0.001:
		fail("save", "hand-set skills did not survive load")
		return
	var save_text := str(host.call("save_json"))
	if save_text == "":
		fail("save", "save_json returned empty")
		return
	if save_text.to_lower().contains("camera"):
		fail("camera", "save text contains 'camera'")
		return
	var parsed = JSON.parse_string(save_text)
	if parsed == null or not (parsed is Dictionary):
		fail("save", "save_json is not a JSON object")
		return
	var cam := camera_key(parsed, "")
	if cam != "":
		fail("camera", "save key '%s'" % cam)
		return
	ok("camera")
	if int(parsed.get("save_version", -1)) != SAVE_VERSION:
		fail("save", "save_version %s, expected %d" % [str(parsed.get("save_version")), SAVE_VERSION])
		return
	var saved_slot := slot_person(parsed, 0)
	if saved_slot.is_empty() or not saved_slot.has("regions"):
		fail("save", "save text has no person regions")
		return
	var saved_region = saved_slot["regions"][REGION_TORSO]
	if not (saved_region is Dictionary) or abs(float(saved_region.get("bleeding", -1.0)) - 1.0) > 0.001:
		fail("save", "save text did not carry the wound (%s)" % str(saved_region))
		return
	if abs(float(saved_slot.get("fatigue", -1.0)) - 0.4) > 0.001 or abs(float(saved_slot.get("warmth", -1.0)) - 0.7) > 0.001:
		fail("save", "save text did not carry fatigue and warmth")
		return
	if array_size(saved_slot.get("skills", [])) != SKILL_COUNT or abs(float(saved_slot["skills"][SKILL_GATHER]) - 0.1) > 0.001:
		fail("save", "save text did not carry skills")
		return
	var saved_hash := hash_string()
	var saved_tick := int(host.call("tick"))
	var saved_buildings := building_sig(snap())
	host.call("new_game", SEED)
	if hash_string() == saved_hash:
		fail("save", "new_game left the saved hash %s" % saved_hash)
		return
	var code = host.call("load_json", save_text)
	if code == null or int(code) != 0:
		fail("save", "load_json returned %s" % str(code))
		return
	if hash_string() != saved_hash:
		fail("save", "hash after load %s != saved %s" % [hash_string(), saved_hash])
		return
	var after := snap()
	if failed:
		return
	if int(after.get("tick", -1)) != saved_tick:
		fail("save", "tick after load %s, expected %d" % [str(after.get("tick")), saved_tick])
		return
	if building_sig(after) != saved_buildings:
		fail("save", "buildings after load %s != saved %s" % [building_sig(after), saved_buildings])
		return
	person = person_by_index(after, 0)
	region = region_of("save", person, REGION_TORSO)
	if failed:
		return
	if abs(float(region.get("bleeding", -1.0)) - 1.0) > 0.001 or abs(float(region.get("infected", -1.0)) - 0.2) > 0.001:
		fail("save", "wound after load is bleeding %s infected %s" % [str(region.get("bleeding")), str(region.get("infected"))])
		return
	if abs(float(person.get("fatigue", -1.0)) - 0.4) > 0.001 or abs(float(person.get("warmth", -1.0)) - 0.7) > 0.001:
		fail("save", "fatigue or warmth changed across the round trip")
		return
	if abs(skill_at("save", person, SKILL_GATHER) - 0.1) > 0.001 or abs(skill_at("save", person, SKILL_MEDICINE) - 0.3) > 0.001:
		fail("save", "skills changed across the round trip")
		return
	ok("save")
	var refused := rewrite_version(save_text, SAVE_VERSION, 2)
	if refused == "":
		fail("save-v2", "save text has no save_version %d to refuse" % SAVE_VERSION)
		return
	var before_hash := hash_string()
	var before_tick := int(host.call("tick"))
	code = host.call("load_json", refused)
	if code == null or int(code) != 1:
		fail("save-v2", "a version 2 save returned %s, expected 1" % str(code))
		return
	if hash_string() != before_hash or int(host.call("tick")) != before_tick:
		fail("save-v2", "refusing a version 2 save changed the world")
		return
	ok("save-v2")

