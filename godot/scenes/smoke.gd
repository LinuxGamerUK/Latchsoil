extends Node

# Milestone 0 smoke harness. This scene is a probe, not a rule: the sim decides
# everything it asserts. If the extension is missing, it fails loudly with a
# non-zero exit so CI cannot mistake a broken build for a green one.

const HOST_CLASS := "SimHost"
const SEED := 42


func _ready() -> void:
	if not ClassDB.class_exists(HOST_CLASS):
		push_error("latchsoil: the extension did not load (%s is not registered)" % HOST_CLASS)
		get_tree().quit(1)
		return

	var host: Object = ClassDB.instantiate(HOST_CLASS)
	# Attach it, so the sim node's own _ready runs and the bridge reports itself.
	add_child(host as Node)
	if not host.has_method("engine_api"):
		push_error("latchsoil: engine_api cannot be called")
		remove_child(host as Node)
		host.free()
		get_tree().quit(1)
		return
	var api: String = str(host.call("engine_api"))
	var running: Dictionary = Engine.get_version_info()
	var expect := "%d.%d" % [int(running["major"]), int(running["minor"])]
	if not api.begins_with(expect):
		push_error("latchsoil: engine API %s does not match the running engine" % api)
		remove_child(host as Node)
		host.free()
		get_tree().quit(1)
		return

	host.call("start", SEED)
	host.call("step")
	var tick: int = host.call("tick")
	var hash: String = host.call("state_hash")

	print("latchsoil: tick %d hash %s" % [tick, hash])

	# A save must survive the boundary in both directions.
	var save: String = host.call("save_json")
	if not save.contains("\"save_version\""):
		push_error("latchsoil: the sim returned a save with no version field")
		host.free()
		get_tree().quit(4)
		return
	print("latchsoil: save bytes %d" % save.length())

	remove_child(host as Node)
	host.free()
	get_tree().quit(0)
