class_name DroneView
extends Node3D
## Модель дрона: коптер (рама, 4 винта) или самолёт (фюзеляж, крыло, хвост).

var kind := 0
var color := Color.WHITE
var props: Array[Node3D] = []
var prop_speed := 0.0
var motor: AudioStreamPlayer3D
var _light: OmniLight3D


func setup(p_kind: int, p_color: Color, with_sound: bool) -> void:
	kind = p_kind
	color = p_color
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dark := Color(0.12, 0.12, 0.13)
	if kind == SimConst.Kind.COPTER:
		WorldBuilder.add_box(st, AABB(Vector3(-0.12, -0.05, -0.2), Vector3(0.24, 0.12, 0.4)), dark)
		WorldBuilder.add_box(st, AABB(Vector3(-0.08, 0.07, -0.12), Vector3(0.16, 0.06, 0.18)), color)
		for k in 4:
			var a := PI / 4.0 + k * PI / 2.0
			var tip := Vector3(cos(a), 0, sin(a)) * 0.32
			# Луч рамы.
			var arm_xf := Transform3D(Basis(Vector3.UP, -a), tip * 0.5)
			WorldBuilder.add_obox(st, arm_xf, Vector3(0.34, 0.03, 0.035), dark)
			WorldBuilder.add_box(st, AABB(tip - Vector3(0.04, 0.02, 0.04), Vector3(0.08, 0.08, 0.08)), dark * 1.4)
			var prop := MeshInstance3D.new()
			var pm := BoxMesh.new()
			pm.size = Vector3(0.36, 0.006, 0.035)
			prop.mesh = pm
			var pmat := StandardMaterial3D.new()
			pmat.albedo_color = color.darkened(0.2)
			prop.material_override = pmat
			prop.position = tip + Vector3(0, 0.07, 0)
			add_child(prop)
			props.append(prop)
		# Груз-заряд снизу.
		WorldBuilder.add_box(st, AABB(Vector3(-0.06, -0.16, -0.1), Vector3(0.12, 0.11, 0.24)), Color(0.32, 0.34, 0.26))
		scale = Vector3.ONE * 1.4
	else:
		WorldBuilder.add_box(st, AABB(Vector3(-0.12, -0.12, -0.9), Vector3(0.24, 0.24, 1.6)), Color(0.5, 0.52, 0.5))
		WorldBuilder.add_box(st, AABB(Vector3(-1.2, 0.02, -0.35), Vector3(2.4, 0.05, 0.42)), Color(0.55, 0.57, 0.55))
		WorldBuilder.add_box(st, AABB(Vector3(-1.2, 0.03, -0.32), Vector3(0.4, 0.05, 0.36)), color)
		WorldBuilder.add_box(st, AABB(Vector3(0.8, 0.03, -0.32), Vector3(0.4, 0.05, 0.36)), color)
		WorldBuilder.add_box(st, AABB(Vector3(-0.45, 0.0, 0.55), Vector3(0.9, 0.04, 0.22)), Color(0.5, 0.52, 0.5))
		WorldBuilder.add_box(st, AABB(Vector3(-0.02, 0.0, 0.55), Vector3(0.04, 0.35, 0.22)), color)
		WorldBuilder.add_box(st, AABB(Vector3(-0.08, -0.2, -0.6), Vector3(0.16, 0.1, 0.5)), Color(0.32, 0.34, 0.26))
		var prop := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.5, 0.05, 0.01)
		prop.mesh = pm
		var pmat := StandardMaterial3D.new()
		pmat.albedo_color = dark
		prop.material_override = pmat
		prop.position = Vector3(0, 0, -0.93)
		add_child(prop)
		props.append(prop)
		scale = Vector3.ONE * 1.6
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.6
	mat.metallic = 0.2
	mi.material_override = mat
	mi.name = "Body"
	add_child(mi)

	# Навигационный огонь цвета игрока — видно издалека.
	_light = OmniLight3D.new()
	_light.light_color = color
	_light.light_energy = 1.5
	_light.omni_range = 6.0
	add_child(_light)
	var dot := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.06
	sm.height = 0.12
	dot.mesh = sm
	var dm := StandardMaterial3D.new()
	dm.emission_enabled = true
	dm.emission = color
	dm.emission_energy_multiplier = 8.0
	dm.albedo_color = color
	dot.material_override = dm
	dot.position = Vector3(0, 0.1, 0.18)
	add_child(dot)

	if with_sound:
		motor = AudioStreamPlayer3D.new()
		motor.stream = SoundBank.motor_loop(kind)
		motor.unit_size = 14.0
		motor.max_distance = 400.0
		motor.volume_db = -4.0
		motor.bus = &"Master"
		motor.autoplay = true
		add_child(motor)


func update_visual(thrust: float, delta: float) -> void:
	prop_speed = lerpf(prop_speed, 30.0 + thrust * 60.0, minf(1.0, delta * 5.0))
	for p in props:
		if kind == SimConst.Kind.COPTER:
			p.rotate_y(prop_speed * delta * (1.0 if props.find(p) % 2 == 0 else -1.0))
		else:
			p.rotate_z(prop_speed * delta)
	if motor:
		motor.pitch_scale = clampf(0.7 + thrust * 0.6, 0.5, 2.0)
