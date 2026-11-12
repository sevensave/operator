class_name ShelterBuilder
## Видимые укрытия четырёх видов (косметика, хитбокс одинаковый) + мачта с цветным огнём.

static func build(style: int, color: Color, name: String, seed: int) -> Node3D:
	var root := Node3D.new()
	var st := SurfaceTool.new()
	WorldBuilder.begin_structure(st)
	const W := WorldBuilder.SURF_WOOD
	const E := WorldBuilder.SURF_SOIL
	const P := WorldBuilder.SURF_PLASTER
	const M := WorldBuilder.SURF_RUST
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var earth := Color(0.36, 0.31, 0.24)
	var wood := Color(0.40, 0.31, 0.21)
	var sand := Color(0.55, 0.50, 0.38)
	var concrete := Color(0.60, 0.59, 0.56)
	match style:
		0: # Блиндаж: накат из брёвен, присыпанный землёй
			for i in 7:
				WorldBuilder.add_box(st, AABB(Vector3(-4.5, 1.6 + (i % 2) * 0.1, -3.5 + i * 1.0), Vector3(9.0, 0.5, 0.45)), wood * rng.randf_range(0.85, 1.1), W, 0.0)
			WorldBuilder.add_box(st, AABB(Vector3(-5.5, -0.5, -4.5), Vector3(11, 2.1, 9)), earth, E, 0.0)
			WorldBuilder.add_box(st, AABB(Vector3(-4.0, 2.0, -3.2), Vector3(8, 0.8, 6.4)), earth * 1.1, E, 0.0)
			WorldBuilder.add_box(st, AABB(Vector3(-1.2, -0.5, 4.4), Vector3(2.4, 1.9, 2.5)), earth * 0.6, E, 0.0)
		1: # Окоп: бруствер из мешков по кругу
			for i in 22:
				var a := TAU * i / 22.0
				var r := 6.0
				var p := Vector3(cos(a) * r, 0.0, sin(a) * r)
				for layer in 3:
					var q := p + Vector3(rng.randf_range(-0.2, 0.2), layer * 0.42, rng.randf_range(-0.2, 0.2))
					WorldBuilder.add_box(st, AABB(q - Vector3(0.6, 0, 0.6), Vector3(1.3, 0.42, 1.0)), sand * rng.randf_range(0.85, 1.05), P, 0.0)
			WorldBuilder.add_box(st, AABB(Vector3(-2.5, -0.3, -1.5), Vector3(5, 1.2, 3)), wood * 0.8, W, 0.0)
		2: # Руины дома: две стены и перекрытие
			WorldBuilder.add_box(st, AABB(Vector3(-5, 0, -4), Vector3(10, 4.5, 0.5)), concrete, WorldBuilder.SURF_CONCRETE, 0.0)
			WorldBuilder.add_box(st, AABB(Vector3(-5, 0, -4), Vector3(0.5, 3.2, 8)), concrete * 0.95, WorldBuilder.SURF_CONCRETE, 0.0)
			WorldBuilder.add_box(st, AABB(Vector3(4.5, 0, -4), Vector3(0.5, 5.5, 5)), concrete * 0.95, WorldBuilder.SURF_CONCRETE, 0.0)
			WorldBuilder.add_box(st, AABB(Vector3(-5, 3.0, -4), Vector3(7, 0.4, 6)), concrete * 0.8, WorldBuilder.SURF_CONCRETE, 0.0)
			for i in 6:
				WorldBuilder.add_box(st, AABB(Vector3(rng.randf_range(-4, 4), 0, rng.randf_range(-3, 4)), Vector3(1.2, 0.7, 1.0)), concrete * 0.7, WorldBuilder.SURF_CONCRETE, 0.0)
		_: # Форт: бетонные блоки и наблюдательная вышка
			for i in 4:
				var a := TAU * i / 4.0 + PI / 4.0
				var c := Vector3(cos(a) * 5.5, 0, sin(a) * 5.5)
				WorldBuilder.add_box(st, AABB(c - Vector3(1.5, 0, 1.5), Vector3(3, 3.2, 3)), concrete, WorldBuilder.SURF_CONCRETE, 0.0)
			WorldBuilder.add_box(st, AABB(Vector3(-4, 0, -0.4), Vector3(8, 2.4, 0.8)), concrete * 0.9, WorldBuilder.SURF_CONCRETE, 0.0)
			WorldBuilder.add_box(st, AABB(Vector3(-0.4, 0, -4), Vector3(0.8, 2.4, 8)), concrete * 0.9, WorldBuilder.SURF_CONCRETE, 0.0)
			WorldBuilder.add_box(st, AABB(Vector3(-1.5, 5.5, -1.5), Vector3(3, 0.4, 3)), concrete * 0.8, WorldBuilder.SURF_CONCRETE, 0.0)
			for k in 4:
				WorldBuilder.add_box(st, AABB(Vector3(-1.4 + (k % 2) * 2.6, 0, -1.4 + (k / 2) * 2.6), Vector3(0.3, 5.5, 0.3)), concrete * 0.7, WorldBuilder.SURF_CONCRETE, 0.0)
	# Мачта антенны.
	WorldBuilder.add_box(st, AABB(Vector3(2.0, 0, 2.0), Vector3(0.25, SimConst.MAST_HEIGHT, 0.25)), Color(0.3, 0.3, 0.3), M, 0.0)
	for k in 3:
		WorldBuilder.add_box(st, AABB(Vector3(1.6, 4.0 + k * 4.0, 2.1), Vector3(1.0, 0.08, 0.08)), Color(0.3, 0.3, 0.3), M, 0.0)
	# Цветная маркировка — щиты в цвет игрока.
	WorldBuilder.add_box(st, AABB(Vector3(-0.8, 0.0, -6.8), Vector3(1.6, 1.6, 0.15)), color, WorldBuilder.SURF_CONCRETE, 0.0)
	WorldBuilder.add_box(st, AABB(Vector3(-6.8, 0.0, -0.8), Vector3(0.15, 1.6, 1.6)), color, WorldBuilder.SURF_CONCRETE, 0.0)
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = WorldBuilder.structure_material()
	mi.name = "Body"
	root.add_child(mi)

	# Мигающий огонь на мачте.
	var beacon := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.45
	sm.height = 0.9
	beacon.mesh = sm
	var bm := StandardMaterial3D.new()
	bm.albedo_color = color
	bm.emission_enabled = true
	bm.emission = color
	bm.emission_energy_multiplier = 4.0
	beacon.material_override = bm
	beacon.position = Vector3(2.12, SimConst.MAST_HEIGHT + 0.4, 2.12)
	beacon.name = "Beacon"
	root.add_child(beacon)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 2.0
	light.omni_range = 18.0
	light.position = beacon.position
	light.name = "BeaconLight"
	root.add_child(light)

	var label := Label3D.new()
	label.text = name
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 96
	label.pixel_size = 0.02
	label.outline_size = 18
	label.modulate = color.lightened(0.3)
	label.position = Vector3(0, SimConst.MAST_HEIGHT + 5.0, 0)
	label.no_depth_test = true
	label.fixed_size = false
	label.name = "Label"
	root.add_child(label)
	return root
