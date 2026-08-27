# 母亲还活着的异色叛军 / a variant rebel whose mother is still alive.
class_name IsRebel
extends BTCondition


func _tick(_delta: float) -> Status:
	return SUCCESS if agent.allegiance().is_rebel() else FAILURE
