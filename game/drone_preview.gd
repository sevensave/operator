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
	env.background_color = Color(0.13, 0.155, 0.175)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.68, 0.76)
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_AGX   # тот же тон, что в матче: мягкие блики, без пересвета
	env.tonemap_agx_contrast = 1.25
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.92
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	# Трёхточечный свет: тёплый рисующий, холодный заполняющий, контровой сзади.
	for l: Array in [[Vector3(-42, -35, 0), 2.6, Color(1.0, 0.96, 0.9)], [Vector3(-12, 70, 0), 0.9, Color(0.75, 0.85, 1.0)],
			[Vector3(-25, 165, 0), 1.6, Color(0.85, 0.92, 1.0)], [Vector3(60, 20, 0), 0.35, Color(0.9, 0.9, 1.0)]]:
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = l[0]
		sun.light_energy = l[1]
		sun.light_color = l[2]
		_vp.add_child(sun)
	_pivot = Node3D.new()
	_vp.add_child(_pivot)
	_cam = Camera3D.new()
	_cam.fov = 32.0
	_vp.add_child(_cam)


func set_drone(kind: int, model: int, color: Color) -> void:
	if _view != null:
		_view.queue_free()
	_view = DroneView.new()
	_view.setup(kind, color, false, model)
	_pivot.add_child(_view)
	# Камера отъезжает так, чтобы модель с винтами помещалась в кадр при любом повороте.
	var info := DroneModels.build(kind, model)
	var reach := 0.0
	for p in info.props:
		reach = maxf(reach, Vector2(p.pos.x, p.pos.z).length() + (p.radius if int(p.axis) == 0 else 0.0))
	var aabb: AABB = info.mesh.get_aabb()
	reach = maxf(reach, maxf(aabb.size.x, aabb.size.z) * 0.5) * float(info.scale)
	if kind == SimConst.Kind.COPTER:
		reach *= 1.12   # защита винтов и лучи по диагонали шире габарита по осям
	var aspect := float(_vp.size.x) / maxf(_vp.size.y, 1.0)
	var d := reach * 1.04 / tan(deg_to_rad(_cam.fov * 0.5)) / minf(aspect, 2.1)
	_cam.look_at_from_position(Vector3(0, d * 0.36, d * 0.93), Vector3(0, -reach * 0.06, 0), Vector3.UP)


func _process(delta: float) -> void:
	_t += delta
	_pivot.rotation.y = _t * 0.6
	if _view != null:
		_view.update_visual(0.45 + 0.1 * sin(_t * 2.0), delta)
