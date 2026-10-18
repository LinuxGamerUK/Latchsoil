extends Node3D

# View state only. Nothing here is written to a save or sent to the sim.
# Edge scroll is intentionally absent: WASD is the way the view moves.

const PITCH_DEG := -35.264
const EYE_DISTANCE := 56.0
const CLOSE_SIZE := 7.0
const HOLDING_SIZE := 42.0
const ZOOM_FACTOR := 0.84
const YAW_START := 45.0

var yaw_deg := YAW_START
var ortho_size := HOLDING_SIZE
var camera: Camera3D


func _ready() -> void:
	var world := get_node_or_null("../World")
	if world != null and world.has_method("peg_position"):
		position = world.peg_position()
	else:
		position = Vector3(16.0, 0.0, 16.0)
	camera = get_node("Camera3D") as Camera3D
	_apply_camera()


func _process(delta: float) -> void:
	var axes := _ground_axes()
	var move := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		move += axes[0]
	if Input.is_key_pressed(KEY_S):
		move -= axes[0]
	if Input.is_key_pressed(KEY_D):
		move += axes[1]
	if Input.is_key_pressed(KEY_A):
		move -= axes[1]
	if move.length_squared() > 0.0:
		position += move.normalized() * ortho_size * 0.7 * delta
	_apply_camera()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			ortho_size = maxf(CLOSE_SIZE, ortho_size * ZOOM_FACTOR)
			_apply_camera()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			ortho_size = minf(HOLDING_SIZE, ortho_size / ZOOM_FACTOR)
			_apply_camera()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_Q:
			yaw_deg = wrapf(yaw_deg - 90.0, 0.0, 360.0)
			_apply_camera()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_E:
			yaw_deg = wrapf(yaw_deg + 90.0, 0.0, 360.0)
			_apply_camera()
			get_viewport().set_input_as_handled()


func _apply_camera() -> void:
	if camera == null:
		return
	rotation_degrees = Vector3(0.0, yaw_deg, 0.0)
	var pitch := deg_to_rad(PITCH_DEG)
	# Camera sits back along local +Z and looks toward the rig origin.
	camera.position = Vector3(0.0, sin(-pitch) * EYE_DISTANCE, cos(pitch) * EYE_DISTANCE)
	camera.rotation_degrees = Vector3(PITCH_DEG, 0.0, 0.0)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = ortho_size
	camera.near = 0.1
	camera.far = 500.0
	camera.current = true


func _ground_axes() -> Array:
	var forward := -global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3(0.0, 0.0, -1.0)
	else:
		forward = forward.normalized()
	var right := global_transform.basis.x
	right.y = 0.0
	if right.length_squared() < 0.0001:
		right = Vector3(1.0, 0.0, 0.0)
	else:
		right = right.normalized()
	return [forward, right]
