extends RefCounted
## Визуал мира (headless): мир строится для всех архетипов, биомов и времени суток без ошибок,
## визуал совпадает с хитбоксами — кроны внутри цилиндров деревьев, руины внутри AABB,
## декорация без коллизий не выше 0,6 м; библиотека поверхностей строится и кэшируется.

var t

const SEEDS := [70, 111, 52, 38, 114]   # сид mod 5 — архетипы 0..4


func _terrain(seed: int) -> Terrain:
	var tr := Terrain.new()
	tr.generate(seed)
	return tr


func test_surface_library_builds_and_caches() -> void:
	var sets := SurfaceLib.ensure(512)
	t.check(sets.size() == SurfaceLib.COUNT, "все %d поверхностей" % SurfaceLib.COUNT)
	for k in SurfaceLib.COUNT:
		var set: Array = sets[k]
		t.check(set.size() == 3, "%s: albedo, normal, orm" % SurfaceLib.NAMES[k])
		for img: Image in set:
			t.check(img.get_width() == 512 and img.get_height() == 512 and img.has_mipmaps(), "%s: 512² с мипами" % SurfaceLib.NAMES[k])
	t.check(is_same(SurfaceLib.ensure(512), sets), "наборы кэшируются")
	t.check(is_same(SurfaceLib.array(WorldBuilder.GROUND_LAYERS, 0, 512), SurfaceLib.array(WorldBuilder.GROUND_LAYERS, 0, 512)), "массив текстур кэшируется")
	# Бесшовность: края плитки близки (верх/низ и лево/право — соседи при повторе).
	var a: Image = sets[SurfaceLib.GRASS][0]
	var diff := 0.0
	for i in 512:
		diff += absf(a.get_pixel(i, 0).get_luminance() - a.get_pixel(i, 511).get_luminance())
		diff += absf(a.get_pixel(0, i).get_luminance() - a.get_pixel(511, i).get_luminance())
	t.check(diff / 1024.0 < 0.12, "трава бесшовна (средний перепад на шве %.3f)" % (diff / 1024.0))


## Все архетипы × биомы × время суток × осадки: мир собирается без ошибок скриптов.
func test_world_builds_for_all_looks() -> void:
	var i := 0
	for seed in SEEDS:
		var tr := _terrain(seed)
		# Косметику перебираем по кругу, чтобы покрыть все 6 времён суток и 4 биома.
		for k in 2:
			var p := tr.preset
			p.daytime = (i * 5 + k * 3) % 6
			p.biome = (i + k * 2) % 4
			p.precip = [MapPreset.Precip.NONE, MapPreset.Precip.RAIN, MapPreset.Precip.SNOW][(i + k) % 3]
			var root := Node3D.new()
			WorldBuilder.build(tr, root, 1 if k == 0 else (i % 3))
			t.check(root.get_node_or_null("Ground") != null and root.get_node_or_null("Ruins") != null, "сид %d: земля и руины" % seed)
			t.check(root.get_node_or_null("ForestFar") != null, "сид %d: лес" % seed)
			var pr := WorldBuilder.precipitation(p, 1)
			if pr != null:
				pr.free()
			root.free()
		i += 1
	var seen := {}
	for d in 6:
		seen[d] = WorldBuilder.atmosphere(d).has("ae_lum")
	t.check(seen.size() == 6 and not seen.values().has(false), "6 наборов времени суток с автоэкспозицией")


## Крона и ствол — внутри цилиндра коллизии (x, z, r, top), с запасом под покачивание.
func test_tree_visuals_inside_collision() -> void:
	var tr := _terrain(70)
	for kind in [MapPreset.TreeKind.SPRUCE, MapPreset.TreeKind.LEAFY, MapPreset.TreeKind.DEAD]:
		var meshes: Array[ArrayMesh] = [FoliageBuilder.tree_mesh_far(kind)]
		for v in FoliageBuilder.VARIANTS:
			meshes.append(FoliageBuilder.tree_mesh_near(kind, v))
		var max_r := 0.0
		var max_y := 0.0
		var min_y := 0.0
		for m in meshes:
			for s in m.get_surface_count():
				for p: Vector3 in m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
					max_r = maxf(max_r, Vector2(p.x, p.z).length())
					max_y = maxf(max_y, p.y)
					min_y = minf(min_y, p.y)
		t.check(max_r <= FoliageBuilder.CROWN_R + 0.001, "вид %d: радиус кроны %.3f ≤ %.2f" % [kind, max_r, FoliageBuilder.CROWN_R])
		t.check(max_y <= 1.0001 and min_y >= -0.0001, "вид %d: высота в [0, 1] (%.3f..%.3f)" % [kind, min_y, max_y])
	# Экземпляры: верх ровно на высоте коллизии, радиус — радиус коллизии.
	var worst := 0.0
	for i in mini(tr.trees.size(), 300):
		var c := tr.trees[i]
		var xf := FoliageBuilder.tree_transform(tr, c, float(i))
		var top := xf * Vector3(0, 1, 0)
		var edge := xf * Vector3(FoliageBuilder.CROWN_R, 1, 0)
		worst = maxf(worst, top.y - c.w)
		t.check(Vector2(edge.x - c.x, edge.z - c.y).length() <= c.z * (FoliageBuilder.CROWN_R + 0.001), "дерево %d в цилиндре" % i)
	t.check(worst < 0.001, "верхушки не выше коллизии (превышение %.4f)" % worst)


## Руины не выходят за AABB построек; мелочь (камни, кусты, валежник) не выше 0,6 м над землёй.
func test_ruins_and_decor_bounds() -> void:
	for seed in [70, 40, 68]:
		var tr := _terrain(seed)
		var root := Node3D.new()
		WorldBuilder.build(tr, root, 1)
		var ruins := root.get_node("Ruins") as MeshInstance3D
		var verts: PackedVector3Array = ruins.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var outside := 0
		for i in range(0, verts.size(), 3):
			var p := verts[i]
			var top := tr.obstacle_top(p.x, p.z, 0.02)
			if top == -INF or p.y > top + 0.02:
				outside += 1
		t.check(outside == 0, "сид %d: вершин руин вне AABB — %d" % [seed, outside])
		var too_high := 0
		var count := 0
		for n in root.get_children():
			if not n.name.begins_with("Decor_"):
				continue
			var mm := (n as MultiMeshInstance3D).multimesh
			var aabb := mm.mesh.get_aabb()
			for xf: Transform3D in n.get_meta("xforms"):
				var hi := -INF
				for c in 8:
					hi = maxf(hi, (xf * aabb.get_endpoint(c)).y)
				var g := FoliageBuilder.mesh_height(tr, xf.origin.x, xf.origin.z)
				count += 1
				if hi - g > FoliageBuilder.DECOR_MAX_H + 0.01:
					too_high += 1
		t.check(count > 100, "сид %d: мелочь расставлена (%d)" % [seed, count])
		t.check(too_high == 0, "сид %d: мелочи выше 0,6 м — %d" % [seed, too_high])
		root.free()
	# Трава: пучок высотой 1 масштабируется не выше 0,6 м.
	var tuft := FoliageBuilder.grass_tuft().get_aabb()
	t.check(tuft.end.y <= 1.0 and 0.3 * 1.2 <= FoliageBuilder.DECOR_MAX_H, "трава ниже 0,6 м")
