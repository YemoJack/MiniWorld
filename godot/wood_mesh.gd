@tool
extends RefCounted

static func create(size: Vector2, depth: float, kind: String, wood: Color, trim: Color, opening := Rect2()) -> ArrayMesh:
	var half := size.x / 2.0
	var xs: Array[float] = [-half, half]
	var ys: Array[float] = [0.0, size.y]
	var frame := opening.grow(0.014)
	match kind:
		"wall":
			ys.append(size.y - 0.055)
			for row in range(1, ceili(size.y / 0.13)):
				ys.append(row * 0.13)
			if opening.has_area():
				xs.append_array([frame.position.x, opening.position.x, opening.end.x, frame.end.x])
				for level in [frame.position.y, opening.position.y, opening.end.y, frame.end.y]:
					if level > 0.0 and level < size.y:
						ys.append(level)
		"door":
			for plank in range(1, 5):
				xs.append(-half + size.x * plank / 5.0)
			ys.append_array([0.1235, 0.1765, 0.6635, 0.7165])
		"floor":
			for plank in range(1, 4):
				ys.append(size.y * plank / 4.0)
	xs.sort()
	ys.sort()

	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_smooth_group(-1)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.88
	surface.set_material(material)
	var front := depth / 2.0
	for col in xs.size() - 1:
		for row in ys.size() - 1:
			if not solid(xs, ys, col, row, opening):
				continue
			var low := Vector2(xs[col], ys[row])
			var high := Vector2(xs[col + 1], ys[row + 1])
			var mid := (low + high) / 2.0
			var tint := wood
			match kind:
				"wall":
					tint = wood.darkened((floori(mid.y / 0.13) % 2) * 0.07)
					if mid.y > size.y - 0.055 or (opening.has_area() and frame.has_point(mid)):
						tint = trim
				"door":
					tint = trim if (mid.y > 0.1235 and mid.y < 0.1765) or (mid.y > 0.6635 and mid.y < 0.7165) else wood.darkened(col % 3 * 0.065)
				"floor":
					tint = wood.lightened(row * 0.045)
			var a := Vector3(low.x, low.y, front)
			var b := Vector3(high.x, low.y, front)
			var c := Vector3(high.x, high.y, front)
			var d := Vector3(low.x, high.y, front)
			var back := Vector3.FORWARD * depth
			quad(surface, a, d, c, b, Vector3.BACK, tint)
			quad(surface, a + back, b + back, c + back, d + back, Vector3.FORWARD, tint)
			if not solid(xs, ys, col - 1, row, opening):
				quad(surface, a, a + back, d + back, d, Vector3.LEFT, trim)
			if not solid(xs, ys, col + 1, row, opening):
				quad(surface, b, c, c + back, b + back, Vector3.RIGHT, trim)
			if not solid(xs, ys, col, row - 1, opening):
				quad(surface, a, b, b + back, a + back, Vector3.DOWN, trim)
			if not solid(xs, ys, col, row + 1, opening):
				quad(surface, d, d + back, c + back, c, Vector3.UP, trim)
	surface.generate_normals()
	return surface.commit()


static func solid(xs: Array[float], ys: Array[float], col: int, row: int, opening: Rect2) -> bool:
	if col < 0 or col >= xs.size() - 1 or row < 0 or row >= ys.size() - 1:
		return false
	return not opening.has_point(Vector2(xs[col] + xs[col + 1], ys[row] + ys[row + 1]) / 2.0)


static func quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, tint: Color) -> void:
	var points := [a, b, c, a, c, d] if (b - a).cross(c - a).dot(normal) < 0.0 else [a, c, b, a, d, c]
	surface.set_color(tint)
	for point: Vector3 in points:
		surface.set_uv(Vector2(point.z, point.y) if normal.x != 0.0 else (
			Vector2(point.x, point.z) if normal.y != 0.0 else Vector2(point.x, point.y)
		))
		surface.add_vertex(point)
