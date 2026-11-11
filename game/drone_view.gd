class_name DroneView
extends Node3D
## Модель дрона в мире: процедурная сетка варианта (DroneModels), винты с диском размытия,
## огни цвета стороны и строб, инверсионный след, дым и искры при отказе.
## Материалы общие для всех дронов; различия — через instance-uniform шейдеров.

const PROP_DISC_SHADER := """
shader_type spatial;
render_mode cull_disabled, depth_draw_never, shadows_disabled;
uniform vec3 tint : source_color = vec3(0.1, 0.1, 0.11);
instance uniform float spin = 0.0;
varying vec3 lp;
void vertex() { lp = VERTEX; }
void fragment() {
	float r = UV.x;
	float ang = atan(lp.z, lp.x);
	float streak = 0.75 + 0.25 * sin(ang * 2.0 - TIME * 50.0);
	float a = spin * (0.12 + 0.32 * smoothstep(0.25, 1.0, r)) * streak;
	a += spin * smoothstep(0.92, 0.98, r) * smoothstep(1.0, 0.98, r) * 0.35;
	ALBEDO = tint;
	ROUGHNESS = 0.5;
	ALPHA = clamp(a, 0.0, 1.0);
}
"""

const PROP_BLADE_SHADER := """
shader_type spatial;
render_mode cull_disabled, depth_draw_always;
uniform vec3 tint : source_color = vec3(0.08, 0.08, 0.09);
instance uniform float spin = 0.0;
void fragment() {
	ALBEDO = tint;
	ROUGHNESS = 0.4;
	ALPHA = clamp(1.0 - spin * 0.92, 0.0, 1.0);
}
"""

const STROBE_SHADER := """
shader_type spatial;
render_mode unshaded, shadows_disabled;
instance uniform float phase = 0.0;
void fragment() {
	float t = fract(TIME * 0.8 + phase);
	float on = step(t, 0.06) + step(0.16, t) * step(t, 0.22);
	ALBEDO = vec3(1.0) * (0.25 + on * 9.0);
}
"""

static var _disc_mat: ShaderMaterial
static var _blade_mat: ShaderMaterial
static var _strobe_mat: ShaderMaterial
static var _nav_mats := {}
static var _trail_mat: StandardMaterial3D
static var _smoke_proc: ParticleProcessMaterial
static var _smoke_draw: QuadMesh
static var _spark_proc: ParticleProcessMaterial
static var _spark_draw: QuadMesh
static var _disc_meshes := {}
static var _blade_meshes := {}

var kind := 0
var model := 0
var color := Color.WHITE
var props: Array[Node3D] = []
var _discs: Array[GeometryInstance3D] = []
var _blades: Array[GeometryInstance3D] = []
var _prop_dirs: Array[float] = []
var prop_speed := 0.0
var motor: AudioStreamPlayer3D
var _light: OmniLight3D
var _trail: MeshInstance3D
var _trail_mesh: ImmediateMesh
var _trail_pts: Array[Vector3] = []
var _trail_t := 0.0
var _smoke: GPUParticles3D
var _sparks: GPUParticles3D


func setup(p_kind: int, p_color: Color, with_sound: bool, p_model := 0) -> void:
	kind = p_kind
	color = p_color
	model = clampi(p_model, 0, SimConst.MODEL_COUNT - 1)
	var info := DroneModels.build(kind, model)
	var body := MeshInstance3D.new()
	body.mesh = info.mesh
	var names: Array = info.mesh.get_meta("mats")
	for i in names.size():
		body.set_surface_override_material(i, DroneModels.material(names[i], color))
	body.name = "Body"
	add_child(body)
	scale = Vector3.ONE * float(info.scale)

	for p in info.props:
		_add_prop(p)

	# Навигационные огни цвета стороны (общий материал на цвет) и белый строб.
	for pos in info.nav:
		add_child(_dot(pos, 0.022, _nav_mat(color)))
	var strobe := _dot(info.strobe, 0.02, _strobe())
	strobe.set_instance_shader_parameter("phase", randf())
	add_child(strobe)
	_light = OmniLight3D.new()
	_light.light_color = color
	_light.light_energy = 1.5
	_light.omni_range = 6.0
	_light.shadow_enabled = false
	add_child(_light)

	if with_sound:
		motor = AudioStreamPlayer3D.new()
		motor.stream = SoundBank.motor_loop(kind)
		motor.unit_size = 14.0
		motor.max_distance = 400.0
		motor.volume_db = -4.0
		motor.bus = &"Master"
		motor.autoplay = true
		add_child(motor)


func _add_prop(p: Dictionary) -> void:
	var r: float = p.radius
	var pivot := Node3D.new()
	pivot.position = p.pos
	if int(p.axis) == 2:
		pivot.rotation = Vector3(PI * 0.5, 0, 0)   # ось винта вдоль −Z
	add_child(pivot)
	var spinner := Node3D.new()
	pivot.add_child(spinner)
	var blades := MeshInstance3D.new()
	blades.mesh = _blade_mesh(r)
	blades.material_override = _blade()
	blades.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	spinner.add_child(blades)
	var disc := MeshInstance3D.new()
	disc.mesh = _disc_mesh(r)
	disc.material_override = _disc()
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(disc)
	props.append(spinner)
	_discs.append(disc)
	_blades.append(blades)
	_prop_dirs.append(float(p.dir))


## Совместимость: старый вызов только с тягой.
func update_visual(thrust: float, delta: float) -> void:
	_spin(thrust, delta)
	if motor:
		motor.pitch_scale = clampf(0.7 + thrust * 0.6, 0.5, 2.0)


## Полное обновление по состоянию дрона: винты, след, дым и искры.
func update_state(d: DroneState, delta: float) -> void:
	var powered := d.control and d.battery > 0.0
	update_visual(d.thrust_frac if powered else 0.0, delta)
	var trail_on := visible and powered and (kind == SimConst.Kind.PLANE or d.thrust_frac > 1.02) and d.vel.length() > 12.0
	_update_trail(trail_on, delta)
	var failing := not d.control or d.battery < 0.12
	if failing and _smoke == null:
		_make_failure_fx()
	if _smoke != null:
		_smoke.emitting = failing and visible
		_sparks.emitting = failing and visible and not d.control


func _spin(thrust: float, delta: float) -> void:
	prop_speed = lerpf(prop_speed, 30.0 + thrust * 60.0 if thrust > 0.0 else 0.0, minf(1.0, delta * 5.0))
	var spin := clampf((prop_speed - 8.0) / 50.0, 0.0, 1.0)
	# Лопасти крутим медленнее настоящих оборотов, чтобы не было стробоскопа;
	# на больших оборотах их почти не видно — виден диск.
	var vis_speed := minf(prop_speed, 9.0)
	for i in props.size():
		props[i].rotate_y(vis_speed * delta * _prop_dirs[i])
		_discs[i].set_instance_shader_parameter("spin", spin)
		_blades[i].set_instance_shader_parameter("spin", spin)


func _update_trail(on: bool, delta: float) -> void:
	if not on and _trail_pts.is_empty():
		return
	if _trail == null:
		_trail_mesh = ImmediateMesh.new()
		_trail = MeshInstance3D.new()
		_trail.mesh = _trail_mesh
		_trail.top_level = true
		_trail.material_override = _trail_material()
		_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_trail)
		_trail.global_transform = Transform3D.IDENTITY
	_trail_t += delta
	var tail := global_position + global_transform.basis.z * (0.9 if kind == SimConst.Kind.PLANE else 0.2)
	if on and (_trail_pts.is_empty() or _trail_t > 0.05):
		_trail_t = 0.0
		_trail_pts.push_front(tail)
		if _trail_pts.size() > 28:
			_trail_pts.pop_back()
	elif not on and _trail_t > 0.05:
		_trail_t = 0.0
		_trail_pts.pop_back()
	_trail_mesh.clear_surfaces()
	if _trail_pts.size() < 2:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var eye := cam.global_position
	var pts := _trail_pts.duplicate()
	if on:
		pts[0] = tail
	_trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var n := pts.size()
	var width := 0.07 if kind == SimConst.Kind.PLANE else 0.05
	for i in n:
		var p: Vector3 = pts[i]
		var dir: Vector3 = (pts[maxi(i - 1, 0)] - pts[mini(i + 1, n - 1)])
		var side := dir.cross(eye - p)
		if side.length_squared() < 0.000001:
			side = Vector3.UP
		side = side.normalized() * width * (0.5 + 2.0 * float(i) / n)
		var f := float(i) / (n - 1)
		var a := 0.3 * (1.0 - f) * clampf(p.distance_to(eye) / 6.0 - 0.3, 0.0, 1.0)
		_trail_mesh.surface_set_color(Color(1, 1, 1, a))
		_trail_mesh.surface_add_vertex(p - side)
		_trail_mesh.surface_set_color(Color(1, 1, 1, a))
		_trail_mesh.surface_add_vertex(p + side)
	_trail_mesh.surface_end()


func _make_failure_fx() -> void:
	if _smoke_proc == null:
		var m := ParticleProcessMaterial.new()
		m.direction = Vector3(0, 1, 0)
		m.spread = 25.0
		m.initial_velocity_min = 0.5
		m.initial_velocity_max = 1.5
		m.gravity = Vector3(0, 1.5, 0)
		m.scale_min = 0.6
		m.scale_max = 1.2
		var c := Curve.new()
		c.add_point(Vector2(0, 0.4))
		c.add_point(Vector2(1, 2.2))
		var ct := CurveTexture.new()
		ct.curve = c
		m.scale_curve = ct
		var g := Gradient.new()
		g.set_color(0, Color(0.15, 0.14, 0.13, 0.75))
		g.set_color(1, Color(0.4, 0.4, 0.4, 0.0))
		var gt := GradientTexture1D.new()
		gt.gradient = g
		m.color_ramp = gt
		_smoke_proc = m
		_smoke_draw = QuadMesh.new()
		_smoke_draw.size = Vector2(1.2, 1.2)
		_smoke_draw.material = Fx.smoke_material()
		var s := ParticleProcessMaterial.new()
		s.direction = Vector3(0, 1, 0)
		s.spread = 180.0
		s.initial_velocity_min = 2.0
		s.initial_velocity_max = 6.0
		s.gravity = Vector3(0, -9.8, 0)
		s.particle_flag_align_y = true
		_spark_proc = s
		_spark_draw = QuadMesh.new()
		_spark_draw.size = Vector2(0.025, 0.25)
		_spark_draw.material = Fx.spark_material()
	_smoke = GPUParticles3D.new()
	_smoke.amount = 24
	_smoke.lifetime = 2.2
	_smoke.local_coords = false
	_smoke.process_material = _smoke_proc
	_smoke.draw_pass_1 = _smoke_draw
	_smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_smoke)
	_sparks = GPUParticles3D.new()
	_sparks.amount = 16
	_sparks.lifetime = 0.5
	_sparks.local_coords = false
	_sparks.process_material = _spark_proc
	_sparks.draw_pass_1 = _spark_draw
	_sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_sparks)


# ---------- Общие сетки и материалы ----------

static func _dot(pos: Vector3, r: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 8
	sm.rings = 4
	mi.mesh = sm
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func _nav_mat(c: Color) -> StandardMaterial3D:
	var key := c.to_html()
	if not _nav_mats.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = c
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 6.0
		_nav_mats[key] = m
	return _nav_mats[key]


static func _shader_mat(code: String) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = code
	var m := ShaderMaterial.new()
	m.shader = sh
	return m


static func _disc() -> ShaderMaterial:
	if _disc_mat == null:
		_disc_mat = _shader_mat(PROP_DISC_SHADER)
	return _disc_mat


static func _blade() -> ShaderMaterial:
	if _blade_mat == null:
		_blade_mat = _shader_mat(PROP_BLADE_SHADER)
	return _blade_mat


static func _strobe() -> ShaderMaterial:
	if _strobe_mat == null:
		_strobe_mat = _shader_mat(STROBE_SHADER)
	return _strobe_mat


static func _trail_material() -> StandardMaterial3D:
	if _trail_mat == null:
		_trail_mat = StandardMaterial3D.new()
		_trail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_trail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_trail_mat.vertex_color_use_as_albedo = true
		_trail_mat.albedo_color = Color(0.92, 0.94, 0.97)
		_trail_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _trail_mat


## Плоский диск в XZ, UV.x — относительный радиус.
static func _disc_mesh(r: float) -> ArrayMesh:
	var key := int(r * 1000.0)
	if _disc_meshes.has(key):
		return _disc_meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 24
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(0, 0))
		st.add_vertex(Vector3.ZERO)
		st.set_uv(Vector2(1, 0))
		st.add_vertex(Vector3(cos(a1), 0, sin(a1)) * r)
		st.set_uv(Vector2(1, 0))
		st.add_vertex(Vector3(cos(a0), 0, sin(a0)) * r)
	var m := st.commit()
	_disc_meshes[key] = m
	return m


## Две лопасти с круткой: узкие у ступицы, шире к середине, скруглённые к концу.
static func _blade_mesh(r: float) -> ArrayMesh:
	var key := int(r * 1000.0)
	if _blade_meshes.has(key):
		return _blade_meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := 6
	for side: float in [-1.0, 1.0]:
		for i in steps:
			var t0 := float(i) / steps
			var t1 := float(i + 1) / steps
			var w0 := r * (0.06 + 0.12 * sin(PI * minf(t0 * 1.1, 1.0)))
			var w1 := r * (0.06 + 0.12 * sin(PI * minf(t1 * 1.1, 1.0)))
			var tw0 := 0.35 * (1.0 - t0)
			var tw1 := 0.35 * (1.0 - t1)
			var x0 := side * (0.04 * r + t0 * r * 0.96)
			var x1 := side * (0.04 * r + t1 * r * 0.96)
			var a := Vector3(x0, -w0 * sin(tw0), -w0 * cos(tw0))
			var b := Vector3(x0, w0 * sin(tw0), w0 * cos(tw0))
			var c := Vector3(x1, w1 * sin(tw1), w1 * cos(tw1))
			var d := Vector3(x1, -w1 * sin(tw1), -w1 * cos(tw1))
			for v in [a, b, c, a, c, d]:
				st.set_normal(Vector3.UP)
				st.add_vertex(v)
	var m := st.commit()
	_blade_meshes[key] = m
	return m
