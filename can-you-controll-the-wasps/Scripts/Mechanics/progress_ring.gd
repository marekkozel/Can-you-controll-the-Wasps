@tool
class_name ProgressRing
extends Line2D

# 沿一条闭合路径按进度画出前 t 段 / partial outline along a closed path.
# 产卵的按住进度、幼虫的饥饿倒计时都用它，把进度接到 set_progress() 就行。

var _path: PackedVector2Array = PackedVector2Array()
var _lengths: PackedFloat32Array = PackedFloat32Array()
var _total: float = 0.0


# 传多边形顶点（不用自己闭合），会预算好累计弧长
func set_ring_path(corners: PackedVector2Array) -> void:
	points = PackedVector2Array()
	_path = PackedVector2Array()
	_lengths = PackedFloat32Array()
	_total = 0.0
	if corners.size() < 2:
		return

	_path = corners.duplicate()
	_path.append(corners[0])

	_lengths.append(0.0)
	for i in range(1, _path.size()):
		_total += _path[i - 1].distance_to(_path[i])
		_lengths.append(_total)


func set_progress(t: float) -> void:
	if t <= 0.0 or _total <= 0.0:
		points = PackedVector2Array()
		return

	var target: float = clampf(t, 0.0, 1.0) * _total
	var out: PackedVector2Array = PackedVector2Array()
	out.append(_path[0])

	for i in range(1, _path.size()):
		if _lengths[i] <= target:
			out.append(_path[i])
			continue
		var start: float = _lengths[i - 1]
		var span: float = _lengths[i] - start
		if span > 0.0:
			out.append(_path[i - 1].lerp(_path[i], (target - start) / span))
		break

	points = out if out.size() >= 2 else PackedVector2Array()  # Line2D 少于两点画不出来
