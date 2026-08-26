@tool
class_name HexLayout
extends Resource

# 六边形网格坐标换算 / hex grid math, axial (q, r) coords.
# 约定照 Red Blob Games 那套。squash 是纵向压扁，做等距俯视的观感。

enum HexOrientation { POINTY_TOP, FLAT_TOP }

const SQRT3: float = 1.7320508

@export var orientation: HexOrientation = HexOrientation.POINTY_TOP
## 中心到顶点的距离，压扁前 / center to corner
@export_range(8.0, 200.0, 1.0) var cell_size: float = 42.0
## 1.0 = 正六边形俯视，0.5~0.75 = 等距斜视感
@export_range(0.2, 1.0, 0.01) var squash: float = 0.7


func axial_to_local(hex: Vector2i) -> Vector2:
	var q: float = float(hex.x)
	var r: float = float(hex.y)
	var point: Vector2
	if orientation == HexOrientation.POINTY_TOP:
		point = Vector2(cell_size * SQRT3 * (q + r * 0.5), cell_size * 1.5 * r)
	else:
		point = Vector2(cell_size * 1.5 * q, cell_size * SQRT3 * (r + q * 0.5))
	point.y *= squash
	return point


# 像素 -> 格子，拖拽吸附靠这个
func local_to_axial(point: Vector2) -> Vector2i:
	var p: Vector2 = Vector2(point.x, point.y / maxf(squash, 0.001))  # 先把压扁还原回去
	var q: float
	var r: float
	if orientation == HexOrientation.POINTY_TOP:
		q = (p.x * SQRT3 / 3.0 - p.y / 3.0) / cell_size
		r = (p.y * 2.0 / 3.0) / cell_size
	else:
		q = (p.x * 2.0 / 3.0) / cell_size
		r = (-p.x / 3.0 + p.y * SQRT3 / 3.0) / cell_size
	return _axial_round(q, r)


# 单个六边形的 6 个顶点（相对自身中心，已压扁）
func corner_points() -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	var start_angle: float = PI / 6.0 if orientation == HexOrientation.POINTY_TOP else 0.0
	for i in 6:
		var angle: float = start_angle + TAU * float(i) / 6.0
		points.append(Vector2(cos(angle), sin(angle) * squash) * cell_size)
	return points


# 半径 radius 内的所有坐标，共 3N(N+1)+1 个
static func hex_area(radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for q in range(-radius, radius + 1):
		var r_low: int = maxi(-radius, -q - radius)
		var r_high: int = mini(radius, -q + radius)
		for r in range(r_low, r_high + 1):
			out.append(Vector2i(q, r))
	return out


# 两格之间要走几步
static func axial_distance(a: Vector2i, b: Vector2i) -> int:
	var dq: int = a.x - b.x
	var dr: int = a.y - b.y
	return int((absi(dq) + absi(dr) + absi(dq + dr)) / 2.0)


# 必须走立方坐标取整，直接 round(q)/round(r) 在边界会取到隔壁格子
func _axial_round(q: float, r: float) -> Vector2i:
	var s: float = -q - r
	var rq: float = roundf(q)
	var rr: float = roundf(r)
	var rs: float = roundf(s)

	var dq: float = absf(rq - q)
	var dr: float = absf(rr - r)
	var ds: float = absf(rs - s)

	if dq > dr and dq > ds:
		rq = -rr - rs
	elif dr > ds:
		rr = -rq - rs
	return Vector2i(int(rq), int(rr))
