extends Label

# 性能读数 / perf readout. F11 开关，默认常驻。
# 帧率掉下去时先看 draw calls 和 physics：前者是巢室的 Polygon2D/Line2D 堆出来的，
# 后者是每只黄蜂/物件都是带 contact_monitor 的刚体。
# When FPS drops, read draw calls and physics first - those are the two things that scale
# with hive size and wasp count here.

## 刷新间隔。每帧拼字符串本身就是开销 / building the string every frame is itself a cost
@export_range(0.05, 2.0, 0.05) var refresh_interval: float = 0.25

const ENTITIES_GROUP: StringName = &"entities"
const WASP_GROUP: StringName = &"wasps"
const CARRIABLE_GROUP: StringName = &"carriable"
const ENEMY_GROUP: StringName = &"Enemy"

var _timer: float = 0.0


func _ready() -> void:
	if not OS.is_debug_build():
		queue_free()
		return
	_refresh()


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = refresh_interval
	_refresh()


func _refresh() -> void:
	var fps: float = Performance.get_monitor(Performance.TIME_FPS)
	var process_ms: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var physics_ms: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var nav_ms: float = Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS) * 1000.0

	var lines: PackedStringArray = PackedStringArray()
	lines.append("FPS %3d      frame %.1f ms" % [int(fps), 1000.0 / maxf(fps, 1.0)])
	lines.append("process %.2f   physics %.2f   nav %.2f" % [process_ms, physics_ms, nav_ms])
	lines.append("draw calls %d   nodes %d" % [
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])
	lines.append("bodies %d   pairs %d   islands %d" % [
		int(Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS)),
		int(Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS)),
		int(Performance.get_monitor(Performance.PHYSICS_2D_ISLAND_COUNT))])
	lines.append("wasps %d   items %d   enemies %d" % [_group_count(WASP_GROUP), _group_count(CARRIABLE_GROUP), _group_count(ENEMY_GROUP)])
	lines.append(_allegiance_line())
	lines.append(_unrest_line())
	lines.append("static mem %.1f MB" % (Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0))

	text = "
".join(lines)


# 调试用。正式玩法里这一行就是答案，别留给玩家看
# Debug only: this line is the answer sheet.
func _allegiance_line() -> String:
	var tally: Array[int] = [0, 0, 0, 0]
	for node in get_tree().get_nodes_in_group(WASP_GROUP):
		var wasp: Wasp = node as Wasp
		if wasp != null:
			tally[wasp.allegiance().state] += 1
	return "loyal %d  queen %d  rebel %d  subdued %d" % [tally[0], tally[1], tally[2], tally[3]]


# 同样是答案纸：正式玩法里不安值只通过画面色调漏出去
# Answer sheet again - in play, unrest only leaks through the colour wash.
func _unrest_line() -> String:
	var director: BetrayalDirector = BetrayalDirector.find(get_tree())
	if director == null:
		return "unrest --"
	var strikers: int = 0
	for node in get_tree().get_nodes_in_group(WASP_GROUP):
		var wasp: Wasp = node as Wasp
		if wasp != null and wasp.allegiance().is_on_strike():
			strikers += 1
	return "unrest %.2f   morale x%.2f   striking %d" % [
		director.unrest, lerpf(1.0, director.morale_floor, director.unrest), strikers]


func _group_count(group: StringName) -> int:
	return get_tree().get_nodes_in_group(group).size()
