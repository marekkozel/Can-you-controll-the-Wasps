class_name NavSteering
extends RefCounted

# 导航转向 / navmesh steering. 两个敌人组件共用这一份。
# 地图是"上走廊 + 下巢室"的 T 形，朝目标直线飞会顶在隔断上，方向必须听路径点。
# The map is a T - a straight line at the nest walks into the divider.
#
# 黄蜂不走这里，wasp.gd 里有自己那份（还带 RVO 回调）/ Wasp keeps its own, with RVO.

var _body: RigidBody2D = null
var _nav: NavigationAgent2D = null
var _goal: Vector2 = Vector2.INF


func _init(body: RigidBody2D, nav: NavigationAgent2D) -> void:
	_body = body
	_nav = nav


func steer(target: Vector2, delta: float, speed: float, smoothing: float) -> void:
	if not is_instance_valid(_body):
		return
	var heading: Vector2 = heading_towards(target)
	if heading == Vector2.ZERO:
		return
	# 和帧率无关的插值系数 / framerate independent
	var blend: float = 1.0 - pow(1.0 - clampf(smoothing, 0.0, 1.0), delta * 60.0)
	_body.linear_velocity = _body.linear_velocity.lerp(heading * speed, blend)


# 目标先吸到网格上：贴墙的巢室会被判成不可达，退回直线 steering 就是原地磨墙
# Snap the goal first - an off-mesh goal reads as unreachable and the fallback grinds walls.
func heading_towards(target: Vector2) -> Vector2:
	if not is_instance_valid(_body):
		return Vector2.ZERO
	var direct: Vector2 = (target - _body.global_position).normalized()
	if _nav == null:
		return direct

	var goal: Vector2 = snap(target)
	if _goal.distance_squared_to(goal) > 256.0:
		_goal = goal
		_nav.target_position = goal

	if _nav.is_navigation_finished():
		return direct
	var to_waypoint: Vector2 = _nav.get_next_path_position() - _body.global_position
	return direct if to_waypoint.length() < 0.01 else to_waypoint.normalized()


func snap(point: Vector2) -> Vector2:
	if not is_instance_valid(_body) or not _body.is_inside_tree():
		return point
	var map: RID = _body.get_world_2d().navigation_map
	return NavigationServer2D.map_get_closest_point(map, point) if map.is_valid() else point
