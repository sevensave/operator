class_name DronePreview
extends SubViewportContainer
## Превью выбранной модели дрона в меню: вращается на подставке в отдельном мире.

var _vp: SubViewport
var _pivot: Node3D
var _view: DroneView
var _cam: Camera3D
var _t := 0.0


func _init(p_size := Vector2i(300, 170)) -> void:
	stretch = true
	custom_minimum_size = p_size
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.size = p_size
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.transparent_bg = false
	add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.17, 0.19, 0.20)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.62)
	env.ambient_light_energy = 1.3
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -30, 0)
	sun.light_energy = 2.4
	_vp.add_child(sun)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-15, 150, 0)
	rim.light_energy = 0.6
	rim.light_color = Color(0.7, 0.8, 1.0)
	_vp.add_child(rim)
	_pivot = Node3D.new()
	_vp.add_child(_pivot)
	_cam = Camera3D.new()
	_cam.fov = 40.0
	_vp.add_child(_cam)


func set_drone(kind: int, model: int, color: Color) -> void:
	if _view != null:
		_view.queue_free()
	_view = DroneView.new()
	_view.setup(kind, color, false, model)
	_pivot.add_child(_view)
	var d := 1.25 if kind == SimConst.Kind.COPTER else 4.6
	_cam.position = Vector3(0, d * 0.42, d)
	_cam.look_at(Vector3(0, 0.0, 0), Vector3.UP)


func _process(delta: float) -> void:
	_t += delta
	_pivot.rotation.y = _t * 0.6
	if _view != null:
		_view.update_visual(0.45 + 0.1 * sin(_t * 2.0), delta)
