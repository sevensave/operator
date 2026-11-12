class_name Fx
## Взрывы, дым, купол сети, купола глушилок.

const DOME_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, fog_disabled;
uniform vec4 tint : source_color = vec4(0.3, 0.8, 1.0, 1.0);
uniform float strength = 0.4;
uniform float grid = 24.0;
varying vec3 lp;
void vertex() { lp = VERTEX; }
void fragment() {
	vec3 n = normalize(lp);
	float lat = asin(n.y) / 3.14159 * grid;
	float lon = atan(n.z, n.x) / 3.14159 * grid;
	float g = max(smoothstep(0.9, 1.0, abs(fract(lat) * 2.0 - 1.0)), smoothstep(0.9, 1.0, abs(fract(lon) * 2.0 - 1.0)));
	float fres = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.5);
	float a = (g * 0.7 + fres * 0.6) * strength;
	ALBEDO = tint.rgb * a;
}
"""

static var _dome_shader: Shader
static var _smoke_mat: ParticleProcessMaterial
static var _spark_mat: ParticleProcessMaterial


static func dome_material(tint: Color, strength: float, grid: float) -> ShaderMaterial:
	if _dome_shader == null:
		_dome_shader = Shader.new()
		_dome_shader.code = DOME_SHADER
	var m := ShaderMaterial.new()
	m.shader = _dome_shader
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("strength", strength)
	m.set_shader_parameter("grid", grid)
	return m


static func dome(radius: float, tint: Color, strength: float, grid: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 48
	sm.rings = 24
	mi.mesh = sm
	mi.material_override = dome_material(tint, strength, grid)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


const FIREBALL_SHADER := """
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, shadows_disabled, fog_disabled;
instance uniform float age = 0.0;      // 0..1 за время жизни шара
instance uniform float seed = 0.0;
varying vec3 lp;
float h(vec3 p) { return fract(sin(dot(p, vec3(12.9898, 78.233, 45.164))) * 43758.5453); }
float vn(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h(i), h(i + vec3(1,0,0)), f.x), mix(h(i + vec3(0,1,0)), h(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(h(i + vec3(0,0,1)), h(i + vec3(1,0,1)), f.x), mix(h(i + vec3(0,1,1)), h(i + vec3(1,1,1)), f.x), f.y), f.z);
}
void vertex() {
	lp = VERTEX;
	float n = vn(VERTEX * 2.6 + vec3(seed * 13.0, -age * 3.0, 0.0));
	VERTEX *= 0.8 + n * 0.45;
}
void fragment() {
	float n = vn(lp * 4.0 + vec3(seed * 7.0, -age * 6.0, 0.0)) * 0.6 + vn(lp * 9.0 - vec3(0.0, age * 9.0, seed)) * 0.4;
	float rim = pow(1.0 - abs(dot(NORMAL, VIEW)), 1.5);
	float heat = clamp(1.2 - age * 1.6 - rim * 0.5 + (n - 0.5) * 0.8, 0.0, 1.0);
	vec3 c = mix(vec3(0.12, 0.08, 0.06), vec3(1.0, 0.45, 0.08), smoothstep(0.1, 0.5, heat));
	c = mix(c, vec3(1.0, 0.92, 0.6), smoothstep(0.6, 1.0, heat));
	ALBEDO = c * (0.7 + heat * 3.2);
	ALPHA = clamp((1.0 - smoothstep(0.55, 1.0, age)) * (0.6 + n * 0.6) - rim * 0.25, 0.0, 1.0);
}
"""

const SHOCK_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled, fog_disabled;
instance uniform float age = 0.0;
void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float ring = smoothstep(0.75, 0.93, r) * (1.0 - smoothstep(0.93, 1.0, r));
	ALBEDO = vec3(1.0, 0.8, 0.55) * ring * (1.0 - age) * 1.2;
	ALPHA = 1.0;
}
"""

static var _fire_mat: ShaderMaterial
static var _shock_mat: ShaderMaterial
static var _smoke_draw_mat: StandardMaterial3D
static var _spark_draw_mat: StandardMaterial3D
static var _debris_mat: StandardMaterial3D
static var _debris_proc: ParticleProcessMaterial
static var _column_proc: ParticleProcessMaterial
static var _scorch_tex: Texture2D
static var _sphere: SphereMesh


static func _shader_mat(code: String) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = code
	var m := ShaderMaterial.new()
	m.shader = sh
	return m


## Общий материал клубов дыма (вершинный цвет задаёт рампа частиц).
static func smoke_material() -> StandardMaterial3D:
	if _smoke_draw_mat == null:
		var qm := StandardMaterial3D.new()
		qm.albedo_color = Color(1, 1, 1, 0.6)
		qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		qm.vertex_color_use_as_albedo = true
		qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		qm.albedo_texture = _puff_texture()
		_smoke_draw_mat = qm
	return _smoke_draw_mat


## Общий материал искр: вытянуты вдоль скорости (align_y в процессе частиц).
static func spark_material() -> StandardMaterial3D:
	if _spark_draw_mat == null:
		var spm := StandardMaterial3D.new()
		spm.albedo_color = Color(1.0, 0.75, 0.35)
		spm.emission_enabled = true
		spm.emission = Color(1.0, 0.6, 0.2)
		spm.emission_energy_multiplier = 6.0
		spm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		spm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
		spm.billboard_keep_scale = true
		_spark_draw_mat = spm
	return _spark_draw_mat


static func explosion(parent: Node, pos: Vector3, big: bool, quality: int) -> void:
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = pos
	var k := 1.8 if big else 1.0
	if _fire_mat == null:
		_fire_mat = _shader_mat(FIREBALL_SHADER)
		_shock_mat = _shader_mat(SHOCK_SHADER)
		_sphere = SphereMesh.new()
		_sphere.radius = 1.0
		_sphere.height = 2.0
		_sphere.radial_segments = 24
		_sphere.rings = 12

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.62, 0.28)
	light.light_energy = 14.0
	light.omni_range = 40.0 * k
	light.shadow_enabled = false
	root.add_child(light)

	# Огненный шар: сфера с шумовой деформацией, цвет и прозрачность — от «возраста».
	var ball := MeshInstance3D.new()
	ball.mesh = _sphere
	ball.material_override = _fire_mat
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ball.set_instance_shader_parameter("seed", randf())
	root.add_child(ball)

	# Кольцо ударной волны по земле/горизонтали.
	var shock := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(2, 2)
	shock.mesh = plane
	shock.material_override = _shock_mat
	shock.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(shock)

	# Столб дыма: долго поднимается и расползается.
	var smoke := GPUParticles3D.new()
	smoke.amount = 46 if quality >= 1 else 20
	smoke.lifetime = 8.0
	smoke.one_shot = true
	smoke.explosiveness = 0.55
	smoke.local_coords = false
	smoke.process_material = _smoke()
	var quad := QuadMesh.new()
	quad.size = Vector2(4, 4) * k
	quad.material = smoke_material()
	smoke.draw_pass_1 = quad
	smoke.emitting = true
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(smoke)

	# Искры, вытянутые по скорости.
	var sparks := GPUParticles3D.new()
	sparks.amount = 70 if quality >= 1 else 28
	sparks.lifetime = 1.3
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.process_material = _sparks()
	var sq := QuadMesh.new()
	sq.size = Vector2(0.08, 0.9)
	sq.material = spark_material()
	sparks.draw_pass_1 = sq
	sparks.emitting = true
	root.add_child(sparks)

	# Обломки: мелкие кувыркающиеся пластины.
	if quality >= 1:
		var debris := GPUParticles3D.new()
		debris.amount = 18 if big else 10
		debris.lifetime = 2.6
		debris.one_shot = true
		debris.explosiveness = 1.0
		debris.process_material = _debris()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.22, 0.05, 0.14) * k
		bm.material = _debris_material()
		debris.draw_pass_1 = bm
		debris.emitting = true
		root.add_child(debris)

	# Подпалина на земле, если взрыв у поверхности.
	var scorch := Decal.new()
	scorch.size = Vector3(9, 12, 9) * k
	scorch.texture_albedo = _scorch_texture()
	scorch.modulate = Color(0.05, 0.04, 0.035, 0.85)
	scorch.albedo_mix = 1.0
	scorch.upper_fade = 0.2
	scorch.lower_fade = 0.2
	scorch.rotation.y = randf() * TAU
	root.add_child(scorch)

	var snd := AudioStreamPlayer3D.new()
	snd.stream = SoundBank.explosion(big)
	snd.unit_size = 40.0
	snd.max_distance = 1500.0
	snd.volume_db = 4.0
	root.add_child(snd)
	snd.play()

	var tw := root.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ball, "scale", Vector3.ONE * 5.0 * k, 0.5).from(Vector3.ONE * 0.6 * k).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_method(func(v: float): ball.set_instance_shader_parameter("age", v), 0.0, 1.0, 0.9)
	tw.tween_property(shock, "scale", Vector3.ONE * 16.0 * k, 0.45).from(Vector3.ONE)
	tw.tween_method(func(v: float): shock.set_instance_shader_parameter("age", v), 0.0, 1.0, 0.45)
	tw.tween_property(light, "light_energy", 0.0, 0.7)
	tw.chain().tween_callback(func():
		ball.queue_free()
		shock.queue_free()
		light.queue_free())
	# Подпалина держится ~25 с, потом тает; дым к тому времени давно рассеялся.
	var tw2 := root.create_tween()
	tw2.tween_interval(22.0)
	tw2.tween_property(scorch, "modulate:a", 0.0, 4.0)
	tw2.tween_callback(root.queue_free)


## Постоянный дым над разрушенным укрытием.
static func smoke_column(parent: Node3D, offset: Vector3, quality: int) -> GPUParticles3D:
	if _column_proc == null:
		var m := ParticleProcessMaterial.new()
		m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		m.emission_sphere_radius = 2.0
		m.direction = Vector3(0, 1, 0)
		m.spread = 12.0
		m.initial_velocity_min = 1.5
		m.initial_velocity_max = 3.0
		m.gravity = Vector3(0.4, 0.8, 0.2)
		m.scale_min = 0.8
		m.scale_max = 1.5
		var curve := Curve.new()
		curve.add_point(Vector2(0, 0.5))
		curve.add_point(Vector2(1, 3.0))
		var ct := CurveTexture.new()
		ct.curve = curve
		m.scale_curve = ct
		var grad := Gradient.new()
		grad.set_color(0, Color(0.12, 0.11, 0.1, 0.8))
		grad.set_color(1, Color(0.45, 0.45, 0.45, 0.0))
		var gt := GradientTexture1D.new()
		gt.gradient = grad
		m.color_ramp = gt
		_column_proc = m
	var p := GPUParticles3D.new()
	p.amount = 28 if quality >= 1 else 12
	p.lifetime = 9.0
	p.preprocess = 4.0
	p.local_coords = false
	p.process_material = _column_proc
	var quad := QuadMesh.new()
	quad.size = Vector2(5, 5)
	quad.material = smoke_material()
	p.draw_pass_1 = quad
	p.position = offset
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-30, -5, -30), Vector3(60, 90, 60))
	parent.add_child(p)
	return p


static func _debris() -> ParticleProcessMaterial:
	if _debris_proc:
		return _debris_proc
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3(0, 1, 0)
	m.spread = 75.0
	m.initial_velocity_min = 6.0
	m.initial_velocity_max = 16.0
	m.gravity = Vector3(0, -9.8, 0)
	m.angular_velocity_min = -540.0
	m.angular_velocity_max = 540.0
	m.angle_min = 0.0
	m.angle_max = 360.0
	m.scale_min = 0.5
	m.scale_max = 1.4
	m.collision_mode = ParticleProcessMaterial.COLLISION_DISABLED
	_debris_proc = m
	return m


static func _debris_material() -> StandardMaterial3D:
	if _debris_mat == null:
		_debris_mat = StandardMaterial3D.new()
		_debris_mat.albedo_color = Color(0.12, 0.12, 0.12)
		_debris_mat.roughness = 0.7
		_debris_mat.emission_enabled = true
		_debris_mat.emission = Color(0.9, 0.35, 0.08)
		_debris_mat.emission_energy_multiplier = 0.5
	return _debris_mat


static func _scorch_texture() -> Texture2D:
	if _scorch_tex:
		return _scorch_tex
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var n := FastNoiseLite.new()
	n.frequency = 0.12
	for y in 64:
		for x in 64:
			var d := Vector2(x - 31.5, y - 31.5).length() / 32.0
			var a := clampf(1.0 - d + n.get_noise_2d(x, y) * 0.35, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, smoothstep(0.0, 0.6, a)))
	_scorch_tex = ImageTexture.create_from_image(img)
	return _scorch_tex


static func _smoke() -> ParticleProcessMaterial:
	if _smoke_mat:
		return _smoke_mat
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3(0, 1, 0)
	m.spread = 55.0
	m.initial_velocity_min = 2.0
	m.initial_velocity_max = 9.0
	m.gravity = Vector3(0, 2.2, 0)
	m.damping_min = 2.0
	m.damping_max = 3.0
	m.scale_min = 0.6
	m.scale_max = 1.6
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 2.4))
	var ct := CurveTexture.new()
	ct.curve = curve
	m.scale_curve = ct
	var grad := Gradient.new()
	grad.set_color(0, Color(0.35, 0.3, 0.25, 0.9))
	grad.set_color(1, Color(0.5, 0.5, 0.5, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	m.color_ramp = gt
	_smoke_mat = m
	return m


static func _sparks() -> ParticleProcessMaterial:
	if _spark_mat:
		return _spark_mat
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3(0, 1, 0)
	m.spread = 180.0
	m.initial_velocity_min = 10.0
	m.initial_velocity_max = 30.0
	m.gravity = Vector3(0, -9.8, 0)
	m.damping_min = 1.0
	m.damping_max = 3.0
	m.scale_min = 0.5
	m.scale_max = 1.5
	m.particle_flag_align_y = true
	_spark_mat = m
	return m


static var _puff: Texture2D

static func _puff_texture() -> Texture2D:
	if _puff:
		return _puff
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 64
	t.height = 64
	_puff = t
	return t
