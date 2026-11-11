extends RefCounted
## Процедурные модели дронов: все варианты строятся, у каждого свои винты и бюджет треугольников.

var t


func test_all_models_build() -> void:
	var props_by_kind := [[4, 4, 6], [1, 1, 1]]
	var seen := {}
	for kind in 2:
		for model in SimConst.MODEL_COUNT:
			var info := DroneModels.build(kind, model)
			var mesh: ArrayMesh = info.mesh
			var name: String = SimConst.MODEL_NAMES[kind][model]
			t.check(mesh.get_surface_count() >= 4, "%s: раздельные материалы (%d поверхностей)" % [name, mesh.get_surface_count()])
			t.check(mesh.get_surface_count() == (mesh.get_meta("mats") as Array).size(), "%s: у каждой поверхности свой материал" % name)
			var tris := 0
			for s in mesh.get_surface_count():
				tris += mesh.surface_get_array_len(s) / 3
			t.check(tris > 150 and tris < 6000, "%s: треугольников %d в бюджете" % [name, tris])
			t.check(info.props.size() == props_by_kind[kind][model], "%s: винтов %d" % [name, info.props.size()])
			t.check(info.nav.size() >= 2, "%s: навигационные огни" % name)
			var aabb := mesh.get_aabb()
			var reach: float = maxf(aabb.size.x, aabb.size.z) * 0.5 * float(info.scale)
			# Размах как у прежних моделей (коптер ~0,55 м от центра, самолёт ~1,9 м), не больше.
			t.check(reach < [0.8, 2.15][kind], "%s: размер как у прежней модели (%.2f м)" % [name, reach])
			seen[tris] = true
	t.check(seen.size() == 6, "все шесть моделей разные")
	t.check(DroneModels.build(0, 1) == DroneModels.build(0, 1), "сетки кэшируются")
	t.check(DroneModels.build(1, 99).mesh == DroneModels.build(1, 2).mesh, "номер модели клампится")
