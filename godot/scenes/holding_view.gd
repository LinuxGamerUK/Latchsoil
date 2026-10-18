extends Node3D

# Draws the acre and whatever the snapshot currently lists.
# Positions are copied from the snapshot. This file does not integrate them.

const ACRE_M := 32.0
const LAYER_GROUND := 1
const LAYER_PERSON := 2
const LAYER_NODE := 4
const LAYER_BUILDING := 8
const BUILD_TICKS := 60
const KIND_CAMPFIRE := 0
const KIND_LEAN_TO := 1
const KIND_STOCKPILE := 2
const BODY_TIMBER := Color(0.34, 0.20, 0.11)
const BODY_DRAFTED := Color(0.10, 0.09, 0.08)
const JOB_REST := 7
const JOB_NAMES: PackedStringArray = ["haul", "build", "farm", "craft", "heal", "cook", "guard", "rest"]
# Marks sit on the capsule. Order is the contract: head, torso, left arm, right arm, left leg, right leg.
const REGION_MARKS: Array = [
	Vector3(0.0, 1.50, -0.30),
	Vector3(0.0, 1.06, -0.33),
	Vector3(-0.40, 1.02, -0.08),
	Vector3(0.40, 1.02, -0.08),
	Vector3(-0.16, 0.38, -0.30),
	Vector3(0.16, 0.38, -0.30),
]
# Day ambient is 0.9. Below that line the person is losing warmth. The far mark
# waits until it is obvious at holding zoom, so a mild day does not paint the acre.
const COLD_CLOSE := 0.82
const COLD_FAR := 0.70
# 1a starting amounts from the sim rules. Mesh scale is remaining over these.
const NODE_START := {
	"wood": 40,
	"stone": 30,
	"fibre": 50,
	"water": 100,
}
const NODE_FILL_MIN := 0.35
const RIBBON_WIDTH := 0.6
# Wider than this, the holding is read from silhouette and ground marks.
# The HUD already names the selected job, and a billboard covers the ring.
const LABEL_HIDE_ABOVE := 30.0
const LABEL_REF_ORTHO := 12.0
const LABEL_FONT := 64
const LABEL_REF_METERS := 0.58
const LABEL_LIFT := 2.75

var label_hide_above := LABEL_HIDE_ABOVE

var people: Dictionary = {}
var eating: Dictionary = {}
var nodes: Dictionary = {}
var path_meshes: Dictionary = {}
var dest_markers: Dictionary = {}
var item_names: Dictionary = {}
var yield_kind: Dictionary = {}
var _warned := {}

var people_root: Node3D
var nodes_root: Node3D
var path_root: Node3D
var buildings_root: Node3D

var buildings: Dictionary = {}
var building_focus := ""
var ghost: Node3D

var sash_mat: StandardMaterial3D
var scrap_mat: StandardMaterial3D
var yoke_mat: StandardMaterial3D
var tool_mat: StandardMaterial3D
var select_mat: StandardMaterial3D
var fail_mat: StandardMaterial3D
var wood_mat: StandardMaterial3D
var stone_mat: StandardMaterial3D
var fibre_mat: StandardMaterial3D
var water_mat: StandardMaterial3D
var unknown_mat: StandardMaterial3D
var path_materials: Array = []
var item_mats: Array = []
var timber_mat: StandardMaterial3D
var ceramic_mat: StandardMaterial3D
var soot_mat: StandardMaterial3D
var site_mat: StandardMaterial3D
var flame_mat: StandardMaterial3D
var canvas_mat: StandardMaterial3D
var ghost_mat: StandardMaterial3D
var cell_mat: StandardMaterial3D
var focus_mat: StandardMaterial3D
var wound_mat: StandardMaterial3D
var infect_mat: StandardMaterial3D
var sick_mat: StandardMaterial3D
var wrap_mat: StandardMaterial3D
var treated_mat: StandardMaterial3D
var hurt_mark_mat: StandardMaterial3D
var cold_mat: StandardMaterial3D
var cold_mark_mat: StandardMaterial3D
var sleep_roll_mat: StandardMaterial3D
var blanket_mat: StandardMaterial3D
var foot_mat: StandardMaterial3D

var shape_wood: BoxShape3D
var shape_stone: SphereShape3D
var shape_fibre: SphereShape3D
var shape_water: CylinderShape3D
var shape_unknown: BoxShape3D


func peg_position() -> Vector3:
	return Vector3(ACRE_M * 0.5, 0.0, ACRE_M * 0.5)


func _ready() -> void:
	_make_materials()
	_make_shapes()
	_build_field()
	people_root = Node3D.new()
	people_root.name = "People"
	add_child(people_root)
	nodes_root = Node3D.new()
	nodes_root.name = "Nodes"
	add_child(nodes_root)
	path_root = Node3D.new()
	path_root.name = "Paths"
	add_child(path_root)
	buildings_root = Node3D.new()
	buildings_root.name = "Buildings"
	add_child(buildings_root)


func _process(_delta: float) -> void:
	# Zoom changes the orthographic size without a new snapshot. The label has
	# to track that, or a fixed-pixel billboard covers the ring on the way out.
	_fit_job_labels()


func set_item_names(items: Array) -> void:
	for row in items:
		if not row is Dictionary:
			continue
		var id := _int_of(row.get("id", -1), -1)
		var kind := _kind_from_name(str(row.get("name", "")))
		if id >= 0 and kind != "":
			item_names[id] = kind


func apply_snapshot(snap: Dictionary, selection: Array, rejects: Dictionary) -> void:
	if not snap.has("people") or not snap.has("nodes"):
		return
	var people_rows = snap.get("people", [])
	var node_rows = snap.get("nodes", [])
	if not people_rows is Array or not node_rows is Array:
		return
	var full := bool(snap.get("full", false))
	var tick := _int_of(snap.get("tick", 0), 0)
	var sel_keys := _selection_keys(selection)
	_sync_people(people_rows, full, sel_keys, rejects, tick)
	_sync_nodes(node_rows, full)
	if snap.has("buildings") and snap.get("buildings") is Array:
		_sync_buildings(snap.get("buildings"), full)
	_sync_removed(snap.get("removed", []))
	_sync_orders(people_rows, full)


func pick_person(camera: Camera3D, mouse: Vector2) -> Dictionary:
	return _entity_from_hit(_raycast(camera, mouse, LAYER_PERSON), "person")


func pick_node(camera: Camera3D, mouse: Vector2) -> Dictionary:
	return _entity_from_hit(_raycast(camera, mouse, LAYER_NODE), "node")


func pick_building(camera: Camera3D, mouse: Vector2) -> Dictionary:
	return _entity_from_hit(_raycast(camera, mouse, LAYER_BUILDING), "building")


# Half away from zero, the same rule the sim applies before a place lands.
func snap_axis(value: float) -> float:
	if value >= 0.0:
		return floorf(value + 0.5)
	return -floorf(-value + 0.5)


func snap_point(point: Vector3) -> Vector3:
	return Vector3(snap_axis(point.x), 0.0, snap_axis(point.z))


func show_ghost(kind: int, at: Vector3) -> void:
	if ghost == null or _int_of(ghost.get_meta("kind", -1), -1) != kind:
		_rebuild_ghost(kind)
	ghost.position = at
	ghost.visible = true


func hide_ghost() -> void:
	if ghost != null:
		ghost.visible = false


func set_building_focus(index: int, generation: int) -> void:
	building_focus = _id_key(index, generation)


func clear_building_focus() -> void:
	building_focus = ""


func pick_ground(camera: Camera3D, mouse: Vector2) -> Variant:
	var hit := _raycast(camera, mouse, LAYER_GROUND)
	if hit.has("position"):
		return hit["position"]
	if camera == null:
		return null
	var origin := camera.project_ray_origin(mouse)
	var normal := camera.project_ray_normal(mouse)
	if absf(normal.y) < 0.0001:
		return null
	var t := -origin.y / normal.y
	if t < 0.0:
		return null
	return origin + normal * t


func _sync_people(rows: Array, full: bool, sel_keys: Dictionary, rejects: Dictionary, tick: int) -> void:
	var seen := {}
	for row in rows:
		if not row is Dictionary:
			continue
		if not row.has("x") or not row.has("y"):
			_warn_once("person_xy", "latchsoil: a person row has no x,y")
			continue
		var index := _int_of(row.get("index", -1), -1)
		var generation := _int_of(row.get("generation", -1), -1)
		var key := _id_key(index, generation)
		seen[key] = true
		var body: AnimatableBody3D = people.get(key)
		if body == null:
			body = _make_person(index, generation)
			people[key] = body
			people_root.add_child(body)
		_place_person(body, row)
		_style_person(body, row, sel_keys.has(key), _marked(row, key, rejects), tick)
	if full:
		_drop_missing(people, seen)


func _sync_nodes(rows: Array, full: bool) -> void:
	var seen := {}
	for row in rows:
		if not row is Dictionary:
			continue
		if not row.has("x") or not row.has("y"):
			_warn_once("node_xy", "latchsoil: a node row has no x,y")
			continue
		var index := _int_of(row.get("index", -1), -1)
		var generation := _int_of(row.get("generation", -1), -1)
		var key := _id_key(index, generation)
		seen[key] = true
		var body: AnimatableBody3D = nodes.get(key)
		if body == null:
			body = _make_node(index, generation)
			nodes[key] = body
			nodes_root.add_child(body)
		body.position = Vector3(_float_of(row.get("x"), 0.0), 0.0, _float_of(row.get("y"), 0.0))
		var kind := _kind_for(row)
		_apply_node_visual(body, kind)
		_apply_node_fill(body, kind, row)
		body.force_update_transform()
	if full:
		_drop_missing(nodes, seen)


func _sync_buildings(rows: Array, full: bool) -> void:
	var seen := {}
	for row in rows:
		if not row is Dictionary:
			continue
		if not row.has("x") or not row.has("y"):
			_warn_once("building_xy", "latchsoil: a building row has no x,y")
			continue
		var index := _int_of(row.get("index", -1), -1)
		var generation := _int_of(row.get("generation", -1), -1)
		var key := _id_key(index, generation)
		seen[key] = true
		var body: AnimatableBody3D = buildings.get(key)
		if body == null:
			body = _make_building(index, generation)
			buildings[key] = body
			buildings_root.add_child(body)
		body.position = Vector3(_float_of(row.get("x"), 0.0), 0.0, _float_of(row.get("y"), 0.0))
		_apply_building(body, row)
		var focus := body.get_node_or_null("Focus") as Node3D
		if focus != null:
			focus.visible = key == building_focus
		body.force_update_transform()
		if body.is_inside_tree():
			PhysicsServer3D.body_set_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, body.global_transform)
	if full:
		_drop_missing(buildings, seen)


func _sync_removed(removed) -> void:
	if not removed is Array or removed.is_empty():
		return
	if removed[0] is Array:
		for entry in removed:
			if entry is Array and entry.size() >= 2:
				_drop_id(_int_of(entry[0], -1), _int_of(entry[1], -1))
		return
	var i := 0
	while i + 1 < removed.size():
		_drop_id(_int_of(removed[i], -1), _int_of(removed[i + 1], -1))
		i += 2


func _sync_orders(rows: Array, full: bool) -> void:
	# Path and destination stay until the job ends or fails, not until deselect.
	var shown := {}
	for row in rows:
		if not row is Dictionary:
			continue
		var index := _int_of(row.get("index", -1), -1)
		var generation := _int_of(row.get("generation", -1), -1)
		var key := _id_key(index, generation)
		var has_path := _pairs(row.get("path", [])).size() > 0
		var has_dest := _dest_point(row.get("dest", [])) is Vector3
		if has_path or has_dest:
			_show_order(key, row, index)
		else:
			_hide_order(key)
		shown[key] = true
	if not full:
		return
	for key in path_meshes.keys():
		if not shown.has(key):
			_hide_order(str(key))
	for key in dest_markers.keys():
		if not shown.has(key):
			_hide_order(str(key))


func _show_order(key: String, row: Dictionary, ordinal: int) -> void:
	var points := _path_points(row)
	var mesh_node := _ensure_path(key)
	if points.size() >= 2:
		mesh_node.visible = true
		mesh_node.material_override = _path_material(ordinal)
		mesh_node.mesh = _ribbon(points, RIBBON_WIDTH)
	else:
		mesh_node.visible = false
	var dest = _dest_point(row.get("dest", []))
	var marker := _ensure_dest(key)
	if dest is Vector3:
		marker.visible = true
		marker.position = dest
		var mat := _path_material(ordinal)
		for child in marker.get_children():
			if child is MeshInstance3D:
				child.material_override = mat
	else:
		marker.visible = false


func _hide_order(key: String) -> void:
	if path_meshes.has(key):
		path_meshes[key].visible = false
	if dest_markers.has(key):
		dest_markers[key].visible = false


func _style_person(body: AnimatableBody3D, row: Dictionary, selected: bool, marked: bool, tick: int) -> void:
	var drafted := bool(row.get("drafted", false))
	var mat := body.get_meta("body_mat") as StandardMaterial3D
	if mat != null:
		mat.albedo_color = BODY_DRAFTED if drafted else BODY_TIMBER
		mat.emission_enabled = selected and not drafted and not marked
		if mat.emission_enabled:
			mat.emission = Color(0.45, 0.28, 0.08)
			mat.emission_energy_multiplier = 0.35
	var sash := body.get_node_or_null("Pose/Sash")
	if sash != null:
		sash.visible = not drafted
	var yoke := body.get_node_or_null("Pose/Yoke")
	if yoke != null:
		yoke.visible = drafted
	var resting := _int_of(row.get("job", -1), -1) == JOB_REST
	var tool := body.get_node_or_null("Pose/Tool")
	if tool != null:
		tool.visible = _is_working(row) and not resting
	var ring := body.get_node_or_null("Ring")
	if ring != null:
		ring.visible = selected or marked
		var ring_mat: Material = fail_mat if marked else select_mat
		for seg in ring.get_children():
			if seg is MeshInstance3D:
				seg.material_override = ring_mat
	body.set_meta("show_job", selected)
	var label := body.get_node_or_null("JobLabel") as Label3D
	if label != null:
		label.text = _job_name(row, tick)
		_fit_job_label(label, selected)
	_apply_condition(body, row)


func _apply_condition(body: AnimatableBody3D, row: Dictionary) -> void:
	var regions := _region_rows(row)
	var resting := _int_of(row.get("job", -1), -1) == JOB_REST
	_apply_wounds(body, regions)
	_apply_posture(body, regions, resting)
	_apply_cold(body, row)


func _apply_wounds(body: AnimatableBody3D, regions: Array) -> void:
	var wounds := body.get_node_or_null("Pose/Wounds") as Node3D
	var hurt := body.get_node_or_null("HurtMark") as Node3D
	if wounds == null:
		return
	var worst := 0.0
	var any_hurt := false
	for child in wounds.get_children():
		child.visible = false
	for i in regions.size():
		var entry = regions[i]
		if not entry is Dictionary:
			continue
		var slot := _region_slot(entry, i)
		if slot < 0 or slot >= wounds.get_child_count():
			continue
		var mark := wounds.get_child(slot) as Node3D
		if mark == null:
			continue
		var severity := _region_severity(entry)
		var bandaged := _flag(entry.get("bandaged", false))
		var treated := _flag(entry.get("treated", false))
		var infected := _float_of(entry.get("infected", 0.0), 0.0)
		var open := severity > 0.001 or bandaged or treated
		mark.visible = open
		if not open:
			continue
		if severity > 0.001:
			any_hurt = true
			worst = maxf(worst, severity)
		var stain := mark.get_node_or_null("Stain") as Node3D
		var wrap := mark.get_node_or_null("Wrap") as Node3D
		var sick := mark.get_node_or_null("Sick") as Node3D
		var dot := mark.get_node_or_null("Dot") as MeshInstance3D
		var scale := lerpf(0.85, 1.45, severity)
		if stain != null:
			stain.visible = severity > 0.001 and not bandaged
			stain.scale = Vector3.ONE * scale
			_paint(stain, infect_mat if infected > 0.001 else wound_mat)
		if wrap != null:
			wrap.visible = bandaged
			wrap.scale = Vector3.ONE * lerpf(0.95, 1.2, severity)
			_paint(wrap, infect_mat if infected > 0.001 else wrap_mat)
		if sick != null:
			# A wider band, not a splatter. Close zoom: it sits outside the stain.
			sick.visible = infected > 0.001
			sick.scale = Vector3.ONE * lerpf(0.9, 1.25, clampf(infected, 0.0, 1.0))
		if dot != null:
			dot.visible = treated
	if hurt != null:
		hurt.visible = any_hurt
		hurt.scale = Vector3(1.0, lerpf(0.7, 1.25, worst), 1.0)


func _apply_posture(body: AnimatableBody3D, regions: Array, resting: bool) -> void:
	var pose := body.get_node_or_null("Pose") as Node3D
	var mat := body.get_node_or_null("SleepMat") as Node3D
	var blanket := body.get_node_or_null("Pose/Blanket") as Node3D
	var stand := body.get_node_or_null("Collision") as CollisionShape3D
	var lying := body.get_node_or_null("SleepCollision") as CollisionShape3D
	if pose == null:
		return
	if resting:
		# Capsule centre sits at local y 0.85. -90 X lays that axis along Z.
		pose.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		pose.position = Vector3(0.0, 0.36, -0.85)
		if blanket != null:
			blanket.visible = true
		if mat != null:
			mat.visible = true
		_set_feet(body, false, false)
		if stand != null:
			stand.disabled = true
		if lying != null:
			lying.disabled = false
		return
	if blanket != null:
		blanket.visible = false
	if mat != null:
		mat.visible = false
	if stand != null:
		stand.disabled = false
	if lying != null:
		lying.disabled = true
	var left := _leg_severity(regions, 4)
	var right := _leg_severity(regions, 5)
	_set_feet(body, left > 0.001, right > 0.001)
	if left <= 0.001 and right <= 0.001:
		pose.rotation_degrees = Vector3.ZERO
		pose.position = Vector3.ZERO
		return
	# A hurt leg leans onto the good one and drags a foot. Both legs: a hunch.
	var roll := 0.0
	var pitch := 0.0
	if left > 0.001 and right > 0.001:
		pitch = lerpf(8.0, 16.0, maxf(left, right))
	elif left > 0.001:
		roll = -lerpf(8.0, 16.0, left)
		pitch = lerpf(4.0, 8.0, left)
	else:
		roll = lerpf(8.0, 16.0, right)
		pitch = lerpf(4.0, 8.0, right)
	pose.rotation_degrees = Vector3(pitch, 0.0, roll)
	pose.position = Vector3(0.0, -0.06, 0.0)


func _apply_cold(body: AnimatableBody3D, row: Dictionary) -> void:
	var shawl := body.get_node_or_null("Pose/Shawl") as MeshInstance3D
	var mark := body.get_node_or_null("ColdMark") as Node3D
	if not row.has("warmth"):
		if shawl != null:
			shawl.visible = false
		if mark != null:
			mark.visible = false
		return
	var warmth := _float_of(row.get("warmth"), 1.0)
	var loss := clampf((COLD_CLOSE - warmth) / COLD_CLOSE, 0.0, 1.0)
	if shawl != null:
		shawl.visible = warmth < COLD_CLOSE
		shawl.scale = Vector3(lerpf(0.85, 1.25, loss), 1.0, lerpf(0.8, 1.15, loss))
	if mark != null:
		mark.visible = warmth < COLD_FAR
		mark.scale = Vector3(lerpf(0.85, 1.2, loss), 1.0, 1.0)


func _set_feet(body: AnimatableBody3D, left: bool, right: bool) -> void:
	var feet := body.get_node_or_null("Pose/Feet") as Node3D
	if feet == null:
		return
	var left_foot := feet.get_node_or_null("Left")
	var right_foot := feet.get_node_or_null("Right")
	if left_foot != null:
		left_foot.visible = left
	if right_foot != null:
		right_foot.visible = right


func _leg_severity(regions: Array, slot: int) -> float:
	for i in regions.size():
		var entry = regions[i]
		if not entry is Dictionary:
			continue
		if _region_slot(entry, i) != slot:
			continue
		return _region_severity(entry)
	return 0.0


func _region_severity(entry: Dictionary) -> float:
	var health := _float_of(entry.get("health", 1.0), 1.0)
	var bleeding := _float_of(entry.get("bleeding", 0.0), 0.0)
	var infected := _float_of(entry.get("infected", 0.0), 0.0)
	return clampf(maxf(1.0 - health, maxf(bleeding, infected)), 0.0, 1.0)


func _region_rows(row: Dictionary) -> Array:
	var value = row.get("regions", null)
	if value is Array:
		return value
	if not value is Dictionary:
		return []
	var names: Array = ["head", "torso", "left arm", "right arm", "left leg", "right leg"]
	var alts: Array = ["head", "torso", "left_arm", "right_arm", "left_leg", "right_leg"]
	var out: Array = []
	var found := false
	for i in names.size():
		var entry = null
		if value.has(names[i]):
			entry = value[names[i]]
			found = true
		elif value.has(alts[i]):
			entry = value[alts[i]]
			found = true
		elif value.has(i):
			entry = value[i]
			found = true
		out.append(entry if entry is Dictionary else {})
	return out if found else []


func _region_slot(entry: Dictionary, fallback: int) -> int:
	if entry.has("kind"):
		var kind := _int_of(entry.get("kind"), -1)
		if kind >= 0 and kind < REGION_MARKS.size():
			return kind
	return fallback


func _flag(value) -> bool:
	if value is bool:
		return value
	if value is int or value is float:
		return int(value) != 0
	return false


func _make_wound_mark(slot: int) -> Node3D:
	var mark := Node3D.new()
	mark.name = "R%d" % slot
	mark.position = _region_at(slot)
	mark.visible = false
	var stain := Node3D.new()
	stain.name = "Stain"
	mark.add_child(stain)
	_add_region_shape(stain, slot, wound_mat, 1.0)
	var wrap := Node3D.new()
	wrap.name = "Wrap"
	wrap.visible = false
	mark.add_child(wrap)
	_add_region_shape(wrap, slot, wrap_mat, 1.15)
	var sick := Node3D.new()
	sick.name = "Sick"
	sick.visible = false
	mark.add_child(sick)
	_add_region_shape(sick, slot, sick_mat, 1.4)
	var dot := MeshInstance3D.new()
	dot.name = "Dot"
	var dot_mesh := SphereMesh.new()
	dot_mesh.radius = 0.06
	dot_mesh.height = 0.12
	dot.mesh = dot_mesh
	dot.position = Vector3(0.0, 0.12, 0.0)
	dot.material_override = treated_mat
	dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dot.visible = false
	mark.add_child(dot)
	return mark


func _region_at(slot: int) -> Vector3:
	match slot:
		0:
			return Vector3(0.0, 1.46, 0.0)
		1:
			return Vector3(0.0, 1.05, 0.0)
		2:
			return Vector3(-0.50, 1.02, 0.0)
		3:
			return Vector3(0.50, 1.02, 0.0)
		4:
			return Vector3(-0.30, 0.30, 0.10)
		_:
			return Vector3(0.30, 0.30, 0.10)


func _add_region_shape(parent: Node3D, slot: int, mat: Material, scale: float) -> void:
	# A band around the trunk reads from every 90 degree camera snap. Arms and
	# legs are a chunk on that side, outside the capsule, so the place is the side.
	if slot <= 1:
		var radius := 0.26 if slot == 0 else 0.42
		_band(parent, radius * scale, 0.1 * scale, mat)
		return
	var chunk := BoxMesh.new()
	if slot <= 3:
		chunk.size = Vector3(0.28, 0.24, 0.24) * scale
	else:
		chunk.size = Vector3(0.24, 0.22, 0.3) * scale
	var node := MeshInstance3D.new()
	node.mesh = chunk
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)


func _band(parent: Node3D, radius: float, thick: float, mat: Material) -> void:
	var count := 8
	var seg := BoxMesh.new()
	seg.size = Vector3(thick, thick * 0.85, TAU * radius / float(count) * 1.2)
	for i in count:
		var piece := MeshInstance3D.new()
		piece.mesh = seg
		var angle := TAU * float(i) / float(count)
		piece.position = Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		piece.rotation.y = -angle
		piece.material_override = mat
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(piece)


func _paint(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = mat
	for child in node.get_children():
		_paint(child, mat)


func _make_foot(foot_name: String, at: Vector3) -> MeshInstance3D:
	var foot := MeshInstance3D.new()
	foot.name = foot_name
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.22, 0.1, 0.34)
	foot.mesh = mesh
	foot.position = at
	foot.material_override = foot_mat
	foot.visible = false
	return foot


func _make_hurt_mark() -> Node3D:
	var mark := Node3D.new()
	mark.name = "HurtMark"
	mark.visible = false
	var stake := MeshInstance3D.new()
	var stake_mesh := BoxMesh.new()
	stake_mesh.size = Vector3(0.18, 0.7, 0.18)
	stake.mesh = stake_mesh
	stake.position = Vector3(0.0, 2.15, 0.0)
	stake.material_override = hurt_mark_mat
	stake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mark.add_child(stake)
	_status_ring(mark, 1.05, hurt_mark_mat)
	return mark


func _make_cold_mark() -> Node3D:
	var mark := Node3D.new()
	mark.name = "ColdMark"
	mark.visible = false
	var bar := MeshInstance3D.new()
	var bar_mesh := BoxMesh.new()
	bar_mesh.size = Vector3(1.8, 0.12, 0.42)
	bar.mesh = bar_mesh
	bar.position = Vector3(0.0, 0.08, 0.0)
	bar.material_override = cold_mark_mat
	bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mark.add_child(bar)
	_status_ring(mark, 1.15, cold_mark_mat)
	return mark


func _make_sleep_mat() -> MeshInstance3D:
	var mat := MeshInstance3D.new()
	mat.name = "SleepMat"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.05, 0.05, 2.35)
	mat.mesh = mesh
	mat.position = Vector3(0.0, 0.04, 0.0)
	mat.material_override = sleep_roll_mat
	mat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mat.visible = false
	return mat


func _status_ring(parent: Node3D, radius: float, mat: Material) -> void:
	var segments := 12
	var seg_mesh := BoxMesh.new()
	var arc := TAU * radius / float(segments)
	seg_mesh.size = Vector3(0.2, 0.06, arc * 1.35)
	for i in segments:
		var seg := MeshInstance3D.new()
		seg.mesh = seg_mesh
		var angle := TAU * float(i) / float(segments)
		seg.position = Vector3(cos(angle) * radius, 0.06, sin(angle) * radius)
		seg.rotation.y = -angle
		seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		seg.material_override = mat
		parent.add_child(seg)


func _job_name(row: Dictionary, tick: int) -> String:
	# Eat is an order, not a JobKind, and it writes no path. The label comes from
	# the submit that returned 0, not from the failure discriminant.
	if _showing_eat(row, tick):
		return "eat"
	var job := _int_of(row.get("job", -1), -1)
	if job >= 0 and job < JOB_NAMES.size():
		return JOB_NAMES[job]
	if _has_target(row.get("target", [])) and _has_route(row):
		return "gather"
	if _has_route(row):
		return "move"
	return "idle"


func note_eat(index: int, generation: int, tick: int) -> void:
	eating[_id_key(index, generation)] = tick


func _showing_eat(row: Dictionary, tick: int) -> bool:
	var key := _id_key(_int_of(row.get("index", -1), -1), _int_of(row.get("generation", -1), -1))
	if not eating.has(key):
		return false
	# The submit applies next tick. Until then the snapshot still has the
	# previous route and failure, which are not this order.
	if tick <= _int_of(eating.get(key, 0), 0):
		return true
	if str(row.get("failure_text", "")) != "":
		eating.erase(key)
		return false
	if _has_route(row) or _has_target(row.get("target", [])):
		eating.erase(key)
		return false
	return true


func _is_working(row: Dictionary) -> bool:
	if _int_of(row.get("job", -1), -1) >= 0:
		return true
	return _has_route(row)


func _has_route(row: Dictionary) -> bool:
	if _pairs(row.get("path", [])).size() > 0:
		return true
	return _dest_point(row.get("dest", [])) is Vector3


func _marked(row: Dictionary, key: String, rejects: Dictionary) -> bool:
	if rejects.has(key):
		return true
	if str(row.get("failure_text", "")) != "":
		return true
	return _int_of(row.get("failure", -1), -1) >= 0


func _place_person(body: AnimatableBody3D, row: Dictionary) -> void:
	# A physics sync copies the server origin back onto the node. look_at reads
	# a stale global transform and writes that origin over the position just
	# set, so the sync then repeats the reset. Place from the snapshot and aim
	# with the basis only, so the origin we wrote is the one that stays.
	body.sync_to_physics = false
	var placed := Vector3(_float_of(row.get("x"), 0.0), 0.0, _float_of(row.get("y"), 0.0))
	var basis := body.basis
	var aim: Variant = _aim_point(placed, row)
	if aim is Vector3:
		var to: Vector3 = aim - placed
		to.y = 0.0
		if to.length_squared() > 0.0004:
			basis = Basis.looking_at(to, Vector3.UP)
	body.transform = Transform3D(basis, placed)
	body.force_update_transform()
	if body.is_inside_tree():
		PhysicsServer3D.body_set_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, body.global_transform)


func _aim_point(origin: Vector3, row: Dictionary) -> Variant:
	for point in _pairs(row.get("path", [])):
		var world := Vector3(point.x, origin.y, point.y)
		if origin.distance_squared_to(world) > 0.04:
			return world
	var dest = _dest_point(row.get("dest", []))
	if dest is Vector3:
		var flat := Vector3(dest.x, origin.y, dest.z)
		if origin.distance_squared_to(flat) > 0.04:
			return flat
	return null


func _fit_job_labels() -> void:
	if people.is_empty():
		return
	for body in people.values():
		var label := body.get_node_or_null("JobLabel") as Label3D
		if label == null:
			continue
		_fit_job_label(label, bool(body.get_meta("show_job", false)))


func _fit_job_label(label: Label3D, selected: bool) -> void:
	var ortho := _view_ortho()
	# Screen size tracks the orthographic size: a fixed-pixel billboard stays
	# huge while the person shrinks and ends up on the ring.
	var fit := clampf(LABEL_REF_ORTHO / maxf(ortho, 1.0), 0.5, 1.15)
	label.fixed_size = false
	label.pixel_size = LABEL_REF_METERS * fit / float(LABEL_FONT)
	label.font_size = LABEL_FONT
	label.outline_size = 12
	var lift := LABEL_LIFT
	var body := label.get_parent()
	if body != null:
		# The starting three stand on one cell. Stagger the billboards or the
		# job names land on each other.
		lift += float(_int_of(body.get_meta("index", 0), 0)) * 1.45
	label.position = Vector3(0.0, lift, 0.0)
	label.visible = selected and ortho <= label_hide_above


func _view_ortho() -> float:
	var rig := get_node_or_null("../CameraRig")
	if rig != null:
		var cam := rig.get_node_or_null("Camera3D") as Camera3D
		if cam != null and cam.projection == Camera3D.PROJECTION_ORTHOGONAL:
			return cam.size
		var stored = rig.get("ortho_size")
		if stored is float or stored is int:
			return float(stored)
	return label_hide_above + 1.0


func _kind_for(row: Dictionary) -> String:
	var item_id := _int_of(row.get("yield_item", -1), -1)
	if item_names.has(item_id):
		return str(item_names[item_id])
	if yield_kind.has(item_id):
		return str(yield_kind[item_id])
	var remaining := _int_of(row.get("remaining", -1), -1)
	var learned := ""
	match remaining:
		40:
			learned = "wood"
		30:
			learned = "stone"
		50:
			learned = "fibre"
		100:
			learned = "water"
	if learned != "" and item_id >= 0:
		yield_kind[item_id] = learned
	return learned


func _kind_from_name(item_name: String) -> String:
	var n := item_name.to_lower()
	if "wood" in n:
		return "wood"
	if "stone" in n:
		return "stone"
	if "fibre" in n or "fiber" in n:
		return "fibre"
	if "water" in n:
		return "water"
	return ""


func _build_field() -> void:
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	ground.position = Vector3(ACRE_M * 0.5, -0.2, ACRE_M * 0.5)
	ground.collision_layer = LAYER_GROUND
	ground.collision_mask = 0
	var box := BoxMesh.new()
	box.size = Vector3(ACRE_M, 0.4, ACRE_M)
	var mesh := MeshInstance3D.new()
	mesh.mesh = box
	mesh.material_override = _flat(Color(0.79, 0.63, 0.38))
	ground.add_child(mesh)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(ACRE_M, 0.4, ACRE_M)
	col.shape = shape
	ground.add_child(col)
	add_child(ground)

	var grid := Node3D.new()
	grid.name = "Grid"
	add_child(grid)
	var minor := _flat(Color(0.46, 0.30, 0.14), true)
	var major := _flat(Color(0.26, 0.15, 0.07), true)
	for i in 33:
		var metres := float(i)
		var is_major := i % 4 == 0
		var width := 0.09 if is_major else 0.035
		var mat: Material = major if is_major else minor
		_grid_line(grid, Vector3(ACRE_M * 0.5, 0.02, metres), Vector3(ACRE_M, 0.02, width), mat)
		_grid_line(grid, Vector3(metres, 0.02, ACRE_M * 0.5), Vector3(width, 0.02, ACRE_M), mat)

	var peg := Node3D.new()
	peg.name = "Peg"
	peg.position = peg_position()
	add_child(peg)
	var post_mesh := CylinderMesh.new()
	post_mesh.top_radius = 0.06
	post_mesh.bottom_radius = 0.09
	post_mesh.height = 1.45
	var post := MeshInstance3D.new()
	post.mesh = post_mesh
	post.position = Vector3(0.0, 0.72, 0.0)
	post.material_override = _flat(Color(0.32, 0.18, 0.08))
	peg.add_child(post)
	var flag_mesh := BoxMesh.new()
	flag_mesh.size = Vector3(0.28, 0.16, 0.03)
	var flag := MeshInstance3D.new()
	flag.mesh = flag_mesh
	flag.position = Vector3(0.16, 1.35, 0.0)
	flag.material_override = scrap_mat
	peg.add_child(flag)


func _grid_line(parent: Node3D, at: Vector3, size: Vector3, mat: Material) -> void:
	var line := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	line.mesh = box
	line.position = at
	line.material_override = mat
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(line)


func _make_person(index: int, generation: int) -> AnimatableBody3D:
	var body := AnimatableBody3D.new()
	body.name = "Person_%d_%d" % [index, generation]
	body.collision_layer = LAYER_PERSON
	body.collision_mask = 0
	# Snapshot placement owns the transform. A physics sync writes a stale
	# origin back over it. The transform notification still moves the shape,
	# so picking keeps working.
	body.sync_to_physics = false
	body.set_meta("entity_kind", "person")
	body.set_meta("index", index)
	body.set_meta("generation", generation)

	var pose := Node3D.new()
	pose.name = "Pose"
	body.add_child(pose)

	var capsule := CapsuleMesh.new()
	capsule.radius = 0.34
	capsule.height = 1.7
	var mesh_node := MeshInstance3D.new()
	mesh_node.name = "Body"
	mesh_node.mesh = capsule
	mesh_node.position = Vector3(0.0, 0.85, 0.0)
	var mat := _flat(BODY_TIMBER)
	body.set_meta("body_mat", mat)
	mesh_node.material_override = mat
	pose.add_child(mesh_node)

	var sash := MeshInstance3D.new()
	sash.name = "Sash"
	var sash_mesh := BoxMesh.new()
	sash_mesh.size = Vector3(0.42, 0.14, 0.06)
	sash.mesh = sash_mesh
	sash.position = Vector3(0.0, 1.12, -0.32)
	sash.material_override = sash_mat
	pose.add_child(sash)

	var scrap := MeshInstance3D.new()
	scrap.name = "Scrap"
	var scrap_mesh := BoxMesh.new()
	scrap_mesh.size = Vector3(0.12, 0.09, 0.03)
	scrap.mesh = scrap_mesh
	scrap.position = Vector3(0.12, 1.14, -0.36)
	scrap.material_override = scrap_mat
	pose.add_child(scrap)

	var yoke := MeshInstance3D.new()
	yoke.name = "Yoke"
	var yoke_mesh := BoxMesh.new()
	yoke_mesh.size = Vector3(1.05, 0.28, 0.32)
	yoke.mesh = yoke_mesh
	yoke.position = Vector3(0.0, 1.29, 0.0)
	yoke.material_override = yoke_mat
	yoke.visible = false
	pose.add_child(yoke)

	var tool := MeshInstance3D.new()
	tool.name = "Tool"
	var tool_mesh := CylinderMesh.new()
	tool_mesh.top_radius = 0.045
	tool_mesh.bottom_radius = 0.055
	tool_mesh.height = 0.8
	tool.mesh = tool_mesh
	tool.position = Vector3(0.55, 0.95, -0.1)
	tool.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	tool.material_override = tool_mat
	tool.visible = false
	pose.add_child(tool)

	var wounds := Node3D.new()
	wounds.name = "Wounds"
	pose.add_child(wounds)
	for i in REGION_MARKS.size():
		wounds.add_child(_make_wound_mark(i))

	var feet := Node3D.new()
	feet.name = "Feet"
	pose.add_child(feet)
	feet.add_child(_make_foot("Left", Vector3(-0.48, 0.08, 0.16)))
	feet.add_child(_make_foot("Right", Vector3(0.48, 0.08, 0.16)))

	var blanket := MeshInstance3D.new()
	blanket.name = "Blanket"
	var blanket_mesh := BoxMesh.new()
	blanket_mesh.size = Vector3(0.82, 0.18, 1.45)
	blanket.mesh = blanket_mesh
	blanket.position = Vector3(0.0, 1.02, -0.06)
	blanket.material_override = blanket_mat
	blanket.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	blanket.visible = false
	pose.add_child(blanket)

	var shawl := MeshInstance3D.new()
	shawl.name = "Shawl"
	var shawl_mesh := BoxMesh.new()
	shawl_mesh.size = Vector3(0.92, 0.14, 0.2)
	shawl.mesh = shawl_mesh
	shawl.position = Vector3(0.0, 1.34, 0.0)
	shawl.material_override = cold_mat
	shawl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shawl.visible = false
	pose.add_child(shawl)

	# Far marks stay on the body, not the pose, so a sleeper does not tip them.
	body.add_child(_make_hurt_mark())
	body.add_child(_make_cold_mark())
	body.add_child(_make_sleep_mat())

	var ring := Node3D.new()
	ring.name = "Ring"
	ring.visible = false
	# Centreline 0.55 m, stroke 0.16 m. 1.45 m enclosed neighbours 1.0 m away.
	var ring_radius := 0.55
	var segments := 16
	var seg_mesh := BoxMesh.new()
	var arc := TAU * ring_radius / float(segments)
	seg_mesh.size = Vector3(0.16, 0.06, arc * 1.3)
	for i in segments:
		var seg := MeshInstance3D.new()
		seg.mesh = seg_mesh
		var angle := TAU * float(i) / float(segments)
		seg.position = Vector3(cos(angle) * ring_radius, 0.05, sin(angle) * ring_radius)
		seg.rotation.y = -angle
		seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		seg.material_override = select_mat
		ring.add_child(seg)
	body.add_child(ring)

	var label := Label3D.new()
	label.name = "JobLabel"
	label.position = Vector3(0.0, LABEL_LIFT, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.fixed_size = false
	label.pixel_size = LABEL_REF_METERS / float(LABEL_FONT)
	label.font_size = LABEL_FONT
	label.outline_size = 12
	label.modulate = Color(0.97, 0.94, 0.86)
	label.outline_modulate = Color(0.08, 0.05, 0.03)
	label.no_depth_test = true
	label.visible = false
	label.text = "idle"
	body.add_child(label)

	var col := CollisionShape3D.new()
	col.name = "Collision"
	var shape := CapsuleShape3D.new()
	shape.radius = 0.5
	shape.height = 1.85
	col.shape = shape
	col.position = Vector3(0.0, 0.92, 0.0)
	body.add_child(col)
	var sleep_col := CollisionShape3D.new()
	sleep_col.name = "SleepCollision"
	var sleep_shape := BoxShape3D.new()
	sleep_shape.size = Vector3(0.85, 0.55, 1.9)
	sleep_col.shape = sleep_shape
	sleep_col.position = Vector3(0.0, 0.28, 0.0)
	sleep_col.disabled = true
	body.add_child(sleep_col)
	return body


func _make_node(index: int, generation: int) -> AnimatableBody3D:
	var body := AnimatableBody3D.new()
	body.name = "Node_%d_%d" % [index, generation]
	body.collision_layer = LAYER_NODE
	body.collision_mask = 0
	body.sync_to_physics = true
	body.set_meta("entity_kind", "node")
	body.set_meta("index", index)
	body.set_meta("generation", generation)
	body.set_meta("kind_drawn", "")
	var col := CollisionShape3D.new()
	col.name = "Collision"
	col.shape = shape_unknown
	body.add_child(col)
	var visual := Node3D.new()
	visual.name = "Visual"
	body.add_child(visual)
	return body


func _make_building(index: int, generation: int) -> AnimatableBody3D:
	var body := AnimatableBody3D.new()
	body.name = "Building_%d_%d" % [index, generation]
	body.collision_layer = LAYER_BUILDING
	body.collision_mask = 0
	body.sync_to_physics = false
	body.set_meta("entity_kind", "building")
	body.set_meta("index", index)
	body.set_meta("generation", generation)
	body.set_meta("kind_drawn", -1)
	var col := CollisionShape3D.new()
	col.name = "Collision"
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.5, 1.6, 1.5)
	col.shape = shape
	col.position = Vector3(0.0, 0.8, 0.0)
	body.add_child(col)
	var visual := Node3D.new()
	visual.name = "Visual"
	body.add_child(visual)
	var focus := Node3D.new()
	focus.name = "Focus"
	focus.visible = false
	_cell_outline(focus, focus_mat, 1.25, 0.08)
	body.add_child(focus)
	return body


func _apply_building(body: AnimatableBody3D, row: Dictionary) -> void:
	var kind := _int_of(row.get("kind", -1), -1)
	var visual := body.get_node("Visual") as Node3D
	if _int_of(body.get_meta("kind_drawn", -1), -1) != kind:
		body.set_meta("kind_drawn", kind)
		for child in visual.get_children():
			child.free()
		_build_kind(visual, kind)
	var progress := _int_of(row.get("progress", 0), 0)
	var done := progress >= BUILD_TICKS
	var site := visual.get_node_or_null("Site") as Node3D
	var structure := visual.get_node_or_null("Structure") as Node3D
	if site != null:
		site.visible = not done
	if structure != null:
		structure.visible = progress > 0 or done
		if done:
			structure.scale = Vector3.ONE
		else:
			var risen := clampf(float(progress) / float(BUILD_TICKS), 0.2, 1.0)
			structure.scale = Vector3(1.0, risen, 1.0)
		var finish := structure.get_node_or_null("Finish") as Node3D
		if finish != null:
			finish.visible = done
		var partial := structure.get_node_or_null("Partial") as Node3D
		if partial != null:
			partial.visible = not done
	if kind == KIND_STOCKPILE:
		var goods := structure.get_node_or_null("Finish/Goods") if structure != null else null
		if goods is Node3D:
			_fill_crates(goods, row.get("contents", []) if done else [])


func _build_kind(visual: Node3D, kind: int) -> void:
	var site := Node3D.new()
	site.name = "Site"
	visual.add_child(site)
	_add_work_site(site, kind)
	var structure := Node3D.new()
	structure.name = "Structure"
	visual.add_child(structure)
	var finish := Node3D.new()
	finish.name = "Finish"
	structure.add_child(finish)
	match kind:
		KIND_CAMPFIRE:
			_add_campfire(structure, finish)
		KIND_LEAN_TO:
			_add_lean_to(structure, finish)
		KIND_STOCKPILE:
			_add_stockpile(structure, finish)
		_:
			_box(structure, Vector3(1.2, 1.0, 1.2), Vector3(0.0, 0.5, 0.0), unknown_mat)


func _add_work_site(site: Node3D, kind: int) -> void:
	# Open timber frame plus a material pile. The frame is the under-construction
	# read at both zooms; the finished mesh hides it.
	_box(site, Vector3(1.7, 0.06, 1.7), Vector3(0.0, 0.05, 0.0), site_mat)
	var post := Vector3(0.28, 1.25, 0.28)
	var half := 0.78
	for corner in [Vector3(-half, 0.62, -half), Vector3(half, 0.62, -half), Vector3(-half, 0.62, half), Vector3(half, 0.62, half)]:
		_box(site, post, corner, timber_mat)
	_box(site, Vector3(1.56, 0.16, 0.16), Vector3(0.0, 1.18, -half), timber_mat)
	_box(site, Vector3(1.56, 0.16, 0.16), Vector3(0.0, 1.18, half), timber_mat)
	_box(site, Vector3(0.16, 0.16, 1.56), Vector3(-half, 1.18, 0.0), timber_mat)
	_box(site, Vector3(0.16, 0.16, 1.56), Vector3(half, 1.18, 0.0), timber_mat)
	_box(site, Vector3(0.7, 0.28, 0.36), Vector3(-0.1, 0.18, 0.05), timber_mat)
	if kind == KIND_CAMPFIRE:
		_sphere(site, 0.22, Vector3(0.28, 0.18, 0.12), stone_mat)
	elif kind == KIND_STOCKPILE:
		_box(site, Vector3(0.9, 0.04, 0.9), Vector3(0.0, 0.1, 0.0), canvas_mat)


func _add_campfire(structure: Node3D, finish: Node3D) -> void:
	var ring := CylinderMesh.new()
	ring.top_radius = 0.62
	ring.bottom_radius = 0.7
	ring.height = 0.28
	_mesh(structure, ring, Vector3(0.0, 0.16, 0.0), stone_mat)
	var inner := CylinderMesh.new()
	inner.top_radius = 0.28
	inner.bottom_radius = 0.32
	inner.height = 0.12
	_mesh(structure, inner, Vector3(0.0, 0.18, 0.0), soot_mat)
	var log := CylinderMesh.new()
	log.top_radius = 0.08
	log.bottom_radius = 0.09
	log.height = 0.85
	var log_a := _mesh(finish, log, Vector3(0.0, 0.32, 0.0), timber_mat)
	log_a.rotation_degrees = Vector3(0.0, 28.0, 90.0)
	var log_b := _mesh(finish, log, Vector3(0.0, 0.40, 0.0), timber_mat)
	log_b.rotation_degrees = Vector3(78.0, 0.0, 0.0)
	var flame := SphereMesh.new()
	flame.radius = 0.34
	flame.height = 0.95
	_mesh(finish, flame, Vector3(0.0, 0.78, 0.0), flame_mat)


func _add_lean_to(structure: Node3D, finish: Node3D) -> void:
	# Tall back, open front, roof falling toward -Z. The wedge still explains
	# the door and the work stump after each 90 degree camera snap.
	_box(structure, Vector3(2.05, 1.65, 0.2), Vector3(0.0, 0.84, 0.82), timber_mat)
	_box(structure, Vector3(0.22, 1.65, 0.22), Vector3(-0.95, 0.84, 0.82), timber_mat)
	_box(structure, Vector3(0.22, 1.65, 0.22), Vector3(0.95, 0.84, 0.82), timber_mat)
	_box(structure, Vector3(0.22, 0.72, 0.22), Vector3(-0.95, 0.36, -0.72), timber_mat)
	_box(structure, Vector3(0.22, 0.72, 0.22), Vector3(0.95, 0.36, -0.72), timber_mat)
	var partial := Node3D.new()
	partial.name = "Partial"
	structure.add_child(partial)
	_box(partial, Vector3(1.6, 0.12, 0.32), Vector3(0.0, 0.95, 0.2), ceramic_mat)
	_box(partial, Vector3(1.6, 0.12, 0.32), Vector3(0.0, 0.55, -0.15), ceramic_mat)
	var roof := _box(finish, Vector3(2.35, 0.16, 2.15), Vector3(0.0, 1.42, 0.05), ceramic_mat)
	roof.rotation_degrees = Vector3(-34.0, 0.0, 0.0)
	_box(finish, Vector3(0.26, 0.1, 0.16), Vector3(0.45, 1.95, 0.55), scrap_mat)
	_box(finish, Vector3(0.42, 0.32, 0.42), Vector3(0.1, 0.16, -1.45), timber_mat)


func _add_stockpile(structure: Node3D, finish: Node3D) -> void:
	_box(structure, Vector3(1.8, 0.08, 1.8), Vector3(0.0, 0.06, 0.0), canvas_mat)
	var post := Vector3(0.16, 0.42, 0.16)
	for corner in [Vector3(-0.78, 0.24, -0.78), Vector3(0.78, 0.24, -0.78), Vector3(-0.78, 0.24, 0.78), Vector3(0.78, 0.24, 0.78)]:
		_box(structure, post, corner, timber_mat)
	var goods := Node3D.new()
	goods.name = "Goods"
	finish.add_child(goods)


func _fill_crates(goods: Node3D, contents) -> void:
	var sig := str(contents)
	if str(goods.get_meta("sig", "")) == sig and goods.get_child_count() > 0:
		return
	if str(goods.get_meta("sig", "")) == sig and goods.get_child_count() == 0 and sig in ["[]", ""]:
		return
	goods.set_meta("sig", sig)
	for child in goods.get_children():
		child.free()
	var pairs := _good_pairs(contents)
	var n := 0
	for pair in pairs:
		var copies := mini(int(pair["count"]), 3)
		for _i in copies:
			if n >= 8:
				return
			var col := n % 4
			var layer := int(float(n) / 4.0)
			var at := Vector3(-0.58 + float(col) * 0.40, 0.28 + float(layer) * 0.40, 0.0)
			_box(goods, Vector3(0.36, 0.36, 0.36), at, _item_mat(int(pair["id"])))
			n += 1


func _good_pairs(value) -> Array:
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


func _item_mat(item_id: int) -> Material:
	if item_id >= 0 and item_id < item_mats.size():
		return item_mats[item_id]
	return unknown_mat


func _rebuild_ghost(kind: int) -> void:
	if ghost != null:
		var old := ghost
		ghost = null
		old.visible = false
		old.free()
	ghost = Node3D.new()
	ghost.name = "Ghost"
	ghost.set_meta("kind", kind)
	ghost.visible = false
	add_child(ghost)
	_cell_outline(ghost, cell_mat, 1.0, 0.1)
	var preview := Node3D.new()
	preview.name = "Preview"
	ghost.add_child(preview)
	_build_kind(preview, kind)
	var site := preview.get_node_or_null("Site") as Node3D
	if site != null:
		site.visible = false
	var structure := preview.get_node_or_null("Structure") as Node3D
	if structure != null:
		structure.visible = true
		structure.scale = Vector3.ONE
		var finish := structure.get_node_or_null("Finish") as Node3D
		if finish != null:
			finish.visible = true
		var partial := structure.get_node_or_null("Partial") as Node3D
		if partial != null:
			partial.visible = false
	_tint_ghost(preview)


func _tint_ghost(node: Node) -> void:
	if node is MeshInstance3D:
		node.material_override = ghost_mat
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_tint_ghost(child)


func _cell_outline(parent: Node3D, mat: Material, span: float, thick: float) -> void:
	var half := span * 0.5
	_box(parent, Vector3(span, 0.06, thick), Vector3(0.0, 0.08, -half), mat).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_box(parent, Vector3(span, 0.06, thick), Vector3(0.0, 0.08, half), mat).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_box(parent, Vector3(thick, 0.06, span), Vector3(-half, 0.08, 0.0), mat).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_box(parent, Vector3(thick, 0.06, span), Vector3(half, 0.08, 0.0), mat).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _box(parent: Node3D, size: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _mesh(parent, mesh, at, mat)


func _sphere(parent: Node3D, radius: float, at: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	return _mesh(parent, mesh, at, mat)


func _mesh(parent: Node3D, mesh: Mesh, at: Vector3, mat: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = at
	node.material_override = mat
	parent.add_child(node)
	return node


func _apply_node_visual(body: AnimatableBody3D, kind: String) -> void:
	if str(body.get_meta("kind_drawn", "")) == kind:
		return
	body.set_meta("kind_drawn", kind)
	var visual := body.get_node("Visual") as Node3D
	var old: Array = visual.get_children()
	for child in old:
		child.free()
	var col := body.get_node("Collision") as CollisionShape3D
	col.position = Vector3.ZERO
	match kind:
		"wood":
			_add_wood(visual)
			col.shape = shape_wood
		"stone":
			_add_stone(visual)
			col.shape = shape_stone
		"fibre":
			_add_fibre(visual)
			col.shape = shape_fibre
			col.position = Vector3(0.0, 0.45, 0.0)
		"water":
			_add_water(visual)
			col.shape = shape_water
		_:
			_add_box(visual, unknown_mat, Vector3(0.55, 0.45, 0.55), Vector3(0.0, 0.22, 0.0))
			col.shape = shape_unknown


func _add_wood(visual: Node3D) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.2
	mesh.bottom_radius = 0.22
	mesh.height = 1.35
	var log := MeshInstance3D.new()
	log.mesh = mesh
	log.rotation_degrees = Vector3(0.0, 18.0, 90.0)
	log.position = Vector3(0.0, 0.22, 0.0)
	log.material_override = wood_mat
	visual.add_child(log)
	var log2 := MeshInstance3D.new()
	log2.mesh = mesh
	log2.rotation_degrees = Vector3(0.0, -24.0, 90.0)
	log2.position = Vector3(0.12, 0.24, 0.32)
	log2.scale = Vector3(0.78, 0.78, 0.78)
	log2.material_override = wood_mat
	visual.add_child(log2)


func _add_stone(visual: Node3D) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 0.42
	mesh.height = 0.72
	var rock := MeshInstance3D.new()
	rock.mesh = mesh
	rock.position = Vector3(0.0, 0.32, 0.0)
	rock.material_override = stone_mat
	visual.add_child(rock)
	var chip := MeshInstance3D.new()
	var small := SphereMesh.new()
	small.radius = 0.22
	small.height = 0.38
	chip.mesh = small
	chip.position = Vector3(0.38, 0.18, 0.22)
	chip.material_override = stone_mat
	visual.add_child(chip)


func _add_fibre(visual: Node3D) -> void:
	# One clump, 0.9 m across, in the existing green. The thin stalks did not read.
	var mesh := SphereMesh.new()
	mesh.radius = 0.45
	mesh.height = 0.9
	var clump := MeshInstance3D.new()
	clump.mesh = mesh
	clump.position = Vector3(0.0, 0.45, 0.0)
	clump.material_override = fibre_mat
	visual.add_child(clump)


func _add_water(visual: Node3D) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.8
	mesh.bottom_radius = 0.8
	mesh.height = 0.16
	var pool := MeshInstance3D.new()
	pool.mesh = mesh
	pool.position = Vector3(0.0, 0.08, 0.0)
	pool.material_override = water_mat
	visual.add_child(pool)


func _add_box(visual: Node3D, mat: Material, size: Vector3, at: Vector3) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var box := MeshInstance3D.new()
	box.mesh = mesh
	box.position = at
	box.material_override = mat
	visual.add_child(box)


func _ensure_path(key: String) -> MeshInstance3D:
	if path_meshes.has(key):
		return path_meshes[key]
	var mesh_node := MeshInstance3D.new()
	mesh_node.name = "Path_%s" % key.replace(":", "_")
	mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	path_root.add_child(mesh_node)
	path_meshes[key] = mesh_node
	return mesh_node


func _ensure_dest(key: String) -> Node3D:
	if dest_markers.has(key):
		return dest_markers[key]
	var marker := Node3D.new()
	marker.name = "Dest_%s" % key.replace(":", "_")
	var post := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.18
	cyl.bottom_radius = 0.22
	cyl.height = 1.15
	post.mesh = cyl
	post.position = Vector3(0.0, 0.58, 0.0)
	post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var marker_mat := _flat(_path_color(0), true)
	post.material_override = marker_mat
	marker.add_child(post)
	var cap := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.32
	sphere.height = 0.64
	cap.mesh = sphere
	cap.position = Vector3(0.0, 1.28, 0.0)
	cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cap.material_override = marker_mat
	marker.add_child(cap)
	path_root.add_child(marker)
	dest_markers[key] = marker
	return marker


func _path_material(ordinal: int) -> StandardMaterial3D:
	var slot := ordinal % 3
	while path_materials.size() <= slot:
		path_materials.append(_flat(_path_color(path_materials.size()), true))
	return path_materials[slot]


func _path_color(ordinal: int) -> Color:
	match ordinal % 3:
		0:
			return Color(0.96, 0.84, 0.22)
		1:
			return Color(0.98, 0.62, 0.18)
		_:
			return Color(0.90, 0.92, 0.55)


func _ribbon(points: PackedVector3Array, width: float) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var half := width * 0.5
	for i in points.size():
		var fwd := Vector3(0.0, 0.0, -1.0)
		if i + 1 < points.size():
			fwd = points[i + 1] - points[i]
		elif i > 0:
			fwd = points[i] - points[i - 1]
		fwd.y = 0.0
		if fwd.length_squared() < 0.000001:
			fwd = Vector3(0.0, 0.0, -1.0)
		else:
			fwd = fwd.normalized()
		var side := fwd.cross(Vector3.UP)
		if side.length_squared() < 0.000001:
			side = Vector3(half, 0.0, 0.0)
		else:
			side = side.normalized() * half
		tool.add_vertex(points[i] + side)
		tool.add_vertex(points[i] - side)
	return tool.commit()


func _path_points(row: Dictionary) -> PackedVector3Array:
	var out := PackedVector3Array()
	for point in _pairs(row.get("path", [])):
		out.append(Vector3(point.x, 0.055, point.y))
	return out


func _pairs(value) -> PackedVector2Array:
	var out := PackedVector2Array()
	if value is PackedVector2Array:
		return value
	if value is PackedFloat32Array or value is PackedFloat64Array or value is Array:
		var n: int = value.size()
		if n > 0 and value[0] is Vector2:
			for point in value:
				if point is Vector2:
					out.append(point)
			return out
		var i := 0
		while i + 1 < n:
			out.append(Vector2(_float_of(value[i], 0.0), _float_of(value[i + 1], 0.0)))
			i += 2
	return out


func _dest_point(value) -> Variant:
	if value is Vector2:
		return Vector3(value.x, 0.06, value.y)
	if value is Vector3:
		return Vector3(value.x, 0.06, value.z)
	if (value is Array or value is PackedFloat32Array or value is PackedFloat64Array) and value.size() >= 2:
		return Vector3(_float_of(value[0], 0.0), 0.06, _float_of(value[1], 0.0))
	return null


func _has_target(value) -> bool:
	return (value is Array or value is PackedInt32Array) and value.size() >= 2


func _raycast(camera: Camera3D, mouse: Vector2, mask: int) -> Dictionary:
	if camera == null:
		return {}
	var world := camera.get_world_3d()
	if world == null:
		return {}
	var space := world.direct_space_state
	if space == null:
		return {}
	var origin := camera.project_ray_origin(mouse)
	var normal := camera.project_ray_normal(mouse)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + normal * 800.0, mask)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	return space.intersect_ray(query)


func _entity_from_hit(hit: Dictionary, kind: String) -> Dictionary:
	if not hit.has("collider"):
		return {}
	var node: Node = hit["collider"]
	while node != null:
		if node.has_meta("entity_kind") and str(node.get_meta("entity_kind")) == kind:
			return {
				"index": _int_of(node.get_meta("index"), -1),
				"generation": _int_of(node.get_meta("generation"), -1),
			}
		node = node.get_parent()
	return {}


func _drop_missing(group: Dictionary, seen: Dictionary) -> void:
	var stale: Array = []
	for key in group.keys():
		if not seen.has(key):
			stale.append(key)
	for key in stale:
		_drop_one(group, str(key))


func _drop_id(index: int, generation: int) -> void:
	var key := _id_key(index, generation)
	_drop_one(people, key)
	_drop_one(nodes, key)
	_drop_one(buildings, key)
	_hide_order(key)


func _drop_one(group: Dictionary, key: String) -> void:
	if not group.has(key):
		return
	var node: Node = group[key]
	group.erase(key)
	node.queue_free()
	eating.erase(key)
	_hide_order(key)


func _apply_node_fill(body: AnimatableBody3D, kind: String, row: Dictionary) -> void:
	var scale := 1.0
	if row.has("remaining") and NODE_START.has(kind):
		var start := int(NODE_START[kind])
		var remaining := _int_of(row.get("remaining", 0), 0)
		if start > 0:
			scale = clampf(float(remaining) / float(start), NODE_FILL_MIN, 1.0)
	var visual := body.get_node_or_null("Visual") as Node3D
	if visual != null:
		visual.scale = Vector3.ONE * scale
	var col := body.get_node_or_null("Collision") as CollisionShape3D
	if col != null:
		col.scale = Vector3.ONE * scale


func _selection_keys(selection: Array) -> Dictionary:
	var keys := {}
	for sel in selection:
		if sel is Dictionary:
			keys[_id_key(_int_of(sel.get("index", -1), -1), _int_of(sel.get("generation", -1), -1))] = true
	return keys


func _make_materials() -> void:
	sash_mat = _flat(Color(0.86, 0.55, 0.16))
	scrap_mat = _flat(Color(0.14, 0.30, 0.58))
	# Harth scrap blue. A near-black yoke on a near-black body does not read.
	yoke_mat = scrap_mat
	tool_mat = _flat(Color(0.74, 0.58, 0.30))
	select_mat = _flat(Color(0.25, 0.58, 1.0), true)
	fail_mat = _flat(Color(0.95, 0.16, 0.10), true)
	wood_mat = _flat(Color(0.52, 0.32, 0.13))
	stone_mat = _flat(Color(0.60, 0.59, 0.56))
	fibre_mat = _flat(Color(0.28, 0.56, 0.20))
	water_mat = _flat(Color(0.20, 0.48, 0.80))
	unknown_mat = _flat(Color(0.48, 0.42, 0.36))
	timber_mat = _flat(Color(0.36, 0.20, 0.10))
	ceramic_mat = _flat(Color(0.74, 0.40, 0.20))
	soot_mat = _flat(Color(0.16, 0.13, 0.11))
	site_mat = _flat(Color(0.93, 0.62, 0.16), true)
	flame_mat = _flat(Color(1.0, 0.52, 0.08), true)
	canvas_mat = _flat(Color(0.78, 0.64, 0.38))
	ghost_mat = _flat(Color(0.98, 0.82, 0.32, 0.48), true)
	ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cell_mat = _flat(Color(0.98, 0.86, 0.18), true)
	focus_mat = _flat(Color(0.25, 0.58, 1.0), true)
	# Injury is a cloth mark, not a splatter. Unshaded so the colour survives the key light.
	wound_mat = _flat(Color(0.58, 0.16, 0.12), true)
	infect_mat = _flat(Color(0.62, 0.70, 0.16), true)
	sick_mat = _flat(Color(0.22, 0.30, 0.06), true)
	wrap_mat = _flat(Color(0.94, 0.92, 0.86), true)
	treated_mat = _flat(Color(0.95, 0.78, 0.20), true)
	hurt_mark_mat = _flat(Color(0.62, 0.14, 0.06), true)
	cold_mat = _flat(Color(0.70, 0.84, 0.96), true)
	cold_mark_mat = _flat(Color(0.12, 0.34, 0.78), true)
	sleep_roll_mat = _flat(Color(0.96, 0.93, 0.84), true)
	blanket_mat = _flat(Color(0.18, 0.32, 0.55))
	foot_mat = _flat(BODY_TIMBER)
	item_mats = [
		_flat(Color(0.84, 0.70, 0.28)),
		_flat(Color(0.52, 0.32, 0.13)),
		_flat(Color(0.62, 0.60, 0.56)),
		_flat(Color(0.30, 0.58, 0.22)),
		_flat(Color(0.22, 0.48, 0.78)),
		_flat(Color(0.74, 0.76, 0.80)),
		_flat(Color(0.80, 0.42, 0.16)),
		_flat(Color(0.92, 0.90, 0.84)),
		_flat(Color(0.46, 0.62, 0.28)),
	]


func _make_shapes() -> void:
	shape_wood = BoxShape3D.new()
	shape_wood.size = Vector3(1.5, 0.6, 0.8)
	shape_stone = SphereShape3D.new()
	shape_stone.radius = 0.6
	shape_fibre = SphereShape3D.new()
	shape_fibre.radius = 0.45
	shape_water = CylinderShape3D.new()
	shape_water.radius = 0.85
	shape_water.height = 0.5
	shape_unknown = BoxShape3D.new()
	shape_unknown.size = Vector3(0.7, 0.5, 0.7)


func _flat(color: Color, unshaded: bool = false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


func _id_key(index: int, generation: int) -> String:
	return "%d:%d" % [index, generation]


func _int_of(value, fallback: int) -> int:
	if value is int or value is float:
		return int(value)
	return fallback


func _float_of(value, fallback: float) -> float:
	if value is int or value is float:
		return float(value)
	return fallback


func _warn_once(key: String, message: String) -> void:
	if _warned.has(key):
		return
	_warned[key] = true
	push_warning(message)
