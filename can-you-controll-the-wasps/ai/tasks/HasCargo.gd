# 手上有货吗 / does the wasp hold something right now.
class_name HasCargo
extends BTCondition


func _tick(_delta: float) -> Status:
	var carry: CarryComponent = agent.carry()
	return SUCCESS if carry != null and carry.is_carrying() else FAILURE
