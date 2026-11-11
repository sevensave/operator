class_name Fx
## Взрывы, дым, купол сети, купола глушилок.

const DOME_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;
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


static func explosion(parent: Node, pos: Vector3, big: bool, quality: int) -> void:
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = pos
	var scale_k := 1.8 if big else 1.0

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.65, 0.3)
	light.light_energy = 12.0
	light.omni_range = 40.0 * scale_k
	light.shadow_enabled = false
	root.add_child(light)

	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	ball.mesh = sm
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(1.0, 0.6, 0.2)
	bm.emission_enabled = true
	bm.emission = Color(1.0, 0.55, 0.15)
	bm.emission_energy_multiplier = 6.0
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ball.material_override = bm
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ball)

	var smoke := GPUParticles3D.new()
	smoke.amount = 40 if quality >= 1 else 18
	smoke.lifetime = 5.0
	smoke.one_shot = true
	smoke.explosiveness = 0.85
	smoke.process_material = _smoke()
	var quad := QuadMesh.new()
	quad.size = Vector2(4, 4) * scale_k
	var qm := StandardMaterial3D.new()
	qm.albedo_color = Color(0.22, 0.21, 0.2, 0.55)
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.vertex_color_use_as_albedo = true
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.albedo_texture = _puff_texture()
	quad.material = qm
	smoke.draw_pass_1 = quad
	smoke.emitting = true
	root.add_child(smoke)

	var sparks := GPUParticles3D.new()
	sparks.amount = 60 if quality >= 1 else 24
	sparks.lifetime = 1.4
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.process_material = _sparks()
	var sq := QuadMesh.new()
	sq.size = Vector2(0.25, 0.25)
	var spm := StandardMaterial3D.new()
	spm.albedo_color = Color(1.0, 0.7, 0.3)
	spm.emission_enabled = true
	spm.emission = Color(1.0, 0.6, 0.2)
	spm.emission_energy_multiplier = 5.0
	spm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	spm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sq.material = spm
	sparks.draw_pass_1 = sq
	sparks.emitting = true
	root.add_child(sparks)

	var snd := AudioStreamPlayer3D.new()
	snd.stream = SoundBank.explosion(big)
	snd.unit_size = 40.0
	snd.max_distance = 1500.0
	snd.volume_db = 4.0
	root.add_child(snd)
	snd.play()

	var tw := root.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ball, "scale", Vector3.ONE * 5.0 * scale_k, 0.35).from(Vector3.ONE * 0.5)
	tw.tween_property(bm, "albedo_color:a", 0.0, 0.45)
	tw.tween_property(light, "light_energy", 0.0, 0.6)
	tw.chain().tween_interval(5.5)
	tw.chain().tween_callback(root.queue_free)


static func _smoke() -> ParticleProcessMaterial:
	if _smoke_mat:
		return _smoke_mat
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3(0, 1, 0)
	m.spread = 70.0
	m.initial_velocity_min = 2.0
	m.initial_velocity_max = 9.0
	m.gravity = Vector3(0, 1.2, 0)
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
	m.initial_velocity_min = 8.0
	m.initial_velocity_max = 26.0
	m.gravity = Vector3(0, -9.8, 0)
	m.scale_min = 0.5
	m.scale_max = 1.5
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
